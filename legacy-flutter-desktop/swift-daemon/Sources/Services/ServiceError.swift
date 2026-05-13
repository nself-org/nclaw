import Foundation

enum ServiceError: Error, LocalizedError {
    case pathOutsideSandbox(String)
    case fileNotFound(String)
    case permissionDenied(String)
    case operationFailed(String)
    case userDenied
    case notImplemented

    var errorDescription: String? {
        switch self {
        case .pathOutsideSandbox(let path):
            return "Path is outside the allowed sandbox: \(path)"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .permissionDenied(let reason):
            return "Permission denied: \(reason)"
        case .operationFailed(let reason):
            return "Operation failed: \(reason)"
        case .userDenied:
            return "User denied the operation"
        case .notImplemented:
            return "Not implemented"
        }
    }
}
