import XCTest
@testable import WatchYouCore

final class ScoreTests: XCTestCase {
    // PRD §14.1 worked example: T=446, W=18, G=480, |Δ|=18 → S=92.
    func testSleepFixtureRoundsTo92() {
        let s = sleepScore(asleepMinutes: 446, awakeMinutes: 18)
        XCTAssertEqual(s?.value, 92)
        XCTAssertEqual(s?.continuity ?? 0, 96.12, accuracy: 0.01)
    }

    func testSleepAbstainsWithoutBaseline() {
        XCTAssertNil(sleepScore(asleepMinutes: 446, awakeMinutes: 18, validNights: 3))
        XCTAssertNil(sleepScore(asleepMinutes: 446, awakeMinutes: 18, coverage: 0.4))
        XCTAssertNil(sleepScore(asleepMinutes: 0, awakeMinutes: 18))
    }

    // PRD §14.2 worked example: HRV=54, RHR=56, S=92 → Q=83.
    func testRecoveryFixtureRoundsTo83() {
        let r = recoveryScore(hrv: 54, restingHeartRate: 56, sleepScoreValue: 92)
        XCTAssertEqual(r?.value, 83)
    }

    func testRecoveryAbstainsWithoutFourteenDays() {
        XCTAssertNil(recoveryScore(hrv: 54, restingHeartRate: 56, sleepScoreValue: 92, validDays: 7))
        XCTAssertNil(recoveryScore(hrv: .nan, restingHeartRate: 56, sleepScoreValue: 92))
        XCTAssertNil(recoveryScore(hrv: 54, restingHeartRate: 56, sleepScoreValue: 92, rhrValidDays: 0))
        XCTAssertNil(recoveryScore(hrv: 54, restingHeartRate: 56, sleepScoreValue: 92, rhrValidDays: 13))
    }

    func testTrainingLoadNeedsRPE() {
        XCTAssertNil(trainingLoad(minutes: 32, rpe: nil))
        XCTAssertEqual(trainingLoad(minutes: 32, rpe: 3), 96)
        XCTAssertNil(trainingLoad(minutes: 32, rpe: 11))
    }

    func testDeterminismSameInputSameOutput() {
        let a = recoveryScore(hrv: 54, restingHeartRate: 56, sleepScoreValue: 92)
        let b = recoveryScore(hrv: 54, restingHeartRate: 56, sleepScoreValue: 92)
        XCTAssertEqual(a, b)
    }
}
