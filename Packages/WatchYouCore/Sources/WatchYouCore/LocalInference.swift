import Foundation

/// Local, deterministic explanations used when the user has not enabled a live model.
/// Always labeled as a rule summary — never presented as a model success.
public func localInference(
    task: String,
    snapshot: HealthSnapshot,
    facts: [EvidenceFact],
    question: String?
) -> AIResult {
    let ids = facts.prefix(4).map(\.id)
    let sleepLabel = snapshot.lastNight.map { formatDurationMinutes($0.asleepMinutes) }
    let hrLabel = snapshot.latestHeartRate?.value.map { "\(Int($0.rounded())) 次/分" }
    let recoveryLabel = snapshot.recoveryScore.map { "\($0.value)" }

    var summary: String
    var suggestions: [String] = ["先观察连续几天的趋势，再作小幅调整。"]
    var emotion: AIEmotion?

    switch task {
    case "today":
        if snapshot.isEmpty {
            summary = "还没有可读的健康摘要。接入健康数据后，会在这里解释睡眠、活动与状态变化。"
        } else {
            var parts: [String] = []
            if let sleepLabel {
                parts.append("昨夜睡眠 \(sleepLabel)")
            }
            if let hrLabel {
                parts.append("最近心率 \(hrLabel)")
            }
            if let recoveryLabel {
                parts.append("恢复参考 \(recoveryLabel)")
            }
            summary = parts.isEmpty
                ? "已读取部分记录，但还不足以形成今日摘要。"
                : parts.joined(separator: "；") + "。这是本地规则摘要，不是模型推断。"
        }
    case "mood":
        emotion = localMood(snapshot: snapshot, hasContext: facts.contains { $0.scope == "context" })
        summary = emotion?.status == "insufficient"
            ? "当前条件不足以估计情绪倾向，保留未知。"
            : "近期生理信号\(emotion?.label ?? "暂无法判断")。仅凭这些信号还不能判断情绪正负向。"
        suggestions = ["停下来做一分钟自然呼吸，再观察自己的状态。"]
    case "sleep":
        if let night = snapshot.lastNight {
            let gap = max(0, 480 - Int(night.asleepMinutes.rounded()))
            summary = "昨夜睡眠 \(formatDurationMinutes(night.asleepMinutes))。关注作息规律比单独追求深睡比例更有价值。"
            if gap > 0 { summary += "距离常见 8 小时参考还差 \(gap) 分钟，这不是医学目标。" }
        } else {
            summary = "没有昨夜睡眠记录，不推算分期或分数。"
        }
    case "heart":
        summary = "夜间 HRV 与日间单次 HRV 对应不同采样情境，不应直接比较高低。把近期数据放回相近时段的个人基线中理解。"
    case "recovery":
        if let score = snapshot.recoveryScore {
            summary = "恢复参考 \(score.value) 来自睡眠、夜间 HRV 与静息心率的本地计算。解释变化，不重写分数，也不据此批准高强度运动。"
        } else {
            summary = "恢复参考缺少足够基线或输入，不输出总分。"
        }
    case "activity":
        if let workout = snapshot.workouts.first {
            summary = "最近一次「\(workout.activity)」\(Int(workout.durationMinutes.rounded())) 分钟。可以结合今天的体感安排轻量活动；当前摘要不足以开出训练处方。"
        } else {
            summary = "还没有已完成的训练记录。缺少记录不等于没有活动。"
        }
    case "habits":
        summary = "先维持容易坚持的小习惯。已记录的饮水不等于实际全部摄入，也不应用一个固定目标替所有人作建议。"
    case "trends":
        if snapshot.sleepTrend.count >= 7 {
            let avg = snapshot.sleepTrend.map(\.asleepMinutes).reduce(0, +) / Double(snapshot.sleepTrend.count)
            summary = "近 \(snapshot.sleepTrend.count) 个有效夜晚的睡眠均值为 \(formatDurationMinutes(avg))。没有足量、可对齐的情绪数据时，不编造相关系数。"
        } else {
            summary = "有效样本还少，只描述已有记录，不外推趋势。"
        }
    default:
        if let question, !question.isEmpty {
            summary = "可以结合已授权摘要解释睡眠、活动和状态变化。判断只是参考，不会把未知数据补成正常，也不会作医学诊断。"
        } else {
            summary = "围绕已授权摘要作解释。没有证据时保留未知。"
        }
    }

    return AIResult(
        summary: summary,
        evidenceIds: Array(ids),
        uncertainties: [
            "生理变化不是某种具体情绪的唯一证据。",
            "这是本地规则摘要，未调用外部模型。"
        ],
        suggestions: suggestions,
        emotion: task == "mood" ? emotion : nil
    )
}

private func localMood(snapshot: HealthSnapshot, hasContext: Bool) -> AIEmotion {
    if snapshot.isEmpty || (snapshot.nocturnalHRV == nil && snapshot.recentHRV == nil && snapshot.latestHeartRate == nil && !hasContext) {
        return AIEmotion(status: "insufficient", label: "暂无法判断", arousal: "unknown", valence: "unknown", evidenceStrength: nil)
    }
    if snapshot.duringWorkout {
        return AIEmotion(status: "insufficient", label: "暂无法判断", arousal: "unknown", valence: "unknown", evidenceStrength: nil)
    }

    let hrv = snapshot.recentHRV ?? snapshot.nocturnalHRV
    let baseline = snapshot.hrvBaseline
    var label = "可能偏平稳"
    var arousal = "unknown"
    if let hrv, let baseline, baseline > 0 {
        let ratio = hrv / baseline
        if ratio < 0.85 {
            label = "可能偏紧绷"
            arousal = "moderate"
        } else if ratio > 1.15 {
            label = "可能偏活跃"
            arousal = "high"
        } else {
            arousal = "low"
        }
    }
    return AIEmotion(
        status: "estimated",
        label: label,
        arousal: arousal,
        valence: "unknown",
        evidenceStrength: "有限 · 未校准"
    )
}