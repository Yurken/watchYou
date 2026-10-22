import XCTest
@testable import WatchYouCore

final class HealthAggregationTests: XCTestCase {
    private var tz: TimeZone { TimeZone(identifier: "Asia/Shanghai")! }
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
    }

    private func sample(
        metric: String,
        start: Date,
        end: Date,
        value: Double?,
        source: String = "com.apple.health",
        uuid: UUID = UUID()
    ) -> HealthSampleRef {
        HealthSampleRef(
            uuid: uuid,
            metric: metric,
            value: value,
            unit: metric == Metric.heartRate ? "bpm" : "min",
            window: TimeWindow(start: start, end: end, timeZone: tz),
            sourceRef: source
        )
    }

    func testLatestHeartRateUsesNewestWhenWindowExceedsLimit() {
        let start = date(2026, 10, 19, 12, 0)
        var samples: [HealthSampleRef] = (0..<500).map { index in
            let stamp = start.addingTimeInterval(Double(index) * 60)
            return sample(metric: Metric.heartRate, start: stamp, end: stamp, value: 60)
        }
        let newestTime = start.addingTimeInterval(500 * 60)
        samples.append(sample(metric: Metric.heartRate, start: newestTime, end: newestTime, value: 180))

        let catalogSamples = heartRateCatalogSamples(samples, seriesLimit: 400)
        let catalog = HealthCatalog(samples: catalogSamples)
        let snapshot = aggregateHealth(
            catalog: catalog,
            preferences: UserPreferences(),
            now: newestTime.addingTimeInterval(60),
            timeZone: tz
        )
        XCTAssertEqual(snapshot.latestHeartRate?.value, 180)
        XCTAssertEqual(snapshot.latestHeartRate?.window.end, newestTime)
        let series = snapshot.heartRateSeries
        XCTAssertFalse(series.isEmpty)
        for index in 1..<series.count {
            XCTAssertLessThanOrEqual(series[index - 1].window.start, series[index].window.start)
        }
        XCTAssertEqual(latestHeartRateSample(from: catalogSamples)?.value, 180)
    }

    func testInBedCoveringDeepSleepDoesNotReplaceAsleepMinutes() {
        let start = date(2026, 10, 20, 23, 0)
        let end = start.addingTimeInterval(60 * 60)
        let catalog = HealthCatalog(samples: [
            sample(metric: Metric.sleepDeep, start: start, end: end, value: 60, source: "watch"),
            sample(metric: Metric.sleepInBed, start: start, end: end, value: 60, source: "phone")
        ])
        let now = date(2026, 10, 21, 12, 0)
        let snapshot = aggregateHealth(catalog: catalog, preferences: UserPreferences(), now: now, timeZone: tz)
        XCTAssertEqual(snapshot.lastNight?.asleepMinutes ?? 0, 60, accuracy: 0.5)
        XCTAssertEqual(snapshot.lastNight?.inBedMinutes ?? 0, 60, accuracy: 0.5)
        XCTAssertEqual(snapshot.lastNight?.stageMinutes[SleepStage.deep.rawValue] ?? 0, 60, accuracy: 0.5)
    }

    func testPreferredInBedSourceDoesNotHideAsleepStages() {
        let start = date(2026, 10, 20, 23, 0)
        let end = start.addingTimeInterval(90 * 60)
        let catalog = HealthCatalog(samples: [
            sample(metric: Metric.sleepCore, start: start, end: end, value: 90, source: "watch"),
            sample(metric: Metric.sleepInBed, start: start, end: end, value: 90, source: "phone")
        ])
        var preferences = UserPreferences()
        preferences.preferredSleepSource = "phone"
        let snapshot = aggregateHealth(
            catalog: catalog,
            preferences: preferences,
            now: date(2026, 10, 21, 12, 0),
            timeZone: tz
        )
        XCTAssertEqual(snapshot.lastNight?.asleepMinutes ?? 0, 90, accuracy: 0.5)
    }

    func testMissingLastNightIsNotBackfilledFromYesterday() {
        let start = date(2026, 10, 19, 23, 0)
        let end = date(2026, 10, 20, 7, 0)
        let catalog = HealthCatalog(samples: [
            sample(metric: Metric.sleepCore, start: start, end: end, value: 480)
        ])
        let now = date(2026, 10, 21, 13, 58)
        let snapshot = aggregateHealth(catalog: catalog, preferences: UserPreferences(), now: now, timeZone: tz)
        XCTAssertNil(snapshot.lastNight)
        XCTAssertNil(snapshot.sleepScore)
        XCTAssertEqual(snapshot.analysisDay, calendar.startOfDay(for: now))
        XCTAssertEqual(snapshot.baselineNights, 1)
        XCTAssertFalse(snapshot.nights.contains { $0.day == snapshot.analysisDay })
    }

    func testAnalyzedNightIsExcludedFromItsOwnBaseline() {
        var catalog = HealthCatalog()
        for offset in 0..<8 {
            let endDay = 21 - (7 - offset)
            let start = date(2026, 10, endDay - 1, 23, 0)
            let end = date(2026, 10, endDay, 7, 0)
            catalog.samples.append(sample(metric: Metric.sleepCore, start: start, end: end, value: 480))
        }
        let now = date(2026, 10, 21, 13, 0)
        let snapshot = aggregateHealth(catalog: catalog, preferences: UserPreferences(), now: now, timeZone: tz)
        XCTAssertEqual(snapshot.lastNight?.day, calendar.startOfDay(for: now))
        XCTAssertEqual(snapshot.baselineNights, 7)
        XCTAssertFalse(snapshot.nights.filter { $0.day < snapshot.lastNight!.day }.isEmpty)
        let windowStart = calendar.date(byAdding: .day, value: -28, to: snapshot.lastNight!.day)!
        let baseline = nightsInCalendarWindow(snapshot.nights, from: windowStart, before: snapshot.lastNight!.day)
        XCTAssertFalse(baseline.contains { $0.day == snapshot.lastNight!.day })
        XCTAssertEqual(baseline.count, 7)
    }

    func testSparseBaselineUsesCalendarDaysNotSuffixEntries() {
        var catalog = HealthCatalog()
        let today = date(2026, 10, 21, 7, 0)
        for offset in 0..<30 {
            let end = calendar.date(byAdding: .day, value: -offset * 2, to: today)!
            let start = end.addingTimeInterval(-8 * 3600)
            catalog.samples.append(sample(metric: Metric.sleepCore, start: start, end: end, value: 480))
        }
        let now = date(2026, 10, 21, 13, 0)
        let snapshot = aggregateHealth(catalog: catalog, preferences: UserPreferences(), now: now, timeZone: tz)
        XCTAssertEqual(snapshot.lastNight?.day, calendar.startOfDay(for: now))
        XCTAssertLessThan(snapshot.baselineNights, 20)
        XCTAssertGreaterThan(snapshot.baselineNights, 0)
        XCTAssertGreaterThan(snapshot.nights.count, snapshot.baselineNights + 1)
        let windowStart = calendar.date(byAdding: .day, value: -28, to: calendar.startOfDay(for: now))!
        let outside = snapshot.nights.filter { $0.day < windowStart }
        XCTAssertFalse(outside.isEmpty)
        XCTAssertFalse(outside.contains { $0.day == snapshot.lastNight?.day })
    }

    func testRestingHeartRateBaselineAggregatesByDay() {
        let today = date(2026, 10, 21, 8, 0)
        var samples: [HealthSampleRef] = []
        let day = date(2026, 10, 20, 8, 0)
        for index in 0..<10 {
            samples.append(sample(
                metric: Metric.restingHeartRate,
                start: day.addingTimeInterval(Double(index) * 60),
                end: day.addingTimeInterval(Double(index) * 60),
                value: index < 9 ? 50 : 140
            ))
        }
        samples.append(sample(metric: Metric.restingHeartRate, start: today, end: today, value: 58))
        let snapshot = aggregateHealth(
            catalog: HealthCatalog(samples: samples),
            preferences: UserPreferences(),
            now: date(2026, 10, 21, 13, 0),
            timeZone: tz
        )
        XCTAssertEqual(snapshot.restingHeartRate, 58)
        XCTAssertEqual(snapshot.restingHeartRateBaseline, 50)
    }

    func testFailedMetricKeepsPreviousReadableHistory() {
        let stamp = date(2026, 10, 21, 12, 0)
        let previous = HealthCatalog(
            samples: [sample(metric: Metric.heartRate, start: stamp, end: stamp, value: 72)],
            lastSuccessfulRead: stamp,
            metricStates: [
                Metric.heartRate: MetricQueryState(metric: Metric.heartRate, status: .ok, lastSuccessAt: stamp, lastAttemptAt: stamp)
            ]
        )
        let later = date(2026, 10, 21, 13, 0)
        let incoming = HealthCatalog(
            lastSuccessfulRead: later,
            readError: "心率",
            metricStates: [
                Metric.heartRate: MetricQueryState(metric: Metric.heartRate, status: .failed, lastAttemptAt: later, error: "心率")
            ]
        )
        let merged = mergeHealthCatalog(previous: previous, incoming: incoming)
        XCTAssertEqual(merged.samples.first?.value, 72)
        XCTAssertEqual(merged.lastSuccessfulRead, stamp)
        XCTAssertEqual(merged.metricStates[Metric.heartRate]?.status, .ok)
        XCTAssertEqual(merged.metricStates[Metric.heartRate]?.lastSuccessAt, stamp)
        XCTAssertNotNil(merged.readError)
    }

    func testEmptyAndFailedMetricStatesAreDistinct() {
        let empty = MetricQueryState(metric: Metric.heartRate, status: .empty, lastAttemptAt: Date())
        let failed = MetricQueryState(metric: Metric.heartRate, status: .failed, lastAttemptAt: Date(), error: "心率")
        XCTAssertNotEqual(empty.status, failed.status)
        XCTAssertNil(empty.error)
        XCTAssertEqual(failed.error, "心率")
    }

    func testStaleHealthRefreshIsNotApplied() {
        XCTAssertTrue(shouldApplyHealthRefresh(startedGeneration: 3, currentGeneration: 3))
        XCTAssertFalse(shouldApplyHealthRefresh(startedGeneration: 2, currentGeneration: 3))
    }

    func testSameSourceStageConflictIsOmittedFromBothSides() {
        let start = date(2026, 10, 20, 23, 0)
        let catalog = HealthCatalog(samples: [
            sample(metric: Metric.sleepCore, start: start, end: start.addingTimeInterval(60 * 60), value: 60, source: "A"),
            sample(metric: Metric.sleepAwake, start: start.addingTimeInterval(20 * 60), end: start.addingTimeInterval(40 * 60), value: 20, source: "A")
        ])
        let snapshot = aggregateHealth(
            catalog: catalog,
            preferences: UserPreferences(),
            now: date(2026, 10, 21, 12, 0),
            timeZone: tz
        )
        XCTAssertEqual(snapshot.lastNight?.asleepMinutes ?? 0, 40, accuracy: 0.5)
        XCTAssertEqual(snapshot.lastNight?.awakeMinutes ?? 0, 0, accuracy: 0.5)
    }

    func testUnspecifiedDoesNotReplaceStagedSleepWhenBothCover() {
        let start = date(2026, 10, 20, 23, 0)
        let end = start.addingTimeInterval(60 * 60)
        let catalog = HealthCatalog(samples: [
            sample(metric: Metric.sleepDeep, start: start, end: end, value: 60, source: "watch"),
            sample(metric: Metric.sleepUnspecified, start: start, end: end, value: 60, source: "phone")
        ])
        let snapshot = aggregateHealth(
            catalog: catalog,
            preferences: UserPreferences(),
            now: date(2026, 10, 21, 12, 0),
            timeZone: tz
        )
        XCTAssertEqual(snapshot.lastNight?.stageMinutes[SleepStage.deep.rawValue] ?? 0, 60, accuracy: 0.5)
        XCTAssertEqual(snapshot.lastNight?.asleepMinutes ?? 0, 60, accuracy: 0.5)
    }
}