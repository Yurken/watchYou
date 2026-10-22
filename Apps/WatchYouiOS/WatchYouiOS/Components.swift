import SwiftUI
import Charts
import WatchYouCore

struct WYCard<Content: View>: View {
    var padding: CGFloat = 17
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WY.card)
        .clipShape(RoundedRectangle(cornerRadius: WY.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: WY.radius, style: .continuous)
                .stroke(Color(hex: 0xEAF0F3), lineWidth: 1)
        )
        .shadow(color: Color(hex: 0x29445A, alpha: 0.04), radius: 4, y: 2)
    }
}

struct WYPill: View {
    var text: String
    var kind: Kind = .blue
    enum Kind { case blue, green, warn, gray, hero }

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(foreground)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private var foreground: Color {
        switch kind {
        case .blue: return WY.blue
        case .green: return WY.green
        case .warn: return WY.warn
        case .gray: return Color(hex: 0x72818E)
        case .hero: return Color(hex: 0xD8ECE4)
        }
    }

    private var background: Color {
        switch kind {
        case .blue: return WY.blueSoft
        case .green: return WY.greenSoft
        case .warn: return WY.warnBg
        case .gray: return Color(hex: 0xEDF0F3)
        case .hero: return Color.white.opacity(0.09)
        }
    }
}

struct WYNotice: View {
    var text: String
    var warn: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 13))
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 12))
                .lineSpacing(4)
        }
        .foregroundStyle(warn ? WY.warn : Color(hex: 0x698092))
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(warn ? WY.warnBg : Color(hex: 0xEDF3F7))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct WYMetric: View {
    var value: String
    var unit: String
    var size: CGFloat = 34

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(value)
                .font(.system(size: size, weight: .semibold, design: .rounded))
                .tracking(-1)
                .foregroundStyle(WY.ink)
            Text(unit)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(WY.muted)
        }
    }
}

struct WYPrimaryButton: View {
    var title: String
    var fill: Bool = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .foregroundStyle(fill ? Color.white : WY.blue)
                .background(fill ? WY.primary : Color(hex: 0xEAF1F6))
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct WYHeroCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [WY.heroTop, WY.heroBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: WY.radius, style: .continuous))
        .foregroundStyle(Color(hex: 0xEEF6F8))
    }
}

struct WYEmptyState: View {
    var action: () -> Void

    var body: some View {
        WYCard {
            VStack(spacing: 10) {
                Image(systemName: "tray")
                    .font(.system(size: 28))
                    .foregroundStyle(Color(hex: 0x91A7B5))
                Text("暂无可读健康数据")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(WY.ink)
                Text("授权健康数据后即可查看。")
                    .font(.system(size: 12))
                    .foregroundStyle(WY.muted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                WYPrimaryButton(title: "请求健康数据授权", action: action)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }
}

struct TitleRow: View {
    var title: String
    var systemImage: String
    var pill: String? = nil

    var body: some View {
        HStack {
            Label(title, systemImage: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .labelStyle(.titleAndIcon)
            Spacer()
            if let pill {
                WYPill(text: pill, kind: .gray)
            }
        }
        .symbolRenderingMode(.hierarchical)
        .tint(WY.blue)
    }
}

struct ScoreRing: View {
    var value: Int?
    var label: String

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.12), lineWidth: 6)
            Circle()
                .trim(from: 0, to: CGFloat(value ?? 0) / 100)
                .stroke(Color(hex: 0xB3D6C9), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text(value.map(String.init) ?? "—")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                Text(label)
                    .font(.system(size: 9))
                    .foregroundStyle(Color(hex: 0xBFD3DD))
            }
        }
        .frame(width: 96, height: 96)
    }
}

struct SleepStageChart: View {
    var slices: [SleepStageSlice]
    var startLabel: String
    var endLabel: String

    var body: some View {
        let total = max(slices.reduce(0) { $0 + $1.minutes }, 1)
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                HStack(alignment: .bottom, spacing: 1) {
                    ForEach(slices) { slice in
                        Capsule()
                            .fill(sleepStageColor(slice.stage))
                            .frame(width: max(2, geo.size.width * CGFloat(slice.minutes / total) - 1), height: 14)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 28)
            HStack {
                Text(startLabel)
                Spacer()
                Text(endLabel)
            }
            .font(.system(size: 10))
            .foregroundStyle(WY.muted)
            HStack(spacing: 12) {
                legend("清醒", WY.awake)
                legend("REM", WY.rem)
                legend("核心", WY.core)
                legend("深睡", WY.deep)
            }
            .font(.system(size: 10))
            .foregroundStyle(WY.muted)
        }
    }

    private func legend(_ text: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text)
        }
    }
}

struct Sparkline: View {
    var values: [Double]
    var color: Color = WY.blue

    var body: some View {
        Chart {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                LineMark(x: .value("i", index), y: .value("v", value))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(color)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
    }
}

struct EvidenceSheet: View {
    var title: String
    var inference: PersistedInference
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    WYPill(text: inference.mode == "live" ? "模型分析" : "本地规则摘要", kind: inference.mode == "live" ? .green : .gray)
                    Text(inference.result.summary)
                        .font(.system(size: 15))
                        .foregroundStyle(WY.ink)
                        .lineSpacing(6)
                    ForEach(inference.result.evidenceIds, id: \.self) { id in
                        if let fact = inference.facts.first(where: { $0.id == id }) {
                            HStack(alignment: .top, spacing: 8) {
                                Text(id)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(WY.blue)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(fact.metric)：\(fact.value.map { $0.formatted() } ?? "—") \(fact.unit)")
                                        .font(.system(size: 13, weight: .medium))
                                    Text("\(WYFormat.dateTime(fact.observedAt ?? fact.window.end, timeZone: fact.window.timeZone)) · \(fact.sourceRef)")
                                        .font(.system(size: 11))
                                        .foregroundStyle(WY.muted)
                                }
                            }
                            .padding(.vertical, 6)
                        }
                    }
                    Text("不确定性")
                        .font(.system(size: 13, weight: .semibold))
                    ForEach(inference.result.uncertainties, id: \.self) { item in
                        Text(item)
                            .font(.system(size: 13))
                            .foregroundStyle(WY.muted)
                    }
                    Text("\(inference.model) · \(WYFormat.dateTime(inference.generatedAt))")
                        .font(.system(size: 11))
                        .foregroundStyle(WY.muted)
                }
                .padding(20)
            }
            .background(WY.bg)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
