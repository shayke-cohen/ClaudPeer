import Foundation
import SwiftData

enum DefaultsSeeder {

    static let seededKey = "claudpeer.defaultsSeeded"

    static func seedIfNeeded(container: ModelContainer) {
        guard !UserDefaults.standard.bool(forKey: seededKey) else { return }

        let context = ModelContext(container)
        let agentCount = (try? context.fetchCount(FetchDescriptor<Agent>())) ?? 0
        if agentCount > 0 { return }

        print("[DefaultsSeeder] First launch detected — seeding defaults")

        let permissionSets = seedPermissionPresets(into: context)
        let mcpServers = seedMCPServers(into: context)
        let skills = seedSkills(into: context)
        seedAgents(into: context, permissionSets: permissionSets, mcpServers: mcpServers, skills: skills)

        do {
            try context.save()
            UserDefaults.standard.set(true, forKey: seededKey)
            print("[DefaultsSeeder] Seeding complete")
        } catch {
            print("[DefaultsSeeder] Failed to save: \(error)")
        }
    }

    static func resetAndReseed(container: ModelContainer) {
        let context = ModelContext(container)
        do {
            try context.delete(model: Agent.self, where: #Predicate { $0.originKind == "builtin" })
            try context.delete(model: Skill.self, where: #Predicate { $0.sourceKind == "builtin" })
            try context.delete(model: MCPServer.self)
            try context.delete(model: PermissionSet.self)
            try context.save()
        } catch {
            print("[DefaultsSeeder] Reset cleanup failed: \(error)")
        }

        UserDefaults.standard.removeObject(forKey: seededKey)
        seedIfNeeded(container: container)
    }

    // MARK: - Permission Presets

    private static func seedPermissionPresets(into context: ModelContext) -> [String: PermissionSet] {
        guard let data = loadResource(name: "DefaultPermissionPresets", ext: "json") else {
            print("[DefaultsSeeder] DefaultPermissionPresets.json not found")
            return [:]
        }

        struct PresetDTO: Decodable {
            let name: String
            let allowRules: [String]
            let denyRules: [String]
            let additionalDirectories: [String]
            let permissionMode: String
        }

        guard let dtos = try? JSONDecoder().decode([PresetDTO].self, from: data) else {
            print("[DefaultsSeeder] Failed to decode permission presets")
            return [:]
        }

        var map: [String: PermissionSet] = [:]
        for dto in dtos {
            let ps = PermissionSet(
                name: dto.name,
                allowRules: dto.allowRules,
                denyRules: dto.denyRules,
                permissionMode: dto.permissionMode
            )
            ps.additionalDirectories = dto.additionalDirectories
            context.insert(ps)
            map[dto.name] = ps
            print("[DefaultsSeeder]   Permission preset: \(dto.name)")
        }
        return map
    }

    // MARK: - MCP Servers

    private static func seedMCPServers(into context: ModelContext) -> [String: MCPServer] {
        guard let data = loadResource(name: "DefaultMCPs", ext: "json") else {
            print("[DefaultsSeeder] DefaultMCPs.json not found")
            return [:]
        }

        struct MCPDTO: Decodable {
            let name: String
            let serverDescription: String
            let transportKind: String
            let transportCommand: String?
            let transportArgs: [String]?
            let transportEnv: [String: String]?
            let transportUrl: String?
            let transportHeaders: [String: String]?
        }

        guard let dtos = try? JSONDecoder().decode([MCPDTO].self, from: data) else {
            print("[DefaultsSeeder] Failed to decode MCP servers")
            return [:]
        }

        var map: [String: MCPServer] = [:]
        for dto in dtos {
            let transport: MCPTransport
            if dto.transportKind == "stdio" {
                transport = .stdio(
                    command: dto.transportCommand ?? "",
                    args: dto.transportArgs ?? [],
                    env: dto.transportEnv ?? [:]
                )
            } else {
                transport = .http(
                    url: dto.transportUrl ?? "",
                    headers: dto.transportHeaders ?? [:]
                )
            }
            let server = MCPServer(name: dto.name, serverDescription: dto.serverDescription, transport: transport)
            context.insert(server)
            map[dto.name] = server
            print("[DefaultsSeeder]   MCP server: \(dto.name)")
        }
        return map
    }

    // MARK: - Skills

    private static func seedSkills(into context: ModelContext) -> [String: Skill] {
        let skillNames = [
            "peer-collaboration",
            "blackboard-patterns",
            "delegation-patterns",
            "workspace-collaboration",
            "agent-identity",
        ]

        var map: [String: Skill] = [:]
        for name in skillNames {
            guard let content = loadSkillContent(name: name) else {
                print("[DefaultsSeeder]   Skill not found: \(name)")
                continue
            }

            let metadata = parseSkillMetadata(content)
            let skill = Skill(
                name: metadata["name"] ?? name,
                skillDescription: metadata["description"] ?? "",
                category: metadata["category"] ?? "ClaudPeer",
                content: content
            )
            skill.source = .builtin
            skill.version = "1.0"
            if let triggers = metadata["triggers"] {
                skill.triggers = triggers.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            }
            context.insert(skill)
            map[name] = skill
            print("[DefaultsSeeder]   Skill: \(name)")
        }
        return map
    }

    // MARK: - Agents

    private static func seedAgents(
        into context: ModelContext,
        permissionSets: [String: PermissionSet],
        mcpServers: [String: MCPServer],
        skills: [String: Skill]
    ) {
        struct AgentDTO: Decodable {
            let name: String
            let agentDescription: String
            let model: String
            let icon: String
            let color: String
            let instancePolicyKind: String
            let instancePolicyPoolMax: Int?
            let skillNames: [String]
            let mcpServerNames: [String]
            let permissionSetName: String
            let systemPromptTemplate: String?
            let systemPromptVariables: [String: String]?
            let maxTurns: Int?
            let maxBudget: Double?
        }

        let agentFiles = [
            "orchestrator", "coder", "reviewer", "researcher", "tester", "devops", "writer",
        ]

        for fileName in agentFiles {
            guard let data = loadResource(directory: "DefaultAgents", name: fileName, ext: "json") else {
                print("[DefaultsSeeder]   Agent file not found: \(fileName).json")
                continue
            }
            guard let dto = try? JSONDecoder().decode(AgentDTO.self, from: data) else {
                print("[DefaultsSeeder]   Failed to decode agent: \(fileName).json")
                continue
            }

            let systemPrompt = buildSystemPrompt(
                template: dto.systemPromptTemplate,
                variables: dto.systemPromptVariables ?? [:]
            )

            let agent = Agent(
                name: dto.name,
                agentDescription: dto.agentDescription,
                systemPrompt: systemPrompt,
                model: dto.model,
                icon: dto.icon,
                color: dto.color
            )
            agent.instancePolicyKind = dto.instancePolicyKind
            agent.instancePolicyPoolMax = dto.instancePolicyPoolMax
            agent.originKind = "builtin"
            agent.maxTurns = dto.maxTurns
            agent.maxBudget = dto.maxBudget

            agent.skillIds = dto.skillNames.compactMap { skills[$0]?.id }
            agent.mcpServerIds = dto.mcpServerNames.compactMap { mcpServers[$0]?.id }
            agent.permissionSetId = permissionSets[dto.permissionSetName]?.id

            context.insert(agent)
            print("[DefaultsSeeder]   Agent: \(dto.name) (skills: \(agent.skillIds.count), mcps: \(agent.mcpServerIds.count))")
        }
    }

    // MARK: - System Prompt Builder

    private static func buildSystemPrompt(template: String?, variables: [String: String]) -> String {
        guard let templateName = template else { return "" }
        guard let content = loadPromptTemplate(name: templateName) else {
            return "You are a helpful AI assistant."
        }
        var result = content
        for (key, value) in variables {
            result = result.replacingOccurrences(of: "{{\(key)}}", with: value)
        }
        return result
    }

    // MARK: - Resource Loading

    private static func loadResource(directory: String? = nil, name: String, ext: String) -> Data? {
        if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: directory) {
            return try? Data(contentsOf: url)
        }

        for basePath in resourceSearchPaths() {
            let dir = directory.map { "\(basePath)/\($0)" } ?? basePath
            let filePath = "\(dir)/\(name).\(ext)"
            if FileManager.default.fileExists(atPath: filePath) {
                return try? Data(contentsOf: URL(fileURLWithPath: filePath))
            }
        }
        return nil
    }

    private static func loadSkillContent(name: String) -> String? {
        if let url = Bundle.main.url(
            forResource: "SKILL",
            withExtension: "md",
            subdirectory: "DefaultSkills/\(name)"
        ) {
            return try? String(contentsOf: url, encoding: .utf8)
        }

        for basePath in resourceSearchPaths() {
            let filePath = "\(basePath)/DefaultSkills/\(name)/SKILL.md"
            if FileManager.default.fileExists(atPath: filePath) {
                return try? String(contentsOf: URL(fileURLWithPath: filePath), encoding: .utf8)
            }
        }
        return nil
    }

    private static func loadPromptTemplate(name: String) -> String? {
        if let url = Bundle.main.url(
            forResource: name,
            withExtension: "md",
            subdirectory: "SystemPromptTemplates"
        ) {
            return try? String(contentsOf: url, encoding: .utf8)
        }

        for basePath in resourceSearchPaths() {
            let filePath = "\(basePath)/SystemPromptTemplates/\(name).md"
            if FileManager.default.fileExists(atPath: filePath) {
                return try? String(contentsOf: URL(fileURLWithPath: filePath), encoding: .utf8)
            }
        }
        return nil
    }

    private static func resourceSearchPaths() -> [String] {
        let fm = FileManager.default
        var paths: [String] = []

        if let override = UserDefaults.standard.string(forKey: AppSettings.sidecarPathKey),
           !override.isEmpty {
            paths.append("\(override)/ClaudPeer/Resources")
        }

        let devPath = "\(fm.currentDirectoryPath)/ClaudPeer/Resources"
        paths.append(devPath)

        let wellKnown = "\(NSHomeDirectory())/ClaudPeer/ClaudPeer/Resources"
        paths.append(wellKnown)

        return paths
    }

    // MARK: - SKILL.md Metadata Parser

    private static func parseSkillMetadata(_ content: String) -> [String: String] {
        var metadata: [String: String] = [:]
        let lines = content.components(separatedBy: "\n")

        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return metadata }

        var inFrontmatter = false
        var currentKey: String?
        var listValues: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed == "---" {
                if inFrontmatter {
                    if let key = currentKey, !listValues.isEmpty {
                        metadata[key] = listValues.joined(separator: ", ")
                    }
                    break
                }
                inFrontmatter = true
                continue
            }

            guard inFrontmatter else { continue }

            if trimmed.hasPrefix("- ") {
                let value = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                listValues.append(value)
                continue
            }

            if let colonIndex = trimmed.firstIndex(of: ":") {
                if let key = currentKey, !listValues.isEmpty {
                    metadata[key] = listValues.joined(separator: ", ")
                    listValues = []
                }
                let key = String(trimmed[trimmed.startIndex..<colonIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(trimmed[trimmed.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                currentKey = key
                if !value.isEmpty {
                    metadata[key] = value
                }
            }
        }
        return metadata
    }
}
