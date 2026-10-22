import SwiftUI
import WatchYouCore

struct MoreContainer: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            switch model.morePath.last {
            case "heart": HeartView()
            case "recovery": RecoveryView()
            case "activity": ActivityView()
            case "habits": HabitsView()
            case "trends": TrendsView()
            case "sources": SourcesView()
            case "settings": SettingsView()
            case "ai": AISettingsView()
            default: MoreMenu()
            }
        }
    }
}

struct MoreMenu: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        WYCard {
            row("心率与 HRV", "heart.fill", "heart")
            row("恢复与压力", "leaf.fill", "recovery")
            row("运动与活动", "figure.walk", "activity")
            row("生活习惯", "drop.fill", "habits")
            row("趋势与周报", "chart.xyaxis.line", "trends")
            row("设置", "gearshape", "settings")
        }
    }

    private func row(_ title: String, _ icon: String, _ path: String) -> some View {
        Button {
            model.morePath.append(path)
        } label: {
            HStack {
                Image(systemName: icon).foregroundStyle(WY.blue).frame(width: 22)
                Text(title).foregroundStyle(WY.ink)
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(WY.muted)
            }
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }
}

struct HeartView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 12) {
            back
            if model.snapshot.isEmpty {
                WYEmptyState { Task { await model.requestHealthAccess() } }
            } else {
                WYCard {
                    TitleRow(title: "最近一次心率记录", systemImage: "heart.fill", pill: "非实时")
                    if let sample = model.snapshot.latestHeartRate, let value = sample.value {
                        WYMetric(value: WYFormat.bpm(value), unit: "次 / 分", size: 44)
                        Text("\(sample.sourceRef) · \(WYFormat.dateTime(sample.window.end, timeZone: sample.window.timeZone))")
                            .font(.system(size: 12))
                            .foregroundStyle(WY.muted)
                        Sparkline(values: model.snapshot.heartRateSeries.compactMap(\.value))
                            .frame(height: 110)
                    } else {
                        Text("暂无心率样本").foregroundStyle(WY.muted)
                    }
                }
                HStack(spacing: 10) {
                    WYCard {
                        Text("静息心率 · 系统记录").font(.system(size: 11)).foregroundStyle(WY.muted)
                        WYMetric(value: model.snapshot.restingHeartRate.map { WYFormat.bpm($0) } ?? "—", unit: "次 / 分", size: 24)
                        Text(model.snapshot.restingHeartRateBaseline.map { "基线中位数 \(WYFormat.bpm($0))" } ?? "尚无基线")
                            .font(.system(size: 11)).foregroundStyle(WY.muted)
                    }
                    WYCard {
                        Text("夜间 HRV · SDNN").font(.system(size: 11)).foregroundStyle(WY.muted)
                        WYMetric(value: model.snapshot.nocturnalHRV.map { "\(Int($0.rounded()))" } ?? "—", unit: "毫秒", size: 24)
                        Text("\(model.snapshot.nocturnalHRVSampleCount) 个有效样本")
                            .font(.system(size: 11)).foregroundStyle(WY.muted)
                    }
                }
                WYNotice(text: "冲突记录会按来源偏好选择，不直接平均。")
                AIModuleCard(task: "heart", title: "心率与 HRV")
            }
        }
    }

    private var back: some View { BackLink() }
}

struct RecoveryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showScore = false

    var body: some View {
        VStack(spacing: 12) {
            BackLink()
            Button { showScore = true } label: {
                WYHeroCard {
                    TitleRow(title: "身体恢复参考", systemImage: "leaf.fill")
                    HStack(spacing: 18) {
                        ScoreRing(value: model.snapshot.recoveryScore?.value, label: "恢复参考")
                        VStack(alignment: .leading, spacing: 6) {
                            Text(model.snapshot.recoveryScore == nil ? "正在建立基线" : "看懂变化的依据")
                                .font(.system(size: 16, weight: .medium))
                            Text(model.snapshot.recoveryScore == nil ? "HRV \(model.snapshot.hrvValidDays) 日 · 静息心率 \(model.snapshot.rhrValidDays) 日" : "查看构成")
                                .font(.system(size: 12))
                                .foregroundStyle(Color(hex: 0xC5D8E2))
                        }
                    }
                    Text("基线：HRV \(model.snapshot.hrvValidDays) 日 · 静息心率 \(model.snapshot.rhrValidDays) 日")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(hex: 0xA9C2CF))
                }
            }
            .buttonStyle(.plain)
            WYCard {
                TitleRow(title: "这次参考分由什么构成", systemImage: "chart.xyaxis.line")
                labeled("睡眠参考", model.snapshot.sleepScore.map { "\($0.value)" } ?? "—")
                labeled("夜间 HRV", model.snapshot.nocturnalHRV.map { "\(Int($0.rounded())) ms" } ?? "—")
                labeled("静息心率", model.snapshot.restingHeartRate.map { "\(WYFormat.bpm($0)) bpm" } ?? "—")
            }
            WYNotice(text: "缺少 HRV 或静息心率历史时不显示恢复参考。")
            AIModuleCard(task: "recovery", title: "恢复解释")
        }
        .sheet(isPresented: $showScore) { ScoreExplainSheet(kind: .recovery) }
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(.system(size: 12)).foregroundStyle(WY.muted)
            Spacer()
            Text(value).font(.system(size: 13, weight: .medium))
        }
    }
}

struct ActivityView: View {
    @EnvironmentObject private var model: AppModel
    @State private var rpeText = ""
    @State private var showRPE = false

    var body: some View {
        VStack(spacing: 12) {
            BackLink()
            if model.snapshot.isEmpty {
                WYEmptyState { Task { await model.requestHealthAccess() } }
            } else {
                WYCard {
                    TitleRow(title: "今日活动", systemImage: "figure.walk", pill: model.snapshot.lastSampleAt.map { WYFormat.clock($0) } ?? "")
                    WYMetric(value: model.snapshot.todaySteps.map { WYFormat.steps($0) } ?? "—", unit: "步", size: 40)
                    HStack {
                        VStack(alignment: .leading) {
                            Text("活动能量").font(.system(size: 11)).foregroundStyle(WY.muted)
                            Text(model.snapshot.todayEnergyKcal.map { "\(Int($0.rounded())) kcal" } ?? "—").font(.system(size: 16, weight: .semibold))
                        }
                        Spacer()
                        VStack(alignment: .leading) {
                            Text("锻炼时间").font(.system(size: 11)).foregroundStyle(WY.muted)
                            Text(model.snapshot.todayExerciseMinutes.map { "\(Int($0.rounded())) 分钟" } ?? "—").font(.system(size: 16, weight: .semibold))
                        }
                    }
                    HStack(alignment: .bottom, spacing: 8) {
                        ForEach(model.snapshot.weekExercise, id: \.day) { day in
                            VStack {
                                Capsule()
                                    .fill(WY.blue.opacity(0.55))
                                    .frame(width: 16, height: max(4, CGFloat(day.value / 60) * 70))
                                Text(WYFormat.shortDay(day.day))
                                    .font(.system(size: 8))
                                    .foregroundStyle(WY.muted)
                            }
                        }
                    }
                    .frame(height: 90)
                }
                if let workout = model.snapshot.workouts.first {
                    WYCard {
                        TitleRow(title: "最近一次训练", systemImage: "figure.walk")
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(workout.activity).font(.system(size: 15, weight: .semibold))
                                Text(WYFormat.dateTime(workout.window.start, timeZone: workout.window.timeZone))
                                    .font(.system(size: 12)).foregroundStyle(WY.muted)
                            }
                            Spacer()
                            WYPill(text: "\(Int(workout.durationMinutes.rounded())) 分钟")
                        }
                        HStack {
                            VStack(alignment: .leading) {
                                Text("平均心率").font(.system(size: 11)).foregroundStyle(WY.muted)
                                Text(workout.averageHeartRate.map { "\(WYFormat.bpm($0)) 次/分" } ?? "—")
                            }
                            Spacer()
                            Button(workout.rpe == nil ? "记录 RPE" : "RPE \(workout.rpe!)") { showRPE = true }
                                .font(.system(size: 13))
                                .foregroundStyle(WY.blue)
                        }
                    }
                    WYCard {
                        TitleRow(title: "主观训练负荷", systemImage: "chart.xyaxis.line")
                        if let load = workout.trainingLoadValue, let rpe = workout.rpe {
                            Text("\(Int(workout.durationMinutes.rounded())) × \(rpe) = \(load)")
                                .font(.system(size: 22, weight: .semibold))
                            Text("任意单位。没有 RPE 就不生成数字。")
                                .font(.system(size: 12)).foregroundStyle(WY.muted)
                        } else {
                            Text("等待你补充强度感受")
                                .font(.system(size: 16, weight: .medium))
                            Text("采用训练时长 × 主观用力程度。")
                                .font(.system(size: 12)).foregroundStyle(WY.muted)
                        }
                    }
                }
                AIModuleCard(task: "activity", title: "运动建议")
            }
        }
        .sheet(isPresented: $showRPE) {
            NavigationStack {
                Form {
                    TextField("0–10", text: $rpeText)
                        .keyboardType(.numberPad)
                }
                .navigationTitle("主观用力程度")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { showRPE = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            if let workout = model.snapshot.workouts.first {
                                model.setRPE(workoutID: workout.uuid, value: Int(rpeText))
                            }
                            showRPE = false
                        }
                    }
                }
            }
        }
    }
}

struct HabitsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var breathing = false
    @State private var elapsed = 0
    @State private var breathTask: Task<Void, Never>?

    var body: some View {
        let water = model.todayWater()
        VStack(spacing: 12) {
            BackLink()
            WYCard {
                TitleRow(title: "饮水记录", systemImage: "drop.fill", pill: "本应用记录")
                WYMetric(value: "\(Int(water.rounded()))", unit: "/ \(model.preferences.waterGoalMl) ml", size: 36)
                ProgressView(value: min(1, water / Double(model.preferences.waterGoalMl))).tint(WY.blue)
                HStack {
                    Button("+150") { model.addWater(150) }.buttonStyle(SecondaryChip())
                    WYPrimaryButton(title: "+250") { model.addWater(250) }
                    Button("+500") { model.addWater(500) }.buttonStyle(SecondaryChip())
                }
                HStack {
                    Stepper("目标 \(model.preferences.waterGoalMl) ml", value: Binding(
                        get: { model.preferences.waterGoalMl },
                        set: { model.setWaterGoal($0) }
                    ), in: 500...4000, step: 50)
                }
                .font(.system(size: 13))
                Button("撤销上一次") { model.undoWater() }
                    .font(.system(size: 12))
                    .foregroundStyle(WY.blue)
            }
            WYCard {
                TitleRow(title: "一分钟，回到当下", systemImage: "wind")
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [Color(hex: 0xD7E9E4), Color(hex: 0x80ACAA)], center: .topLeading, startRadius: 10, endRadius: 80))
                        .frame(width: 110, height: 110)
                        .scaleEffect(breathing ? 1.05 : 0.86)
                        .animation(breathing ? .easeInOut(duration: 5).repeatForever(autoreverses: true) : .default, value: breathing)
                    Text(breathing ? (elapsed % 10 < 4 ? "自然吸气" : "缓慢呼气") : "准备")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color(hex: 0x42665E))
                }
                .frame(maxWidth: .infinity)
                Text("自然吸气，缓慢呼气，不屏息。不适时立即停止。")
                    .font(.system(size: 12))
                    .foregroundStyle(WY.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                WYPrimaryButton(title: breathing ? "停止 · \(max(0, 60 - elapsed))s" : "开始 1 分钟练习") {
                    breathing ? stop(false) : start()
                }
            }
            AIModuleCard(task: "habits", title: "习惯建议")
        }
        .onDisappear { stop(false) }
    }

    private func start() {
        breathing = true
        elapsed = 0
        breathTask?.cancel()
        breathTask = Task { @MainActor in
            for _ in 0..<60 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                elapsed += 1
            }
            if !Task.isCancelled { stop(true) }
        }
    }

    private func stop(_ completed: Bool) {
        breathTask?.cancel()
        breathTask = nil
        breathing = false
        if completed { model.completeBreath() }
        elapsed = 0
    }
}

struct TrendsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var days = 7

    var body: some View {
        let trend = Array(model.snapshot.sleepTrend.suffix(days))
        let avg = trend.isEmpty ? 0 : trend.map(\.asleepMinutes).reduce(0, +) / Double(trend.count)
        VStack(spacing: 12) {
            BackLink()
            Picker("范围", selection: $days) {
                Text("近 7 天").tag(7)
                Text("近 28 天").tag(28)
            }
            .pickerStyle(.segmented)
            WYCard {
                TitleRow(title: "睡眠时长趋势", systemImage: "moon.fill", pill: "\(trend.count) 个有效夜晚")
                WYMetric(value: "\(Int(avg) / 60)", unit: "小时 \(Int(avg.rounded()) % 60) 分", size: 28)
                Sparkline(values: trend.map(\.asleepMinutes))
                    .frame(height: 120)
                Text("未将缺失日期补成 0")
                    .font(.system(size: 11))
                    .foregroundStyle(WY.muted)
            }
            WYCard {
                TitleRow(title: "情绪与身体，一起回看", systemImage: "face.smiling")
                Text("先积累，再谈关联")
                    .font(.system(size: 16, weight: .medium))
                Text("配对记录不足时不显示相关系数。自动推断与本人反馈分开。")
                    .font(.system(size: 12))
                    .foregroundStyle(WY.muted)
            }
            AIModuleCard(task: "trends", title: "趋势与报告")
        }
    }
}

struct SourcesView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 12) {
            BackLink()
            WYCard {
                TitleRow(title: "数据来源", systemImage: "book", pill: "记录来源")
                ForEach(model.snapshot.sources, id: \.id) { source in
                    HStack(spacing: 12) {
                        Image(systemName: source.unknown ? "questionmark.circle" : "heart.fill")
                            .foregroundStyle(WY.blue)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(source.name).font(.system(size: 14, weight: .medium))
                            Text(source.unknown ? "无法可靠识别为固定设备" : source.id)
                                .font(.system(size: 11))
                                .foregroundStyle(WY.muted)
                        }
                    }
                    .padding(.vertical, 6)
                }
                if model.snapshot.sources.isEmpty {
                    Text("还没有读到来源。授权并产生记录后会显示在这里。")
                        .font(.system(size: 12))
                        .foregroundStyle(WY.muted)
                }
                HStack(spacing: 12) {
                    Image(systemName: "drop.fill").foregroundStyle(WY.blue)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("本应用记录").font(.system(size: 14, weight: .medium))
                        Text("饮水、呼吸与自愿反馈")
                            .font(.system(size: 11))
                            .foregroundStyle(WY.muted)
                    }
                }
            }
            WYNotice(text: "改变来源偏好不会改写 Apple 健康。")
        }
    }
}

struct BackLink: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        Button("‹ 返回更多") {
            if !model.morePath.isEmpty { model.morePath.removeLast() }
        }
        .font(.system(size: 12))
        .foregroundStyle(WY.blue)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
