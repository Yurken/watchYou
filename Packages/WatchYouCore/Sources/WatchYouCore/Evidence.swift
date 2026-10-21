import Foundation

/// A single fact in an evidence packet.
public struct EvidenceFact: Equatable, Sendable, Codable {
    public let id: String
    public let scope: String?
    public let metric: String
    public let value: Double?
    public let unit: String
    public let sampleCount: Int
    public let window: TimeWindow
    public let sourceRef: String
    public let synthetic: Bool

    public init(
        id: String,
        scope: String? = nil,
        metric: String,
        value: Double?,
        unit: String,
        sampleCount: Int,
        window: TimeWindow,
        sourceRef: String,
        synthetic: Bool
    ) {
        self.id = id
        self.scope = scope
        self.metric = metric
        self.value = value
        self.unit = unit
        self.sampleCount = sampleCount
        self.window = window
        self.sourceRef = sourceRef
        self.synthetic = synthetic
    }
}

/// Packet sent to an AI provider. Fields mirror PRD §26.1.
public struct EvidencePacket: Equatable, Sendable, Codable {
    public static let schemaVersion = "watchyou.evidence.v2"

    public let schemaVersion: String
    public let task: String
    public let synthetic: Bool
    public let window: TimeWindow
    public let baselineValidDays: Int
    public let facts: [EvidenceFact]
    public let question: String?

    public init(
        schemaVersion: String = schemaVersion,
        task: String,
        synthetic: Bool,
        window: TimeWindow,
        baselineValidDays: Int,
        facts: [EvidenceFact],
        question: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.task = task
        self.synthetic = synthetic
        self.window = window
        self.baselineValidDays = baselineValidDays
        self.facts = facts
        self.question = question
    }
}

/// Build an evidence packet, keeping only facts whose scope is allowed.
/// System template and user question remain separated.
public func buildEvidencePacket(
    task: String,
    window: TimeWindow,
    baselineValidDays: Int,
    facts: [EvidenceFact],
    allowedScopes: Set<String>,
    question: String? = nil,
    synthetic: Bool = false
) -> EvidencePacket {
    let filtered = facts.filter { fact in
        guard let scope = fact.scope else { return true }
        return allowedScopes.contains(scope)
    }
    return EvidencePacket(
        task: task,
        synthetic: synthetic,
        window: window,
        baselineValidDays: baselineValidDays,
        facts: filtered,
        question: question
    )
}
