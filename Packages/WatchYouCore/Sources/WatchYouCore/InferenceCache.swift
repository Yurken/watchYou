import Foundation

/// Deterministic, non-cryptographic digest used for cache-key stability.
public func inputDigest(_ input: String) -> String {
    var hash: UInt64 = 14695981039346656037
    for byte in input.utf8 {
        hash ^= UInt64(byte)
        hash = hash &* 1099511628211
    }
    return String(format: "%016llx", hash)
}

/// Cache key covering all inputs that can invalidate a previous inference.
public struct InferenceCacheKey: Equatable, Hashable, Sendable {
    public let task: String
    public let inputHash: String
    public let window: TimeWindow
    public let model: String
    public let normalizedEndpoint: String
    public let promptVersion: String
    public let sourcePolicyVersion: String
    public let consentVersion: String
    public let generation: Int

    public init(
        task: String,
        inputHash: String,
        window: TimeWindow,
        model: String,
        normalizedEndpoint: String,
        promptVersion: String,
        sourcePolicyVersion: String,
        consentVersion: String,
        generation: Int
    ) {
        self.task = task
        self.inputHash = inputHash
        self.window = window
        self.model = model
        self.normalizedEndpoint = normalizedEndpoint
        self.promptVersion = promptVersion
        self.sourcePolicyVersion = sourcePolicyVersion
        self.consentVersion = consentVersion
        self.generation = generation
    }
}

public struct InferenceRecord: Equatable, Sendable {
    public let result: AIResult
    public let evidenceIDs: Set<String>
    public let generation: Int
    public let originalGeneratedAt: Date
    public let cachedAt: Date

    public init(
        result: AIResult,
        evidenceIDs: Set<String>,
        generation: Int,
        originalGeneratedAt: Date = Date(),
        cachedAt: Date? = nil
    ) {
        self.result = result
        self.evidenceIDs = evidenceIDs
        self.generation = generation
        self.originalGeneratedAt = originalGeneratedAt
        self.cachedAt = cachedAt ?? originalGeneratedAt
    }
}

/// Thread-safe inference cache. A generation bump invalidates older entries implicitly via the key.
public actor InferenceCache {
    private var storage: [InferenceCacheKey: InferenceRecord] = [:]
    private let ttl: TimeInterval
    private let capacity: Int

    public init(ttl: TimeInterval = 12 * 3600, capacity: Int = 48) {
        self.ttl = ttl
        self.capacity = max(1, capacity)
    }

    public func put(_ record: InferenceRecord, for key: InferenceCacheKey, now: Date = Date()) {
        evictExpired(now: now)
        storage[key] = record
        if storage.count > capacity {
            let overflow = storage.count - capacity
            let oldest = storage.sorted { $0.value.originalGeneratedAt < $1.value.originalGeneratedAt }.prefix(overflow)
            for item in oldest {
                storage.removeValue(forKey: item.key)
            }
        }
    }

    public func get(_ key: InferenceCacheKey, now: Date = Date()) -> InferenceRecord? {
        guard let record = storage[key] else { return nil }
        if now.timeIntervalSince(record.originalGeneratedAt) > ttl {
            storage.removeValue(forKey: key)
            return nil
        }
        return record
    }

    /// Remove entries that depend on any of the supplied evidence IDs.
    public func invalidate(evidenceIDs: Set<String>) {
        storage = storage.filter { _, record in
            record.evidenceIDs.isDisjoint(with: evidenceIDs)
        }
    }

    public func removeAll() {
        storage.removeAll()
    }

    private func evictExpired(now: Date) {
        storage = storage.filter { _, record in
            now.timeIntervalSince(record.originalGeneratedAt) <= ttl
        }
    }
}
