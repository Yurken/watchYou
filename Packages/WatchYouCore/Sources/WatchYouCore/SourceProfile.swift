import Foundation

/// Raw source revision metadata from a sample or import record.
public struct SourceRevision: Equatable, Sendable, Codable {
    public let sourceName: String?
    public let bundleID: String?
    public let productType: String?
    public let manufacturer: String?

    public init(
        sourceName: String? = nil,
        bundleID: String? = nil,
        productType: String? = nil,
        manufacturer: String? = nil
    ) {
        self.sourceName = sourceName
        self.bundleID = bundleID
        self.productType = productType
        self.manufacturer = manufacturer
    }
}

/// Consolidated source profile. `unknown` is a valid state when a device cannot be reliably identified.
public struct SourceProfile: Equatable, Sendable, Codable {
    public let id: String
    public let name: String
    public let unknown: Bool
    public let sourceRefs: [String]

    public init(id: String, name: String, unknown: Bool, sourceRefs: [String]) {
        self.id = id
        self.name = name
        self.unknown = unknown
        self.sourceRefs = sourceRefs
    }
}

/// Group revisions into profiles. Revisions without a reliable bundle identifier are collapsed into an unknown profile.
public func resolve(revisions: [SourceRevision]) -> [SourceProfile] {
    var known: [String: [SourceRevision]] = [:]
    var unknown: [SourceRevision] = []

    for revision in revisions {
        if let bundleID = revision.bundleID, !bundleID.isEmpty {
            known[bundleID, default: []].append(revision)
        } else {
            unknown.append(revision)
        }
    }

    var profiles: [SourceProfile] = known.map { bundleID, group in
        let name = group.first?.sourceName ?? bundleID
        return SourceProfile(
            id: bundleID,
            name: name,
            unknown: false,
            sourceRefs: group.compactMap { $0.sourceName ?? $0.bundleID }
        )
    }

    if !unknown.isEmpty {
        profiles.append(SourceProfile(
            id: "unknown",
            name: "未知来源",
            unknown: true,
            sourceRefs: unknown.compactMap { $0.sourceName ?? $0.bundleID }
        ))
    }

    return profiles.sorted { $0.id < $1.id }
}

/// Outcome of picking a preferred source among possibly conflicting heart-rate samples.
public struct PreferredHeartRate: Equatable, Sendable {
    /// Samples retained after applying the policy (ties preserved, no averaging).
    public let samples: [HealthSampleRef]
    /// Maximum absolute time span among retained samples, if more than one.
    public let timeDifference: TimeInterval?
}

/// Resolve heart-rate conflicts: preserve ties, prefer the chosen source, never average across sources.
public func pickPreferred(
    conflicts: [HealthSampleRef],
    preferred source: String?
) -> PreferredHeartRate {
    let valid = conflicts.filter { !$0.deleted && $0.window.end > $0.window.start }
    guard !valid.isEmpty else { return PreferredHeartRate(samples: [], timeDifference: nil) }

    let grouped = Dictionary(grouping: valid) { $0.sourceRef }
    let chosen = source.flatMap { grouped[$0] } ?? []

    let samples = chosen.isEmpty ? valid : chosen
    let sorted = samples.sorted { $0.window.start < $1.window.start }
    let span = sorted.count > 1 ? sorted.last!.window.start.timeIntervalSince(sorted.first!.window.start) : nil
    return PreferredHeartRate(samples: sorted, timeDifference: span)
}
