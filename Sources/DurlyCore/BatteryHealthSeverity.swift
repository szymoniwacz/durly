import Foundation

// Presentation levels, not a diagnosis or hardware safety policy.
public enum BatteryHealthSeverity: Equatable {
    case normal, warning, service, unknown

    public static func classify(_ condition: String?) -> Self {
        guard let value = condition?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !value.isEmpty else { return .unknown }
        switch value {
        case "normal", "good": return .normal
        case "check battery", "replace soon", "fair": return .warning
        case "service recommended", "service battery", "poor", "replace now": return .service
        default: return .unknown
        }
    }
}
