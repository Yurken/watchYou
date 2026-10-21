import Foundation

// Deterministic experimental scores mirroring PRD §14.
// These are product heuristics under test, not medical instruments.
// Same inputs + same version must reproduce the same result.

public enum ScoreError: Error {
    case invalidInput
}

public struct SleepScore: Equatable {
    public let value: Int
    public let duration: Double
    public let regularity: Double
    public let continuity: Double
    public static let version = "sleep-experimental-0.1"
}

/// S = round(0.50D + 0.25R + 0.25C); returns nil when conditions are unmet
/// (nil, never 0) so missing data is never displayed as a perfect/nil score.
public func sleepScore(
    asleepMinutes: Double,
    awakeMinutes: Double,
    goalMinutes: Double = 480,
    midpointDeviationMinutes: Double = 18,
    validNights: Int = 28,
    coverage: Double = 1
) -> SleepScore? {
    let inputs = [asleepMinutes, awakeMinutes, goalMinutes, midpointDeviationMinutes, coverage]
    guard inputs.allSatisfy(\.isFinite), asleepMinutes > 0, awakeMinutes >= 0,
          goalMinutes > 0, validNights >= 7, coverage >= 0.8
    else { return nil }
    let d = 100 * min(asleepMinutes / goalMinutes, 1)
    let r = 100 * max(0, 1 - abs(midpointDeviationMinutes) / 120)
    let c = 100 * asleepMinutes / (asleepMinutes + awakeMinutes)
    return SleepScore(
        value: Int((0.5 * d + 0.25 * r + 0.25 * c).rounded()),
        duration: d, regularity: r, continuity: c
    )
}

public struct RecoveryScore: Equatable {
    public let value: Int
    public let hrvPart: Double
    public let rhrPart: Double
    public let sleepPart: Double
    public static let version = "recovery-experimental-0.1"
}

/// Q = round(clip(65 + 12zH − 8zR + 0.20(S−70), 0, 100)).
/// Baseline uses days BEFORE the current day; callers must not leak today in.
public func recoveryScore(
    hrv: Double,
    restingHeartRate: Double,
    sleepScoreValue: Double,
    baselineHRV: Double = 48,
    baselineRHR: Double = 58,
    logHRVScale: Double = 0.18,
    rhrScale: Double = 3,
    validDays: Int = 28
) -> RecoveryScore? {
    let inputs = [hrv, restingHeartRate, sleepScoreValue, baselineHRV, baselineRHR, logHRVScale, rhrScale]
    guard inputs.allSatisfy(\.isFinite), hrv > 0, baselineHRV > 0,
          logHRVScale > 0, rhrScale > 0, validDays >= 14
    else { return nil }
    func clip(_ x: Double) -> Double { min(3, max(-3, x)) }
    let zH = clip((log(hrv) - log(baselineHRV)) / logHRVScale)
    let zR = clip((restingHeartRate - baselineRHR) / rhrScale)
    let raw = 65 + 12 * zH - 8 * zR + 0.20 * (sleepScoreValue - 70)
    return RecoveryScore(
        value: Int(min(100, max(0, raw)).rounded()),
        hrvPart: 12 * zH, rhrPart: -8 * zR, sleepPart: 0.20 * (sleepScoreValue - 70)
    )
}

/// Training load = minutes × RPE in arbitrary units; nil unless both exist
/// (no RPE → no number, never a fabricated default).
public func trainingLoad(minutes: Double, rpe: Int?) -> Int? {
    guard let rpe, minutes.isFinite, minutes > 0, minutes <= 1440,
          (0...10).contains(rpe) else { return nil }
    return Int((minutes * Double(rpe)).rounded())
}
