import SwiftUI
import WatchYouCore

struct AISettingsView: View {
    @EnvironmentObject private var model: AppModel

    @State private var name = ""
    @State private var baseURL = ""
    @State private var modelID = ""
    @State private var protocolName = "chat"
    @State private var auth = "bearer"
    @State private var secret = ""
    @State private var temperature = ""
    @State private var maxTokens = 1200
    @State private var timeout = 45
    @State private var tokenField = "max_tokens"
    @State private var allowLocalHTTP = false
    @State private var mode = "demo"
    @State private var auto = true
    @State private var dailyLimit = 20
    @State private var modules: [String: Bool] = [:]
    @State private var scopes: [String: Bool] = [:]
    @State private var testNote = ""
    @State private var testing = false

    private let moduleNames: [(String, String)] = [
        ("today", "今日摘要"), ("mood", "情绪推断"), ("sleep", "睡眠解读"),
        ("heart", "心率与 HRV"), ("recovery", "恢复与压力"), ("activity", "运动建议"),
        ("habits", "习惯建议"), ("trends", "趋势与报告"), ("assistant", "健康问答")
    ]
    private let scopeNames: [(String, String)] = [
        ("sleep", "睡眠摘要"), ("heart", "心率 / HRV 摘要"),
        ("activity", "活动摘要"), ("habits", "习惯记录"),
        ("context", "自愿提供的文字与纠正")
    ]

    var body: some View {
        VStack(spacing: 12) {
            BackLink()
            WYCard {
                TitleRow(title: "模型服务", systemImage: "book", pill: "BYOK")
                field("配置名称", text: $name)
                picker("协议", selection: $protocolName, options: [
                    ("chat", "OpenAI 兼容 · Chat Completions"),
                    ("responses", "OpenAI Responses"),
                    ("anthropic", "Anthropic Messages")
                ])
                field("Base URL", text: $baseURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                picker("认证方式", selection: $auth, options: [
                    ("bearer", "Authorization: Bearer"),
                    ("x-api-key", "x-api-key"),
                    ("none", "无认证")
                ])
                if auth != "none" {
                    SecureField("API Key（保存到 Keychain）", text: $secret)
                        .textInputAutocapitalization(.never)
                }
                field("Model", text: $modelID)
                    .textInputAutocapitalization(.never)
                HStack {
                    Button(testing ? "测试中…" : "测试 /models") {
                        Task { await test() }
                    }
                    .disabled(testing)
                    .buttonStyle(SecondaryChip())
                }
                if !testNote.isEmpty {
                    Text(testNote)
                        .font(.system(size: 12))
                        .foregroundStyle(testNote.contains("成功") ? WY.green : Color.red)
                }
                Text("测试不含健康数据。密钥不会写入备份。")
                    .font(.system(size: 11))
                    .foregroundStyle(WY.muted)
            }
            WYCard {
                TitleRow(title: "调用参数", systemImage: "slider.horizontal.3")
                field("Temperature（可空）", text: $temperature)
                    .keyboardType(.decimalPad)
                Stepper("最大输出 Token \(maxTokens)", value: $maxTokens, in: 64...16000, step: 50)
                Stepper("超时 \(timeout) 秒", value: $timeout, in: 5...180, step: 5)
                Stepper("每日调用上限 \(dailyLimit)", value: $dailyLimit, in: 1...200)
                picker("Chat Token 字段", selection: $tokenField, options: [
                    ("max_tokens", "max_tokens"),
                    ("max_completion_tokens", "max_completion_tokens")
                ])
                Toggle("允许本机 / 私网 HTTP", isOn: $allowLocalHTTP)
                    .font(.system(size: 13))
            }
            WYCard {
                TitleRow(title: "分析方式与数据范围", systemImage: "lock.fill")
                picker("运行模式", selection: $mode, options: [
                    ("demo", "本地规则摘要 · 不调用模型"),
                    ("live", "真实 AI · 发送已授权摘要")
                ])
                Toggle("授权后自动分析（相同摘要不重复）", isOn: $auto)
                    .font(.system(size: 13))
                ForEach(scopeNames, id: \.0) { key, label in
                    Toggle(label, isOn: binding(for: key, in: $scopes))
                        .font(.system(size: 13))
                }
            }
            WYCard {
                TitleRow(title: "AI 功能开关", systemImage: "switch.2")
                ForEach(moduleNames, id: \.0) { key, label in
                    Toggle(label, isOn: binding(for: key, in: $modules))
                        .font(.system(size: 13))
                }
            }
            WYPrimaryButton(title: "保存 AI 配置") { save() }
            logs
        }
        .onAppear { load() }
    }

    private var logs: some View {
        WYCard {
            TitleRow(title: "调用记录", systemImage: "list.bullet")
            Text("今天 \(model.state.usage.count) / \(model.config.dailyLimit) 次。不记录密钥、完整提示词或健康数值。")
                .font(.system(size: 12))
                .foregroundStyle(WY.muted)
            ForEach(model.state.logs.prefix(12)) { log in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(WYFormat.clock(log.at)) · \(log.kind) · \(log.status)")
                        .font(.system(size: 12, weight: .medium))
                    Text("\(log.model) · \(log.scope)\(log.latencyMs.map { " · \($0) ms" } ?? "")")
                        .font(.system(size: 11))
                        .foregroundStyle(WY.muted)
                }
                .padding(.vertical, 4)
            }
            if model.aiBusy != nil {
                Button("取消正在进行的请求") { model.cancelAI() }
                    .foregroundStyle(WY.warn)
            }
        }
    }

    private func load() {
        let profile = model.config.activeProfile
        name = profile.name
        baseURL = profile.baseURL
        modelID = profile.model
        protocolName = profile.protocolName
        auth = profile.auth
        temperature = profile.temperature.map { String($0) } ?? ""
        maxTokens = profile.maxTokens
        timeout = profile.timeout
        tokenField = profile.tokenField
        allowLocalHTTP = profile.allowLocalHTTP
        mode = model.config.mode
        auto = model.config.auto
        dailyLimit = model.config.dailyLimit
        modules = model.config.modules
        scopes = model.config.scopes
        secret = ""
    }

    private func save() {
        model.saveAIConfig(
            name: name,
            baseURL: baseURL,
            model: modelID,
            protocolName: protocolName,
            auth: auth,
            temperature: Double(temperature),
            maxTokens: maxTokens,
            timeout: timeout,
            tokenField: tokenField,
            allowLocalHTTP: allowLocalHTTP,
            mode: mode,
            auto: auto,
            dailyLimit: dailyLimit,
            modules: modules,
            scopes: scopes,
            secret: secret
        )
        secret = ""
    }

    private func test() async {
        save()
        testing = true
        defer { testing = false }
        switch await model.testModels() {
        case .success(let pair):
            testNote = "连接成功，返回 \(pair.0) 个模型。\(pair.1.prefix(3).joined(separator: "、"))"
        case .failure(let error):
            testNote = userFacingError(error)
        }
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 11)).foregroundStyle(WY.muted)
            TextField(title, text: text)
                .padding(11)
                .background(Color(hex: 0xF7FAFB))
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
    }

    private func picker(_ title: String, selection: Binding<String>, options: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 11)).foregroundStyle(WY.muted)
            Picker(title, selection: selection) {
                ForEach(options, id: \.0) { Text($0.1).tag($0.0) }
            }
            .pickerStyle(.menu)
        }
    }

    private func binding(for key: String, in dict: Binding<[String: Bool]>) -> Binding<Bool> {
        Binding(
            get: { dict.wrappedValue[key] ?? false },
            set: { dict.wrappedValue[key] = $0 }
        )
    }
}
