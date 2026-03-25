import Foundation

/// The mode of a launch intent — what kind of session to create.
enum LaunchMode: Sendable, Equatable {
    case chat
    case agent(name: String)
    case group(name: String)
}

/// A parsed launch intent from CLI args or a `claudpeer://` URL.
///
/// Parsed eagerly (no SwiftData dependency). Execution is deferred until
/// `AppState.executeLaunchIntent(_:modelContext:)` is called.
struct LaunchIntent: Sendable {
    let mode: LaunchMode
    let prompt: String?
    let workingDirectory: String?
    let autonomous: Bool

    // MARK: - CLI Parsing

    /// Parses `CommandLine.arguments` for launch flags.
    ///
    /// Recognized flags:
    /// - `--chat` — freeform chat
    /// - `--agent <name>` — session with a named agent
    /// - `--group <name>` — group chat with a named group
    /// - `--prompt <text>` — initial message to auto-send
    /// - `--workdir <path>` — override working directory
    /// - `--autonomous` — start in autonomous mode
    ///
    /// Returns `nil` when no launch-mode flag is present.
    static func fromCommandLine() -> LaunchIntent? {
        let args = CommandLine.arguments

        var mode: LaunchMode?
        var prompt: String?
        var workingDirectory: String?
        var autonomous = false

        var i = 1 // skip argv[0]
        while i < args.count {
            switch args[i] {
            case "--chat":
                mode = .chat

            case "--agent":
                i += 1
                guard i < args.count else { break }
                mode = .agent(name: args[i])

            case "--group":
                i += 1
                guard i < args.count else { break }
                mode = .group(name: args[i])

            case "--prompt":
                i += 1
                guard i < args.count else { break }
                prompt = args[i]

            case "--workdir":
                i += 1
                guard i < args.count else { break }
                workingDirectory = args[i]

            case "--autonomous":
                autonomous = true

            default:
                break
            }
            i += 1
        }

        guard let mode else { return nil }
        return LaunchIntent(
            mode: mode,
            prompt: prompt,
            workingDirectory: workingDirectory,
            autonomous: autonomous
        )
    }

    // MARK: - URL Scheme Parsing

    /// Parses a `claudestudio://` URL into a launch intent.
    ///
    /// Supported formats:
    /// - `claudestudio://chat?prompt=...`
    /// - `claudestudio://agent/Coder?prompt=...&workdir=/path&autonomous=true`
    /// - `claudestudio://group/Dev%20Team?autonomous=true`
    ///
    /// Returns `nil` when the URL is not a valid `claudestudio://` intent.
    static func fromURL(_ url: URL) -> LaunchIntent? {
        guard url.scheme == "claudestudio" else { return nil }

        let host = url.host(percentEncoded: false) ?? ""
        let pathName = url.pathComponents.count > 1 ? url.pathComponents[1] : ""
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []

        func queryValue(_ name: String) -> String? {
            queryItems.first(where: { $0.name == name })?.value
        }

        let mode: LaunchMode
        switch host {
        case "chat":
            mode = .chat
        case "agent":
            guard !pathName.isEmpty else { return nil }
            mode = .agent(name: pathName)
        case "group":
            guard !pathName.isEmpty else { return nil }
            mode = .group(name: pathName)
        default:
            return nil
        }

        return LaunchIntent(
            mode: mode,
            prompt: queryValue("prompt"),
            workingDirectory: queryValue("workdir"),
            autonomous: queryValue("autonomous") == "true"
        )
    }
}
