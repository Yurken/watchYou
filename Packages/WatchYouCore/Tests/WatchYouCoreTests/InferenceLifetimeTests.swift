import XCTest
@testable import WatchYouCore

final class InferenceLifetimeTests: XCTestCase {
    private var tz: TimeZone { TimeZone(identifier: "Asia/Shanghai")! }
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
    }

    private func window(_ start: Date, _ end: Date) -> TimeWindow {
        TimeWindow(start: start, end: end, timeZone: tz)
    }

    private func fact(
        id: String,
        scope: String = "heart",
        metric: String = "最近心率",
        value: Double? = 68,
        start: Date,
        end: Date,
        observedAt: Date? = nil
    ) -> EvidenceFact {
        EvidenceFact(
            id: id,
            scope: scope,
            metric: metric,
            value: value,
            unit: "bpm",
            sampleCount: 1,
            window: window(start, end),
            sourceRef: "health",
            synthetic: false,
            observedAt: observedAt ?? end
        )
    }

    private func inference(
        task: String,
        label: String,
        generatedAt: Date,
        inputHash: String,
        observedEnd: Date
    ) -> PersistedInference {
        PersistedInference(
            task: task,
            result: AIResult(
                summary: "历史摘要",
                evidenceIds: ["H1"],
                uncertainties: ["样本有限"],
                suggestions: [],
                emotion: AIEmotion(
                    status: "estimated",
                    label: label,
                    arousal: "moderate",
                    valence: "unknown",
                    evidenceStrength: nil
                )
            ),
            facts: [],
            model: "m",
            mode: "live",
            generatedAt: generatedAt,
            observedEnd: observedEnd,
            inputHash: inputHash,
            window: window(generatedAt, generatedAt)
        )
    }

    private func context(id: UUID, generation: Int, hash: String) -> InferenceRequestContext {
        InferenceRequestContext(
            requestID: id,
            generation: generation,
            task: "mood",
            profileID: "default",
            model: "m",
            normalizedEndpoint: "https://model.example/v1",
            protocolName: "chat",
            authType: "bearer",
            consentVersion: "c",
            inputHash: hash,
            window: window(Date(timeIntervalSince1970: 0), Date(timeIntervalSince1970: 1)),
            createdAt: Date(timeIntervalSince1970: 1)
        )
    }

    private func sample(
        metric: String,
        start: Date,
        end: Date,
        value: Double?,
        source: String = "health"
    ) -> HealthSampleRef {
        HealthSampleRef(
            uuid: UUID(),
            metric: metric,
            value: value,
            unit: metric == Metric.heartRate || metric == Metric.restingHeartRate ? "bpm" : "ms",
            window: window(start, end),
            sourceRef: source
        )
    }

    func testCommitRejectedWhenInputHashChanges() {
        let requestID = UUID()
        let ctx = context(id: requestID, generation: 4, hash: "old")
        XCTAssertTrue(shouldCommitInference(
            context: ctx,
            currentGeneration: 4,
            currentRequestID: requestID,
            currentInputHash: "old"
        ))
        XCTAssertFalse(shouldCommitInference(
            context: ctx,
            currentGeneration: 4,
            currentRequestID: requestID,
            currentInputHash: "new"
        ))
        XCTAssertTrue(shouldCommitInference(
            context: ctx,
            currentGeneration: 4,
            currentRequestID: requestID
        ))
    }

    func testEmptyOrNextDayHealthDoesNotKeepOldMoodCurrent() {
        let now = date(2026, 10, 21, 13, 58)
        let threeDaysAgo = date(2026, 10, 18, 10, 0)
        let old = inference(
            task: "mood",
            label: "可能偏紧绷",
            generatedAt: threeDaysAgo,
            inputHash: "old",
            observedEnd: threeDaysAgo
        )
        let stored = ["mood": old, "today": inference(
            task: "today",
            label: "可能偏紧绷",
            generatedAt: threeDaysAgo,
            inputHash: "old-today",
            observedEnd: threeDaysAgo
        )]

        let emptyShown = displayedInferences(
            stored: stored,
            currentHashes: ["mood": "old", "today": "old-today"],
            analysisDay: now,
            timeZone: tz,
            snapshotEmpty: true,
            modules: ["mood": true, "today": true]
        )
        XCTAssertTrue(emptyShown.isEmpty)
        let emptyWatch = makeWatchSnapshot(
            snapshot: HealthSnapshot(generatedAt: now, timeZone: tz, lastSampleAt: now, isEmpty: true),
            inferences: emptyShown,
            events: [],
            preferences: UserPreferences(),
            now: now
        )
        XCTAssertEqual(emptyWatch.moodLabel, "等待分析")
        XCTAssertNotEqual(emptyWatch.todayTitle, "今日洞察")

        let nextDay = date(2026, 10, 22, 8, 0)
        let nextDayShown = displayedInferences(
            stored: stored,
            currentHashes: ["mood": "old", "today": "old-today"],
            analysisDay: nextDay,
            timeZone: tz,
            snapshotEmpty: false,
            modules: ["mood": true, "today": true]
        )
        XCTAssertTrue(nextDayShown.isEmpty)
        let nextWatch = makeWatchSnapshot(
            snapshot: HealthSnapshot(generatedAt: nextDay, timeZone: tz, lastSampleAt: nextDay, isEmpty: false, baselineNights: 10),
            inferences: nextDayShown,
            events: [],
            preferences: UserPreferences(),
            now: nextDay
        )
        XCTAssertEqual(nextWatch.moodLabel, "等待分析")
        XCTAssertNotEqual(nextWatch.moodLabel, "可能偏紧绷")
        XCTAssertNotEqual(nextWatch.todayTitle, "今日洞察")
    }

    func testClosedModuleHidesCurrentInference() {
        let now = date(2026, 10, 21, 13, 58)
        let stored = inference(task: "mood", label: "可能偏紧绷", generatedAt: now, inputHash: "h", observedEnd: now)
        XCTAssertNil(displayedInference(
            stored: stored,
            currentInputHash: "h",
            analysisDay: now,
            timeZone: tz,
            snapshotEmpty: false,
            moduleEnabled: false
        ))
        let shown = displayedInferences(
            stored: ["mood": stored],
            currentHashes: ["mood": "h"],
            analysisDay: now,
            timeZone: tz,
            snapshotEmpty: false,
            modules: ["mood": false]
        )
        XCTAssertTrue(shown.isEmpty)
    }

    func testHealthChangeInvalidatesCurrentByHash() {
        let now = date(2026, 10, 21, 13, 58)
        let stored = inference(task: "mood", label: "可能偏紧绷", generatedAt: now, inputHash: "before", observedEnd: now)
        XCTAssertNil(displayedInference(
            stored: stored,
            currentInputHash: "after",
            analysisDay: now,
            timeZone: tz,
            snapshotEmpty: false,
            moduleEnabled: true
        ))
        XCTAssertNotNil(displayedInference(
            stored: stored,
            currentInputHash: "before",
            analysisDay: now,
            timeZone: tz,
            snapshotEmpty: false,
            moduleEnabled: true
        ))
    }

    func testPendingLiveKeepsLatestWins() {
        var pending: [String: PendingLiveWork] = [:]
        pending = enqueuePendingLive(pending, task: "mood", inputHash: "h1", question: "q1")
        pending = enqueuePendingLive(pending, task: "today", inputHash: "t1")
        pending = enqueuePendingLive(pending, task: "mood", inputHash: "h2", question: "q2", force: true)
        XCTAssertEqual(pending["mood"]?.inputHash, "h2")
        XCTAssertEqual(pending["mood"]?.question, "q2")
        XCTAssertEqual(pending["mood"]?.force, true)
        XCTAssertEqual(pending.count, 2)
        let taken = takePendingLive(pending, task: "mood")
        XCTAssertEqual(taken.work?.inputHash, "h2")
        XCTAssertNil(taken.remaining["mood"])
        XCTAssertEqual(taken.remaining["today"]?.inputHash, "t1")
        let empty = takePendingLive(taken.remaining, task: "mood")
        XCTAssertNil(empty.work)
    }

    func testObservedAtComesFromSampleNotBucketEnd() {
        let now = date(2026, 10, 21, 14, 0)
        let dayStart = calendar.startOfDay(for: now)
        let bucket = calendarDayWindow(containing: now, timeZone: tz)
        XCTAssertEqual(bucket.end, date(2026, 10, 22, 0, 0))
        let steps = fact(
            id: "A1",
            scope: "activity",
            metric: "今日步数",
            value: 3200,
            start: dayStart,
            end: bucket.end,
            observedAt: now
        )
        XCTAssertEqual(inferenceObservedAt(facts: [steps]), now)
        XCTAssertLessThan(inferenceObservedAt(facts: [steps])!, bucket.end)

        let persisted = applyCachedInference(
            result: AIResult(summary: "s", evidenceIds: ["A1"], uncertainties: ["u"], suggestions: [], emotion: nil),
            facts: [steps],
            model: "m",
            mode: "live",
            originalGeneratedAt: now,
            servedAt: now,
            cacheHit: false,
            inputHash: "h",
            window: bucket,
            observedAt: inferenceObservedAt(facts: [steps]) ?? now,
            task: "today"
        )
        XCTAssertEqual(persisted.observedEnd, now)
        XCTAssertLessThan(persisted.observedEnd, bucket.end)

        let snapshot = HealthSnapshot(
            generatedAt: now,
            timeZone: tz,
            todaySteps: 3200,
            todayStepsObservedAt: now,
            isEmpty: false
        )
        let facts = factsForTask(
            task: "today",
            snapshot: snapshot,
            preferences: UserPreferences(),
            events: [],
            contextNote: "",
            allowedScopes: ["activity": true, "sleep": false, "heart": false, "habits": false, "context": false],
            now: now
        )
        let a1 = facts.first { $0.id == "A1" }
        XCTAssertEqual(a1?.observedAt, now)
        XCTAssertEqual(a1?.window.end, bucket.end)
        XCTAssertEqual(inferenceObservedAt(facts: facts), now)
    }

    func testSameDayIdenticalFactsShareInputHash() throws {
        let first = date(2026, 10, 21, 13, 58)
        let later = first.addingTimeInterval(47)
        let recorded = date(2026, 10, 21, 9, 0)
        let hrEnd = date(2026, 10, 21, 12, 10)
        let snapshot = HealthSnapshot(
            generatedAt: first,
            timeZone: tz,
            latestHeartRate: sample(metric: Metric.heartRate, start: hrEnd, end: hrEnd, value: 68),
            todaySteps: 3200,
            todayStepsObservedAt: date(2026, 10, 21, 12, 0),
            isEmpty: false,
            baselineNights: 7
        )
        let profile = try cleanProfile([
            "id": "default",
            "name": "t",
            "baseURL": "https://model.example/v1",
            "protocol": "chat",
            "model": "test-model",
            "auth": "bearer",
            "maxTokens": 1200,
            "tokenField": "max_tokens",
            "timeout": 45,
            "allowLocalHTTP": false
        ])
        func hash(at callTime: Date) -> String {
            let facts = factsForTask(
                task: "mood",
                snapshot: snapshot,
                preferences: UserPreferences(),
                events: [],
                contextNote: "刚喝了咖啡",
                contextRecordedAt: recorded,
                allowedScopes: Dictionary(uniqueKeysWithValues: AIDataScopes.map { ($0, true) }),
                now: callTime
            )
            let packet = buildEvidencePacket(
                task: "mood",
                window: inferenceObservationWindow(facts: facts, lastNight: snapshot.lastNight, timeZone: tz),
                baselineValidDays: 7,
                facts: facts,
                allowedScopes: Set(AIDataScopes),
                question: nil,
                synthetic: false
            )
            return makeInferenceCacheKey(
                packet: packet,
                contextText: sentContextText(facts),
                profile: profile,
                promptVersion: promptVersion,
                sourcePolicyVersion: sourcePolicyVersion,
                consentVersion: "c",
                generation: 1
            ).inputHash
        }
        XCTAssertEqual(hash(at: first), hash(at: later))
    }

    func testExpiredContextDoesNotUnlockValence() throws {
        let now = date(2026, 10, 21, 13, 58)
        let yesterday = date(2026, 10, 20, 16, 0)
        let facts = factsForTask(
            task: "mood",
            snapshot: HealthSnapshot(generatedAt: now, timeZone: tz, hrvValidDays: 7, isEmpty: false, baselineNights: 7),
            preferences: UserPreferences(),
            events: [],
            contextNote: "刚喝了咖啡",
            contextRecordedAt: yesterday,
            allowedScopes: Dictionary(uniqueKeysWithValues: AIDataScopes.map { ($0, true) }),
            now: now
        )
        XCTAssertFalse(facts.contains { $0.id == "C1" })
        XCTAssertFalse(hasSendableContext(facts))
        let heart = fact(id: "H1", start: now, end: now, observedAt: now)
        let json = """
        {"summary":"观测只能支持有限推断。","evidenceIds":["H1"],"uncertainties":["无法确定具体情绪。"],"suggestions":[],"emotion":{"status":"estimated","label":"可能偏紧绷","arousal":"moderate","valence":"positive"}}
        """
        XCTAssertThrowsError(try parseResult(text: json, facts: [heart] + facts)) { error in
            XCTAssertTrue(String(describing: error).contains("愉悦度方向"))
        }
    }

    func testMissingRHRHistoryYieldsNoRecoveryScore() {
        XCTAssertNil(recoveryScore(
            hrv: 50,
            restingHeartRate: 80,
            sleepScoreValue: 90,
            baselineHRV: 48,
            baselineRHR: 80,
            validDays: 14,
            rhrValidDays: 0
        ))

        var catalog = HealthCatalog()
        for day in 0..<15 {
            let endDay = 21 - (14 - day)
            let start = date(2026, 10, endDay - 1, 23, 0)
            let end = date(2026, 10, endDay, 7, 0)
            catalog.samples.append(sample(metric: Metric.sleepCore, start: start, end: end, value: 480))
            catalog.samples.append(sample(metric: Metric.hrvSDNN, start: end.addingTimeInterval(-60), end: end.addingTimeInterval(-60), value: 50))
        }
        let todayRHR = date(2026, 10, 21, 8, 0)
        catalog.samples.append(sample(metric: Metric.restingHeartRate, start: todayRHR, end: todayRHR, value: 80))
        let now = date(2026, 10, 21, 13, 58)
        let snapshot = aggregateHealth(catalog: catalog, preferences: UserPreferences(), now: now, timeZone: tz)
        XCTAssertEqual(snapshot.rhrValidDays, 0)
        XCTAssertEqual(snapshot.restingHeartRate, 80)
        XCTAssertNil(snapshot.restingHeartRateBaseline)
        XCTAssertNil(snapshot.recoveryScore)
        XCTAssertGreaterThanOrEqual(snapshot.hrvValidDays, 14)
    }

    func testBusyDrainLeavesPendingIntact() {
        var pending: [String: PendingLiveWork] = [:]
        pending = enqueuePendingLive(pending, task: "mood", inputHash: "h1")
        XCTAssertFalse(shouldDrainPendingLive(isBusy: true, isDraining: false))
        XCTAssertFalse(shouldDrainPendingLive(isBusy: false, isDraining: true))
        XCTAssertEqual(pending["mood"]?.inputHash, "h1")
        XCTAssertTrue(shouldDrainPendingLive(isBusy: false, isDraining: false))
        let taken = takePendingLive(pending, task: "mood")
        XCTAssertEqual(taken.work?.inputHash, "h1")
        XCTAssertTrue(taken.remaining.isEmpty)
    }

    func testCorrectedSleepFactsInvalidateDisplayedInference() throws {
        let now = date(2026, 10, 21, 13, 58)
        let long = sleepSnapshot(asleep: 420, now: now)
        let short = sleepSnapshot(asleep: 360, now: now)
        let hashLong = try taskHash("sleep", snapshot: long, now: now)
        let hashShort = try taskHash("sleep", snapshot: short, now: now)
        XCTAssertNotEqual(hashLong, hashShort)
        let stored = inference(task: "sleep", label: "可能偏平稳", generatedAt: now, inputHash: hashLong, observedEnd: now)
        XCTAssertNotNil(displayedInference(
            stored: stored,
            currentInputHash: hashLong,
            analysisDay: now,
            timeZone: tz,
            snapshotEmpty: false,
            moduleEnabled: true
        ))
        XCTAssertNil(displayedInference(
            stored: stored,
            currentInputHash: hashShort,
            analysisDay: now,
            timeZone: tz,
            snapshotEmpty: false,
            moduleEnabled: true
        ))
        XCTAssertEqual(displayedInference(
            stored: stored,
            currentInputHash: hashLong,
            analysisDay: now,
            timeZone: tz,
            snapshotEmpty: false,
            moduleEnabled: true
        )?.inputHash, stored.inputHash)
    }

    func testQualityGateBlocksDisplayedInference() {
        let now = date(2026, 10, 21, 13, 58)
        let stored = inference(task: "mood", label: "可能偏紧绷", generatedAt: now, inputHash: "h", observedEnd: now)
        XCTAssertNotNil(displayedInference(
            stored: stored,
            currentInputHash: "h",
            analysisDay: now,
            timeZone: tz,
            snapshotEmpty: false,
            moduleEnabled: true,
            qualityBlocked: false
        ))
        XCTAssertNil(displayedInference(
            stored: stored,
            currentInputHash: "h",
            analysisDay: now,
            timeZone: tz,
            snapshotEmpty: false,
            moduleEnabled: true,
            qualityBlocked: true
        ))
    }

    func testUnsavedContextDraftIsNotSent() {
        let now = date(2026, 10, 21, 13, 58)
        var state = AppPersistedState()
        state = applyingContextNote(state, text: "刚喝了咖啡", at: now)
        let scopes = Dictionary(uniqueKeysWithValues: AIDataScopes.map { ($0, true) })
        let saved = factsForTask(
            task: "mood",
            snapshot: HealthSnapshot(generatedAt: now, timeZone: tz, hrvValidDays: 7, isEmpty: false, baselineNights: 7),
            preferences: UserPreferences(),
            events: [],
            contextNote: state.contextNote,
            contextRecordedAt: state.contextNoteRecordedAt,
            allowedScopes: scopes,
            now: now
        )
        XCTAssertEqual(saved.first { $0.id == "C1" }?.text, "刚喝了咖啡")
        let draft = "刚喝了茶"
        XCTAssertEqual(state.contextNote, "刚喝了咖啡")
        XCTAssertFalse(saved.contains { $0.text == draft })
        var empty = AppPersistedState()
        let closed = factsForTask(
            task: "mood",
            snapshot: HealthSnapshot(generatedAt: now, timeZone: tz, hrvValidDays: 7, isEmpty: false, baselineNights: 7),
            preferences: UserPreferences(),
            events: [],
            contextNote: empty.contextNote,
            contextRecordedAt: empty.contextNoteRecordedAt,
            allowedScopes: scopes,
            now: now
        )
        XCTAssertFalse(closed.contains { $0.id == "C1" })
        empty = applyingContextNote(empty, text: draft, at: now)
        XCTAssertEqual(empty.contextNote, draft)
    }

    func testFailedSaveLeavesStateUnchangedAndRetryAddsOnce() {
        var memory = AppPersistedState()
        var disk: AppPersistedState?
        struct Full: Error {}
        var fail = true
        let save: (AppPersistedState) throws -> Void = { next in
            if fail { throw Full() }
            disk = next
        }
        let event = HabitEvent(id: "w1", kind: "water", amount: 250, createdAt: date(2026, 10, 21, 13, 0))
        XCTAssertThrowsError(try committingAppState(current: memory, update: { next in
            let merged = addingEvent(next.events, event, tombstones: next.eventTombstones)
            next.events = merged.events
            next.eventTombstones = merged.tombstones
        }, save: save))
        XCTAssertTrue(memory.events.isEmpty)
        XCTAssertNil(disk)

        fail = false
        memory = try! committingAppState(current: memory, update: { next in
            let merged = addingEvent(next.events, event, tombstones: next.eventTombstones)
            next.events = merged.events
            next.eventTombstones = merged.tombstones
        }, save: save)
        XCTAssertEqual(memory.events.count, 1)
        XCTAssertEqual(disk?.events.count, 1)
        XCTAssertEqual(disk?.events.first?.amount, 250)
    }

    func testFailedResetKeepsRecords() {
        var memory = AppPersistedState()
        memory.contextNote = "刚喝了咖啡"
        memory.events = [HabitEvent(id: "w1", kind: "water", amount: 250, createdAt: date(2026, 10, 21, 13, 0))]
        struct Full: Error {}
        XCTAssertThrowsError(try committingAppState(current: memory, update: { $0 = resettingAppRecords($0) }, save: { _ in throw Full() }))
        XCTAssertEqual(memory.contextNote, "刚喝了咖啡")
        XCTAssertEqual(memory.events.count, 1)
    }

    private func sleepSnapshot(asleep: Double, now: Date) -> HealthSnapshot {
        let start = date(2026, 10, 20, 23, 18)
        let end = date(2026, 10, 21, 7, 2)
        let night = SleepNight(
            day: calendar.startOfDay(for: now),
            mainStart: start,
            mainEnd: end,
            asleepMinutes: asleep,
            awakeMinutes: 12,
            inBedMinutes: asleep + 12,
            stageMinutes: [:],
            naps: [],
            slices: [],
            coverage: 1,
            sourceRef: "health",
            midpointMinutes: nil
        )
        return HealthSnapshot(
            generatedAt: now,
            timeZone: tz,
            lastNight: night,
            isEmpty: false,
            baselineNights: 10,
            analysisDay: calendar.startOfDay(for: now)
        )
    }

    private func taskHash(_ task: String, snapshot: HealthSnapshot, now: Date) throws -> String {
        let facts = factsForTask(
            task: task,
            snapshot: snapshot,
            preferences: UserPreferences(),
            events: [],
            contextNote: "",
            allowedScopes: Dictionary(uniqueKeysWithValues: AIDataScopes.map { ($0, true) }),
            now: now
        )
        let packet = buildEvidencePacket(
            task: task,
            window: inferenceObservationWindow(facts: facts, lastNight: snapshot.lastNight, timeZone: tz),
            baselineValidDays: snapshot.hrvValidDays,
            facts: facts,
            allowedScopes: Set(AIDataScopes),
            question: nil,
            synthetic: false
        )
        let profile = try cleanProfile([
            "id": "default",
            "name": "t",
            "baseURL": "https://model.example/v1",
            "protocol": "chat",
            "model": "test-model",
            "auth": "bearer",
            "maxTokens": 1200,
            "tokenField": "max_tokens",
            "timeout": 45,
            "allowLocalHTTP": false
        ])
        return makeInferenceCacheKey(
            packet: packet,
            contextText: sentContextText(facts),
            profile: profile,
            promptVersion: promptVersion,
            sourcePolicyVersion: sourcePolicyVersion,
            consentVersion: "c",
            generation: 1
        ).inputHash
    }
}
