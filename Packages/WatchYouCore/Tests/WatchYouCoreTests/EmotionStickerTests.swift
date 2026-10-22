import XCTest
@testable import WatchYouCore

final class EmotionStickerTests: XCTestCase {
    func testInsufficientUsesCalm() {
        XCTAssertEqual(emotionStickerKind(for: nil), .calm)
        XCTAssertEqual(
            emotionStickerKind(for: AIEmotion(
                status: "insufficient",
                label: "暂无法判断",
                arousal: "unknown",
                valence: "unknown",
                evidenceStrength: nil
            )),
            .calm
        )
        XCTAssertEqual(emotionStickerKind(status: nil, label: "等待分析"), .calm)
        XCTAssertEqual(emotionStickerKind(status: "insufficient", label: "待更新"), .calm)
        XCTAssertFalse(emotionStickerPlays(nil))
    }

    func testPhysiologyLabels() {
        XCTAssertEqual(emotionStickerKind(status: "estimated", label: "可能偏平稳", arousal: "low", valence: "unknown"), .calm)
        XCTAssertEqual(emotionStickerKind(status: "estimated", label: "可能偏紧绷", arousal: "moderate", valence: "unknown"), .nervous)
        XCTAssertEqual(emotionStickerKind(status: "estimated", label: "可能偏活跃", arousal: "high", valence: "unknown"), .happy)
    }

    func testContextLabels() {
        XCTAssertEqual(emotionStickerKind(status: "estimated", label: "有些开心", arousal: "moderate", valence: "positive"), .happy)
        XCTAssertEqual(emotionStickerKind(status: "estimated", label: "略感低落", arousal: "low", valence: "negative"), .sad)
        XCTAssertEqual(emotionStickerKind(status: "estimated", label: "有点紧张", arousal: "moderate", valence: "unknown"), .nervous)
        XCTAssertEqual(emotionStickerKind(status: "estimated", label: "有些困倦", arousal: "low", valence: "unknown"), .sleepy)
        XCTAssertEqual(emotionStickerKind(status: "estimated", label: "有些烦躁", arousal: "high", valence: "negative"), .angry)
    }

    func testAxesFallback() {
        XCTAssertEqual(emotionStickerKind(status: "estimated", label: "当前倾向", arousal: "low", valence: "negative"), .sad)
        XCTAssertEqual(emotionStickerKind(status: "estimated", label: "当前倾向", arousal: "high", valence: "negative"), .angry)
        XCTAssertEqual(emotionStickerKind(status: "estimated", label: "当前倾向", arousal: "high", valence: "positive"), .happy)
        XCTAssertEqual(emotionStickerKind(status: "estimated", label: "当前倾向", arousal: "moderate", valence: "unknown"), .nervous)
    }

    func testEstimatedPlays() {
        let emotion = AIEmotion(
            status: "estimated",
            label: "可能偏平稳",
            arousal: "low",
            valence: "unknown",
            evidenceStrength: "有限 · 未校准"
        )
        XCTAssertTrue(emotionStickerPlays(emotion))
        XCTAssertEqual(emotionStickerKind(for: emotion), .calm)
    }
}
