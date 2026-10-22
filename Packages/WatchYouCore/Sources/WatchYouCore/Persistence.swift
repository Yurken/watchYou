import Foundation

public enum BackupError: Error, Equatable {
    case invalid(String)
    var message: String {
        switch self {
        case .invalid(let msg): return msg
        }
    }
}

public struct AppBackupEnvelope: Equatable, Sendable, Codable {
    public var schema: String
    public var exportedAt: Date
    public var synthetic: Bool
    public var state: AppPersistedState

    public init(schema: String = appBackupSchema, exportedAt: Date, synthetic: Bool = false, state: AppPersistedState) {
        self.schema = schema
        self.exportedAt = exportedAt
        self.synthetic = synthetic
        self.state = state
    }
}

public func exportBackup(state: AppPersistedState, now: Date) throws -> Data {
    var copy = state
    copy.consent = nil
    copy.aiConfig = copy.aiConfig.replacing(mode: "demo")
    copy.chat = []
    copy.contextNote = ""
    copy.contextNoteRecordedAt = nil
    let envelope = AppBackupEnvelope(exportedAt: now, state: copy)
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(envelope)
}

public func importBackup(_ data: Data) throws -> AppPersistedState {
    guard data.count <= 2_000_000 else { throw BackupError.invalid("备份不能超过 2 MB") }
    if let text = String(data: data, encoding: .utf8),
       text.range(of: "apiKey|secret|Authorization", options: .regularExpression) != nil {
        throw BackupError.invalid("备份含有疑似密钥字段，已拒绝导入")
    }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let envelope: AppBackupEnvelope
    do {
        envelope = try decoder.decode(AppBackupEnvelope.self, from: data)
    } catch {
        throw BackupError.invalid("无法解析备份")
    }
    guard envelope.schema == appBackupSchema else {
        throw BackupError.invalid("仅支持 watch you 应用备份")
    }
    return try validatePersistedState(envelope.state)
}

public func validatePersistedState(_ state: AppPersistedState) throws -> AppPersistedState {
    guard state.events.count <= 2000 else { throw BackupError.invalid("习惯事件数量无效") }
    guard state.feedback.count <= 500 else { throw BackupError.invalid("反馈记录数量无效") }
    var events: [HabitEvent] = []
    var seen = Set<String>()
    for event in state.events {
        guard event.id.range(of: "^[A-Za-z0-9_-]{1,100}$", options: .regularExpression) != nil,
              ["water", "mindful"].contains(event.kind),
              event.amount > 0, event.amount <= 10000 else {
            throw BackupError.invalid("事件记录无效")
        }
        if seen.insert(event.id).inserted {
            events.append(event)
        }
    }
    for item in state.feedback {
        guard item.id.range(of: "^[A-Za-z0-9_-]{1,100}$", options: .regularExpression) != nil,
              item.valence >= -1, item.valence <= 1 else {
            throw BackupError.invalid("反馈记录无效")
        }
    }
    var next = state
    next.events = events
    next.preferences = UserPreferences(
        sleepGoalMinutes: state.preferences.sleepGoalMinutes,
        waterGoalMl: state.preferences.waterGoalMl,
        preferredHeartSource: state.preferences.preferredHeartSource,
        preferredSleepSource: state.preferences.preferredSleepSource,
        remindersEnabled: state.preferences.remindersEnabled,
        reminderPrefs: validateReminderPrefs(state.preferences.reminderPrefs),
        hasCompletedOnboarding: state.preferences.hasCompletedOnboarding,
        lastSignedNote: state.preferences.lastSignedNote
    )
    next.aiConfig = next.aiConfig.replacing(mode: "demo")
    next.consent = nil
    next.logs = Array(state.logs.prefix(100))
    next.chat = []
    next.contextNote = ""
    next.contextNoteRecordedAt = nil
    return next
}

public func applyingContextNote(_ state: AppPersistedState, text: String, at now: Date) -> AppPersistedState {
    var next = state
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
        next.contextNote = ""
        next.contextNoteRecordedAt = nil
    } else {
        next.contextNote = trimmed
        next.contextNoteRecordedAt = now
    }
    return next
}

/// Copy, mutate, save, then return the saved value. Failure leaves `current` unchanged.
public func committingAppState(
    current: AppPersistedState,
    update: (inout AppPersistedState) -> Void,
    save: (AppPersistedState) throws -> Void
) throws -> AppPersistedState {
    var next = current
    update(&next)
    next.watchSnapshotRevision += 1
    try save(next)
    return next
}

public struct FileAppStore: Sendable {
    public let fileURL: URL

    public init(directory: URL) {
        self.fileURL = directory.appendingPathComponent("watchyou-state.json")
    }

    public func load() throws -> AppPersistedState {
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AppPersistedState.self, from: data)
    }

    public func save(_ state: AppPersistedState) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(state)
        let temp = fileURL.appendingPathExtension("tmp")
        try data.write(to: temp, options: .atomic)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: temp)
        } else {
            try FileManager.default.moveItem(at: temp, to: fileURL)
        }
    }
}