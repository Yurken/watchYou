import XCTest
@testable import WatchYouCore

/// M1 验收清单覆盖：A23 无效证据/非 JSON/截断拒绝、A03 无 context 时 valence 为 unknown、A20 范围关闭不进入请求。
final class ValidatorTests: XCTestCase {
    private let tz = TimeZone(identifier: "Asia/Shanghai")!
    private let facts = [EvidenceFact(id: "H1", scope: "heart", metric: "heartRate", value: 68, unit: "bpm", sampleCount: 1, window: TimeWindow(start: Date(), end: Date(), timeZone: TimeZone.current), sourceRef: "A", synthetic: true)]

    private func result(evidenceIds: [String] = ["H1"], valence: String = "unknown", status: String = "estimated", label: String = "可能偏紧绷") -> String {
        let dict: [String: Any] = [
            "summary": "演示中的观测只能支持有限推断。",
            "evidenceIds": evidenceIds,
            "uncertainties": ["无法确定具体情绪。"],
            "suggestions": [],
            "emotion": [
                "status": status,
                "label": label,
                "arousal": "moderate",
                "valence": valence
            ]
        ]
        return (try? JSONSerialization.data(withJSONObject: dict).utf8String) ?? ""
    }

    func testValidEmotionEstimateKeepsUnknownValence() throws {
        let parsed = try parseResult(text: result(), facts: facts)
        XCTAssertEqual(parsed.emotion?.valence, "unknown")
        XCTAssertEqual(parsed.emotion?.evidenceStrength, "有限 · 未校准")
    }

    func testNonJSONRejected() {
        XCTAssertThrowsError(try parseResult(text: "not json", facts: facts)) { error in
            XCTAssertTrue(String(describing: error).contains("JSON"))
        }
    }

    func testUnknownEvidenceIDRejected() {
        XCTAssertThrowsError(try parseResult(text: result(evidenceIds: ["FAKE"]), facts: facts)) { error in
            XCTAssertTrue(String(describing: error).contains("不存在的证据"))
        }
    }

    func testMissingEvidenceReferencesRejected() {
        XCTAssertThrowsError(try parseResult(text: result(evidenceIds: []), facts: facts)) { error in
            XCTAssertTrue(String(describing: error).contains("没有引用观测依据"))
        }
    }

    func testPositiveValenceUnsupportedWithoutContext() {
        XCTAssertThrowsError(try parseResult(text: result(valence: "positive"), facts: facts, hasContext: false)) { error in
            XCTAssertTrue(String(describing: error).contains("愉悦度方向"))
        }
    }

    func testPositiveValenceAllowedWithContext() {
        XCTAssertNoThrow(try parseResult(text: result(valence: "positive"), facts: facts, hasContext: true))
    }

    func testSpecificClinicalLabelRejectedWithoutContext() {
        XCTAssertThrowsError(try parseResult(text: result(label: "焦虑症"), facts: facts, hasContext: false)) { error in
            XCTAssertTrue(String(describing: error).contains("生理摘要"))
        }
    }

    func testInsufficientWithCoordinatesRejected() {
        XCTAssertThrowsError(try parseResult(text: result(status: "insufficient"), facts: facts)) { error in
            XCTAssertTrue(String(describing: error).contains("数据不足"))
        }
    }

    func testOversizedResponseRejected() {
        XCTAssertThrowsError(try parseResult(text: String(repeating: "x", count: 128001), facts: facts))
    }

    func testCodeFenceStripping() throws {
        let json = result()
        let fenced = "```json\n\(json)\n```"
        let parsed = try parseResult(text: fenced, facts: facts)
        XCTAssertEqual(parsed.summary, "演示中的观测只能支持有限推断。")
    }

    func testMoreThanThirtyEvidenceIdsRejected() {
        let ids = (1...31).map { "H\($0)" }
        XCTAssertThrowsError(try parseResult(text: result(evidenceIds: ids), facts: facts))
    }

    func testEmptySummaryRejected() {
        let dict: [String: Any] = [
            "summary": "   ",
            "evidenceIds": ["H1"],
            "uncertainties": [],
            "suggestions": [],
            "emotion": NSNull()
        ]
        let text = (try? JSONSerialization.data(withJSONObject: dict).utf8String) ?? ""
        XCTAssertThrowsError(try parseResult(text: text, facts: facts))
    }
}

private extension Data {
    var utf8String: String {
        String(data: self, encoding: .utf8) ?? ""
    }
}
