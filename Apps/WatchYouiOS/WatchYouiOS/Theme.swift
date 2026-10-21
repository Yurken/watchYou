import SwiftUI
import WatchYouCore

enum WY {
    static let ink = Color(hex: 0x182A3C)
    static let muted = Color(hex: 0x748391)
    static let line = Color(hex: 0xE5EBEF)
    static let bg = Color(hex: 0xF2F5F7)
    static let card = Color.white
    static let blue = Color(hex: 0x3F7192)
    static let blueSoft = Color(hex: 0xEAF2F7)
    static let green = Color(hex: 0x407B6B)
    static let greenSoft = Color(hex: 0xEDF5EF)
    static let warn = Color(hex: 0x7E612E)
    static let warnBg = Color(hex: 0xFAF3E7)
    static let heroTop = Color(hex: 0x243F52)
    static let heroBottom = Color(hex: 0x3E626E)
    static let primary = Color(hex: 0x335F7B)
    static let awake = Color(hex: 0xB5C7D2)
    static let rem = Color(hex: 0x9DBBD0)
    static let core = Color(hex: 0x5E8BAB)
    static let deep = Color(hex: 0x335C7B)
    static let unspecified = Color(hex: 0x7A93A3)
    static let radius: CGFloat = 22
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

enum WYFormat {
    static let locale = Locale(identifier: "zh_CN")

    static func dayTitle(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = "M 月 d 日，EEEE"
        return formatter.string(from: date)
    }

    static func clock(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    static func shortDay(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = "M/d"
        return formatter.string(from: date)
    }

    static func dateTime(_ date: Date, timeZone: TimeZone = .current) -> String {
        "\(shortDay(date, timeZone: timeZone)) \(clock(date, timeZone: timeZone))"
    }

    static func bpm(_ value: Double) -> String {
        "\(Int(value.rounded()))"
    }

    static func steps(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(Int(value))"
    }
}

func sleepStageColor(_ stage: SleepStage) -> Color {
    switch stage {
    case .awake: return WY.awake
    case .rem: return WY.rem
    case .core: return WY.core
    case .deep: return WY.deep
    case .unspecified, .inBed: return WY.unspecified
    }
}
