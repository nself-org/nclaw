import Foundation

/// Server connection configuration.
struct ServerConfig: Codable, Equatable {
    var serverURL: String
    var port: Int

    static let defaultConfig = ServerConfig(
        serverURL: "wss://api.nself.org/claw/ws",
        port: 7710
    )
}
