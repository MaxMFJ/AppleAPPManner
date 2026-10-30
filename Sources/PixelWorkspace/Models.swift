import Foundation

enum Department: String, CaseIterable, Codable, Identifiable {
    case development = "开发", communication = "沟通", creative = "创作", system = "系统", other = "其他"
    var id: String { rawValue }
    var colorHex: UInt32 {
        switch self { case .development: 0x69B7FF; case .communication: 0xFFB45F; case .creative: 0xD391FF; case .system: 0x6ED6A4; case .other: 0xAAB4C5 }
    }
}

struct AppRule: Codable, Equatable {
    var bundleID: String
    var department: Department
}

struct ProcessRecord: Codable, Identifiable, Equatable {
    var id: String { bundleID + ":" + String(pid) }
    var bundleID: String
    var name: String
    var pid: Int32
    var department: Department
    var isFrontmost: Bool
    var cpuPercent: Double?
    var memoryBytes: UInt64?
    var deviceID: String
    var updatedAt: Date
}

struct DeviceSnapshot: Codable, Identifiable, Equatable {
    var id: String { deviceID }
    var deviceID: String
    var deviceName: String
    var capturedAt: Date
    var apps: [ProcessRecord]
}

enum WorkspaceMessage: Codable, Equatable {
    case snapshot(DeviceSnapshot)
    case upsert(ProcessRecord)
    case remove(deviceID: String, pid: Int32, bundleID: String)

    private enum Keys: String, CodingKey { case type, payload, deviceID, pid, bundleID }
    private enum MessageType: String, Codable { case snapshot, upsert, remove }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: Keys.self)
        switch try values.decode(MessageType.self, forKey: .type) {
        case .snapshot: self = .snapshot(try values.decode(DeviceSnapshot.self, forKey: .payload))
        case .upsert: self = .upsert(try values.decode(ProcessRecord.self, forKey: .payload))
        case .remove: self = .remove(deviceID: try values.decode(String.self, forKey: .deviceID), pid: try values.decode(Int32.self, forKey: .pid), bundleID: try values.decode(String.self, forKey: .bundleID))
        }
    }
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: Keys.self)
        switch self {
        case .snapshot(let snapshot): try values.encode(MessageType.snapshot, forKey: .type); try values.encode(snapshot, forKey: .payload)
        case .upsert(let record): try values.encode(MessageType.upsert, forKey: .type); try values.encode(record, forKey: .payload)
        case .remove(let deviceID, let pid, let bundleID):
            try values.encode(MessageType.remove, forKey: .type); try values.encode(deviceID, forKey: .deviceID); try values.encode(pid, forKey: .pid); try values.encode(bundleID, forKey: .bundleID)
        }
    }
}

struct WireEnvelope: Codable {
    var protocolVersion: Int
    var nonce: Data
    var ciphertext: Data
    var tag: Data
}

enum RuleStore {
    private static let key = "pixelworkspace.rules.v1"
    static func load() -> [String: Department] {
        guard let data = UserDefaults.standard.data(forKey: key), let rules = try? JSONDecoder().decode([AppRule].self, from: data) else { return [:] }
        return Dictionary(rules.map { ($0.bundleID, $0.department) }, uniquingKeysWith: { _, newest in newest })
    }
    static func save(_ rules: [String: Department]) {
        let values = rules.map { AppRule(bundleID: $0.key, department: $0.value) }
        if let data = try? JSONEncoder().encode(values) { UserDefaults.standard.set(data, forKey: key) }
    }
}

enum Classifier {
    static func department(for bundleID: String, name: String, rules: [String: Department]) -> Department {
        if let rule = rules[bundleID] { return rule }
        let value = (bundleID + " " + name).lowercased()
        if ["xcode", "terminal", "iterm", "visual studio", "code", "cursor", "docker", "postman"].contains(where: value.contains) { return .development }
        if ["mail", "messages", "slack", "teams", "wechat", "钉钉", "飞书", "zoom"].contains(where: value.contains) { return .communication }
        if ["photoshop", "figma", "sketch", "logic", "final cut", "music", "pixelmator"].contains(where: value.contains) { return .creative }
        if ["system", "settings", "activity monitor", "finder", "loginwindow"].contains(where: value.contains) { return .system }
        return .other
    }
}
