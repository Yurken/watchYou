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
    public let text: String?
    public let observedAt: Date?

    public init(
        id: String,
        scope: String? = nil,
        metric: String,
        value: Double?,
        unit: String,
        sampleCount: Int,
        window: TimeWindow,
        sourceRef: String,
        synthetic: Bool,
        text: String? = nil,
        observedAt: Date? = nil
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
        self.text = text
        self.observedAt = observedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, scope, metric, value, unit, sampleCount, window, sourceRef, synthetic, text, observedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        scope = try container.decodeIfPresent(String.self, forKey: .scope)
        metric = try container.decode(String.self, forKey: .metric)
        value = try container.decodeIfPresent(Double.self, forKey: .value)
        unit = try container.decode(String.self, forKey: .unit)
        sampleCount = try container.decode(Int.self, forKey: .sampleCount)
        window = try container.decode(TimeWindow.self, forKey: .window)
        sourceRef = try container.decode(String.self, forKey: .sourceRef)
        synthetic = try container.decode(Bool.self, forKey: .synthetic)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        observedAt = try container.decodeIfPresent(Date.self, forKey: .observedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(scope, forKey: .scope)
        try container.encode(metric, forKey: .metric)
        try container.encode(value, forKey: .value)
        try container.encode(unit, forKey: .unit)
        try container.encode(sampleCount, forKey: .sampleCount)
        try container.encode(window, forKey: .window)
        try container.encode(sourceRef, forKey: .sourceRef)
        try container.encode(synthetic, forKey: .synthetic)
        try container.encodeIfPresent(text, forKey: .text)
        try container.encodeIfPresent(observedAt, forKey: .observedAt)
    }
}

/// Authorized C1 body that was actually included in the evidence packet.
public func sentContextText(_ facts: [EvidenceFact]) -> String {
    guard let fact = facts.first(where: { $0.id == "C1" && $0.scope == "context" }) else {
        return ""
    }
    return fact.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
}

/// True only when a C1 context fact with non-empty authorized text is present.
public func hasSendableContext(_ facts: [EvidenceFact]) -> Bool {
    !sentContextText(facts).isEmpty
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
