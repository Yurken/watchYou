import Foundation

/// Visual sticker for a mood estimate. Independent of the brand mark.
public enum EmotionStickerKind: String, Sendable, CaseIterable, Equatable {
    case happy
    case calm
    case sad
    case angry
    case nervous
    case sleepy
}

/// Maps a validated emotion to one of six sticker poses.
/// Insufficient or empty results use the resting calm pose; they do not invent a mood.
public func emotionStickerKind(for emotion: AIEmotion?) -> EmotionStickerKind {
    emotionStickerKind(
        status: emotion?.status,
        label: emotion?.label,
        arousal: emotion?.arousal,
        valence: emotion?.valence
    )
}

public func emotionStickerKind(
    status: String?,
    label: String?,
    arousal: String? = nil,
    valence: String? = nil
) -> EmotionStickerKind {
    let status = status ?? "insufficient"
    let label = label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if status == "insufficient"
        || label.isEmpty
        || label == "暂无法判断"
        || label == "等待分析"
        || label == "等待 AI 分析"
        || label == "待更新" {
        return .calm
    }

    switch label {
    case "可能偏平稳": return .calm
    case "可能偏紧绷": return .nervous
    case "可能偏活跃": return .happy
    default: break
    }

    if let matched = stickerKindMatchingLabel(label) {
        return matched
    }

    return stickerKindFromAxes(arousal: arousal ?? "unknown", valence: valence ?? "unknown")
}

public func emotionStickerPlays(_ emotion: AIEmotion?) -> Bool {
    emotion?.status == "estimated"
}

private func stickerKindMatchingLabel(_ label: String) -> EmotionStickerKind? {
    let groups: [(EmotionStickerKind, [String])] = [
        (.sleepy, ["困倦", "疲惫", "疲倦", "嗜睡", "很累"]),
        (.angry, ["生气", "愤怒", "恼火", "烦躁", "发火"]),
        (.sad, ["低落", "难过", "悲伤", "沮丧", "难受", "伤心"]),
        (.nervous, ["紧张", "焦虑", "不安", "紧绷", "担心"]),
        (.happy, ["开心", "高兴", "愉悦", "快乐", "积极", "不错"]),
        (.calm, ["平静", "平稳", "放松", "安定"]),
    ]
    for (kind, keys) in groups {
        if keys.contains(where: { label.contains($0) }) {
            return kind
        }
    }
    return nil
}

private func stickerKindFromAxes(arousal: String, valence: String) -> EmotionStickerKind {
    switch (valence, arousal) {
    case ("positive", "low"): return .calm
    case ("positive", _): return .happy
    case ("negative", "low"): return .sad
    case ("negative", "high"): return .angry
    case ("negative", _): return .nervous
    case (_, "low"): return .calm
    case (_, "high"), (_, "moderate"): return .nervous
    default: return .calm
    }
}
