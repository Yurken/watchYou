import Foundation

/// Stable metric identifiers used in samples, evidence and UI.
public enum Metric {
    public static let heartRate = "heartRate"
    public static let restingHeartRate = "restingHeartRate"
    public static let hrvSDNN = "hrvSDNN"
    public static let stepCount = "stepCount"
    public static let activeEnergy = "activeEnergy"
    public static let exerciseMinutes = "exerciseMinutes"
    public static let sleepCore = "sleep.core"
    public static let sleepDeep = "sleep.deep"
    public static let sleepREM = "sleep.rem"
    public static let sleepUnspecified = "sleep.unspecified"
    public static let sleepAwake = "sleep.awake"
    public static let sleepInBed = "sleep.inBed"

    public static let sleepMetrics: Set<String> = [
        sleepCore, sleepDeep, sleepREM, sleepUnspecified, sleepAwake, sleepInBed
    ]
}

public enum SleepStage: String, Equatable, Sendable, Codable, CaseIterable {
    case core
    case deep
    case rem
    case unspecified
    case awake
    case inBed

    public var isAsleep: Bool {
        switch self {
        case .core, .deep, .rem, .unspecified: return true
        case .awake, .inBed: return false
        }
    }

    public var label: String {
        switch self {
        case .core: return "核心睡眠"
        case .deep: return "深度睡眠"
        case .rem: return "快速眼动"
        case .unspecified: return "未细分睡眠"
        case .awake: return "清醒"
        case .inBed: return "在床"
        }
    }

    public var metric: String {
        switch self {
        case .core: return Metric.sleepCore
        case .deep: return Metric.sleepDeep
        case .rem: return Metric.sleepREM
        case .unspecified: return Metric.sleepUnspecified
        case .awake: return Metric.sleepAwake
        case .inBed: return Metric.sleepInBed
        }
    }

    public static func from(metric: String) -> SleepStage? {
        switch metric {
        case Metric.sleepCore: return .core
        case Metric.sleepDeep: return .deep
        case Metric.sleepREM: return .rem
        case Metric.sleepUnspecified: return .unspecified
        case Metric.sleepAwake: return .awake
        case Metric.sleepInBed: return .inBed
        default: return nil
        }
    }
}

public let sourcePolicyVersion = "source-policy-v1"
public let promptVersion = "watchyou.prompt.v1"
public let appBackupSchema = "watchyou.app.v1"

public func median(_ values: [Double]) -> Double? {
    let sorted = values.filter(\.isFinite).sorted()
    guard !sorted.isEmpty else { return nil }
    let mid = sorted.count / 2
    if sorted.count % 2 == 0 {
        return (sorted[mid - 1] + sorted[mid]) / 2
    }
    return sorted[mid]
}

public func minutesFromMidnight(_ date: Date, timeZone: TimeZone) -> Double {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let components = calendar.dateComponents([.hour, .minute, .second], from: date)
    return Double((components.hour ?? 0) * 60 + (components.minute ?? 0)) + Double(components.second ?? 0) / 60
}

public func circularMeanMinutes(_ values: [Double]) -> Double? {
    guard !values.isEmpty else { return nil }
    let tau = 2 * Double.pi
    let period = 24.0 * 60
    let x = values.map { cos($0 / period * tau) }.reduce(0, +) / Double(values.count)
    let y = values.map { sin($0 / period * tau) }.reduce(0, +) / Double(values.count)
    var angle = atan2(y, x)
    if angle < 0 { angle += tau }
    return angle / tau * period
}

public func circularDeltaMinutes(_ a: Double, _ b: Double) -> Double {
    let period = 24.0 * 60
    let delta = abs(a - b).truncatingRemainder(dividingBy: period)
    return min(delta, period - delta)
}

public func formatDurationMinutes(_ minutes: Double) -> String {
    guard minutes.isFinite, minutes >= 0 else { return "—" }
    let total = Int(minutes.rounded())
    let hours = total / 60
    let mins = total % 60
    if hours == 0 { return "\(mins) 分" }
    if mins == 0 { return "\(hours) 小时" }
    return "\(hours) 小时 \(mins) 分"
}

public func clamp(_ value: Double, _ lo: Double, _ hi: Double) -> Double {
    min(hi, max(lo, value))
}