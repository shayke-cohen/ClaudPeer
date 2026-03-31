import Foundation

enum BlackboardInspectorScope: String, CaseIterable, Identifiable {
    case relevant = "Relevant"
    case all = "All"

    var id: String { rawValue }
}

struct BlackboardSnapshotEntry: Equatable, Sendable, Identifiable, Decodable {
    let key: String
    let value: String
    let writtenBy: String
    let workspaceId: String?
    let createdAt: Date
    let updatedAt: Date

    var id: String { key }

    private enum CodingKeys: String, CodingKey {
        case key
        case value
        case writtenBy
        case workspaceId
        case createdAt
        case updatedAt
    }

    init(
        key: String,
        value: String,
        writtenBy: String,
        workspaceId: String?,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.key = key
        self.value = value
        self.writtenBy = writtenBy
        self.workspaceId = workspaceId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        value = try container.decode(BlackboardSnapshotValue.self, forKey: .value).rawString
        writtenBy = try container.decodeIfPresent(String.self, forKey: .writtenBy) ?? "unknown"
        workspaceId = try container.decodeIfPresent(String.self, forKey: .workspaceId)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

enum BlackboardSnapshotClientError: Error, Equatable, LocalizedError {
    case sidecarUnavailable
    case invalidResponse
    case requestFailed(statusCode: Int)
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .sidecarUnavailable:
            return "The sidecar blackboard is unavailable right now."
        case .invalidResponse:
            return "The sidecar returned an invalid response."
        case .requestFailed(let statusCode):
            return "The sidecar blackboard request failed with status \(statusCode)."
        case .decodingFailed:
            return "The blackboard response could not be decoded."
        }
    }
}

struct BlackboardSnapshotClient {
    let baseURL: URL
    var session: URLSession = .shared

    static func live(port: Int, session: URLSession = .shared) -> BlackboardSnapshotClient? {
        guard port > 0, let baseURL = URL(string: "http://127.0.0.1:\(port)") else {
            return nil
        }
        return BlackboardSnapshotClient(baseURL: baseURL, session: session)
    }

    func fetchAllEntries() async throws -> [BlackboardSnapshotEntry] {
        var components = URLComponents(
            url: baseURL.appending(path: "blackboard/query"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "pattern", value: "*")]

        guard let url = components?.url else {
            throw BlackboardSnapshotClientError.invalidResponse
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw BlackboardSnapshotClientError.sidecarUnavailable
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw BlackboardSnapshotClientError.invalidResponse
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw BlackboardSnapshotClientError.requestFailed(statusCode: httpResponse.statusCode)
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                let value = try container.decode(String.self)

                if let date = Self.parseISO8601(value) {
                    return date
                }

                throw BlackboardSnapshotClientError.decodingFailed
            }
            let entries = try decoder.decode([BlackboardSnapshotEntry].self, from: data)
            return entries.sorted { lhs, rhs in
                lhs.updatedAt > rhs.updatedAt
            }
        } catch {
            throw BlackboardSnapshotClientError.decodingFailed
        }
    }

    private static func parseISO8601(_ value: String) -> Date? {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: value) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

enum BlackboardSnapshotFilter {
    static func filteredEntries(
        _ entries: [BlackboardSnapshotEntry],
        scope: BlackboardInspectorScope,
        searchText: String,
        relevantKeys: Set<String>,
        relevantWriters: Set<String>
    ) -> [BlackboardSnapshotEntry] {
        let scopedEntries: [BlackboardSnapshotEntry]
        switch scope {
        case .all:
            scopedEntries = entries
        case .relevant:
            scopedEntries = entries.filter { entry in
                isRelevant(entry, relevantKeys: relevantKeys, relevantWriters: relevantWriters)
            }
        }

        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSearch.isEmpty else { return scopedEntries }

        return scopedEntries.filter { entry in
            matchesSearch(entry: entry, searchText: trimmedSearch)
        }
    }

    static func isRelevant(
        _ entry: BlackboardSnapshotEntry,
        relevantKeys: Set<String>,
        relevantWriters: Set<String>
    ) -> Bool {
        relevantKeys.contains(entry.key) || relevantWriters.contains(entry.writtenBy.lowercased())
    }

    private static func matchesSearch(entry: BlackboardSnapshotEntry, searchText: String) -> Bool {
        let needle = searchText.lowercased()
        return entry.key.lowercased().contains(needle)
            || entry.writtenBy.lowercased().contains(needle)
            || entry.value.lowercased().contains(needle)
    }
}

private enum BlackboardSnapshotValue: Decodable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: BlackboardSnapshotValue])
    case array([BlackboardSnapshotValue])
    case null

    var rawString: String {
        switch self {
        case .string(let value):
            return value
        default:
            return jsonString
        }
    }

    private var jsonString: String {
        guard let data = try? JSONSerialization.data(withJSONObject: foundationValue, options: []),
              let string = String(data: data, encoding: .utf8) else {
            return String(describing: foundationValue)
        }
        return string
    }

    private var foundationValue: Any {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            return value
        case .bool(let value):
            return value
        case .object(let value):
            return value.mapValues(\.foundationValue)
        case .array(let value):
            return value.map(\.foundationValue)
        case .null:
            return NSNull()
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else if let boolValue = try? container.decode(Bool.self) {
            self = .bool(boolValue)
        } else if let intValue = try? container.decode(Int.self) {
            self = .number(Double(intValue))
        } else if let doubleValue = try? container.decode(Double.self) {
            self = .number(doubleValue)
        } else if let objectValue = try? container.decode([String: BlackboardSnapshotValue].self) {
            self = .object(objectValue)
        } else if let arrayValue = try? container.decode([BlackboardSnapshotValue].self) {
            self = .array(arrayValue)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported blackboard value payload."
            )
        }
    }
}
