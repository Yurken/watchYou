import Foundation

/// Immutable snapshot of a live inference request. Return path must re-check this before writing state.
public struct InferenceRequestContext: Equatable, Sendable {
    public let requestID: UUID
    public let generation: Int
    public let task: String
    public let profileID: String
    public let model: String
    public let normalizedEndpoint: String
    public let protocolName: String
    public let authType: String
    public let consentVersion: String
    public let inputHash: String
    public let window: TimeWindow
    public let createdAt: Date

    public init(
        requestID: UUID = UUID(),
        generation: Int,
        task: String,
        profileID: String,
        model: String,
        normalizedEndpoint: String,
        protocolName: String,
        authType: String,
        consentVersion: String,
        inputHash: String,
        window: TimeWindow,
        createdAt: Date
    ) {
        self.requestID = requestID
        self.generation = generation
        self.task = task
        self.profileID = profileID
        self.model = model
        self.normalizedEndpoint = normalizedEndpoint
        self.protocolName = protocolName
        self.authType = authType
        self.consentVersion = consentVersion
        self.inputHash = inputHash
        self.window = window
        self.createdAt = createdAt
    }
}

public func shouldCommitInference(
    context: InferenceRequestContext,
    currentGeneration: Int,
    currentRequestID: UUID?
) -> Bool {
    currentRequestID == context.requestID && currentGeneration == context.generation
}

public func shouldClearBusy(finishing: UUID, currentRequestID: UUID?) -> Bool {
    currentRequestID == finishing
}

/// Stable observation window from facts. Does not use wall-clock call time.
public func inferenceObservationWindow(
    facts: [EvidenceFact],
    lastNight: SleepNight?,
    timeZone: TimeZone
) -> TimeWindow {
    let starts = facts.map(\.window.start)
    let ends = facts.map(\.window.end)
    if let start = starts.min(), let end = ends.max(), end >= start {
        return TimeWindow(start: start, end: end, timeZone: timeZone)
    }
    if let night = lastNight, let start = night.mainStart, let end = night.mainEnd {
        return TimeWindow(start: start, end: end, timeZone: timeZone)
    }
    return TimeWindow(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 0), timeZone: timeZone)
}

public func evidenceInputCanonicalString(
    packet: EvidencePacket,
    contextText: String,
    profile: AIProviderProfile,
    promptVersion: String,
    sourcePolicyVersion: String,
    consentVersion: String
) -> String {
    func stamp(_ date: Date) -> String {
        String(format: "%.3f", date.timeIntervalSince1970)
    }
    let facts = packet.facts.sorted { $0.id < $1.id }.map { fact in
        let value = fact.value.map { String(format: "%.6f", $0) } ?? ""
        return [
            fact.id,
            fact.scope ?? "",
            fact.metric,
            value,
            fact.unit,
            "\(fact.sampleCount)",
            stamp(fact.window.start),
            stamp(fact.window.end),
            fact.window.timeZone.identifier,
            fact.sourceRef,
            fact.synthetic ? "1" : "0",
            fact.text ?? ""
        ].joined(separator: "=")
    }.joined(separator: "\n")
    let temperature = profile.temperature.map { String(format: "%.4f", $0) } ?? ""
    return [
        packet.schemaVersion,
        packet.task,
        stamp(packet.window.start),
        stamp(packet.window.end),
        packet.window.timeZone.identifier,
        "\(packet.baselineValidDays)",
        packet.question ?? "",
        contextText,
        facts,
        profile.id,
        profile.protocolName,
        profile.model,
        profile.baseURL,
        profile.auth,
        temperature,
        "\(profile.maxTokens)",
        profile.tokenField,
        promptVersion,
        sourcePolicyVersion,
        consentVersion
    ].joined(separator: "\u{1e}")
}

public func makeInferenceCacheKey(
    packet: EvidencePacket,
    contextText: String,
    profile: AIProviderProfile,
    promptVersion: String,
    sourcePolicyVersion: String,
    consentVersion: String,
    generation: Int
) -> InferenceCacheKey {
    let canonical = evidenceInputCanonicalString(
        packet: packet,
        contextText: contextText,
        profile: profile,
        promptVersion: promptVersion,
        sourcePolicyVersion: sourcePolicyVersion,
        consentVersion: consentVersion
    )
    return InferenceCacheKey(
        task: packet.task,
        inputHash: inputDigest(canonical),
        window: packet.window,
        model: profile.model,
        normalizedEndpoint: (try? normalizeBase(profile.baseURL, allowLocalHTTP: profile.allowLocalHTTP)) ?? profile.baseURL,
        promptVersion: promptVersion,
        sourcePolicyVersion: sourcePolicyVersion,
        consentVersion: consentVersion,
        generation: generation
    )
}

public let automaticLiveDebounceSeconds: TimeInterval = 45

/// Automatic today/mood live calls skip identical hashes and bursts within the debounce window.
public func shouldStartAutomaticLive(
    task: String,
    inputHash: String,
    previousHash: String?,
    lastAttemptAt: Date?,
    now: Date,
    debounceSeconds: TimeInterval = automaticLiveDebounceSeconds,
    moduleEnabled: Bool = true,
    consentValid: Bool = true,
    force: Bool = false
) -> Bool {
    guard AIModules.contains(task) else { return false }
    guard moduleEnabled, consentValid else { return false }
    if let previousHash, previousHash == inputHash { return false }
    if !force, let lastAttemptAt, now.timeIntervalSince(lastAttemptAt) < debounceSeconds { return false }
    return true
}

public func applyCachedInference(
    result: AIResult,
    facts: [EvidenceFact],
    model: String,
    mode: String,
    originalGeneratedAt: Date,
    servedAt: Date,
    cacheHit: Bool,
    inputHash: String,
    window: TimeWindow,
    task: String
) -> PersistedInference {
    PersistedInference(
        task: task,
        result: result,
        facts: facts,
        model: model,
        mode: mode,
        generatedAt: originalGeneratedAt,
        observedEnd: window.end,
        inputHash: inputHash,
        window: window,
        servedAt: servedAt,
        cacheHit: cacheHit
    )
}
