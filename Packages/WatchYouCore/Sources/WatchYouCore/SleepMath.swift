import Foundation

/// Sleep interval category used for duration and timeline calculations.
public enum SleepCategory: Equatable, Sendable {
    case asleep
    case inBed
    case unknown
}

/// A sleep interval tied to a source.
public struct SleepInterval: Equatable, Sendable {
    public let start: Date
    public let end: Date
    public let category: SleepCategory
    public let sourceRef: String

    public init(start: Date, end: Date, category: SleepCategory, sourceRef: String) {
        self.start = start
        self.end = end
        self.category = category
        self.sourceRef = sourceRef
    }
}

/// A sliced timeline segment with a resolved category per source.
public struct SleepSegment: Equatable, Sendable {
    public let start: Date
    public let end: Date
    public let sourceRef: String
    public let category: SleepCategory
}

/// Union of asleep intervals, counting overlaps once. In-bed intervals are excluded from sleep duration.
public func unionAsleepMinutes(intervals: [SleepInterval]) -> Double {
    let asleep = intervals.filter { $0.category == .asleep && $0.end > $0.start }
    let sorted = asleep.sorted { $0.start < $1.start }

    var total: TimeInterval = 0
    var currentStart: Date?
    var currentEnd: Date?

    for interval in sorted {
        if let start = currentStart, let end = currentEnd {
            if interval.start <= end {
                currentEnd = max(end, interval.end)
            } else {
                total += end.timeIntervalSince(start)
                currentStart = interval.start
                currentEnd = interval.end
            }
        } else {
            currentStart = interval.start
            currentEnd = interval.end
        }
    }

    if let start = currentStart, let end = currentEnd {
        total += end.timeIntervalSince(start)
    }

    return total / 60.0
}

/// Slice the timeline by all interval boundaries. Segments where the same source provides conflicting stages are marked `.unknown`.
public func timelineSegments(intervals: [SleepInterval]) -> [SleepSegment] {
    let valid = intervals.filter { $0.end > $0.start }
    guard !valid.isEmpty else { return [] }

    let boundaries = Set(valid.flatMap { [$0.start, $0.end] }).sorted()
    guard boundaries.count > 1 else { return [] }

    var segments: [SleepSegment] = []
    let bySource = Dictionary(grouping: valid) { $0.sourceRef }

    for i in 0..<(boundaries.count - 1) {
        let sliceStart = boundaries[i]
        let sliceEnd = boundaries[i + 1]

        for sourceRef in bySource.keys.sorted() {
            let covering = bySource[sourceRef]!.filter { $0.start < sliceEnd && $0.end > sliceStart }
            let category: SleepCategory
            if covering.count > 1 {
                category = .unknown
            } else if let single = covering.first {
                category = single.category
            } else {
                continue
            }
            segments.append(SleepSegment(start: sliceStart, end: sliceEnd, sourceRef: sourceRef, category: category))
        }
    }

    return mergeContiguousSegments(segments)
}

private func mergeContiguousSegments(_ segments: [SleepSegment]) -> [SleepSegment] {
    var merged: [SleepSegment] = []
    for segment in segments {
        if let last = merged.last,
           last.end == segment.start,
           last.sourceRef == segment.sourceRef,
           last.category == segment.category {
            merged[merged.count - 1] = SleepSegment(
                start: last.start,
                end: segment.end,
                sourceRef: last.sourceRef,
                category: last.category
            )
        } else {
            merged.append(segment)
        }
    }
    return merged
}
