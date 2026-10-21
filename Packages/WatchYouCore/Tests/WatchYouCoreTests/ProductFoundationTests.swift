import XCTest
@testable import WatchYouCore

final class ProductFoundationTests: XCTestCase {
    private var tz: TimeZone { TimeZone(identifier: "Asia/Shanghai")! }
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func sample(
        metric: String,
        start: Date,
        end: Date,
        value: Double?,
        source: String = "com.apple.health"
    ) -> HealthSampleRef {
        HealthSampleRef(
            uuid: UUID(),
            metric: metric,
            value: value,
            unit: "min",
            window: TimeWindow(start: start, end: end, timeZone: tz),
            sourceRef: source
        )
    }

    func testLastNightUsesLongestEpisodeAndExcludesNapFromScore() {
        let mainStart = date(2026, 10, 20, 23, 18)
        let mainEnd = date(2026, 10, 21, 7, 2)
        let napStart = date(2026, 10, 21, 14, 20)
        let napEnd = date(2026, 10, 21, 14, 50)
        var catalog = HealthCatalog()
        catalog.samples = [
            sample(metric: Metric.sleepCore, start: mainStart, end: mainStart.addingTimeInterval(274 * 60), value: 274),
            sample(metric: Metric.sleepDeep, start: mainStart.addingTimeInterval(274 * 60), end: mainStart.addingTimeInterval(347 * 60), value: 73),
            sample(metric: Metric.sleepREM, start: mainStart.addingTimeInterval(347 * 60), end: mainStart.addingTimeInterval(446 * 60), value: 99),
            sample(metric: Metric.sleepAwake, start: mainStart.addingTimeInterval(200 * 60), end: mainStart.addingTimeInterval(218 * 60), value: 18),
            sample(metric: Metric.sleepUnspecified, start: napStart, end: napEnd, value: 30)
        ]
        catalog.lastSuccessfulRead = mainEnd

        let now = date(2026, 10, 21, 13, 58)
        let snapshot = aggregateHealth(catalog: catalog, preferences: UserPreferences(), now: now, timeZone: tz)

        XCTAssertEqual(snapshot.lastNight?.asleepMinutes ?? 0, 446, accuracy: 1)
        XCTAssertEqual(snapshot.lastNight?.naps.count, 1)
        XCTAssertEqual(snapshot.lastNight?.naps.first?.minutes ?? 0, 30, accuracy: 1)
        XCTAssertNil(snapshot.sleepScore, "单夜不足以构成规律基线，应弃权而不是给分")
    }

    func testSleepScoreAppearsWithSevenHistoricalNights() {
        var catalog = HealthCatalog()
        for day in 0..<8 {
            let endDay = 21 - (7 - day)
            let start = date(2026, 10, endDay - 1, 23, 18)
            let end = date(2026, 10, endDay, 7, 2)
            catalog.samples.append(sample(metric: Metric.sleepCore, start: start, end: end, value: 446))
        }
        let now = date(2026, 10, 21, 13, 58)
        let snapshot = aggregateHealth(catalog: catalog, preferences: UserPreferences(), now: now, timeZone: tz)
        XCTAssertEqual(snapshot.baselineNights, 7)
        XCTAssertNotNil(snapshot.sleepScore)
        XCTAssertEqual(snapshot.lastNight?.asleepMinutes ?? 0, 464, accuracy: 1)
    }

    func testEmptyCatalogStaysUnknown() {
        let snapshot = aggregateHealth(
            catalog: HealthCatalog(),
            preferences: UserPreferences(),
            now: date(2026, 10, 21, 13, 58),
            timeZone: tz
        )
        XCTAssertTrue(snapshot.isEmpty)
        XCTAssertNil(snapshot.sleepScore)
        XCTAssertNil(snapshot.recoveryScore)
        XCTAssertNil(snapshot.latestHeartRate)
    }

    func testOverlappingSleepDoesNotDoubleCount() {
        let start = date(2026, 10, 20, 23, 0)
        let catalog = HealthCatalog(samples: [
            sample(metric: Metric.sleepCore, start: start, end: start.addingTimeInterval(120 * 60), value: 120, source: "A"),
            sample(metric: Metric.sleepCore, start: start.addingTimeInterval(60 * 60), end: start.addingTimeInterval(180 * 60), value: 120, source: "A")
        ])
        let now = date(2026, 10, 21, 12, 0)
        let snapshot = aggregateHealth(catalog: catalog, preferences: UserPreferences(), now: now, timeZone: tz)
        XCTAssertEqual(snapshot.lastNight?.asleepMinutes ?? 0, 180, accuracy: 1)
    }

    func testWaterEventsAreIdempotentAndDayScoped() {
        let day = date(2026, 10, 21, 10, 0)
        let a = HabitEvent(id: "w1", kind: "water", amount: 250, createdAt: day)
        let dup = HabitEvent(id: "w1", kind: "water", amount: 250, createdAt: day)
        let otherDay = HabitEvent(id: "w2", kind: "water", amount: 500, createdAt: date(2026, 10, 20, 10, 0))
        let events = addingEvent(addingEvent([a], dup), otherDay)
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(waterTotal(events: events, day: day, timeZone: tz), 250)
    }

    func testQualityGateEmptyAndWorkout() {
        var snapshot = HealthSnapshot(generatedAt: Date(), timeZone: tz, isEmpty: true)
        let config = defaultAIConfig()
        XCTAssertEqual(
            qualityGate(task: "mood", snapshot: snapshot, config: config, facts: [], hasContext: false, now: Date()),
            "暂无可读数据，暂不推断"
        )
        snapshot.isEmpty = false
        snapshot.duringWorkout = true
        XCTAssertEqual(
            qualityGate(task: "mood", snapshot: snapshot, config: config, facts: [], hasContext: false, now: Date()),
            "正在运动或刚结束运动，暂不比较静息状态"
        )
    }

    func testLocalMoodDoesNotSetValence() {
        var snapshot = HealthSnapshot(generatedAt: Date(), timeZone: tz, isEmpty: false)
        snapshot.nocturnalHRV = 40
        snapshot.hrvBaseline = 54
        snapshot.latestHeartRate = sample(
            metric: Metric.heartRate,
            start: Date(),
            end: Date(),
            value: 70
        )
        let result = localInference(task: "mood", snapshot: snapshot, facts: [], question: nil)
        XCTAssertEqual(result.emotion?.valence, "unknown")
        XCTAssertEqual(result.emotion?.label, "可能偏紧绷")
        XCTAssertTrue(result.uncertainties.contains { $0.contains("本地规则") })
    }

    func testBackupStripsConsentAndForcesDemo() throws {
        var state = AppPersistedState()
        state.aiConfig = state.aiConfig.replacing(mode: "live")
        state.consent = AIPermission(
            profileID: "default",
            normalizedEndpoint: "https://example.com/v1",
            model: "x",
            authType: "bearer",
            scopes: ["sleep": true],
            scopeVersion: "1",
            grantedAt: Date()
        )
        state.events = [HabitEvent(id: "w1", kind: "water", amount: 250, createdAt: Date())]
        let data = try exportBackup(state: state, now: Date())
        let restored = try importBackup(data)
        XCTAssertEqual(restored.aiConfig.mode, "demo")
        XCTAssertNil(restored.consent)
        XCTAssertEqual(restored.events.count, 1)
    }

    func testBackupRejectsOversizedAndSecrets() {
        XCTAssertThrowsError(try importBackup(Data(repeating: 1, count: 2_000_001)))
        let payload = "{\"schema\":\"watchyou.app.v1\",\"apiKey\":\"sk-secret\"}"
        XCTAssertThrowsError(try importBackup(Data(payload.utf8)))
    }

    func testWatchSnapshotTruncatesAndOmitsSecrets() {
        let snapshot = HealthSnapshot(
            generatedAt: Date(),
            timeZone: tz,
            isEmpty: true
        )
        let watch = makeWatchSnapshot(
            snapshot: snapshot,
            inferences: [:],
            events: [],
            preferences: UserPreferences(),
            now: Date()
        )
        XCTAssertEqual(watch.todayTitle, "等待数据")
        XCTAssertTrue(watch.empty)
        XCTAssertEqual(watch.waterGoal, 2000)
        XCTAssertEqual(watch.sleepWindowText, "暂无睡眠")
    }

    func testWatchSnapshotTitlesForStaleBaselineAndInsight() {
        let now = date(2026, 10, 21, 13, 58)
        let staleSnap = HealthSnapshot(
            generatedAt: now,
            timeZone: tz,
            lastSampleAt: now.addingTimeInterval(-48 * 3600),
            isEmpty: false,
            baselineNights: 10
        )
        let stale = makeWatchSnapshot(
            snapshot: staleSnap,
            inferences: [:],
            events: [],
            preferences: UserPreferences(),
            now: now
        )
        XCTAssertEqual(stale.todayTitle, "历史摘要")
        XCTAssertTrue(stale.stale)

        let baseline = HealthSnapshot(
            generatedAt: now,
            timeZone: tz,
            lastSampleAt: now,
            isEmpty: false,
            baselineNights: 3
        )
        XCTAssertEqual(
            makeWatchSnapshot(snapshot: baseline, inferences: [:], events: [], preferences: UserPreferences(), now: now).todayTitle,
            "正在认识你的节奏"
        )

        let night = SleepNight(
            day: calendar.startOfDay(for: date(2026, 10, 21, 7, 2)),
            mainStart: date(2026, 10, 20, 23, 18),
            mainEnd: date(2026, 10, 21, 7, 2),
            asleepMinutes: 446,
            awakeMinutes: 18,
            inBedMinutes: 0,
            stageMinutes: ["core": 274, "deep": 73, "rem": 99],
            naps: [],
            slices: [],
            coverage: 1,
            sourceRef: "health",
            midpointMinutes: 3 * 60 + 10
        )
        let ready = HealthSnapshot(
            generatedAt: now,
            timeZone: tz,
            lastNight: night,
            lastSampleAt: now,
            isEmpty: false,
            baselineNights: 7
        )
        let today = PersistedInference(
            task: "today",
            result: AIResult(
                summary: "昨夜睡眠接近个人目标。",
                evidenceIds: ["S1"],
                uncertainties: ["本地规则摘要"],
                suggestions: [],
                emotion: nil
            ),
            facts: [],
            model: "本地规则摘要",
            mode: "local",
            generatedAt: now,
            observedEnd: now,
            inputHash: "h",
            window: TimeWindow(start: night.mainStart!, end: night.mainEnd!, timeZone: tz)
        )
        let insight = makeWatchSnapshot(
            snapshot: ready,
            inferences: ["today": today],
            events: [HabitEvent(id: "w1", kind: "water", amount: 250, createdAt: now)],
            preferences: UserPreferences(),
            now: now
        )
        XCTAssertEqual(insight.todayTitle, "今日洞察")
        XCTAssertEqual(insight.sleepText, "7 小时 26 分")
        XCTAssertEqual(insight.sleepWindowText, "23:18–07:02")
        XCTAssertEqual(insight.waterMl, 250)
        XCTAssertFalse(insight.stale)
    }

    func testLocalInferenceIsRuleSummaryNotLiveSuccess() {
        let snapshot = HealthSnapshot(generatedAt: Date(), timeZone: tz, isEmpty: false)
        let result = localInference(task: "today", snapshot: snapshot, facts: [], question: nil)
        XCTAssertTrue(result.uncertainties.contains { $0.contains("本地规则摘要") })
        XCTAssertFalse(result.uncertainties.contains { $0.contains("模型分析") })
        XCTAssertFalse(result.summary.contains("已收到模型"))
    }

    func testParseResultRejectsUnknownEvidenceAndDoesNotLabelSuccess() {
        let fact = EvidenceFact(
            id: "S1",
            scope: "sleep",
            metric: "睡眠时长",
            value: 446,
            unit: "min",
            sampleCount: 1,
            window: TimeWindow(start: date(2026, 10, 20, 23, 18), end: date(2026, 10, 21, 7, 2), timeZone: tz),
            sourceRef: "health",
            synthetic: false
        )
        let invalid = """
        {"summary":"看起来一切正常。","evidenceIds":["FAKE"],"uncertainties":["无"],"suggestions":[],"emotion":null}
        """
        XCTAssertThrowsError(try parseResult(text: invalid, facts: [fact])) { error in
            XCTAssertTrue(String(describing: error).contains("不存在的证据"))
        }
        let valid = """
        {"summary":"昨夜睡眠接近个人目标，仍有不确定性。","evidenceIds":["S1"],"uncertainties":["样本有限"],"suggestions":[],"emotion":null}
        """
        let parsed = try? parseResult(text: valid, facts: [fact])
        XCTAssertEqual(parsed?.evidenceIds, ["S1"])
        XCTAssertFalse(parsed?.uncertainties.isEmpty ?? true)
    }

    func testWatchOutboundIsIdempotentByIDAndRevision() {
        let first = WatchOutboundEvent(id: "e1", kind: "water", amount: 250, createdAt: Date(), revision: 1)
        let duplicate = WatchOutboundEvent(id: "e1", kind: "water", amount: 250, createdAt: Date(), revision: 1)
        let updated = WatchOutboundEvent(id: "e1", kind: "water", amount: 250, createdAt: Date(), revision: 2)
        var queue: [WatchOutboundEvent] = []
        queue = mergingOutbound(queue, first)
        queue = mergingOutbound(queue, duplicate)
        XCTAssertEqual(queue.count, 1)
        queue = mergingOutbound(queue, updated)
        XCTAssertEqual(queue.first?.revision, 2)
        queue = removingOutbound(queue, id: "e1")
        XCTAssertTrue(queue.isEmpty)
        let habit = first.asHabitEvent()
        XCTAssertEqual(habit.source, "watch")
        XCTAssertEqual(addingEvent([habit], habit).count, 1)
    }

    func testCircularMeanNearMidnight() {
        let mean = circularMeanMinutes([23 * 60 + 50, 10])
        XCTAssertNotNil(mean)
        XCTAssertEqual(circularDeltaMinutes(mean!, 0), 0, accuracy: 15)
    }

    func testFactsRespectScopes() {
        var snapshot = HealthSnapshot(generatedAt: Date(), timeZone: tz, isEmpty: false)
        snapshot.lastNight = SleepNight(
            day: calendar.startOfDay(for: date(2026, 10, 21, 7, 0)),
            mainStart: date(2026, 10, 20, 23, 18),
            mainEnd: date(2026, 10, 21, 7, 2),
            asleepMinutes: 446,
            awakeMinutes: 18,
            inBedMinutes: 0,
            stageMinutes: ["core": 446],
            naps: [],
            slices: [],
            coverage: 1,
            sourceRef: "health",
            midpointMinutes: 3 * 60 + 10
        )
        let facts = factsForTask(
            task: "mood",
            snapshot: snapshot,
            preferences: UserPreferences(),
            events: [],
            contextNote: "刚喝了咖啡",
            allowedScopes: ["sleep": true, "heart": false, "activity": false, "habits": false, "context": false],
            now: date(2026, 10, 21, 13, 58)
        )
        XCTAssertTrue(facts.contains { $0.id == "S1" })
        XCTAssertFalse(facts.contains { $0.scope == "heart" })
        XCTAssertFalse(facts.contains { $0.id == "C1" }, "未授权的文字范围不得进入证据")
    }

    func testLoadConfigPreservesLiveModeOnlyWhenAsked() throws {
        let dict: [String: Any] = [
            "version": 2,
            "active": "default",
            "profiles": [profileDictionary(defaultAIProfile())],
            "mode": "live",
            "auto": true,
            "dailyLimit": 20,
            "modules": ["today": true],
            "scopes": ["sleep": true]
        ]
        let restored = try loadConfig(dict, preserveMode: false)
        XCTAssertEqual(restored.mode, "demo")
        let kept = try loadConfig(dict, preserveMode: true)
        XCTAssertEqual(kept.mode, "live")
    }

    func testDailyQuantityIfPresentSkipsNilAndZero() {
        XCTAssertNil(dailyQuantityIfPresent(
            day: date(2026, 10, 21, 0, 0),
            metric: Metric.stepCount,
            value: nil,
            unit: "steps",
            lastSampleAt: date(2026, 10, 21, 13, 58),
            sourceRef: "health"
        ))
        XCTAssertNil(dailyQuantityIfPresent(
            day: date(2026, 10, 21, 0, 0),
            metric: Metric.stepCount,
            value: 0,
            unit: "steps",
            lastSampleAt: date(2026, 10, 21, 13, 58),
            sourceRef: "health"
        ))
        let row = dailyQuantityIfPresent(
            day: date(2026, 10, 21, 0, 0),
            metric: Metric.stepCount,
            value: 3200,
            unit: "steps",
            lastSampleAt: date(2026, 10, 21, 12, 0),
            sourceRef: "health"
        )
        XCTAssertEqual(row?.value, 3200)
        XCTAssertEqual(row?.lastSampleAt, date(2026, 10, 21, 12, 0))
    }

    func testZeroDailyRowsDoNotFabricateTodayActivityOrFreshness() {
        let now = date(2026, 10, 21, 13, 58)
        let sleepStart = date(2026, 10, 18, 23, 18)
        let sleepEnd = date(2026, 10, 19, 7, 2)
        var catalog = HealthCatalog()
        catalog.samples = [
            sample(metric: Metric.sleepCore, start: sleepStart, end: sleepEnd, value: 446)
        ]
        catalog.daily = [
            DailyQuantity(day: calendar.startOfDay(for: now), metric: Metric.stepCount, value: 0, unit: "steps", lastSampleAt: now, sourceRef: "health"),
            DailyQuantity(day: calendar.startOfDay(for: now), metric: Metric.activeEnergy, value: 0, unit: "kcal", lastSampleAt: now, sourceRef: "health"),
            DailyQuantity(day: calendar.startOfDay(for: now), metric: Metric.exerciseMinutes, value: 0, unit: "min", lastSampleAt: now, sourceRef: "health")
        ]

        let snapshot = aggregateHealth(catalog: catalog, preferences: UserPreferences(), now: now, timeZone: tz)

        XCTAssertNil(snapshot.todaySteps)
        XCTAssertNil(snapshot.todayEnergyKcal)
        XCTAssertNil(snapshot.todayExerciseMinutes)
        XCTAssertEqual(snapshot.lastSampleAt, sleepEnd)
        XCTAssertGreaterThan(now.timeIntervalSince(snapshot.lastSampleAt!), 36 * 3600)

        let facts = factsForTask(
            task: "activity",
            snapshot: snapshot,
            preferences: UserPreferences(),
            events: [],
            contextNote: "",
            allowedScopes: ["sleep": true, "heart": true, "activity": true, "habits": false, "context": false],
            now: now
        )
        XCTAssertFalse(facts.contains { $0.id == "A1" })
        XCTAssertFalse(facts.contains { $0.metric == "今日步数" })
    }

    func testWaterEventDoesNotFillHealthEmptiness() {
        let now = date(2026, 10, 21, 13, 58)
        let events = [HabitEvent(id: "w1", kind: "water", amount: 250, createdAt: now)]
        let snapshot = aggregateHealth(
            catalog: HealthCatalog(),
            preferences: UserPreferences(),
            events: events,
            now: now,
            timeZone: tz
        )
        XCTAssertTrue(snapshot.isEmpty)
        XCTAssertNil(snapshot.todaySteps)
        XCTAssertNil(snapshot.todayEnergyKcal)
        XCTAssertNil(snapshot.todayExerciseMinutes)
        XCTAssertNil(snapshot.lastNight)
        XCTAssertNil(snapshot.lastSampleAt)
    }

    func testDisplayedWaterDoesNotDoubleCountMergedIds() {
        let now = date(2026, 10, 21, 13, 58)
        let pending = WatchOutboundEvent(id: "w1", kind: "water", amount: 250, createdAt: now)
        let extra = WatchOutboundEvent(id: "w2", kind: "water", amount: 150, createdAt: now)
        let snapshot = WatchSnapshot(
            generatedAt: now,
            observedAt: now,
            todayTitle: "t",
            todaySummary: "s",
            moodLabel: "m",
            moodNote: "n",
            sleepText: "sleep",
            sleepWindowText: "—",
            recoveryText: "—",
            waterMl: 250,
            waterGoal: 2000,
            empty: false,
            stale: false,
            includedWaterIds: ["w1"]
        )
        XCTAssertEqual(displayedWater(snapshot: snapshot, pending: [pending]), 250)
        XCTAssertEqual(displayedWater(snapshot: snapshot, pending: [pending, extra]), 400)
        XCTAssertEqual(displayedWater(snapshot: nil, pending: [pending]), 250)

        let health = HealthSnapshot(generatedAt: now, timeZone: tz, isEmpty: true)
        let watch = makeWatchSnapshot(
            snapshot: health,
            inferences: [:],
            events: [HabitEvent(id: "w1", kind: "water", amount: 250, createdAt: now)],
            preferences: UserPreferences(),
            now: now
        )
        XCTAssertEqual(watch.waterMl, 250)
        XCTAssertEqual(watch.includedWaterIds, ["w1"])
        XCTAssertEqual(displayedWater(snapshot: watch, pending: [pending]), 250)

        let json = """
        {"generatedAt":"2026-10-21T05:58:00Z","todayTitle":"t","todaySummary":"s","moodLabel":"m","moodNote":"n","sleepText":"sleep","sleepWindowText":"—","recoveryText":"—","waterMl":250,"waterGoal":2000,"empty":false,"stale":false}
        """
        let decoded = decodeWatchPayload(WatchSnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(decoded?.includedWaterIds, [])
        XCTAssertEqual(decoded?.waterMl, 250)
    }
}