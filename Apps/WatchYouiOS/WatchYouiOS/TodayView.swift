import SwiftUI
import WatchYouCore

struct TodayView: View {
    @EnvironmentObject private var model: AppModel
    @State private var evidenceTask: String?

    var body: some View {
        VStack(spacing: 12) {
            if let error = model.snapshot.readError {
                WYNotice(text: error, warn: true)
            }
            hero
            if model.snapshot.isEmpty {
                WYEmptyState {
                    Task { await model.requestHealthAccess() }
                }
            } else {
                metrics
                moodCard
                hrvRecovery
            }
            HStack(spacing: 8) {
                Button("饮水 +250 ml") { model.addWater(250) }
                    .buttonStyle(SecondaryChip())
                Button("一分钟呼吸") {
                    model.tab = .more
                    model.morePath = ["habits"]
                }
                .buttonStyle(SecondaryChip())
            }
        }
        .sheet(item: Binding(
            get: { evidenceTask.map { Tag($0) } },
            set: { evidenceTask = $0?.value }
        )) { tag in
            if let inference = model.inference(tag.value) {
                EvidenceSheet(title: "依据", inference: inference)
            }
        }
    }

    private var hero: some View {
        WYHeroCard {
            HStack {
                Label("watch you · 今日洞察", systemImage: "book")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                WYPill(text: model.config.mode == "live" ? "AI" : "本地摘要", kind: .hero)
            }
            Text(headline)
                .font(.system(size: 22, weight: .semibold))
                .tracking(-0.4)
                .padding(.top, 4)
            Text(model.inference("today")?.result.summary ?? "配置你的模型，或使用本地规则，为睡眠与活动生成一份有依据的解释。")
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: 0xCBDEE3))
                .lineSpacing(5)
            HStack(spacing: 8) {
                Button("问问 AI") { model.tab = .assistant }
                    .buttonStyle(HeroChip())
                Button(model.aiBusy == "today" ? "分析中…" : "更新洞察") {
                    Task { await model.runAI(task: "today") }
                }
                .buttonStyle(HeroChip())
                .disabled(model.aiBusy != nil)
            }
            .padding(.top, 4)
            HStack {
                Text(model.inference("today")?.model ?? (model.config.mode == "live" ? model.config.activeProfile.model : "本地规则摘要"))
                Spacer()
                Text(model.snapshot.lastSampleAt.map { WYFormat.dateTime($0, timeZone: model.snapshot.timeZone) } ?? "尚无样本时间")
            }
            .font(.system(size: 10))
            .foregroundStyle(Color(hex: 0xB4CBD4))
            .padding(.top, 6)
        }
    }

    private var headline: String {
        if model.snapshot.isEmpty { return "等待你的第一份数据" }
        if model.snapshot.baselineNights < 7 { return "正在认识你的节奏" }
        return "先照顾节奏，再安排今天。"
    }

    private var metrics: some View {
        HStack(spacing: 10) {
            Button {
                model.tab = .sleep
            } label: {
                WYCard {
                    TitleRow(title: "昨夜睡眠", systemImage: "moon.fill")
                    if let night = model.snapshot.lastNight {
                        WYMetric(value: hourPart(night.asleepMinutes), unit: "小时 \(minutePart(night.asleepMinutes)) 分", size: 28)
                        SleepMiniBars(slices: night.slices)
                        Text(rangeLabel(night))
                            .font(.system(size: 11))
                            .foregroundStyle(WY.muted)
                    } else {
                        Text("暂无昨夜记录")
                            .foregroundStyle(WY.muted)
                    }
                }
            }
            .buttonStyle(.plain)
            Button {
                model.tab = .more
                model.morePath = ["heart"]
            } label: {
                WYCard {
                    TitleRow(title: "最近心率", systemImage: "heart.fill")
                    if let hr = model.snapshot.latestHeartRate?.value {
                        WYMetric(value: WYFormat.bpm(hr), unit: "次/分", size: 28)
                        Sparkline(values: model.snapshot.heartRateSeries.compactMap(\.value).suffix(24).map { $0 })
                            .frame(height: 34)
                        Text(model.snapshot.latestHeartRate.map { WYFormat.clock($0.window.end, timeZone: $0.window.timeZone) } ?? "")
                            .font(.system(size: 11))
                            .foregroundStyle(WY.muted)
                    } else {
                        Text("暂无心率记录")
                            .foregroundStyle(WY.muted)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var moodCard: some View {
        Button {
            model.tab = .mood
        } label: {
            WYCard {
                HStack {
                    Text("AI 情绪洞察")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    WYPill(text: "自动推断", kind: .green)
                }
                Text(model.inference("mood")?.result.emotion?.label ?? "暂无法判断")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(WY.ink)
                Text(model.inference("mood")?.result.summary ?? "等待分析")
                    .font(.system(size: 12))
                    .foregroundStyle(WY.muted)
                    .lineSpacing(4)
                Text("查看状态、依据与趋势 →")
                    .font(.system(size: 11))
                    .foregroundStyle(WY.blue)
            }
        }
        .buttonStyle(.plain)
    }

    private var hrvRecovery: some View {
        HStack(spacing: 10) {
            WYCard {
                Text("夜间 HRV · SDNN")
                    .font(.system(size: 11))
                    .foregroundStyle(WY.muted)
                WYMetric(value: model.snapshot.nocturnalHRV.map { "\(Int($0.rounded()))" } ?? "—", unit: "ms", size: 26)
                Text(model.snapshot.nocturnalHRVSampleCount > 0 ? "\(model.snapshot.nocturnalHRVSampleCount) 个样本" : "暂无样本")
                    .font(.system(size: 11))
                    .foregroundStyle(WY.muted)
            }
            Button {
                model.tab = .more
                model.morePath = ["recovery"]
            } label: {
                WYCard {
                    Text("恢复参考")
                        .font(.system(size: 11))
                        .foregroundStyle(WY.muted)
                    WYMetric(value: model.snapshot.recoveryScore.map { "\($0.value)" } ?? "—", unit: "/ 100", size: 26)
                    Text(model.snapshot.recoveryScore == nil ? "正在建立基线" : "查看依据 →")
                        .font(.system(size: 11))
                        .foregroundStyle(WY.muted)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func hourPart(_ minutes: Double) -> String { "\(Int(minutes) / 60)" }
    private func minutePart(_ minutes: Double) -> String { "\(Int(minutes.rounded()) % 60)" }
    private func rangeLabel(_ night: SleepNight) -> String {
        guard let start = night.mainStart, let end = night.mainEnd else { return "Apple 健康" }
        return "\(WYFormat.clock(start, timeZone: model.snapshot.timeZone))–\(WYFormat.clock(end, timeZone: model.snapshot.timeZone))"
    }
}

private struct Tag: Identifiable {
    var value: String
    var id: String { value }
    init(_ value: String) { self.value = value }
}

struct SleepMiniBars: View {
    var slices: [SleepStageSlice]
    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(slices.prefix(12).enumerated()), id: \.offset) { _, slice in
                Capsule()
                    .fill(sleepStageColor(slice.stage).opacity(0.85))
                    .frame(height: min(26, max(8, CGFloat(slice.minutes / 8))))
            }
        }
        .frame(height: 28)
    }
}

struct HeroChip: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color.white.opacity(configuration.isPressed ? 0.08 : 0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .foregroundStyle(Color(hex: 0xD9EBE6))
    }
}

struct SecondaryChip: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(Color(hex: 0xEAF1F6))
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .foregroundStyle(Color(hex: 0x426C86))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
