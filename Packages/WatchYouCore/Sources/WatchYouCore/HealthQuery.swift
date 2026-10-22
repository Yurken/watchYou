import Foundation

public enum SampleQueryOrder: Equatable, Sendable {
    case endDateAscending
    case endDateDescending
}

public enum MetricLoadStatus: String, Equatable, Sendable, Codable {
    case ok
    case empty
    case failed
}

public struct MetricQueryState: Equatable, Sendable, Codable {
    public var metric: String
    public var status: MetricLoadStatus
    public var lastSuccessAt: Date?
    public var lastAttemptAt: Date?
    public var error: String?

    public init(
        metric: String,
        status: MetricLoadStatus,
        lastSuccessAt: Date? = nil,
        lastAttemptAt: Date? = nil,
        error: String? = nil
    ) {
        self.metric = metric
        self.status = status
        self.lastSuccessAt = lastSuccessAt
        self.lastAttemptAt = lastAttemptAt
        self.error = error
    }
}

public let metricGroupSleep = "sleep"
public let metricGroupWorkout = "workout"

public func metricGroup(for metric: String) -> String {
    if Metric.sleepMetrics.contains(metric) { return metricGroupSleep }
    return metric
}

/// Mirrors HKSampleQuery limit+sort: take the first `limit` samples after ordering by end date.
public func applySampleQueryLimit(
    _ samples: [HealthSampleRef],
    limit: Int,
    order: SampleQueryOrder
) -> [HealthSampleRef] {
    let sorted: [HealthSampleRef]
    switch order {
    case .endDateAscending:
        sorted = samples.sorted(by: sampleEndAscending)
    case .endDateDescending:
        sorted = samples.sorted(by: sampleEndDescending)
    }
    guard limit > 0 else { return [] }
    return Array(sorted.prefix(limit))
}

/// Latest heart rate is descending limit=1; the chart window is a descending cap then merged by UUID.
public func heartRateCatalogSamples(
    _ samples: [HealthSampleRef],
    seriesLimit: Int = 400
) -> [HealthSampleRef] {
    let heart = samples.filter { $0.metric == Metric.heartRate && !$0.deleted }
    let latest = applySampleQueryLimit(heart, limit: 1, order: .endDateDescending)
    let series = applySampleQueryLimit(heart, limit: seriesLimit, order: .endDateDescending)
    return mergingByUUID(existing: series, incoming: latest)
}

public func latestHeartRateSample(from samples: [HealthSampleRef]) -> HealthSampleRef? {
    samples.filter { $0.metric == Metric.heartRate && !$0.deleted }.max(by: sampleEndAscending)
}

public func heartRateSeries(from samples: [HealthSampleRef], since: Date) -> [HealthSampleRef] {
    samples
        .filter { $0.metric == Metric.heartRate && !$0.deleted && $0.window.end >= since }
        .sorted { $0.window.start < $1.window.start }
}

public func shouldApplyHealthRefresh(startedGeneration: Int, currentGeneration: Int) -> Bool {
    startedGeneration == currentGeneration
}

public func calendarDay(of date: Date, timeZone: TimeZone) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    return calendar.startOfDay(for: date)
}

public func nightsInCalendarWindow(
    _ nights: [SleepNight],
    from startDay: Date,
    before endDay: Date
) -> [SleepNight] {
    nights.filter { $0.day >= startDay && $0.day < endDay && $0.asleepMinutes > 0 }
}

public func dailyMedianValues(
    samples: [HealthSampleRef],
    metric: String,
    from startDay: Date,
    before endDay: Date,
    timeZone: TimeZone
) -> [Date: Double] {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    var buckets: [Date: [Double]] = [:]
    for sample in samples where sample.metric == metric && !sample.deleted {
        let day = calendar.startOfDay(for: sample.window.end)
        guard day >= startDay && day < endDay, let value = sample.value else { continue }
        buckets[day, default: []].append(value)
    }
    var result: [Date: Double] = [:]
    for (day, values) in buckets {
        if let med = median(values) {
            result[day] = med
        }
    }
    return result
}

public func mergeHealthCatalog(previous: HealthCatalog?, incoming: HealthCatalog) -> HealthCatalog {
    guard let previous, !incoming.metricStates.isEmpty else { return incoming }

    var samples = incoming.samples
    var daily = incoming.daily
    var workouts = incoming.workouts
    var revisions = incoming.revisions
    var states = incoming.metricStates

    for (group, state) in incoming.metricStates where state.status == .failed {
        samples.removeAll { metricGroup(for: $0.metric) == group }
        samples.append(contentsOf: previous.samples.filter { metricGroup(for: $0.metric) == group })
        daily.removeAll { metricGroup(for: $0.metric) == group }
        daily.append(contentsOf: previous.daily.filter { metricGroup(for: $0.metric) == group })
        if group == metricGroupWorkout {
            workouts = previous.workouts
        }
        let kept = previous.metricStates[group]
        states[group] = MetricQueryState(
            metric: group,
            status: kept?.status == .ok || kept?.status == .empty ? (kept?.status ?? .failed) : .failed,
            lastSuccessAt: kept?.lastSuccessAt,
            lastAttemptAt: state.lastAttemptAt,
            error: state.error
        )
        revisions.append(contentsOf: previous.revisions)
    }

    let lastSuccess = states.values.compactMap(\.lastSuccessAt).max()
    let failed = states.values.filter { $0.status == .failed || $0.error != nil }.map(\.metric)
    let uniqueFailed = Array(Set(failed)).sorted()
    let readError: String?
    if uniqueFailed.isEmpty {
        readError = incoming.readError
    } else {
        readError = "部分读取未完成：\(uniqueFailed.joined(separator: "、"))。已保留成功读到的记录。"
    }

    return HealthCatalog(
        samples: samples,
        daily: daily,
        workouts: workouts,
        revisions: revisions,
        lastSuccessfulRead: lastSuccess,
        readError: readError,
        metricStates: states
    )
}

func sampleEndAscending(_ lhs: HealthSampleRef, _ rhs: HealthSampleRef) -> Bool {
    if lhs.window.end != rhs.window.end { return lhs.window.end < rhs.window.end }
    return lhs.uuid.uuidString < rhs.uuid.uuidString
}

func sampleEndDescending(_ lhs: HealthSampleRef, _ rhs: HealthSampleRef) -> Bool {
    if lhs.window.end != rhs.window.end { return lhs.window.end > rhs.window.end }
    return lhs.uuid.uuidString < rhs.uuid.uuidString
}