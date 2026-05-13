import Foundation

/// Outer envelope for messages received from nself-claw server.
/// Actual format: {"seq":N,"type":"action","payload":{"type":"action","action":{...}},"ts":N}
struct ServerMessage: Codable {
    let type: String
    let payload: Payload?

    struct Payload: Codable {
        let action: Action?
    }
}

/// Action dispatched from the nself-claw server to this daemon.
/// Server format:
/// {"id":"<uuid>","action_type":"file_op","params":{...},"session_id":null}
struct Action: Codable, Identifiable {
    let id: String
    let action_type: String
    let params: [String: AnyCodable]?
    let session_id: String?

    /// Convenience: get a param value as String
    func param(_ key: String) -> String? {
        params?[key]?.stringValue
    }

    enum ActionStatus: String, Codable {
        case pending
        case running
        case completed
        case failed
        case denied
    }
}

/// AnyCodable wraps arbitrary JSON values so params can hold mixed types.
struct AnyCodable: Codable {
    let value: Any

    var stringValue: String? {
        if let s = value as? String { return s }
        if let n = value as? NSNumber { return n.stringValue }
        return nil
    }

    init(_ value: Any) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) { value = s; return }
        if let n = try? container.decode(Double.self) { value = n; return }
        if let b = try? container.decode(Bool.self) { value = b; return }
        if let a = try? container.decode([AnyCodable].self) { value = a; return }
        if let d = try? container.decode([String: AnyCodable].self) { value = d; return }
        value = NSNull()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let s as String: try container.encode(s)
        case let n as Double: try container.encode(n)
        case let b as Bool: try container.encode(b)
        case let a as [AnyCodable]: try container.encode(a)
        case let d as [String: AnyCodable]: try container.encode(d)
        default: try container.encodeNil()
        }
    }
}

/// Response sent back to the server after handling an action.
struct ActionResponse: Codable {
    let type: String
    let action_id: String
    let success: Bool
    let result: String?
    let error: String?
}
