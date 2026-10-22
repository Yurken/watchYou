import XCTest
@testable import WatchYouCore

final class WatchSyncTests: XCTestCase {
    private var tz: TimeZone { TimeZone(identifier: "Asia/Shanghai")! }
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    func testHigherRevisionWinsAndLowerRevisionIsIgnored() {
        let first = HabitEvent(id: "w1", kind: "water", amount: 250, createdAt: Date(), revision: 1)
        let second = HabitEvent(id: "w1", kind: "water", amount: 500, createdAt: Date(), revision: 2)
        let merged = addingEvent(addingEvent([], second), first)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.amount, 500)
        XCTAssertEqual(merged.first?.revision, 2)
    }

    func testSameRevisionIsIdempotent() {
        let first = HabitEvent(id: "w1", kind: "water", amount: 250, createdAt: Date(), revision: 2)
        let copy = HabitEvent(id: "w1", kind: "water", amount: 900, createdAt: Date(), revision: 2)
        let merged = addingEvent([first], copy)
        XCTAssertEqual(merged.first?.amount, 250)
    }

    func testTombstoneBlocksLateLowerRevision() {
        let live = HabitEvent(id: "w1", kind: "water", amount: 250, createdAt: Date(), revision: 1)
        let deleted = deletingEvent([live], id: "w1", revision: 2, tombstones: [:])
        XCTAssertTrue(deleted.events.isEmpty)
        let late = HabitEvent(id: "w1", kind: "water", amount: 250, createdAt: Date(), revision: 1)
        let revived = addingEvent(deleted.events, late, tombstones: deleted.tombstones)
        XCTAssertTrue(revived.events.isEmpty)
        XCTAssertEqual(revived.tombstones["w1"], 2)
    }

    func testNewerRevisionCanReviveAfterTombstone() {
        let live = HabitEvent(id: "w1", kind: "water", amount: 250, createdAt: Date(), revision: 1)
        let deleted = deletingEvent([live], id: "w1", revision: 2, tombstones: [:])
        let restored = HabitEvent(id: "w1", kind: "water", amount: 250, createdAt: Date(), revision: 3)
        let merged = addingEvent(deleted.events, restored, tombstones: deleted.tombstones)
        XCTAssertEqual(merged.events.count, 1)
        XCTAssertNil(merged.tombstones["w1"])
    }

    func testDisplayedWaterIgnoresOtherDayPending() {
        let today = date(2026, 10, 21, 10, 0)
        let yesterday = date(2026, 10, 20, 22, 0)
        let snapshot = WatchSnapshot(
            generatedAt: today,
            observedAt: today,
            todayTitle: "t",
            todaySummary: "s",
            moodLabel: "m",
            moodNote: "n",
            sleepText: "sleep",
            sleepWindowText: "—",
            recoveryText: "—",
            waterMl: 100,
            waterGoal: 2000,
            empty: false,
            stale: false,
            includedWaterIds: ["today"],
            logicalDay: calendar.startOfDay(for: today),
            timeZoneIdentifier: tz.identifier,
            snapshotRevision: 4
        )
        let pendingYesterday = WatchOutboundEvent(id: "old", kind: "water", amount: 250, createdAt: yesterday)
        XCTAssertEqual(displayedWater(snapshot: snapshot, pending: [pendingYesterday], now: today), 100)
        let pendingToday = WatchOutboundEvent(id: "new", kind: "water", amount: 150, createdAt: today)
        XCTAssertEqual(displayedWater(snapshot: snapshot, pending: [pendingYesterday, pendingToday], now: today), 250)
    }

    func testOlderSnapshotDoesNotRollBackWatchUI() {
        let now = date(2026, 10, 21, 10, 0)
        let current = WatchSnapshot(
            generatedAt: now,
            observedAt: now,
            todayTitle: "new",
            todaySummary: "s",
            moodLabel: "m",
            moodNote: "n",
            sleepText: "sleep",
            sleepWindowText: "—",
            recoveryText: "—",
            waterMl: 400,
            waterGoal: 2000,
            empty: false,
            stale: false,
            snapshotRevision: 5
        )
        let older = WatchSnapshot(
            generatedAt: now.addingTimeInterval(-60),
            observedAt: now,
            todayTitle: "old",
            todaySummary: "s",
            moodLabel: "m",
            moodNote: "n",
            sleepText: "sleep",
            sleepWindowText: "—",
            recoveryText: "—",
            waterMl: 100,
            waterGoal: 2000,
            empty: false,
            stale: false,
            snapshotRevision: 3
        )
        XCTAssertTrue(shouldAcceptWatchSnapshot(current: nil, incoming: current))
        XCTAssertFalse(shouldAcceptWatchSnapshot(current: current, incoming: older))
        XCTAssertTrue(shouldAcceptWatchSnapshot(current: older, incoming: current))
    }

    func testAckOnlyRemovesMatchingOrOlderRevision() {
        let first = WatchOutboundEvent(id: "e1", kind: "water", amount: 250, createdAt: Date(), revision: 1)
        let second = WatchOutboundEvent(id: "e1", kind: "water", amount: 250, createdAt: Date(), revision: 2)
        var queue = mergingOutbound(mergingOutbound([], first), second)
        queue = acknowledgeOutbound(queue, ack: WatchAck(eventID: "e1", revision: 1))
        XCTAssertEqual(queue.first?.revision, 2)
        queue = acknowledgeOutbound(queue, ack: WatchAck(eventID: "e1", revision: 2))
        XCTAssertTrue(queue.isEmpty)
    }

    func testPersistFailureDoesNotProduceAck() {
        let event = WatchOutboundEvent(id: "e1", kind: "water", amount: 250, createdAt: Date(), revision: 1)
        struct DiskFull: Error {}
        let ack = ingestWatchEvent(events: [], tombstones: [:], event: event) { _, _ in
            throw DiskFull()
        }
        XCTAssertNil(ack)
        var saved: [HabitEvent] = []
        let ok = ingestWatchEvent(events: [], tombstones: [:], event: event) { events, _ in
            saved = events
        }
        XCTAssertEqual(ok?.eventID, "e1")
        XCTAssertEqual(ok?.revision, 1)
        XCTAssertEqual(saved.count, 1)
    }

    func testTombstonedIdIsIncludedSoWatchPendingDoesNotRevive() {
        let now = date(2026, 10, 21, 10, 0)
        let health = HealthSnapshot(generatedAt: now, timeZone: tz, isEmpty: true)
        let watch = makeWatchSnapshot(
            snapshot: health,
            inferences: [:],
            events: [],
            preferences: UserPreferences(),
            now: now,
            tombstones: ["w1": 2],
            snapshotRevision: 1
        )
        XCTAssertTrue(watch.includedWaterIds.contains("w1"))
        let pending = WatchOutboundEvent(id: "w1", kind: "water", amount: 250, createdAt: now, revision: 1)
        XCTAssertEqual(displayedWater(snapshot: watch, pending: [pending], now: now), 0)
    }

    func testResetTombstonesBlockReplayAndKeepNewEvents() {
        let old = HabitEvent(id: "w1", kind: "water", amount: 250, createdAt: Date(), revision: 1)
        var state = AppPersistedState()
        state.events = [old]
        state.contextNote = "刚喝了咖啡"
        state.contextNoteRecordedAt = Date()
        state.inferences = ["mood": PersistedInference(
            task: "mood",
            result: AIResult(summary: "s", evidenceIds: ["H1"], uncertainties: ["u"], suggestions: [], emotion: nil),
            facts: [],
            model: "m",
            mode: "live",
            generatedAt: Date(),
            observedEnd: Date(),
            inputHash: "h",
            window: TimeWindow(start: Date(), end: Date(), timeZone: tz)
        )]
        let cleared = resettingAppRecords(state)
        XCTAssertTrue(cleared.events.isEmpty)
        XCTAssertTrue(cleared.inferences.isEmpty)
        XCTAssertEqual(cleared.contextNote, "")
        XCTAssertNil(cleared.contextNoteRecordedAt)
        XCTAssertEqual(cleared.eventTombstones["w1"], 1)
        XCTAssertEqual(cleared.generation, state.generation + 1)

        let replay = addingEvent(cleared.events, old, tombstones: cleared.eventTombstones)
        XCTAssertTrue(replay.events.isEmpty)
        XCTAssertEqual(replay.tombstones["w1"], 1)

        let fresh = HabitEvent(id: "w2", kind: "water", amount: 150, createdAt: Date(), revision: 1)
        let kept = addingEvent(replay.events, fresh, tombstones: replay.tombstones)
        XCTAssertEqual(kept.events.map(\.id), ["w2"])

        var persisted: [HabitEvent] = []
        let ack = ingestWatchEvent(
            events: cleared.events,
            tombstones: cleared.eventTombstones,
            event: WatchOutboundEvent(id: "w1", kind: "water", amount: 250, createdAt: Date(), revision: 1)
        ) { events, _ in
            persisted = events
        }
        XCTAssertEqual(ack?.eventID, "w1")
        XCTAssertTrue(persisted.isEmpty)
    }

    func testImportedBackupDoesNotRollBackWatchSnapshotOrder() {
        let now = date(2026, 10, 21, 13, 58)
        var current = AppPersistedState()
        current.watchSnapshotRevision = 120
        current.generation = 8
        var imported = AppPersistedState()
        imported.watchSnapshotRevision = 30
        imported.generation = 2
        imported.events = [HabitEvent(id: "w1", kind: "water", amount: 250, createdAt: now)]
        let next = applyingImportedBackup(current: current, imported: imported)
        XCTAssertEqual(next.watchSnapshotRevision, 120)
        XCTAssertEqual(next.generation, 9)
        XCTAssertEqual(next.events.count, 1)

        let watchCurrent = WatchSnapshot(
            generatedAt: now.addingTimeInterval(-120),
            observedAt: now,
            todayTitle: "old",
            todaySummary: "s",
            moodLabel: "m",
            moodNote: "n",
            sleepText: "sleep",
            sleepWindowText: "—",
            recoveryText: "—",
            waterMl: 1000,
            waterGoal: 2000,
            empty: false,
            stale: false,
            snapshotRevision: 120
        )
        let rolledBack = WatchSnapshot(
            generatedAt: now,
            observedAt: now,
            todayTitle: "restored",
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
            snapshotRevision: 31
        )
        XCTAssertFalse(shouldAcceptWatchSnapshot(current: watchCurrent, incoming: rolledBack))
        let forwarded = WatchSnapshot(
            generatedAt: now,
            observedAt: now,
            todayTitle: "new",
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
            snapshotRevision: next.watchSnapshotRevision + 1
        )
        XCTAssertTrue(shouldAcceptWatchSnapshot(current: watchCurrent, incoming: forwarded))
    }

    func testYesterdaySnapshotPlusTodayPendingShowsTodayWater() {
        let yesterday = date(2026, 10, 21, 23, 59)
        let today = date(2026, 10, 22, 0, 1)
        let snapshot = WatchSnapshot(
            generatedAt: yesterday,
            observedAt: yesterday,
            todayTitle: "t",
            todaySummary: "s",
            moodLabel: "m",
            moodNote: "n",
            sleepText: "sleep",
            sleepWindowText: "—",
            recoveryText: "—",
            waterMl: 1000,
            waterGoal: 2000,
            empty: false,
            stale: false,
            includedWaterIds: ["old"],
            logicalDay: calendar.startOfDay(for: yesterday),
            timeZoneIdentifier: tz.identifier,
            snapshotRevision: 8
        )
        let pending = WatchOutboundEvent(id: "new", kind: "water", amount: 250, createdAt: today)
        XCTAssertEqual(displayedWater(snapshot: snapshot, pending: [pending], now: today), 250)
        XCTAssertEqual(
            displayedWater(
                snapshot: snapshot,
                pending: [
                    WatchOutboundEvent(id: "old", kind: "water", amount: 1000, createdAt: yesterday),
                    pending
                ],
                now: today
            ),
            250
        )
    }

    func testAckWithOnlyEventIDDoesNotDropHigherRevision() {
        let ack = parseWatchAck(["ack": "e"])
        XCTAssertEqual(ack?.eventID, "e")
        XCTAssertEqual(ack?.revision, 1)
        let first = WatchOutboundEvent(id: "e", kind: "water", amount: 250, createdAt: Date(), revision: 1)
        let second = WatchOutboundEvent(id: "e", kind: "water", amount: 250, createdAt: Date(), revision: 2)
        var queue = mergingOutbound(mergingOutbound([], first), second)
        queue = acknowledgeOutbound(queue, ack: ack!)
        XCTAssertEqual(queue.first?.revision, 2)
        XCTAssertEqual(queue.count, 1)
    }

    func testWatchMoodBecomesPendingAfterLocalMidnight() {
        let yesterday = date(2026, 10, 21, 13, 58)
        let today = date(2026, 10, 22, 8, 0)
        let mood = PersistedInference(
            task: "mood",
            result: AIResult(
                summary: "s",
                evidenceIds: ["H1"],
                uncertainties: ["u"],
                suggestions: [],
                emotion: AIEmotion(
                    status: "estimated",
                    label: "可能偏紧绷",
                    arousal: "moderate",
                    valence: "unknown",
                    evidenceStrength: "有限"
                )
            ),
            facts: [],
            model: "m",
            mode: "live",
            generatedAt: yesterday,
            observedEnd: yesterday,
            inputHash: "h",
            window: TimeWindow(start: yesterday, end: yesterday, timeZone: tz)
        )
        let snapshot = makeWatchSnapshot(
            snapshot: HealthSnapshot(
                generatedAt: yesterday,
                timeZone: tz,
                lastSampleAt: yesterday,
                isEmpty: false,
                baselineNights: 10
            ),
            inferences: ["mood": mood],
            events: [],
            preferences: UserPreferences(),
            now: yesterday
        )
        let current = watchMoodDisplay(snapshot: snapshot, now: yesterday)
        XCTAssertEqual(current.label, "可能偏紧绷")
        XCTAssertTrue(current.current)
        let nextDay = watchMoodDisplay(snapshot: snapshot, now: today)
        XCTAssertEqual(nextDay.label, "待更新")
        XCTAssertEqual(nextDay.note, "10月21日")
        XCTAssertFalse(nextDay.current)
    }

    func testWatchFooterOmitsConnectedNote() {
        XCTAssertNil(watchFooterStatus(connectionNote: "iPhone 已连接", pending: false))
        XCTAssertNil(watchFooterStatus(connectionNote: "正在连接 iPhone", pending: false))
        XCTAssertEqual(watchFooterStatus(connectionNote: "iPhone 已连接", pending: true), "待同步")
        XCTAssertEqual(watchFooterStatus(connectionNote: "请在 iPhone 安装 watch you", pending: false), "请在 iPhone 安装 watch you")
    }
}
