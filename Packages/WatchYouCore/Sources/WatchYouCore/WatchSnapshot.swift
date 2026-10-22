import Foundation

/// Compact payload sent to the watch. No secrets, no full evidence packets.
public struct WatchSnapshot: Equatable, Sendable, Codable {
    public var generatedAt: Date
    public var observedAt: Date?
    public var todayTitle: String
    public var todaySummary: String
    public var moodLabel: String
    public var moodNote: String
    public var sleepText: String
    public var sleepWindowText: String
    public var recoveryText: String
    public var waterMl: Int
    public var waterGoal: Int
    public var empty: Bool
    public var stale: Bool
    public var includedWaterIds: [String]
    public var logicalDay: Date?
    public var timeZoneIdentifier: String
    public var snapshotRevision: Int

    public init(
        generatedAt: Date,
        observedAt: Date?,
        todayTitle: String,
        todaySummary: String,
        moodLabel: String,
        moodNote: String,
        sleepText: String,
        sleepWindowText: String,
        recoveryText: String,
        waterMl: Int,
        waterGoal: Int,
        empty: Bool,
        stale: Bool,
        includedWaterIds: [String] = [],
        logicalDay: Date? = nil,
        timeZoneIdentifier: String = "",
        snapshotRevision: Int = 0
    ) {
        self.generatedAt = generatedAt
        self.observedAt = observedAt
        self.todayTitle = String(todayTitle.prefix(40))
        self.todaySummary = String(todaySummary.prefix(160))
        self.moodLabel = String(moodLabel.prefix(24))
        self.moodNote = String(moodNote.prefix(80))
        self.sleepText = String(sleepText.prefix(40))
        self.sleepWindowText = String(sleepWindowText.prefix(40))
        self.recoveryText = String(recoveryText.prefix(24))
        self.waterMl = waterMl
        self.waterGoal = waterGoal
        self.empty = empty
        self.stale = stale
        self.includedWaterIds = includedWaterIds
        self.logicalDay = logicalDay
        self.timeZoneIdentifier = timeZoneIdentifier
        self.snapshotRevision = snapshotRevision
    }

    private enum CodingKeys: String, CodingKey {
        case generatedAt, observedAt, todayTitle, todaySummary, moodLabel, moodNote
        case sleepText, sleepWindowText, recoveryText, waterMl, waterGoal, empty, stale
        case includedWaterIds, logicalDay, timeZoneIdentifier, snapshotRevision
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        observedAt = try container.decodeIfPresent(Date.self, forKey: .observedAt)
        todayTitle = try container.decode(String.self, forKey: .todayTitle)
        todaySummary = try container.decode(String.self, forKey: .todaySummary)
        moodLabel = try container.decode(String.self, forKey: .moodLabel)
        moodNote = try container.decode(String.self, forKey: .moodNote)
        sleepText = try container.decode(String.self, forKey: .sleepText)
        sleepWindowText = try container.decodeIfPresent(String.self, forKey: .sleepWindowText) ?? ""
        recoveryText = try container.decode(String.self, forKey: .recoveryText)
        waterMl = try container.decode(Int.self, forKey: .waterMl)
        waterGoal = try container.decode(Int.self, forKey: .waterGoal)
        empty = try container.decode(Bool.self, forKey: .empty)
        stale = try container.decode(Bool.self, forKey: .stale)
        includedWaterIds = try container.decodeIfPresent([String].self, forKey: .includedWaterIds) ?? []
        logicalDay = try container.decodeIfPresent(Date.self, forKey: .logicalDay)
        timeZoneIdentifier = try container.decodeIfPresent(String.self, forKey: .timeZoneIdentifier) ?? ""
        snapshotRevision = try container.decodeIfPresent(Int.self, forKey: .snapshotRevision) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(generatedAt, forKey: .generatedAt)
        try container.encodeIfPresent(observedAt, forKey: .observedAt)
        try container.encode(todayTitle, forKey: .todayTitle)
        try container.encode(todaySummary, forKey: .todaySummary)
        try container.encode(moodLabel, forKey: .moodLabel)
        try container.encode(moodNote, forKey: .moodNote)
        try container.encode(sleepText, forKey: .sleepText)
        try container.encode(sleepWindowText, forKey: .sleepWindowText)
        try container.encode(recoveryText, forKey: .recoveryText)
        try container.encode(waterMl, forKey: .waterMl)
        try container.encode(waterGoal, forKey: .waterGoal)
        try container.encode(empty, forKey: .empty)
        try container.encode(stale, forKey: .stale)
        try container.encode(includedWaterIds, forKey: .includedWaterIds)
        try container.encodeIfPresent(logicalDay, forKey: .logicalDay)
        try container.encode(timeZoneIdentifier, forKey: .timeZoneIdentifier)
        try container.encode(snapshotRevision, forKey: .snapshotRevision)
    }
}

public struct WatchOutboundEvent: Equatable, Sendable, Codable {
    public var id: String
    public var kind: String
    public var amount: Double
    public var createdAt: Date
    public var revision: Int

    public init(id: String, kind: String, amount: Double, createdAt: Date, revision: Int = 1) {
        self.id = id
        self.kind = kind
        self.amount = amount
        self.createdAt = createdAt
        self.revision = revision
    }

    public func asHabitEvent() -> HabitEvent {
        HabitEvent(
            id: id,
            kind: kind,
            amount: amount,
            createdAt: createdAt,
            pending: false,
            revision: revision,
            source: "watch"
        )
    }
}

public func mergingOutbound(_ existing: [WatchOutboundEvent], _ event: WatchOutboundEvent) -> [WatchOutboundEvent] {
    if let index = existing.firstIndex(where: { $0.id == event.id }) {
        var next = existing
        if event.revision > next[index].revision {
            next[index] = event
        }
        return next
    }
    return existing + [event]
}

public func removingOutbound(_ existing: [WatchOutboundEvent], id: String) -> [WatchOutboundEvent] {
    existing.filter { $0.id != id }
}

public func encodeWatchPayload<T: Encodable>(_ value: T) -> Data? {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return try? encoder.encode(value)
}

public func decodeWatchPayload<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try? decoder.decode(type, from: data)
}

public func makeWatchSnapshot(
    snapshot: HealthSnapshot,
    inferences: [String: PersistedInference],
    events: [HabitEvent],
    preferences: UserPreferences,
    now: Date,
    tombstones: [String: Int] = [:],
    snapshotRevision: Int = 0
) -> WatchSnapshot {
    let today = inferences["today"]
    let mood = inferences["mood"]
    let empty = snapshot.isEmpty
    let stale: Bool = {
        guard let observed = snapshot.lastSampleAt else { return empty }
        return now.timeIntervalSince(observed) > 36 * 3600
    }()
    let title: String = {
        if empty { return "等待数据" }
        if stale { return "历史摘要" }
        if snapshot.baselineNights < 7 { return "正在认识你的节奏" }
        return today?.result.summary.isEmpty == false ? "今日洞察" : "等待分析"
    }()
    let summary = empty
        ? "暂无可读摘要，不生成状态。"
        : (today?.result.summary ?? "在手机完成设置后显示分析摘要。")
    let waterEvents = events.filter { event in
        event.kind == "water"
    }
    let water = Int(waterTotal(events: events, day: now, timeZone: snapshot.timeZone).rounded())
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = snapshot.timeZone
    let dayStart = calendar.startOfDay(for: now)
    let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
    let includedWaterIds = Array(Set(
        waterEvents.filter { $0.createdAt >= dayStart && $0.createdAt < dayEnd }.map(\.id)
            + tombstones.keys
    )).sorted()
    let sleepWindow: String = {
        guard let night = snapshot.lastNight, let start = night.mainStart, let end = night.mainEnd else {
            return snapshot.lastNight == nil ? "暂无睡眠" : "时间未知"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = snapshot.timeZone
        formatter.dateFormat = "HH:mm"
        return "\(formatter.string(from: start))–\(formatter.string(from: end))"
    }()
    return WatchSnapshot(
        generatedAt: now,
        observedAt: snapshot.lastSampleAt,
        todayTitle: title,
        todaySummary: summary,
        moodLabel: mood?.result.emotion?.label ?? "等待分析",
        moodNote: mood?.result.emotion?.evidenceStrength ?? "证据有限 · 正负向未知",
        sleepText: snapshot.lastNight.map { formatDurationMinutes($0.asleepMinutes) } ?? "暂无睡眠",
        sleepWindowText: sleepWindow,
        recoveryText: snapshot.recoveryScore.map { "\($0.value)" } ?? "—",
        waterMl: water,
        waterGoal: preferences.waterGoalMl,
        empty: empty,
        stale: stale,
        includedWaterIds: includedWaterIds,
        logicalDay: dayStart,
        timeZoneIdentifier: snapshot.timeZone.identifier,
        snapshotRevision: snapshotRevision
    )
}

/// Watch display total: phone snapshot already contains merged events; pending ids in `includedWaterIds` are not added again.
/// Pending water only counts when it falls on the snapshot's logical day.
public func displayedWater(snapshot: WatchSnapshot?, pending: [WatchOutboundEvent], now: Date = Date()) -> Int {
    let timeZone = TimeZone(identifier: snapshot?.timeZoneIdentifier ?? "") ?? .current
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let day = snapshot?.logicalDay ?? calendar.startOfDay(for: snapshot?.generatedAt ?? now)
    let included = Set(snapshot?.includedWaterIds ?? [])
    let extra = pending
        .filter { event in
            guard event.kind == "water", !included.contains(event.id) else { return false }
            return calendar.startOfDay(for: event.createdAt) == calendar.startOfDay(for: day)
        }
        .reduce(0) { $0 + Int($1.amount.rounded()) }
    return (snapshot?.waterMl ?? 0) + extra
}

public let watchContextKey = "watchyou.snapshot.v1"
public let watchEventKey = "watchyou.event.v1"