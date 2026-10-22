import SwiftUI
import WatchYouCore

enum WatchPage: String, CaseIterable, Identifiable {
    case overview = "概览"
    case sleep = "睡眠"
    case mood = "情绪"
    case water = "饮水"
    case breath = "呼吸"
    var id: String { rawValue }
}

struct ContentView: View {
    @EnvironmentObject private var model: WatchAppModel
    @State private var page: WatchPage = .overview

    var body: some View {
        TabView(selection: $page) {
            overviewPage.tag(WatchPage.overview).tabItem { Text("概览") }
            sleepPage.tag(WatchPage.sleep).tabItem { Text("睡眠") }
            moodPage.tag(WatchPage.mood).tabItem { Text("情绪") }
            waterPage.tag(WatchPage.water).tabItem { Text("饮水") }
            breathPage.tag(WatchPage.breath).tabItem { Text("呼吸") }
        }
        .tabViewStyle(.verticalPage)
        .onAppear { model.activate() }
    }

    private var snapshot: WatchSnapshot? { model.snapshot }

    private var overviewPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("watch you · 概览")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(red: 0.72, green: 0.84, blue: 0.87))
                if let snapshot {
                    Text(snapshot.todayTitle)
                        .font(.system(size: 18, weight: .semibold))
                    Text(snapshot.todaySummary)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    if !snapshot.empty {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(snapshot.sleepText).font(.system(size: 16, weight: .semibold))
                                Text("睡眠").font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text(snapshot.recoveryText).font(.system(size: 16, weight: .semibold))
                                Text("恢复参考").font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Text("暂无数据")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Button("查看情绪") { page = .mood }
                } else {
                    Text("等待 iPhone 摘要")
                        .font(.system(size: 18, weight: .semibold))
                }
                footer
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 4)
    }

    private var sleepPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("睡眠")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                if let snapshot, !snapshot.empty {
                    Text(snapshot.sleepText)
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                    Text(snapshot.stale ? "历史缓存 · \(snapshot.sleepWindowText)" : snapshot.sleepWindowText)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                } else {
                    Text("暂无睡眠")
                        .font(.system(size: 16, weight: .semibold))
                }
                footer
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 4)
    }

    private var moodPage: some View {
        let mood = watchMoodDisplay(snapshot: snapshot, now: Date())
        return ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("情绪")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                WatchEmotionSticker(
                    kind: emotionStickerKind(
                        status: mood.current ? "estimated" : "insufficient",
                        label: mood.label
                    ),
                    size: 56,
                    animated: mood.current
                )
                .frame(maxWidth: .infinity)
                Text(mood.label)
                    .font(.system(size: 20, weight: .semibold))
                    .frame(maxWidth: .infinity)
                Text(mood.note)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                footer
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 4)
    }

    private var waterPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("饮水")
                    .font(.system(size: 18, weight: .semibold))
                Text("\(model.waterMl)")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                + Text(" ml")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                Text("目标 \(model.waterGoal) ml · 本应用记录")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                ProgressView(value: min(1, Double(model.waterMl) / Double(max(model.waterGoal, 1))))
                Button("+ 250 ml") { model.addWater(250) }
                Button("+ 150 ml") { model.addWater(150) }
                footer
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 4)
    }

    private var breathPage: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text("呼吸")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Circle()
                    .fill(RadialGradient(
                        colors: [Color(red: 0.84, green: 0.91, blue: 0.89), Color(red: 0.50, green: 0.67, blue: 0.67)],
                        center: .topLeading,
                        startRadius: 8,
                        endRadius: 48
                    ))
                    .frame(width: 88, height: 88)
                    .scaleEffect(model.breathing ? 1.06 : 0.88)
                    .animation(model.breathing ? .easeInOut(duration: 5).repeatForever(autoreverses: true) : .default, value: model.breathing)
                    .overlay {
                        Text(model.breathing ? (model.elapsed % 10 < 4 ? "自然吸气" : "缓慢呼气") : "准备")
                            .font(.system(size: 12, weight: .medium))
                    }
                Button(model.breathing ? "停止练习 · \(max(0, 60 - model.elapsed))s" : "开始练习") {
                    model.breathing ? model.stopBreath(completed: false) : model.startBreath()
                }
                Text("不屏息，不适即停止。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                footer
            }
        }
        .padding(.horizontal, 4)
        .onDisappear {
            if model.breathing { model.stopBreath(completed: false) }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let status = watchFooterStatus(connectionNote: model.note, pending: !model.pending.isEmpty) {
                Text(status)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            if let toast = model.toast {
                Text(toast)
                    .font(.system(size: 12, weight: .medium))
            }
        }
        .padding(.top, 6)
    }
}

private struct WatchEmotionSticker: View {
    var kind: EmotionStickerKind
    var size: CGFloat
    var animated: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let loop = [0, 1, 2, 3, 4, 0]
    private let frameDuration = 2.0 / 6.0

    var body: some View {
        let plays = animated && !reduceMotion
        TimelineView(.periodic(from: .now, by: plays ? frameDuration : 86_400)) { context in
            let index = plays
                ? loop[Int(context.date.timeIntervalSinceReferenceDate / frameDuration) % loop.count]
                : 0
            Image("Emotion-\(kind.rawValue)-\(index)")
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }
}
