import Foundation

public struct ReminderPrefs: Equatable, Sendable, Codable {
    public var sleepPrep: Bool
    public var habits: Bool
    public var water: Bool
    public var maintenance: Bool
    public var quietStart: String
    public var quietEnd: String
    public var dailyCap: Int

    public init(
        sleepPrep: Bool = false,
        habits: Bool = false,
        water: Bool = false,
        maintenance: Bool = false,
        quietStart: String = "22:00",
        quietEnd: String = "07:00",
        dailyCap: Int = 3
    ) {
        self.sleepPrep = sleepPrep
        self.habits = habits
        self.water = water
        self.maintenance = maintenance
        self.quietStart = quietStart
        self.quietEnd = quietEnd
        self.dailyCap = dailyCap
    }
}

public func validateReminderPrefs(_ raw: ReminderPrefs?) -> ReminderPrefs {
    let defaults = ReminderPrefs()
    guard let raw else { return defaults }
    func validTime(_ value: String, fallback: String) -> String {
        value.range(of: "^([01]\\d|2[0-3]):[0-5]\\d$", options: .regularExpression) != nil ? value : fallback
    }
    return ReminderPrefs(
        sleepPrep: raw.sleepPrep,
        habits: raw.habits,
        water: raw.water,
        maintenance: raw.maintenance,
        quietStart: validTime(raw.quietStart, fallback: defaults.quietStart),
        quietEnd: validTime(raw.quietEnd, fallback: defaults.quietEnd),
        dailyCap: (1...10).contains(raw.dailyCap) ? raw.dailyCap : defaults.dailyCap
    )
}

public struct UserPreferences: Equatable, Sendable, Codable {
    public var sleepGoalMinutes: Int
    public var waterGoalMl: Int
    public var preferredHeartSource: String?
    public var preferredSleepSource: String?
    public var remindersEnabled: Bool
    public var reminderPrefs: ReminderPrefs
    public var hasCompletedOnboarding: Bool
    public var lastSignedNote: String

    public init(
        sleepGoalMinutes: Int = 480,
        waterGoalMl: Int = 2000,
        preferredHeartSource: String? = nil,
        preferredSleepSource: String? = nil,
        remindersEnabled: Bool = false,
        reminderPrefs: ReminderPrefs = ReminderPrefs(),
        hasCompletedOnboarding: Bool = false,
        lastSignedNote: String = ""
    ) {
        self.sleepGoalMinutes = clampInt(sleepGoalMinutes, 360, 600)
        self.waterGoalMl = clampInt(waterGoalMl, 500, 4000)
        self.preferredHeartSource = preferredHeartSource
        self.preferredSleepSource = preferredSleepSource
        self.remindersEnabled = remindersEnabled
        self.reminderPrefs = validateReminderPrefs(reminderPrefs)
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.lastSignedNote = lastSignedNote
    }
}

public struct HabitEvent: Equatable, Sendable, Codable, Identifiable {
    public let id: String
    public let kind: String
    public let amount: Double
    public let createdAt: Date
    public var pending: Bool
    public var revision: Int
    public var source: String

    public init(
        id: String,
        kind: String,
        amount: Double,
        createdAt: Date,
        pending: Bool = false,
        revision: Int = 1,
        source: String = "app"
    ) {
        self.id = id
        self.kind = kind
        self.amount = amount
        self.createdAt = createdAt
        self.pending = pending
        self.revision = revision
        self.source = source
    }
}

public struct UserFeedback: Equatable, Sendable, Codable, Identifiable {
    public let id: String
    public let inferenceTask: String?
    public let valence: Double
    public let note: String
    public let tags: [String]
    public let createdAt: Date
    public let kind: String

    public init(
        id: String,
        inferenceTask: String? = nil,
        valence: Double,
        note: String,
        tags: [String] = [],
        createdAt: Date,
        kind: String = "momentary"
    ) {
        self.id = id
        self.inferenceTask = inferenceTask
        self.valence = valence
        self.note = String(note.prefix(300))
        self.tags = Array(tags.prefix(8))
        self.createdAt = createdAt
        self.kind = kind == "daily" ? "daily" : "momentary"
    }
}

public struct ChatTurn: Equatable, Sendable, Codable, Identifiable {
    public let id: String
    public let role: String
    public let text: String
    public let createdAt: Date

    public init(id: String = UUID().uuidString, role: String, text: String, createdAt: Date) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
    }
}

public struct AuditRecord: Equatable, Sendable, Codable, Identifiable {
    public let id: String
    public let at: Date
    public let kind: String
    public let status: String
    public let model: String
    public let scope: String
    public let latencyMs: Int?

    public init(
        id: String = UUID().uuidString,
        at: Date,
        kind: String,
        status: String,
        model: String,
        scope: String,
        latencyMs: Int? = nil
    ) {
        self.id = id
        self.at = at
        self.kind = kind
        self.status = status
        self.model = model
        self.scope = scope
        self.latencyMs = latencyMs
    }
}

public struct UsageCounter: Equatable, Sendable, Codable {
    public var day: String
    public var count: Int

    public init(day: String, count: Int) {
        self.day = day
        self.count = count
    }
}

public struct PersistedInference: Equatable, Sendable, Codable {
    public var task: String
    public var result: AIResult
    public var facts: [EvidenceFact]
    public var model: String
    public var mode: String
    public var generatedAt: Date
    public var observedEnd: Date
    public var inputHash: String
    public var window: TimeWindow
    public var servedAt: Date?
    public var cacheHit: Bool?

    public init(
        task: String,
        result: AIResult,
        facts: [EvidenceFact],
        model: String,
        mode: String,
        generatedAt: Date,
        observedEnd: Date,
        inputHash: String,
        window: TimeWindow,
        servedAt: Date? = nil,
        cacheHit: Bool? = nil
    ) {
        self.task = task
        self.result = result
        self.facts = facts
        self.model = model
        self.mode = mode
        self.generatedAt = generatedAt
        self.observedEnd = observedEnd
        self.inputHash = inputHash
        self.window = window
        self.servedAt = servedAt
        self.cacheHit = cacheHit
    }
}

public struct WorkoutRecord: Equatable, Sendable, Codable, Identifiable {
    public let uuid: UUID
    public let activity: String
    public let window: TimeWindow
    public let durationMinutes: Double
    public let averageHeartRate: Double?
    public let energyKcal: Double?
    public let sourceRef: String
    public var rpe: Int?

    public var id: UUID { uuid }

    public init(
        uuid: UUID,
        activity: String,
        window: TimeWindow,
        durationMinutes: Double,
        averageHeartRate: Double?,
        energyKcal: Double?,
        sourceRef: String,
        rpe: Int? = nil
    ) {
        self.uuid = uuid
        self.activity = activity
        self.window = window
        self.durationMinutes = durationMinutes
        self.averageHeartRate = averageHeartRate
        self.energyKcal = energyKcal
        self.sourceRef = sourceRef
        self.rpe = rpe
    }

    public var trainingLoadValue: Int? {
        trainingLoad(minutes: durationMinutes, rpe: rpe)
    }
}

public struct DailyQuantity: Equatable, Sendable, Codable {
    public let day: Date
    public let metric: String
    public let value: Double
    public let unit: String
    public let lastSampleAt: Date?
    public let sourceRef: String

    public init(
        day: Date,
        metric: String,
        value: Double,
        unit: String,
        lastSampleAt: Date?,
        sourceRef: String
    ) {
        self.day = day
        self.metric = metric
        self.value = value
        self.unit = unit
        self.lastSampleAt = lastSampleAt
        self.sourceRef = sourceRef
    }
}

public struct NapRecord: Equatable, Sendable, Codable {
    public let start: Date
    public let end: Date
    public let minutes: Double
    public let sourceRef: String

    public init(start: Date, end: Date, minutes: Double, sourceRef: String) {
        self.start = start
        self.end = end
        self.minutes = minutes
        self.sourceRef = sourceRef
    }
}

public struct SleepStageSlice: Equatable, Sendable, Codable, Identifiable {
    public var id: String { "\(start.timeIntervalSince1970)-\(stage.rawValue)-\(sourceRef)" }
    public let start: Date
    public let end: Date
    public let stage: SleepStage
    public let sourceRef: String

    public init(start: Date, end: Date, stage: SleepStage, sourceRef: String) {
        self.start = start
        self.end = end
        self.stage = stage
        self.sourceRef = sourceRef
    }

    public var minutes: Double {
        end.timeIntervalSince(start) / 60
    }
}

public struct SleepNight: Equatable, Sendable, Codable {
    public let day: Date
    public let mainStart: Date?
    public let mainEnd: Date?
    public let asleepMinutes: Double
    public let awakeMinutes: Double
    public let inBedMinutes: Double
    public let stageMinutes: [String: Double]
    public let naps: [NapRecord]
    public let slices: [SleepStageSlice]
    public let coverage: Double
    public let sourceRef: String
    public let midpointMinutes: Double?

    public init(
        day: Date,
        mainStart: Date?,
        mainEnd: Date?,
        asleepMinutes: Double,
        awakeMinutes: Double,
        inBedMinutes: Double,
        stageMinutes: [String: Double],
        naps: [NapRecord],
        slices: [SleepStageSlice],
        coverage: Double,
        sourceRef: String,
        midpointMinutes: Double?
    ) {
        self.day = day
        self.mainStart = mainStart
        self.mainEnd = mainEnd
        self.asleepMinutes = asleepMinutes
        self.awakeMinutes = awakeMinutes
        self.inBedMinutes = inBedMinutes
        self.stageMinutes = stageMinutes
        self.naps = naps
        self.slices = slices
        self.coverage = coverage
        self.sourceRef = sourceRef
        self.midpointMinutes = midpointMinutes
    }
}

public struct HealthCatalog: Equatable, Sendable {
    public var samples: [HealthSampleRef]
    public var daily: [DailyQuantity]
    public var workouts: [WorkoutRecord]
    public var revisions: [SourceRevision]
    public var lastSuccessfulRead: Date?
    public var readError: String?
    public var metricStates: [String: MetricQueryState]

    public init(
        samples: [HealthSampleRef] = [],
        daily: [DailyQuantity] = [],
        workouts: [WorkoutRecord] = [],
        revisions: [SourceRevision] = [],
        lastSuccessfulRead: Date? = nil,
        readError: String? = nil,
        metricStates: [String: MetricQueryState] = [:]
    ) {
        self.samples = samples
        self.daily = daily
        self.workouts = workouts
        self.revisions = revisions
        self.lastSuccessfulRead = lastSuccessfulRead
        self.readError = readError
        self.metricStates = metricStates
    }

    public var isEmpty: Bool {
        samples.isEmpty && daily.allSatisfy { $0.value == 0 } && workouts.isEmpty
    }
}

public struct HealthSnapshot: Equatable, Sendable {
    public var generatedAt: Date
    public var timeZone: TimeZone
    public var lastNight: SleepNight?
    public var nights: [SleepNight]
    public var sleepScore: SleepScore?
    public var recoveryScore: RecoveryScore?
    public var latestHeartRate: HealthSampleRef?
    public var heartRateSeries: [HealthSampleRef]
    public var restingHeartRate: Double?
    public var restingHeartRateBaseline: Double?
    public var nocturnalHRV: Double?
    public var nocturnalHRVSampleCount: Int
    public var hrvBaseline: Double?
    public var hrvValidDays: Int
    public var recentHRV: Double?
    public var recentHRVAt: Date?
    public var todaySteps: Double?
    public var todayEnergyKcal: Double?
    public var todayExerciseMinutes: Double?
    public var weekExercise: [DailyQuantity]
    public var sleepTrend: [SleepNight]
    public var workouts: [WorkoutRecord]
    public var sources: [SourceProfile]
    public var lastSampleAt: Date?
    public var lastReadAt: Date?
    public var readError: String?
    public var isEmpty: Bool
    public var duringWorkout: Bool
    public var baselineNights: Int
    public var metricStates: [String: MetricQueryState]
    public var analysisDay: Date?

    public init(
        generatedAt: Date,
        timeZone: TimeZone,
        lastNight: SleepNight? = nil,
        nights: [SleepNight] = [],
        sleepScore: SleepScore? = nil,
        recoveryScore: RecoveryScore? = nil,
        latestHeartRate: HealthSampleRef? = nil,
        heartRateSeries: [HealthSampleRef] = [],
        restingHeartRate: Double? = nil,
        restingHeartRateBaseline: Double? = nil,
        nocturnalHRV: Double? = nil,
        nocturnalHRVSampleCount: Int = 0,
        hrvBaseline: Double? = nil,
        hrvValidDays: Int = 0,
        recentHRV: Double? = nil,
        recentHRVAt: Date? = nil,
        todaySteps: Double? = nil,
        todayEnergyKcal: Double? = nil,
        todayExerciseMinutes: Double? = nil,
        weekExercise: [DailyQuantity] = [],
        sleepTrend: [SleepNight] = [],
        workouts: [WorkoutRecord] = [],
        sources: [SourceProfile] = [],
        lastSampleAt: Date? = nil,
        lastReadAt: Date? = nil,
        readError: String? = nil,
        isEmpty: Bool = true,
        duringWorkout: Bool = false,
        baselineNights: Int = 0,
        metricStates: [String: MetricQueryState] = [:],
        analysisDay: Date? = nil
    ) {
        self.generatedAt = generatedAt
        self.timeZone = timeZone
        self.lastNight = lastNight
        self.nights = nights
        self.sleepScore = sleepScore
        self.recoveryScore = recoveryScore
        self.latestHeartRate = latestHeartRate
        self.heartRateSeries = heartRateSeries
        self.restingHeartRate = restingHeartRate
        self.restingHeartRateBaseline = restingHeartRateBaseline
        self.nocturnalHRV = nocturnalHRV
        self.nocturnalHRVSampleCount = nocturnalHRVSampleCount
        self.hrvBaseline = hrvBaseline
        self.hrvValidDays = hrvValidDays
        self.recentHRV = recentHRV
        self.recentHRVAt = recentHRVAt
        self.todaySteps = todaySteps
        self.todayEnergyKcal = todayEnergyKcal
        self.todayExerciseMinutes = todayExerciseMinutes
        self.weekExercise = weekExercise
        self.sleepTrend = sleepTrend
        self.workouts = workouts
        self.sources = sources
        self.lastSampleAt = lastSampleAt
        self.lastReadAt = lastReadAt
        self.readError = readError
        self.isEmpty = isEmpty
        self.duringWorkout = duringWorkout
        self.baselineNights = baselineNights
        self.metricStates = metricStates
        self.analysisDay = analysisDay
    }
}

public struct AppPersistedState: Equatable, Sendable, Codable {
    public var preferences: UserPreferences
    public var events: [HabitEvent]
    public var feedback: [UserFeedback]
    public var rpeByWorkout: [String: Int]
    public var aiConfig: AIConfig
    public var consent: AIPermission?
    public var usage: UsageCounter
    public var inferences: [String: PersistedInference]
    public var logs: [AuditRecord]
    public var chat: [ChatTurn]
    public var contextNote: String
    public var generation: Int
    public var eventTombstones: [String: Int]
    public var watchSnapshotRevision: Int

    public init(
        preferences: UserPreferences = UserPreferences(),
        events: [HabitEvent] = [],
        feedback: [UserFeedback] = [],
        rpeByWorkout: [String: Int] = [:],
        aiConfig: AIConfig = defaultAIConfig(),
        consent: AIPermission? = nil,
        usage: UsageCounter = UsageCounter(day: "", count: 0),
        inferences: [String: PersistedInference] = [:],
        logs: [AuditRecord] = [],
        chat: [ChatTurn] = [],
        contextNote: String = "",
        generation: Int = 0,
        eventTombstones: [String: Int] = [:],
        watchSnapshotRevision: Int = 0
    ) {
        self.preferences = preferences
        self.events = events
        self.feedback = feedback
        self.rpeByWorkout = rpeByWorkout
        self.aiConfig = aiConfig
        self.consent = consent
        self.usage = usage
        self.inferences = inferences
        self.logs = logs
        self.chat = chat
        self.contextNote = contextNote
        self.generation = generation
        self.eventTombstones = eventTombstones
        self.watchSnapshotRevision = watchSnapshotRevision
    }

    enum CodingKeys: String, CodingKey {
        case preferences, events, feedback, rpeByWorkout, aiConfig, consent, usage, inferences, logs, chat, contextNote, generation
        case eventTombstones, watchSnapshotRevision
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        preferences = try container.decode(UserPreferences.self, forKey: .preferences)
        events = try container.decode([HabitEvent].self, forKey: .events)
        feedback = try container.decode([UserFeedback].self, forKey: .feedback)
        rpeByWorkout = try container.decode([String: Int].self, forKey: .rpeByWorkout)
        aiConfig = try container.decode(AIConfig.self, forKey: .aiConfig)
        consent = try container.decodeIfPresent(AIPermission.self, forKey: .consent)
        usage = try container.decode(UsageCounter.self, forKey: .usage)
        inferences = try container.decode([String: PersistedInference].self, forKey: .inferences)
        logs = try container.decode([AuditRecord].self, forKey: .logs)
        chat = try container.decode([ChatTurn].self, forKey: .chat)
        contextNote = try container.decode(String.self, forKey: .contextNote)
        generation = try container.decode(Int.self, forKey: .generation)
        eventTombstones = try container.decodeIfPresent([String: Int].self, forKey: .eventTombstones) ?? [:]
        watchSnapshotRevision = try container.decodeIfPresent(Int.self, forKey: .watchSnapshotRevision) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(preferences, forKey: .preferences)
        try container.encode(events, forKey: .events)
        try container.encode(feedback, forKey: .feedback)
        try container.encode(rpeByWorkout, forKey: .rpeByWorkout)
        try container.encode(aiConfig, forKey: .aiConfig)
        try container.encodeIfPresent(consent, forKey: .consent)
        try container.encode(usage, forKey: .usage)
        try container.encode(inferences, forKey: .inferences)
        try container.encode(logs, forKey: .logs)
        try container.encode(chat, forKey: .chat)
        try container.encode(contextNote, forKey: .contextNote)
        try container.encode(generation, forKey: .generation)
        try container.encode(eventTombstones, forKey: .eventTombstones)
        try container.encode(watchSnapshotRevision, forKey: .watchSnapshotRevision)
    }
}

private func clampInt(_ value: Int, _ lo: Int, _ hi: Int) -> Int {
    min(hi, max(lo, value))
}