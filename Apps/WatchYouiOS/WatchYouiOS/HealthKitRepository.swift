import Foundation
import HealthKit
import WatchYouCore

final class HealthKitRepository: @unchecked Sendable {
    private let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    static var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [
            HKObjectType.workoutType()
        ]
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { types.insert(sleep) }
        for identifier in [
            HKQuantityTypeIdentifier.heartRate,
            .restingHeartRate,
            .heartRateVariabilitySDNN,
            .stepCount,
            .activeEnergyBurned,
            .appleExerciseTime
        ] {
            if let type = HKObjectType.quantityType(forIdentifier: identifier) {
                types.insert(type)
            }
        }
        return types
    }

    func requestAuthorization() async throws {
        try await store.requestAuthorization(toShare: [], read: Self.readTypes)
    }

    func load(now: Date, timeZone: TimeZone, rpe: [String: Int]) async -> HealthCatalog {
        guard isAvailable else {
            return HealthCatalog(readError: "此设备不支持健康数据")
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let end = now
        let start90 = calendar.date(byAdding: .day, value: -90, to: calendar.startOfDay(for: now)) ?? now
        let start2 = calendar.date(byAdding: .day, value: -2, to: now) ?? now
        let start28 = calendar.date(byAdding: .day, value: -28, to: calendar.startOfDay(for: now)) ?? now

        var catalog = HealthCatalog()
        var errors: [String] = []
        var revisions: [SourceRevision] = []

        do {
            let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
            let sleep = try await samples(type: sleepType, start: start90, end: end)
            for sample in sleep.compactMap({ $0 as? HKCategorySample }) {
                guard let stage = Self.stage(from: sample) else { continue }
                let ref = Self.sampleRef(sample, metric: stage.metric, value: sample.endDate.timeIntervalSince(sample.startDate) / 60, unit: "min", timeZone: timeZone)
                catalog.samples.append(ref)
                revisions.append(Self.revision(sample))
            }
        } catch {
            errors.append("睡眠")
        }

        do {
            let type = HKObjectType.quantityType(forIdentifier: .heartRate)!
            let rows = try await samples(type: type, start: start2, end: end, limit: 400)
            for sample in rows.compactMap({ $0 as? HKQuantitySample }) {
                catalog.samples.append(
                    Self.sampleRef(sample, metric: Metric.heartRate, value: sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute())), unit: "bpm", timeZone: timeZone)
                )
                revisions.append(Self.revision(sample))
            }
        } catch {
            errors.append("心率")
        }

        do {
            let type = HKObjectType.quantityType(forIdentifier: .restingHeartRate)!
            let rows = try await samples(type: type, start: start90, end: end)
            for sample in rows.compactMap({ $0 as? HKQuantitySample }) {
                catalog.samples.append(
                    Self.sampleRef(sample, metric: Metric.restingHeartRate, value: sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute())), unit: "bpm", timeZone: timeZone)
                )
                revisions.append(Self.revision(sample))
            }
        } catch {
            errors.append("静息心率")
        }

        do {
            let type = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!
            let rows = try await samples(type: type, start: start90, end: end)
            for sample in rows.compactMap({ $0 as? HKQuantitySample }) {
                catalog.samples.append(
                    Self.sampleRef(sample, metric: Metric.hrvSDNN, value: sample.quantity.doubleValue(for: HKUnit.secondUnit(with: .milli)), unit: "ms", timeZone: timeZone)
                )
                revisions.append(Self.revision(sample))
            }
        } catch {
            errors.append("HRV")
        }

        if let steps = HKObjectType.quantityType(forIdentifier: .stepCount) {
            do {
                catalog.daily.append(contentsOf: try await daily(
                    type: steps,
                    unit: .count(),
                    metric: Metric.stepCount,
                    unitName: "steps",
                    start: start28,
                    end: end,
                    timeZone: timeZone,
                    options: .cumulativeSum
                ))
            } catch { errors.append("步数") }
        }

        if let energy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) {
            do {
                catalog.daily.append(contentsOf: try await daily(
                    type: energy,
                    unit: .kilocalorie(),
                    metric: Metric.activeEnergy,
                    unitName: "kcal",
                    start: start28,
                    end: end,
                    timeZone: timeZone,
                    options: .cumulativeSum
                ))
            } catch { errors.append("活动能量") }
        }

        if let exercise = HKObjectType.quantityType(forIdentifier: .appleExerciseTime) {
            do {
                catalog.daily.append(contentsOf: try await daily(
                    type: exercise,
                    unit: .minute(),
                    metric: Metric.exerciseMinutes,
                    unitName: "min",
                    start: start28,
                    end: end,
                    timeZone: timeZone,
                    options: .cumulativeSum
                ))
            } catch { errors.append("锻炼时间") }
        }

        do {
            let workouts = try await samples(type: HKObjectType.workoutType(), start: start28, end: end)
            for sample in workouts.compactMap({ $0 as? HKWorkout }) {
                let id = sample.uuid.uuidString
                catalog.workouts.append(
                    WorkoutRecord(
                        uuid: sample.uuid,
                        activity: Self.workoutName(sample.workoutActivityType),
                        window: TimeWindow(start: sample.startDate, end: sample.endDate, timeZone: timeZone),
                        durationMinutes: sample.duration / 60,
                        averageHeartRate: sample.statistics(for: HKQuantityType(.heartRate))?
                            .averageQuantity()?
                            .doubleValue(for: HKUnit.count().unitDivided(by: .minute())),
                        energyKcal: sample.statistics(for: HKQuantityType(.activeEnergyBurned))?
                            .sumQuantity()?
                            .doubleValue(for: .kilocalorie()),
                        sourceRef: sample.sourceRevision.source.bundleIdentifier,
                        rpe: rpe[id]
                    )
                )
                revisions.append(Self.revision(sample))
            }
        } catch {
            errors.append("训练")
        }

        catalog.revisions = revisions
        catalog.lastSuccessfulRead = now
        if !errors.isEmpty {
            catalog.readError = "部分读取未完成：\(errors.joined(separator: "、"))。已保留成功读到的记录。"
        }
        return catalog
    }

    private func samples(type: HKSampleType, start: Date, end: Date, limit: Int = HKObjectQueryNoLimit) async throws -> [HKSample] {
        try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: limit, sortDescriptors: [sort]) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: samples ?? [])
                }
            }
            store.execute(query)
        }
    }

    private func daily(
        type: HKQuantityType,
        unit: HKUnit,
        metric: String,
        unitName: String,
        start: Date,
        end: Date,
        timeZone: TimeZone,
        options: HKStatisticsOptions
    ) async throws -> [DailyQuantity] {
        try await withCheckedThrowingContinuation { continuation in
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            let anchor = calendar.startOfDay(for: start)
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: options,
                anchorDate: anchor,
                intervalComponents: DateComponents(day: 1)
            )
            query.initialResultsHandler = { _, collection, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                var rows: [DailyQuantity] = []
                collection?.enumerateStatistics(from: start, to: end) { stats, _ in
                    let quantity = options.contains(.cumulativeSum) ? stats.sumQuantity() : stats.averageQuantity()
                    if let row = dailyQuantityIfPresent(
                        day: calendar.startOfDay(for: stats.startDate),
                        metric: metric,
                        value: quantity?.doubleValue(for: unit),
                        unit: unitName,
                        lastSampleAt: stats.mostRecentQuantityDateInterval()?.end,
                        sourceRef: "health"
                    ) {
                        rows.append(row)
                    }
                }
                continuation.resume(returning: rows)
            }
            store.execute(query)
        }
    }

    private static func stage(from sample: HKCategorySample) -> SleepStage? {
        switch sample.value {
        case HKCategoryValueSleepAnalysis.inBed.rawValue: return .inBed
        case HKCategoryValueSleepAnalysis.awake.rawValue: return .awake
        case HKCategoryValueSleepAnalysis.asleepCore.rawValue: return .core
        case HKCategoryValueSleepAnalysis.asleepDeep.rawValue: return .deep
        case HKCategoryValueSleepAnalysis.asleepREM.rawValue: return .rem
        case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue: return .unspecified
        case 1: return .unspecified
        default: return nil
        }
    }

    private static func sampleRef(
        _ sample: HKSample,
        metric: String,
        value: Double?,
        unit: String,
        timeZone: TimeZone
    ) -> HealthSampleRef {
        HealthSampleRef(
            uuid: sample.uuid,
            metric: metric,
            value: value,
            unit: unit,
            window: TimeWindow(start: sample.startDate, end: sample.endDate, timeZone: timeZone),
            sourceRef: sample.sourceRevision.source.bundleIdentifier.isEmpty
                ? "unknown"
                : sample.sourceRevision.source.bundleIdentifier
        )
    }

    private static func revision(_ sample: HKSample) -> SourceRevision {
        SourceRevision(
            sourceName: sample.sourceRevision.source.name,
            bundleID: sample.sourceRevision.source.bundleIdentifier,
            productType: sample.device?.model,
            manufacturer: sample.device?.manufacturer
        )
    }

    private static func workoutName(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .walking: return "步行"
        case .running: return "跑步"
        case .cycling: return "骑行"
        case .hiking: return "徒步"
        case .swimming: return "游泳"
        case .yoga: return "瑜伽"
        case .traditionalStrengthTraining, .functionalStrengthTraining: return "力量训练"
        case .coreTraining: return "核心训练"
        case .elliptical: return "椭圆机"
        case .rowing: return "划船"
        case .dance: return "舞蹈"
        case .cooldown: return "放松"
        case .mindAndBody: return "身心练习"
        default: return "训练"
        }
    }
}
