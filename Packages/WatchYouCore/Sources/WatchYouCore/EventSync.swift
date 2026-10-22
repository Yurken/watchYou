import Foundation

public struct WatchAck: Equatable, Sendable, Codable {
    public var eventID: String
    public var revision: Int

    public init(eventID: String, revision: Int) {
        self.eventID = eventID
        self.revision = revision
    }
}

public let watchAckKey = "watchyou.ack.v1"

public func addingEvent(_ events: [HabitEvent], _ event: HabitEvent) -> [HabitEvent] {
    addingEvent(events, event, tombstones: [:]).events
}

public func addingEvent(
    _ events: [HabitEvent],
    _ event: HabitEvent,
    tombstones: [String: Int]
) -> (events: [HabitEvent], tombstones: [String: Int]) {
    if let buried = tombstones[event.id], buried >= event.revision {
        return (events, tombstones)
    }
    var nextTombs = tombstones
    if (nextTombs[event.id] ?? 0) < event.revision {
        nextTombs[event.id] = nil
    }
    if let index = events.firstIndex(where: { $0.id == event.id }) {
        if event.revision < events[index].revision {
            return (events, nextTombs)
        }
        if event.revision == events[index].revision {
            return (events, nextTombs)
        }
        var next = events
        next[index] = event
        return (next, nextTombs)
    }
    return (events + [event], nextTombs)
}

public func resettingEvents(
    events: [HabitEvent],
    tombstones: [String: Int]
) -> (events: [HabitEvent], tombstones: [String: Int]) {
    var nextTombs = tombstones
    for event in events {
        nextTombs[event.id] = max(nextTombs[event.id] ?? 0, event.revision)
    }
    return ([], nextTombs)
}

public func resettingAppRecords(_ state: AppPersistedState) -> AppPersistedState {
    let cleared = resettingEvents(events: state.events, tombstones: state.eventTombstones)
    var next = state
    next.events = cleared.events
    next.eventTombstones = cleared.tombstones
    next.feedback = []
    next.inferences = [:]
    next.chat = []
    next.contextNote = ""
    next.contextNoteRecordedAt = nil
    next.generation += 1
    return next
}

public func adoptedWatchSnapshotRevision(current: Int, imported: Int) -> Int {
    max(current, imported)
}

public func applyingImportedBackup(current: AppPersistedState, imported: AppPersistedState) -> AppPersistedState {
    var next = imported
    next.watchSnapshotRevision = adoptedWatchSnapshotRevision(
        current: current.watchSnapshotRevision,
        imported: imported.watchSnapshotRevision
    )
    next.generation = current.generation + 1
    return next
}

public func deletingEvent(
    _ events: [HabitEvent],
    id: String,
    revision: Int,
    tombstones: [String: Int]
) -> (events: [HabitEvent], tombstones: [String: Int]) {
    var nextTombs = tombstones
    nextTombs[id] = max(tombstones[id] ?? 0, revision)
    let remaining = events.filter { event in
        event.id != id || event.revision > (nextTombs[id] ?? 0)
    }
    return (remaining, nextTombs)
}

public func ingestWatchEvent(
    events: [HabitEvent],
    tombstones: [String: Int],
    event: WatchOutboundEvent,
    persist: ([HabitEvent], [String: Int]) throws -> Void
) -> WatchAck? {
    let merged = addingEvent(events, event.asHabitEvent(), tombstones: tombstones)
    do {
        try persist(merged.events, merged.tombstones)
        return WatchAck(eventID: event.id, revision: event.revision)
    } catch {
        return nil
    }
}

public func acknowledgeOutbound(_ existing: [WatchOutboundEvent], ack: WatchAck) -> [WatchOutboundEvent] {
    existing.filter { event in
        event.id != ack.eventID || event.revision > ack.revision
    }
}

public func shouldAcceptWatchSnapshot(current: WatchSnapshot?, incoming: WatchSnapshot) -> Bool {
    guard let current else { return true }
    if incoming.snapshotRevision != current.snapshotRevision {
        return incoming.snapshotRevision > current.snapshotRevision
    }
    return incoming.generatedAt >= current.generatedAt
}

public func watchAckPayload(_ ack: WatchAck) -> [String: Any] {
    var payload: [String: Any] = [
        "ack": ack.eventID,
        "ackRevision": ack.revision
    ]
    if let data = encodeWatchPayload(ack) {
        payload[watchAckKey] = data
    }
    return payload
}

public func parseWatchAck(_ payload: [String: Any]) -> WatchAck? {
    if let data = payload[watchAckKey] as? Data, let ack = decodeWatchPayload(WatchAck.self, from: data) {
        return ack
    }
    guard let id = payload["ack"] as? String else { return nil }
    if let revision = payload["ackRevision"] as? Int {
        return WatchAck(eventID: id, revision: revision)
    }
    return WatchAck(eventID: id, revision: 1)
}