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
}