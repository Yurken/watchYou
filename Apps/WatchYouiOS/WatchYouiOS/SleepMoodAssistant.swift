import SwiftUI
import WatchYouCore

struct SleepView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showScore = false
    @State private var showEvidence = false

    var body: some View {
        VStack(spacing: 12) {
            if model.snapshot.isEmpty {
                WYEmptyState { Task { await model.requestHealthAccess() } }
            } else if let night = model.snapshot.lastNight {
                WYCard {
                    TitleRow(title: "睡眠时长", systemImage: "moon.fill", pill: night.sourceRef)
                    WYMetric(value: "\(Int(night.asleepMinutes) / 60)", unit: "小时 \(Int(night.asleepMinutes.rounded()) % 60) 分", size: 42)
                    HStack {
                        Text("目标 \(model.preferences.sleepGoalMinutes / 60) 小时")
                        Spacer()
                        Button("调整目标") {
                            model.tab = .more
                            model.morePath = ["settings"]
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(WY.blue)
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(WY.muted)
                    ProgressView(value: min(1, night.asleepMinutes / Double(model.preferences.sleepGoalMinutes)))
                        .tint(WY.blue)
                    HStack {
                        Text(night.mainStart.map { WYFormat.clock($0, timeZone: model.snapshot.timeZone) } ?? "—")
                        Spacer()
                        Text(night.mainEnd.map { WYFormat.clock($0, timeZone: model.snapshot.timeZone) } ?? "—")
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(WY.muted)
                    SleepStageChart(
                        slices: night.slices.filter { $0.stage != .inBed },
                        startLabel: night.mainStart.map { WYFormat.clock($0, timeZone: model.snapshot.timeZone) } ?? "",
                        endLabel: night.mainEnd.map { WYFormat.clock($0, timeZone: model.snapshot.timeZone) } ?? ""
                    )
                }
                HStack(spacing: 10) {
                    Button { showScore = true } label: {
                        WYCard {
                            Text("睡眠参考分 · 实验性")
                                .font(.system(size: 11))
                                .foregroundStyle(WY.muted)
                            WYMetric(value: model.snapshot.sleepScore.map { "\($0.value)" } ?? "—", unit: "/ 100", size: 26)
                            Text(model.snapshot.sleepScore == nil ? "有效夜晚不足 7 天" : "查看构成 →")
                                .font(.system(size: 11))
                                .foregroundStyle(WY.muted)
                        }
                    }
                    .buttonStyle(.plain)
                    WYCard {
                        Text("记录内连续性")
                            .font(.system(size: 11))
                            .foregroundStyle(WY.muted)
                        WYMetric(value: "\(Int((night.coverage * 100).rounded()))", unit: "%", size: 26)
                        Text("已知清醒 \(Int(night.awakeMinutes.rounded())) 分钟")
                            .font(.system(size: 11))
                            .foregroundStyle(WY.muted)
                    }
                }
                WYCard {
                    TitleRow(title: "各阶段构成", systemImage: "moon.fill")
                    stageRow("核心睡眠", night.stageMinutes["core"] ?? 0, night.asleepMinutes, WY.core)
                    stageRow("快速眼动", night.stageMinutes["rem"] ?? 0, night.asleepMinutes, WY.rem)
                    stageRow("深度睡眠", night.stageMinutes["deep"] ?? 0, night.asleepMinutes, WY.deep)
                    Text("阶段比例只展示，不奖励深睡越多越好。系统未提供分期时只显示总时长。")
                        .font(.system(size: 11))
                        .foregroundStyle(WY.muted)
                }
                if !night.naps.isEmpty {
                    WYCard {
                        TitleRow(title: "日间小睡", systemImage: "moon.fill", pill: "不计入主睡眠评分")
                        ForEach(Array(night.naps.enumerated()), id: \.offset) { _, nap in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(WYFormat.clock(nap.start, timeZone: model.snapshot.timeZone))–\(WYFormat.clock(nap.end, timeZone: model.snapshot.timeZone))")
                                        .font(.system(size: 14, weight: .medium))
                                    Text("\(Int(nap.minutes.rounded())) 分钟")
                                        .font(.system(size: 12))
                                        .foregroundStyle(WY.muted)
                                }
                                Spacer()
                            }
                        }
                    }
                }
                AIModuleCard(task: "sleep", title: "睡眠解读")
            } else {
                WYNotice(text: "最近没有可识别的主睡眠段。")
            }
        }
        .sheet(isPresented: $showScore) { ScoreExplainSheet(kind: .sleep) }
    }

    private func stageRow(_ name: String, _ minutes: Double, _ total: Double, _ color: Color) -> some View {
        HStack {
            Text(name).font(.system(size: 12)).frame(width: 64, alignment: .leading)
            ProgressView(value: total > 0 ? minutes / total : 0)
                .tint(color)
            Text(formatDurationMinutes(minutes))
                .font(.system(size: 12, weight: .medium))
                .frame(width: 64, alignment: .trailing)
        }
    }
}

struct MoodView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showContext = false
    @State private var showEvidence = false
    @State private var note = ""
    @State private var valence: Double = 0

    var body: some View {
        let inference = model.inference("mood")
        let emotion = inference?.result.emotion
        VStack(spacing: 12) {
            WYHeroCard {
                HStack {
                    Label("AI 情绪洞察", systemImage: "face.smiling")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    WYPill(text: "自动分析", kind: .hero)
                }
                Circle()
                    .fill(
                        RadialGradient(colors: [Color(hex: 0xE5EFD8), Color(hex: 0xA9D0C2), Color(hex: 0x5D8E9E)], center: .topLeading, startRadius: 4, endRadius: 50)
                    )
                    .frame(width: 78, height: 78)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                Text(emotion?.label ?? "等待 AI 分析")
                    .font(.system(size: 22, weight: .semibold))
                    .frame(maxWidth: .infinity)
                Text(inference?.result.summary ?? "先完成健康授权与可选的模型设置。不需要打卡。")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: 0xCBDEE3))
                    .multilineTextAlignment(.center)
                HStack {
                    Text("证据强度：\(emotion?.evidenceStrength ?? "尚未评估")")
                    Spacer()
                    Text(inference.map { WYFormat.clock($0.observedEnd) } ?? "")
                }
                .font(.system(size: 10))
                .foregroundStyle(Color(hex: 0xB4CBD4))
            }
            WYCard {
                HStack(spacing: 8) {
                    axis("唤醒倾向", arousalLabel(emotion?.arousal))
                    axis("情绪正负向", valenceLabel(emotion?.valence))
                }
                HStack(spacing: 8) {
                    WYPrimaryButton(title: model.aiBusy == "mood" ? "正在分析…" : "重新分析") {
                        Task { await model.runAI(task: "mood") }
                    }
                    .disabled(model.aiBusy != nil)
                    Button("为什么这样判断") { showEvidence = true }
                        .buttonStyle(SecondaryChip())
                        .disabled(inference == nil)
                }
                if let error = model.aiError {
                    WYNotice(text: error, warn: true)
                }
                Text("\(inference?.model ?? "未分析") · 不展示未经校准的准确率")
                    .font(.system(size: 11))
                    .foregroundStyle(WY.muted)
            }
            WYCard {
                TitleRow(title: "让分析更贴近你", systemImage: "leaf")
                Text("不需要打卡。你可以自愿补充背景，或记下与推断不同的感受。反馈与推断分开保存。")
                    .font(.system(size: 12))
                    .foregroundStyle(WY.muted)
                Button("补充背景 / 纠正判断") { showContext = true }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(WY.blue)
            }
            WYNotice(text: "HRV 与心率不能单独证明焦虑、悲伤或愉悦。推断不会自动写成健康 App 中的本人心境。")
        }
        .sheet(isPresented: $showEvidence) {
            if let inference {
                EvidenceSheet(title: "情绪依据", inference: inference)
            }
        }
        .sheet(isPresented: $showContext) {
            NavigationStack {
                Form {
                    Section("可选背景") {
                        TextField("例如：刚喝了咖啡。请勿填入高度敏感信息。", text: $model.state.contextNote, axis: .vertical)
                            .lineLimit(3...6)
                    }
                    Section("可选纠正") {
                        Slider(value: $valence, in: -1...1, step: 0.1)
                        Text(valenceLabel(nil, value: valence))
                        TextField("一句话", text: $note)
                        Button("保存感受") {
                            model.saveFeedback(valence: valence, note: note, tags: [])
                            showContext = false
                        }
                    }
                }
                .navigationTitle("补充与纠正")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("关闭") { showContext = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存背景") {
                            model.persist()
                            showContext = false
                        }
                    }
                }
            }
        }
    }

    private func axis(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 10)).foregroundStyle(WY.muted)
            Text(value).font(.system(size: 14, weight: .semibold))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0xF0F5F7))
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private func arousalLabel(_ value: String?) -> String {
        switch value {
        case "low": return "偏低"
        case "moderate": return "略有变化"
        case "high": return "偏高"
        default: return "未知"
        }
    }

    private func valenceLabel(_ value: String?, value slider: Double? = nil) -> String {
        if let slider {
            if slider <= -0.6 { return "有些难受" }
            if slider < -0.2 { return "略感低落" }
            if slider <= 0.2 { return "平静" }
            if slider < 0.7 { return "感觉不错" }
            return "很愉悦"
        }
        switch value {
        case "positive": return "可能偏积极"
        case "negative": return "可能偏消极"
        case "neutral": return "可能偏中性"
        default: return "待更多情境"
        }
    }
}

struct AssistantView: View {
    @EnvironmentObject private var model: AppModel
    @State private var question = ""
    @State private var showEvidence = false

    var body: some View {
        VStack(spacing: 12) {
            WYHeroCard {
                HStack {
                    Label("AI 健康助手", systemImage: "book")
                    Spacer()
                    WYPill(text: model.config.mode == "live" ? "自定义服务" : "本地摘要", kind: .hero)
                }
                .font(.system(size: 12, weight: .semibold))
                Text("把数据，变成能理解的回答。")
                    .font(.system(size: 22, weight: .semibold))
                Text("围绕睡眠、恢复、情绪与习惯作解释。每次回答保留证据，不代替诊疗。")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: 0xCBDEE3))
            }
            WYCard {
                HStack {
                    chip("今天的状态", "为什么今天感觉有点疲惫？")
                    chip("睡眠与情绪", "睡眠和情绪可能有什么关系？")
                    chip("习惯建议", "帮我制定一个容易坚持的小目标。")
                }
                if model.state.chat.isEmpty {
                    Text("直接提问。发送时只附当前问题与已授权摘要。")
                        .font(.system(size: 12))
                        .foregroundStyle(WY.muted)
                        .padding(.vertical, 8)
                } else {
                    ForEach(model.state.chat.suffix(12)) { turn in
                        Text(turn.text)
                            .font(.system(size: 13))
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(turn.role == "user" ? Color(hex: 0xDFEAF1) : Color(hex: 0xF1F6F8))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .padding(.leading, turn.role == "user" ? 24 : 0)
                    }
                }
                TextField("例如：帮我解释今天的睡眠和恢复变化。", text: $question, axis: .vertical)
                    .lineLimit(3...6)
                    .padding(12)
                    .background(Color(hex: 0xF7FAFB))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                HStack {
                    WYPrimaryButton(title: model.aiBusy == "assistant" ? "正在回答…" : "发送问题") {
                        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !q.isEmpty else { model.flash("请先输入问题"); return }
                        Task {
                            await model.runAI(task: "assistant", question: q)
                            question = ""
                        }
                    }
                    .disabled(model.aiBusy != nil)
                    Button("查看依据") { showEvidence = true }
                        .buttonStyle(SecondaryChip())
                        .disabled(model.inference("assistant") == nil)
                }
            }
        }
        .sheet(isPresented: $showEvidence) {
            if let inference = model.inference("assistant") {
                EvidenceSheet(title: "回答依据", inference: inference)
            }
        }
    }

    private func chip(_ title: String, _ text: String) -> some View {
        Button(title) { question = text }
            .font(.system(size: 11))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(hex: 0xEAF2F6))
            .foregroundStyle(Color(hex: 0x59788C))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

struct AIModuleCard: View {
    @EnvironmentObject private var model: AppModel
    var task: String
    var title: String
    @State private var showEvidence = false

    var body: some View {
        let inference = model.inference(task)
        WYCard {
            TitleRow(title: "AI \(title)", systemImage: "book", pill: model.config.mode == "live" ? "自定义模型" : "本地摘要")
            Text(model.aiBusy == task ? "正在分析…" : (inference?.result.summary ?? "为这组数据生成一份解释"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(WY.ink)
            Text(inference?.result.suggestions.first ?? "只使用你授权的摘要，结果保留数据时间与依据。")
                .font(.system(size: 12))
                .foregroundStyle(WY.muted)
            HStack {
                Button(inference == nil ? "生成分析" : "重新分析") {
                    Task { await model.runAI(task: task) }
                }
                .buttonStyle(SecondaryChip())
                .disabled(model.aiBusy != nil)
                Button("查看依据") { showEvidence = true }
                    .buttonStyle(SecondaryChip())
                    .disabled(inference == nil)
            }
            Text("\(inference?.model ?? (model.config.mode == "live" ? model.config.activeProfile.model : "本地规则摘要")) · 非诊断")
                .font(.system(size: 11))
                .foregroundStyle(WY.muted)
        }
        .sheet(isPresented: $showEvidence) {
            if let inference {
                EvidenceSheet(title: title, inference: inference)
            }
        }
    }
}

struct ScoreExplainSheet: View {
    enum Kind { case sleep, recovery }
    var kind: Kind
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if kind == .sleep {
                        Text("睡眠参考分 \(model.snapshot.sleepScore.map { "\($0.value)" } ?? "—") / 100，版本 sleep-experimental-0.1。这是待验证的产品启发式，不是医学量表。")
                        Text("总分 = round(0.50 时长达成 + 0.25 规律 + 0.25 记录内连续性)。没有深睡比例奖励。有效夜晚不足 7 天或覆盖不足时不输出总分。")
                    } else {
                        Text("恢复参考 \(model.snapshot.recoveryScore.map { "\($0.value)" } ?? "—") / 100，版本 recovery-experimental-0.1。不是身体电量、疾病概率或运动许可。")
                        Text("使用当日之前的夜间 HRV 与静息心率基线。有效日不足 14 天或输入缺失时不输出总分。")
                    }
                }
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: 0x607584))
                .padding(20)
            }
            .background(WY.bg)
            .navigationTitle(kind == .sleep ? "睡眠参考分的依据" : "恢复参考的依据")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("我已了解") { dismiss() } } }
        }
    }
}
