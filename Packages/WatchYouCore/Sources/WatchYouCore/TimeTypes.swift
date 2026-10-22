import Foundation

/// Absolute time window with an explicit interpretation timezone.
/// Durations use absolute differences; bucket assignment uses the local date at `end`.
public struct TimeWindow: Equatable, Hashable, Sendable, Codable {
    public let start: Date
    public let end: Date
    public let timeZone: TimeZone

    public init(start: Date, end: Date, timeZone: TimeZone = .current) {
        self.start = start
        self.end = end
        self.timeZone = timeZone
    }

    private enum CodingKeys: String, CodingKey {
        case start, end, timeZone
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        start = try container.decode(Date.self, forKey: .start)
        end = try container.decode(Date.self, forKey: .end)
        let identifier = try container.decode(String.self, forKey: .timeZone)
        timeZone = TimeZone(identifier: identifier) ?? TimeZone(secondsFromGMT: 0)!
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(start, forKey: .start)
        try container.encode(end, forKey: .end)
        try container.encode(timeZone.identifier, forKey: .timeZone)
    }

    /// Absolute duration in seconds.
    public var duration: TimeInterval {
        end.timeIntervalSince(start)
    }

    /// Local calendar date of the window end, resolved in `timeZone`.
    public var dayBucket: Date {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        return calendar.startOfDay(for: end)
    }
}

/// Inclusive-start, exclusive-end calendar day in `timeZone`. Does not use wall-clock call time.
public func calendarDayWindow(containing date: Date, timeZone: TimeZone) -> TimeWindow {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let start = calendar.startOfDay(for: date)
    let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(24 * 3600)
    return TimeWindow(start: start, end: end, timeZone: timeZone)
}

/// Injectable source of the current moment.
public protocol Clock: Sendable {
    var now: Date { get }
}

/// Production clock.
public struct SystemClock: Clock {
    public init() {}
    public var now: Date { Date() }
}

/// Deterministic clock for tests.
public struct FixedClock: Clock {
    public var now: Date
    public init(now: Date) {
        self.now = now
    }
}
