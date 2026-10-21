import Foundation

/// A lightweight reference to a health sample with identity, value, time and provenance.
public struct HealthSampleRef: Equatable, Hashable, Identifiable, Sendable, Codable {
    public let uuid: UUID
    public let metric: String
    public let value: Double?
    public let unit: String
    public let window: TimeWindow
    public let sourceRef: String
    public let deleted: Bool

    public init(
        uuid: UUID,
        metric: String,
        value: Double?,
        unit: String,
        window: TimeWindow,
        sourceRef: String,
        deleted: Bool = false
    ) {
        self.uuid = uuid
        self.metric = metric
        self.value = value
        self.unit = unit
        self.window = window
        self.sourceRef = sourceRef
        self.deleted = deleted
    }

    public var id: UUID { uuid }
}

/// Merge samples by UUID. Incoming values overwrite existing ones so re-imports are idempotent.
public func mergingByUUID(
    existing: [HealthSampleRef],
    incoming: [HealthSampleRef]
) -> [HealthSampleRef] {
    var map: [UUID: HealthSampleRef] = Dictionary(uniqueKeysWithValues: existing.map { ($0.uuid, $0) })
    for sample in incoming {
        map[sample.uuid] = sample
    }
    return Array(map.values).sorted { $0.window.start < $1.window.start }
}

/// Categorized read status. Empty results are not interpreted as permission denied.
public enum ReadOutcome: Equatable, Sendable {
    case unknown
    case empty
    case readable([HealthSampleRef])
    case failed(ReadErrorKind)
}

/// Stable classification of read failures.
public struct ReadErrorKind: Equatable, Sendable {
    public let code: String
    public let message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}
