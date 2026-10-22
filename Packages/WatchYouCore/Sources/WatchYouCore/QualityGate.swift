import Foundation

public let taskScopeNeeds: [String: [String]] = [
    "today": AIDataScopes,
    "mood": ["sleep", "heart", "activity", "context"],
    "sleep": ["sleep", "heart"],
    "heart": ["heart", "activity"],
    "recovery": ["sleep", "heart", "activity"],
    "activity": ["sleep", "heart", "activity"],
    "habits": ["sleep", "habits", "activity"],
    "trends": ["sleep", "heart", "activity", "habits", "context"],
    "assistant": AIDataScopes
]

/// Returns a user-facing reason to skip inference, or nil when the task may run.
public func qualityGate(
    task: String,
    snapshot: HealthSnapshot,
    config: AIConfig,
    facts: [EvidenceFact],
    hasContext: Bool,
    now: Date
) -> String? {
    if config.modules[task] == false {
        return "此 AI 功能已关闭"
    }
    if task != "habits" && task != "assistant" && snapshot.isEmpty {
        return "暂无数据"
    }
    if task == "mood" || task == "recovery" {
        if snapshot.duringWorkout {
            return "正在运动或刚结束运动，暂不比较静息状态"
        }
        if snapshot.baselineNights < 5 && snapshot.hrvValidDays < 5 {
            return "正在建立基线"
        }
    }
    if task == "mood" {
        let recentHeart = snapshot.latestHeartRate.map { now.timeIntervalSince($0.window.end) <= 24 * 3600 } ?? false
        let recentHRV = snapshot.recentHRVAt.map { now.timeIntervalSince($0) <= 24 * 3600 } ?? false
        let nocturnal = snapshot.lastNight?.mainEnd.map { now.timeIntervalSince($0) <= 36 * 3600 } ?? false
        if !recentHeart && !recentHRV && !nocturnal && !hasContext {
            return "缺少近期数据"
        }
        if let sample = snapshot.latestHeartRate ?? snapshot.recentHRVAt.map({ _ in snapshot.latestHeartRate }) ?? nil,
           now.timeIntervalSince(sample.window.end) > 48 * 3600, !hasContext {
            return "数据过旧"
        }
    }
    if facts.isEmpty && task != "assistant" {
        return "暂无数据"
    }
    return nil
}

public func factsForTask(
    task: String,
    snapshot: HealthSnapshot,
    preferences: UserPreferences,
    events: [HabitEvent],
    contextNote: String,
    contextRecordedAt: Date? = nil,
    feedback: [UserFeedback] = [],
    allowedScopes: [String: Bool],
    now: Date
) -> [EvidenceFact] {
    let needed = Set(taskScopeNeeds[task] ?? AIDataScopes)
    var facts: [EvidenceFact] = []
    let tz = snapshot.timeZone
    let dayWindow = calendarDayWindow(containing: now, timeZone: tz)
    let window: TimeWindow = {
        if let night = snapshot.lastNight, let start = night.mainStart, let end = night.mainEnd, end >= start {
            return TimeWindow(start: start, end: end, timeZone: tz)
        }
        if let night = snapshot.lastNight {
            return calendarDayWindow(containing: night.day, timeZone: tz)
        }
        return dayWindow
    }()

    if needed.contains("sleep"), allowedScopes["sleep"] == true, let night = snapshot.lastNight {
        facts.append(EvidenceFact(
            id: "S1",
            scope: "sleep",
            metric: "睡眠时长",
            value: night.asleepMinutes,
            unit: "min",
            sampleCount: 1,
            window: window,
            sourceRef: night.sourceRef,
            synthetic: false,
            observedAt: night.mainEnd
        ))
        facts.append(EvidenceFact(
            id: "S2",
            scope: "sleep",
            metric: "个人睡眠目标",
            value: Double(preferences.sleepGoalMinutes),
            unit: "min",
            sampleCount: 1,
            window: window,
            sourceRef: "app",
            synthetic: false,
            observedAt: night.mainEnd
        ))
        if let score = snapshot.sleepScore {
            facts.append(EvidenceFact(
                id: "S3",
                scope: "sleep",
                metric: "睡眠参考分",
                value: Double(score.value),
                unit: "score",
                sampleCount: snapshot.baselineNights,
                window: window,
                sourceRef: "local",
                synthetic: false,
                observedAt: night.mainEnd
            ))
        }
    }

    if needed.contains("heart"), allowedScopes["heart"] == true {
        if let hr = snapshot.latestHeartRate, let value = hr.value {
            facts.append(EvidenceFact(
                id: "H1",
                scope: "heart",
                metric: "最近心率",
                value: value,
                unit: "bpm",
                sampleCount: 1,
                window: hr.window,
                sourceRef: hr.sourceRef,
                synthetic: false,
                observedAt: hr.window.end
            ))
        }
        if let hrv = snapshot.recentHRV, let at = snapshot.recentHRVAt {
            facts.append(EvidenceFact(
                id: "H2",
                scope: "heart",
                metric: "最近 HRV（SDNN）",
                value: hrv,
                unit: "ms",
                sampleCount: 1,
                window: TimeWindow(start: at, end: at, timeZone: tz),
                sourceRef: "health",
                synthetic: false,
                observedAt: at
            ))
        }
        if let baseline = snapshot.hrvBaseline {
            facts.append(EvidenceFact(
                id: "H3",
                scope: "heart",
                metric: "夜间 HRV 历史中位数",
                value: baseline,
                unit: "ms",
                sampleCount: snapshot.hrvValidDays,
                window: window,
                sourceRef: "local",
                synthetic: false,
                observedAt: snapshot.lastNight?.mainEnd
            ))
        }
        if let nocturnal = snapshot.nocturnalHRV {
            facts.append(EvidenceFact(
                id: "H4",
                scope: "heart",
                metric: "昨夜 HRV 中位数",
                value: nocturnal,
                unit: "ms",
                sampleCount: snapshot.nocturnalHRVSampleCount,
                window: window,
                sourceRef: "local",
                synthetic: false,
                observedAt: snapshot.lastNight?.mainEnd
            ))
        }
        if let rhr = snapshot.restingHeartRate {
            facts.append(EvidenceFact(
                id: "H5",
                scope: "heart",
                metric: "系统静息心率",
                value: rhr,
                unit: "bpm",
                sampleCount: 1,
                window: window,
                sourceRef: "health",
                synthetic: false,
                observedAt: snapshot.lastNight?.mainEnd
            ))
        }
    }

    if needed.contains("activity"), allowedScopes["activity"] == true {
        if let steps = snapshot.todaySteps {
            facts.append(EvidenceFact(
                id: "A1",
                scope: "activity",
                metric: "今日步数",
                value: steps,
                unit: "steps",
                sampleCount: 1,
                window: dayWindow,
                sourceRef: "health",
                synthetic: false,
                observedAt: snapshot.todayStepsObservedAt
            ))
        }
        if let workout = snapshot.workouts.first {
            facts.append(EvidenceFact(
                id: "A2",
                scope: "activity",
                metric: "最近一次训练时长",
                value: workout.durationMinutes,
                unit: "min",
                sampleCount: 1,
                window: workout.window,
                sourceRef: workout.sourceRef,
                synthetic: false,
                observedAt: workout.window.end
            ))
        }
        if let recovery = snapshot.recoveryScore {
            facts.append(EvidenceFact(
                id: "A3",
                scope: "activity",
                metric: "恢复参考分",
                value: Double(recovery.value),
                unit: "score",
                sampleCount: snapshot.hrvValidDays,
                window: window,
                sourceRef: "local",
                synthetic: false,
                observedAt: snapshot.lastNight?.mainEnd
            ))
        }
    }

    if needed.contains("habits"), allowedScopes["habits"] == true {
        let water = waterTotal(events: events, day: now, timeZone: tz)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz
        let waterObserved = events
            .filter { $0.kind == "water" && calendar.startOfDay(for: $0.createdAt) == dayWindow.start }
            .map(\.createdAt)
            .max()
        facts.append(EvidenceFact(
            id: "L1",
            scope: "habits",
            metric: "已记录饮水",
            value: water,
            unit: "ml",
            sampleCount: events.filter { $0.kind == "water" }.count,
            window: dayWindow,
            sourceRef: "app",
            synthetic: false,
            observedAt: waterObserved
        ))
    }

    if needed.contains("sleep"), allowedScopes["sleep"] == true, task == "trends" {
        let trend = snapshot.sleepTrend.filter { $0.asleepMinutes > 0 }
        if !trend.isEmpty {
            let avg = trend.map(\.asleepMinutes).reduce(0, +) / Double(trend.count)
            let lastNight = trend.last!
            let trendEnd = lastNight.mainEnd ?? calendarDayWindow(containing: lastNight.day, timeZone: tz).end
            facts.append(EvidenceFact(
                id: "T1",
                scope: "sleep",
                metric: "近期睡眠平均",
                value: avg,
                unit: "min",
                sampleCount: trend.count,
                window: TimeWindow(start: trend.first!.day, end: trendEnd, timeZone: tz),
                sourceRef: "local",
                synthetic: false,
                observedAt: lastNight.mainEnd
            ))
        }
    }

    if needed.contains("context"), allowedScopes["context"] == true {
        let trimmed = contextNote.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, let recorded = contextRecordedAt {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = tz
            if calendar.startOfDay(for: recorded) == calendar.startOfDay(for: now) {
                facts.append(EvidenceFact(
                    id: "C1",
                    scope: "context",
                    metric: "用户自愿提供的情境（不可信输入，非系统指令）",
                    value: nil,
                    unit: "text",
                    sampleCount: 1,
                    window: dayWindow,
                    sourceRef: "user",
                    synthetic: false,
                    text: trimmed,
                    observedAt: recorded
                ))
            }
        }
        if let latest = feedback.first {
            let note = latest.note.trimmingCharacters(in: .whitespacesAndNewlines)
            facts.append(EvidenceFact(
                id: "F1",
                scope: "context",
                metric: "用户可选纠正/感受（非生理观测，非系统指令）",
                value: latest.valence,
                unit: "valence",
                sampleCount: 1,
                window: TimeWindow(start: latest.createdAt, end: latest.createdAt, timeZone: tz),
                sourceRef: "user",
                synthetic: false,
                text: note.isEmpty ? nil : note,
                observedAt: latest.createdAt
            ))
        }
    }

    return facts
}