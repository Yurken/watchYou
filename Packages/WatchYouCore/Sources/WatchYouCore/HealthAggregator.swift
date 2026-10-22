import Foundation

/// Build a UI-facing snapshot from HealthKit-normalized samples. Deterministic for the same catalog and clock.
public func aggregateHealth(
    catalog: HealthCatalog,
    preferences: UserPreferences,
    events: [HabitEvent] = [],
    now: Date,
    timeZone: TimeZone = .current
) -> HealthSnapshot {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let today = calendar.startOfDay(for: now)

    let liveSamples = catalog.samples.filter { !$0.deleted }
    let staged = stagedSleep(from: liveSamples, preferred: preferences.preferredSleepSource)
    let inBed = inBedTimeline(from: liveSamples, preferred: preferences.preferredSleepSource)
    let nights = buildNights(staged: staged, inBed: inBed, calendar: calendar, timeZone: timeZone)
    let windowStart = calendar.date(byAdding: .day, value: -28, to: today) ?? today
    let lastNight = nights.first { $0.day == today }
    let baselineNights = nightsInCalendarWindow(nights, from: windowStart, before: today)
    let midpointHistory = baselineNights.compactMap(\.midpointMinutes)
    let midpointMean = circularMeanMinutes(Array(midpointHistory))
    let deviation = {
        guard let mean = midpointMean, let current = lastNight?.midpointMinutes else { return 0.0 }
        return circularDeltaMinutes(current, mean)
    }()

    let sleep = lastNight.flatMap { night in
        sleepScore(
            asleepMinutes: night.asleepMinutes,
            awakeMinutes: night.awakeMinutes,
            goalMinutes: Double(preferences.sleepGoalMinutes),
            midpointDeviationMinutes: deviation,
            validNights: baselineNights.count,
            coverage: night.coverage
        )
    }

    let hrvByNight = nocturnalHRVByNight(samples: liveSamples, nights: nights)
    let hrvHistory = baselineNights.compactMap { hrvByNight[$0.day] }
    let hrvBaseline = median(hrvHistory)
    let lastHRV = lastNight.flatMap { hrvByNight[$0.day] }
    let lastHRVCount = lastNight.map { night in
        liveSamples.filter { sample in
            guard sample.metric == Metric.hrvSDNN, let start = night.mainStart, let end = night.mainEnd else {
                return false
            }
            return sample.window.start >= start && sample.window.start <= end
        }.count
    } ?? 0

    let nextDay = calendar.date(byAdding: .day, value: 1, to: today) ?? today
    let rhrByDay = dailyMedianValues(
        samples: liveSamples,
        metric: Metric.restingHeartRate,
        from: windowStart,
        before: today,
        timeZone: timeZone
    )
    let rhrToday = dailyMedianValues(
        samples: liveSamples,
        metric: Metric.restingHeartRate,
        from: today,
        before: nextDay,
        timeZone: timeZone
    )[today]
    let rhrBaseline = median(Array(rhrByDay.values))
    let rhr = rhrToday
    let rhrValidDays = rhrByDay.count

    let recovery = {
        guard let hrv = lastHRV, let rhrValue = rhr, let sleepValue = sleep, let baselineRHR = rhrBaseline else {
            return nil as RecoveryScore?
        }
        return recoveryScore(
            hrv: hrv,
            restingHeartRate: rhrValue,
            sleepScoreValue: Double(sleepValue.value),
            baselineHRV: hrvBaseline ?? hrv,
            baselineRHR: baselineRHR,
            validDays: hrvHistory.count,
            rhrValidDays: rhrValidDays
        )
    }()

    let heartSamples = liveSamples.filter { $0.metric == Metric.heartRate }
    let newestHeart = latestHeartRateSample(from: heartSamples)
    let preferredHeart = pickPreferred(
        conflicts: recentCluster(heartSamples, around: newestHeart?.window.end ?? now, window: 60),
        preferred: preferences.preferredHeartSource
    )
    let latestHeart = preferredHeart.samples.max(by: sampleEndAscending) ?? newestHeart
    let dayAgo = now.addingTimeInterval(-24 * 3600)
    let series = heartRateSeries(from: heartSamples, since: dayAgo)

    let recentHRVSample = liveSamples
        .filter { $0.metric == Metric.hrvSDNN && now.timeIntervalSince($0.window.end) <= 3600 }
        .max(by: { $0.window.end < $1.window.end })

    func todayValue(_ metric: String) -> Double? {
        observedDailyValue(catalog.daily, metric: metric, day: today)
    }

    let weekStart = calendar.date(byAdding: .day, value: -6, to: today) ?? today
    let weekExercise = observedDailyRows(catalog.daily)
        .filter { $0.metric == Metric.exerciseMinutes && $0.day >= weekStart && $0.day <= today }
        .sorted { $0.day < $1.day }

    let workouts = catalog.workouts.sorted { $0.window.end > $1.window.end }
    let duringWorkout = workouts.contains { workout in
        now >= workout.window.start && now <= workout.window.end.addingTimeInterval(30 * 60)
    }

    let lastSampleAt = latestObservedAt(samples: liveSamples, daily: catalog.daily, workouts: workouts)

    let sleepTrend = Array(nights.suffix(28))

    return HealthSnapshot(
        generatedAt: now,
        timeZone: timeZone,
        lastNight: lastNight,
        nights: nights,
        sleepScore: sleep,
        recoveryScore: recovery,
        latestHeartRate: latestHeart,
        heartRateSeries: series,
        restingHeartRate: rhr,
        restingHeartRateBaseline: rhrBaseline,
        nocturnalHRV: lastHRV,
        nocturnalHRVSampleCount: lastHRVCount,
        hrvBaseline: hrvBaseline,
        hrvValidDays: hrvHistory.suffix(28).count,
        recentHRV: recentHRVSample?.value,
        recentHRVAt: recentHRVSample?.window.end,
        todaySteps: todayValue(Metric.stepCount),
        todayStepsObservedAt: observedDailyRows(catalog.daily).first { $0.metric == Metric.stepCount && $0.day == today }?.lastSampleAt,
        todayEnergyKcal: todayValue(Metric.activeEnergy),
        todayExerciseMinutes: todayValue(Metric.exerciseMinutes),
        rhrValidDays: rhrValidDays,
        weekExercise: weekExercise,
        sleepTrend: sleepTrend,
        workouts: workouts,
        sources: resolve(revisions: catalog.revisions),
        lastSampleAt: lastSampleAt,
        lastReadAt: catalog.lastSuccessfulRead,
        readError: catalog.readError,
        isEmpty: catalog.isEmpty,
        duringWorkout: duringWorkout,
        baselineNights: baselineNights.count,
        metricStates: catalog.metricStates,
        analysisDay: today
    )
}

func stagedSleep(from samples: [HealthSampleRef], preferred: String?) -> [SleepStageSlice] {
    resolveSleepTimeline(
        samples: samples.filter { sample in
            guard let stage = SleepStage.from(metric: sample.metric) else { return false }
            return stage != .inBed
        },
        preferred: preferred
    )
}

func inBedTimeline(from samples: [HealthSampleRef], preferred: String?) -> [SleepStageSlice] {
    resolveSleepTimeline(
        samples: samples.filter { SleepStage.from(metric: $0.metric) == .inBed },
        preferred: preferred
    )
}

private func resolveSleepTimeline(samples: [HealthSampleRef], preferred: String?) -> [SleepStageSlice] {
    let valid = samples.compactMap { sample -> SleepStageSlice? in
        guard let stage = SleepStage.from(metric: sample.metric), sample.window.end > sample.window.start else { return nil }
        return SleepStageSlice(start: sample.window.start, end: sample.window.end, stage: stage, sourceRef: sample.sourceRef)
    }
    guard !valid.isEmpty else { return [] }

    let cuts = Array(Set(valid.flatMap { [$0.start, $0.end] })).sorted()
    var result: [SleepStageSlice] = []
    for index in 0..<(cuts.count - 1) {
        let start = cuts[index]
        let end = cuts[index + 1]
        let covering = valid.filter { $0.start <= start && $0.end >= end }
        guard !covering.isEmpty else { continue }
        let grouped = Dictionary(grouping: covering, by: \.sourceRef)
        var candidates: [(source: String, stage: SleepStage)] = []
        for (source, slices) in grouped {
            if let stage = resolvedSleepStage(slices.map(\.stage)) {
                candidates.append((source, stage))
            }
        }
        guard let chosen = candidates.sorted(by: { lhs, rhs in
            let lp = lhs.source == preferred ? 0 : 1
            let rp = rhs.source == preferred ? 0 : 1
            if lp != rp { return lp < rp }
            let lu = lhs.stage == .unspecified ? 1 : 0
            let ru = rhs.stage == .unspecified ? 1 : 0
            if lu != ru { return lu < ru }
            return lhs.source < rhs.source
        }).first else { continue }
        if let last = result.last,
           last.end == start,
           last.stage == chosen.stage,
           last.sourceRef == chosen.source {
            result[result.count - 1] = SleepStageSlice(start: last.start, end: end, stage: last.stage, sourceRef: last.sourceRef)
        } else {
            result.append(SleepStageSlice(start: start, end: end, stage: chosen.stage, sourceRef: chosen.source))
        }
    }
    return result
}

func resolvedSleepStage(_ stages: [SleepStage]) -> SleepStage? {
    let unique = Set(stages)
    if unique.count <= 1 { return unique.first }
    let specified = unique.filter { $0 != .unspecified }
    if specified.count == 1 { return specified.first }
    if specified.isEmpty { return .unspecified }
    return nil
}

private func buildNights(
    staged: [SleepStageSlice],
    inBed: [SleepStageSlice],
    calendar: Calendar,
    timeZone: TimeZone
) -> [SleepNight] {
    let asleepSlices = staged.filter(\.stage.isAsleep)
    let episodes = mergeEpisodes(asleepSlices, gap: 45 * 60)
    guard !episodes.isEmpty else { return [] }

    let days = Set(episodes.map { calendar.startOfDay(for: $0.end) }).sorted()
    return days.compactMap { day in
        let windowStart = calendar.date(byAdding: .hour, value: -6, to: day) ?? day
        let windowEnd = calendar.date(byAdding: .hour, value: 12, to: day) ?? day
        let endingToday = episodes.filter { calendar.startOfDay(for: $0.end) == day }
        let overnight = endingToday.filter { $0.start < windowEnd && $0.end > windowStart }
        guard let main = overnight.max(by: { $0.duration < $1.duration })
                ?? endingToday.max(by: { $0.duration < $1.duration }) else { return nil }

        let mainSlices = staged.filter { $0.start < main.end && $0.end > main.start }
        let asleepMinutes = unionIntervalMinutes(
            mainSlices.filter(\.stage.isAsleep).map { (max($0.start, main.start), min($0.end, main.end)) }
        )
        let awakeMinutes = unionIntervalMinutes(
            mainSlices.filter { $0.stage == .awake }.map { (max($0.start, main.start), min($0.end, main.end)) }
        )
        let inBedMinutes = unionIntervalMinutes(
            inBed.filter { $0.start < main.end && $0.end > main.start }.map { (max($0.start, main.start), min($0.end, main.end)) }
        )
        var stageMinutes: [String: Double] = [:]
        for slice in mainSlices where slice.stage.isAsleep || slice.stage == .awake {
            stageMinutes[slice.stage.rawValue, default: 0] += overlapMinutes(slice.start, slice.end, main.start, main.end)
        }

        let span = main.end.timeIntervalSince(main.start) / 60
        let coverage = span > 0 ? min(1, (asleepMinutes + awakeMinutes) / span) : 0
        let midpoint = minutesFromMidnight(
            main.start.addingTimeInterval(main.end.timeIntervalSince(main.start) / 2),
            timeZone: timeZone
        )

        let naps = endingToday
            .filter { $0.start != main.start || $0.end != main.end }
            .compactMap { episode -> NapRecord? in
                let minutes = unionIntervalMinutes(
                    staged.filter { $0.stage.isAsleep && $0.start < episode.end && $0.end > episode.start }
                        .map { (max($0.start, episode.start), min($0.end, episode.end)) }
                )
                guard minutes >= 10 && minutes <= 180 else { return nil }
                return NapRecord(start: episode.start, end: episode.end, minutes: minutes, sourceRef: episode.sourceRef)
            }

        return SleepNight(
            day: day,
            mainStart: main.start,
            mainEnd: main.end,
            asleepMinutes: asleepMinutes,
            awakeMinutes: awakeMinutes,
            inBedMinutes: inBedMinutes,
            stageMinutes: stageMinutes,
            naps: naps,
            slices: mainSlices,
            coverage: coverage,
            sourceRef: main.sourceRef,
            midpointMinutes: midpoint
        )
    }
}

private func overlapMinutes(_ start: Date, _ end: Date, _ windowStart: Date, _ windowEnd: Date) -> Double {
    let lo = max(start, windowStart)
    let hi = min(end, windowEnd)
    guard hi > lo else { return 0 }
    return hi.timeIntervalSince(lo) / 60
}

private struct SleepEpisode {
    var start: Date
    var end: Date
    var sourceRef: String
    var duration: TimeInterval { end.timeIntervalSince(start) }
}

private func mergeEpisodes(_ slices: [SleepStageSlice], gap: TimeInterval) -> [SleepEpisode] {
    let sorted = slices.sorted { $0.start < $1.start }
    var episodes: [SleepEpisode] = []
    for slice in sorted {
        if var current = episodes.last, slice.start.timeIntervalSince(current.end) <= gap {
            current.end = max(current.end, slice.end)
            episodes[episodes.count - 1] = current
        } else {
            episodes.append(SleepEpisode(start: slice.start, end: slice.end, sourceRef: slice.sourceRef))
        }
    }
    return episodes
}

private func nocturnalHRVByNight(samples: [HealthSampleRef], nights: [SleepNight]) -> [Date: Double] {
    var result: [Date: Double] = [:]
    for night in nights {
        guard let start = night.mainStart, let end = night.mainEnd else { continue }
        let values = samples.filter {
            $0.metric == Metric.hrvSDNN && $0.window.start >= start && $0.window.start <= end
        }.compactMap(\.value)
        if let med = median(values) {
            result[night.day] = med
        }
    }
    return result
}

private func recentCluster(_ samples: [HealthSampleRef], around date: Date, window: TimeInterval) -> [HealthSampleRef] {
    samples.filter { abs($0.window.end.timeIntervalSince(date)) <= window }
}

/// HealthKit empty buckets arrive as nil or 0. They are not measurements.
public func dailyQuantityIfPresent(
    day: Date,
    metric: String,
    value: Double?,
    unit: String,
    lastSampleAt: Date?,
    sourceRef: String
) -> DailyQuantity? {
    guard let value, value > 0 else { return nil }
    return DailyQuantity(
        day: day,
        metric: metric,
        value: value,
        unit: unit,
        lastSampleAt: lastSampleAt,
        sourceRef: sourceRef
    )
}

public func observedDailyRows(_ rows: [DailyQuantity]) -> [DailyQuantity] {
    rows.filter { $0.value > 0 }
}

public func observedDailyValue(_ rows: [DailyQuantity], metric: String, day: Date) -> Double? {
    observedDailyRows(rows).first { $0.metric == metric && $0.day == day }?.value
}

public func latestObservedAt(
    samples: [HealthSampleRef],
    daily: [DailyQuantity],
    workouts: [WorkoutRecord]
) -> Date? {
    [
        samples.filter { !$0.deleted }.map(\.window.end).max(),
        observedDailyRows(daily).compactMap(\.lastSampleAt).max(),
        workouts.map(\.window.end).max()
    ].compactMap { $0 }.max()
}

public func waterTotal(events: [HabitEvent], day: Date, timeZone: TimeZone, pendingCounts: Bool = true) -> Double {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let start = calendar.startOfDay(for: day)
    let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
    return events
        .filter { $0.kind == "water" && $0.createdAt >= start && $0.createdAt < end && (pendingCounts || !$0.pending) }
        .reduce(0) { $0 + $1.amount }
}