@testable import OdysseyLocalAgentCore
import Foundation

struct StubRemoteToolCaller: RemoteToolCalling {
    let handler: @Sendable (String, [String: DynamicValue], ToolExecutionContext) async throws -> ToolExecutionResult

    func callTool(
        name: String,
        arguments: [String: DynamicValue],
        context: ToolExecutionContext
    ) async throws -> ToolExecutionResult {
        try await handler(name, arguments, context)
    }
}

func makeStubMCPServer(
    in directory: URL,
    name: String = "stub-mcp",
    toolName: String = "mcp_echo",
    toolDescription: String = "Echo text back from MCP",
    responsePrefix: String = "MCP"
) throws -> LocalAgentMCPServer {
    let scriptURL = directory.appendingPathComponent("\(name)-server.rb")
    try """
    #!/usr/bin/env ruby
    require "json"

    STDOUT.sync = true

    tool_name = ENV.fetch("MCP_TOOL_NAME", "mcp_echo")
    tool_description = ENV.fetch("MCP_TOOL_DESCRIPTION", "Echo text back from MCP")
    response_prefix = ENV.fetch("MCP_RESPONSE_PREFIX", "MCP")

    loop do
      headers = []
      line = nil

      while (line = STDIN.gets)
        line = line.sub(/\\r?\\n\\z/, "")
        break if line.empty?
        headers << line
      end

      break if line.nil? && headers.empty?

      content_length = headers.filter_map { |header| header[/\\AContent-Length:\\s*(\\d+)/i, 1]&.to_i }.first
      break unless content_length

      body = STDIN.read(content_length)
      break if body.nil? || body.empty?

      request = JSON.parse(body)
      id = request["id"]
      method = request["method"]

      result = case method
      when "initialize"
        {
          "protocolVersion" => "2024-11-05",
          "capabilities" => { "tools" => {} },
          "serverInfo" => {
            "name" => "StubMCP",
            "version" => "1.0.0",
          },
        }
      when "tools/list"
        {
          "tools" => [
            {
              "name" => tool_name,
              "description" => tool_description,
              "inputSchema" => {
                "type" => "object",
                "properties" => {
                  "text" => { "type" => "string" },
                },
              },
            },
          ],
        }
      when "tools/call"
        arguments = request.dig("params", "arguments") || {}
        {
          "content" => [
            {
              "type" => "text",
              "text" => "#{response_prefix}: #{arguments["text"] || ""}",
            },
          ],
          "isError" => false,
        }
      else
        {
          "content" => [
            {
              "type" => "text",
              "text" => "Unhandled method: #{method}",
            },
          ],
          "isError" => true,
        }
      end

      response = JSON.generate({
        "jsonrpc" => "2.0",
        "id" => id,
        "result" => result,
      })

      STDOUT.write("Content-Length: #{response.bytesize}\\r\\n\\r\\n")
      STDOUT.write(response)
    end
    """.write(to: scriptURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

    return LocalAgentMCPServer(
        name: name,
        command: scriptURL.path,
        env: [
            "MCP_TOOL_NAME": toolName,
            "MCP_TOOL_DESCRIPTION": toolDescription,
            "MCP_RESPONSE_PREFIX": responsePrefix,
        ]
    )
}
