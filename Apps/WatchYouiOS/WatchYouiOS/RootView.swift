import SwiftUI
import WatchYouCore

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            WY.bg.ignoresSafeArea()
            if model.showOnboarding {
                OnboardingView()
            } else {
                VStack(spacing: 0) {
                    header
                    content
                    tabBar
                }
            }
            if let toast = model.toast {
                VStack {
                    Spacer()
                    Text(toast)
                        .font(.system(size: 13))
                        .foregroundStyle(Color(hex: 0xEEF6F8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(WY.heroTop)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .padding(.bottom, 88)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.toast)
        .tint(WY.blue)
        .preferredColorScheme(.light)
        .onAppear { model.bootstrap() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await model.refreshHealth() }
            }
        }
        .sheet(item: $model.consentRequest) { request in
            ConsentSheet(request: request)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(WYFormat.dayTitle(Date(), timeZone: model.snapshot.timeZone))
                    .font(.system(size: 11))
                    .foregroundStyle(WY.muted)
                Text(title)
                    .font(.system(size: 26, weight: .semibold))
                    .tracking(-0.6)
                    .foregroundStyle(WY.ink)
            }
            Spacer()
            Button {
                model.tab = .more
                model.morePath = ["settings"]
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x52748B))
                    .frame(width: 37, height: 37)
                    .background(Color(hex: 0xE1EAF0))
                    .clipShape(Circle())
            }
            .accessibilityLabel("打开设置")
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private var title: String {
        switch model.tab {
        case .today: return "今日"
        case .sleep: return "睡眠"
        case .mood: return "情绪"
        case .assistant: return "AI 助手"
        case .more:
            switch model.morePath.last {
            case "heart": return "心率与 HRV"
            case "recovery": return "恢复与压力"
            case "activity": return "运动与活动"
            case "habits": return "生活习惯"
            case "trends": return "趋势"
            case "sources": return "数据来源"
            case "settings": return "设置"
            case "ai": return "AI 服务"
            default: return "更多"
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            Group {
                switch model.tab {
                case .today: TodayView()
                case .sleep: SleepView()
                case .mood: MoodView()
                case .assistant: AssistantView()
                case .more: MoreContainer()
                }
            }
            .padding(.horizontal, 17)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .refreshable { await model.refreshHealth() }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    model.tab = tab
                    if tab != .more { model.morePath = [] }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 18))
                        Text(tab.title)
                            .font(.system(size: 10, weight: model.tab == tab ? .semibold : .regular))
                    }
                    .foregroundStyle(model.tab == tab ? Color(hex: 0x315E7B) : Color(hex: 0x8C99A3))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                    .padding(.bottom, 10)
                }
                .buttonStyle(.plain)
            }
        }
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider() }
    }
}

struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            Text("HEALTH, UNDERSTOOD BY AI.")
                .font(.system(size: 11, weight: .semibold))
                .tracking(2)
                .foregroundStyle(Color(hex: 0x6C8493))
            Text("让 AI，读懂身体与情绪。")
                .font(.system(size: 32, weight: .semibold))
                .tracking(-0.6)
                .foregroundStyle(WY.ink)
                .padding(.top, 10)
            Text("睡眠、心率与恢复先由本机计算。模型只在你授权的范围内解释，没有证据就保留未知。")
                .font(.system(size: 14))
                .foregroundStyle(WY.muted)
                .lineSpacing(6)
                .padding(.top, 12)
            VStack(alignment: .leading, spacing: 12) {
                row("moon.fill", "睡眠、心率、HRV、活动", "只读，按使用请求")
                row("face.smiling", "情绪自动推断", "无需每日打卡")
                row("lock.fill", "密钥留在本机", "外发前预览摘要")
            }
            .padding(.top, 28)
            Spacer()
            WYPrimaryButton(title: "授权并读取健康数据") {
                Task { await model.completeOnboarding(requestHealth: true) }
            }
            Button("先看看界面") {
                Task { await model.completeOnboarding(requestHealth: false) }
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(WY.blue)
            .frame(maxWidth: .infinity)
            .padding(.top, 12)
            Text("授权弹窗返回不等于每一项读取都已获准。空结果可能是未授权、无记录或尚未同步。")
                .font(.system(size: 11))
                .foregroundStyle(WY.muted)
                .padding(.top, 16)
        }
        .padding(24)
    }

    private func row(_ icon: String, _ title: String, _ subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(WY.blue)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(WY.ink)
                Text(subtitle).font(.system(size: 12)).foregroundStyle(WY.muted)
            }
        }
    }
}

struct ConsentSheet: View {
    @EnvironmentObject private var model: AppModel
    let request: ConsentRequest
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("本次会把下面的摘要发送到你配置的服务。授权绑定当前服务、模型和范围；更换后再确认。")
                        .font(.system(size: 13))
                        .foregroundStyle(WY.muted)
                    LabeledContent("服务", value: model.config.activeProfile.name)
                    LabeledContent("模型", value: model.config.activeProfile.model)
                    Text(request.preview)
                        .font(.system(size: 11, design: .monospaced))
                        .padding(12)
                        .background(Color(hex: 0xEDF3F7))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    Text("第三方如何保留数据由其服务决定，客户端不能保证零保留。")
                        .font(.system(size: 11))
                        .foregroundStyle(WY.muted)
                    WYPrimaryButton(title: "同意并分析") {
                        Task {
                            await model.approveConsent()
                            dismiss()
                        }
                    }
                    Button("取消") { dismiss() }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                }
                .padding(20)
            }
            .background(WY.bg)
            .navigationTitle("确认分析范围")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
