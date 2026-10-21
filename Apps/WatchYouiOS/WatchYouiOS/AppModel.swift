import Foundation
import SwiftUI
import WatchYouCore

enum AppTab: String, CaseIterable, Identifiable {
    case today, sleep, mood, assistant, more
    var id: String { rawValue }
    var title: String {
        switch self {
        case .today: return "今日"
        case .sleep: return "睡眠"
        case .mood: return "情绪"
        case .assistant: return "AI 助手"
        case .more: return "更多"
        }
    }
    var symbol: String {
        switch self {
        case .today: return "square.grid.2x2"
        case .sleep: return "moon.fill"
        case .mood: return "face.smiling"
        case .assistant: return "book"
        case .more: return "ellipsis"
        }
    }
}

struct ConsentRequest: Identifiable {
    let id = UUID()
    let task: String
    let question: String
    let packet: EvidencePacket
    let preview: String
}

@MainActor
final class AppModel: ObservableObject {
    @Published var tab: AppTab = .today
    @Published var morePath: [String] = []
    @Published var state = AppPersistedState()
    @Published var snapshot = HealthSnapshot(generatedAt: Date(), timeZone: .current)
    @Published var healthAvailable = true
    @Published var isRefreshing = false
    @Published var toast: String?
    @Published var aiBusy: String?
    @Published var aiError: String?
    @Published var consentRequest: ConsentRequest?
    @Published var showOnboarding: Bool = true
    @Published var connectivityNote = ""
    @Published var secretDraft = ""

    let health = HealthKitRepository()
    let credentials: any CredentialStore = KeychainCredentialStore()
    let connectivity = PhoneConnectivity()
    private let store: FileAppStore
    private let provider = AIProvider()
    private let cache = InferenceCache()
    private var aiTask: Task<Void, Never>?
    private var waterUndo: HabitEvent?
    private var toastTask: Task<Void, Never>?
    private var didLoad = false

    var preferences: UserPreferences { state.preferences }
    var config: AIConfig { state.aiConfig }
    var events: [HabitEvent] { state.events }

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("watchyou", isDirectory: true)
        store = FileAppStore(directory: directory)
        healthAvailable = health.isAvailable
        connectivity.onEvent = { [weak self] event in
            self?.ingestWatch(event)
        }
        connectivity.onNoteChange = { [weak self] note in
            self?.connectivityNote = note
        }
    }

    func bootstrap() {
        guard !didLoad else { return }
        didLoad = true
        if let loaded = try? store.load() {
            state = loaded
        }
        showOnboarding = !state.preferences.hasCompletedOnboarding
        connectivity.activate()
        connectivityNote = connectivity.note
        if state.preferences.hasCompletedOnboarding {
            Task { await refreshHealth() }
        }
        pushWatch()
    }

    func completeOnboarding(requestHealth: Bool) async {
        if requestHealth {
            await requestHealthAccess()
        }
        state.preferences.hasCompletedOnboarding = true
        showOnboarding = false
        persist()
        await refreshHealth()
    }

    func requestHealthAccess() async {
        guard health.isAvailable else {
            flash("系统健康数据不可用")
            return
        }
        do {
            try await health.requestAuthorization()
            await refreshHealth()
        } catch {
            flash("授权流程未完成：\(error.localizedDescription)")
        }
    }

    func refreshHealth() async {
        isRefreshing = true
        defer { isRefreshing = false }
        let catalog = await health.load(now: Date(), timeZone: .current, rpe: state.rpeByWorkout)
        snapshot = aggregateHealth(
            catalog: catalog,
            preferences: state.preferences,
            events: state.events,
            now: Date(),
            timeZone: .current
        )
        pushWatch()
        if config.auto {
            if config.mode == "live" {
                if consentMatches(state.consent, profile: config.activeProfile, scopes: config.scopes) {
                    await runAI(task: "today", automatic: true)
                    await runAI(task: "mood", automatic: true)
                }
            } else {
                await runAI(task: "today", automatic: true)
                await runAI(task: "mood", automatic: true)
            }
        }
    }

    func persist() {
        do {
            try store.save(state)
        } catch {
            flash("本地保存失败")
        }
        pushWatch()
    }

    func flash(_ text: String) {
        toast = text
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            if !Task.isCancelled { toast = nil }
        }
    }

    func addWater(_ amount: Double) {
        waterUndo = nil
        let event = HabitEvent(id: UUID().uuidString, kind: "water", amount: amount, createdAt: Date())
        state.events = addingEvent(state.events, event)
        persist()
        flash("已记录 \(Int(amount)) ml")
    }

    func undoWater() {
        if let restored = waterUndo {
            state.events = addingEvent(state.events, restored)
            waterUndo = nil
            persist()
            flash("已恢复 \(Int(restored.amount)) ml")
            return
        }
        guard let index = state.events.lastIndex(where: { $0.kind == "water" }) else {
            flash("没有可撤销的饮水记录")
            return
        }
        waterUndo = state.events[index]
        state.events.remove(at: index)
        persist()
        flash("已撤销 \(Int(waterUndo?.amount ?? 0)) ml，再次点击可恢复")
    }

    func completeBreath() {
        let event = HabitEvent(id: UUID().uuidString, kind: "mindful", amount: 1, createdAt: Date())
        state.events = addingEvent(state.events, event)
        persist()
        flash("已记录 1 分钟练习")
    }

    func setWaterGoal(_ value: Int) {
        state.preferences.waterGoalMl = min(4000, max(500, value))
        persist()
    }

    func setSleepGoal(_ value: Int) {
        state.preferences.sleepGoalMinutes = min(600, max(360, value))
        persist()
        Task { await refreshHealth() }
    }

    func setRPE(workoutID: UUID, value: Int?) {
        if let value, (0...10).contains(value) {
            state.rpeByWorkout[workoutID.uuidString] = value
        } else {
            state.rpeByWorkout.removeValue(forKey: workoutID.uuidString)
        }
        persist()
        Task { await refreshHealth() }
    }

    func saveFeedback(valence: Double, note: String, tags: [String]) {
        let item = UserFeedback(
            id: UUID().uuidString,
            inferenceTask: "mood",
            valence: valence,
            note: note,
            tags: tags,
            createdAt: Date()
        )
        state.feedback.insert(item, at: 0)
        persist()
        flash("感受已保存在本应用，不会自动写入健康库")
    }

    func deleteFeedback(_ id: String) {
        state.feedback.removeAll { $0.id == id }
        persist()
    }

    func todayWater() -> Double {
        waterTotal(events: state.events, day: Date(), timeZone: snapshot.timeZone)
    }

    func inference(_ task: String) -> PersistedInference? {
        state.inferences[task]
    }

    func runAI(task: String, question: String = "", automatic: Bool = false, approved: Bool = false) async {
        guard AIModules.contains(task), config.modules[task] != false else {
            if !automatic { flash("此 AI 功能已关闭") }
            return
        }
        if aiBusy != nil {
            if !automatic { flash("已有请求进行中") }
            return
        }

        let facts = currentFacts(task: task)
        let hasContext = facts.contains { $0.scope == "context" }
        if let gate = qualityGate(task: task, snapshot: snapshot, config: config, facts: facts, hasContext: hasContext, now: Date()) {
            if !automatic { flash(gate) }
            return
        }

        if config.mode != "live" {
            applyLocal(task: task, facts: facts, question: question)
            if task == "assistant", !question.isEmpty {
                state.chat.append(ChatTurn(role: "user", text: question, createdAt: Date()))
                state.chat.append(ChatTurn(role: "assistant", text: "【本地规则摘要，并非对你的问题进行模型推理】\n" + (state.inferences[task]?.result.summary ?? ""), createdAt: Date()))
                persist()
            }
            if !automatic { flash("已更新本地规则摘要，未调用模型") }
            return
        }

        let profile = config.activeProfile
        if profile.baseURL.isEmpty || profile.model.isEmpty {
            if !automatic {
                flash("请先在设置中填写 URL 与 Model")
                morePath = ["settings", "ai"]
                tab = .more
            }
            return
        }

        if !approved && !consentMatches(state.consent, profile: profile, scopes: config.scopes) {
            if automatic { return }
            let packet = currentPacket(task: task, facts: facts, question: question)
            let preview = (try? encodePacket(packet)) ?? "{}"
            consentRequest = ConsentRequest(task: task, question: question, packet: packet, preview: preview)
            return
        }

        aiTask?.cancel()
        aiTask = Task { await performLive(task: task, facts: facts, question: question, automatic: automatic) }
        await aiTask?.value
    }

    func approveConsent() async {
        guard let request = consentRequest else { return }
        do {
            state.consent = try makePermission(profile: config.activeProfile, scopes: config.scopes, now: Date())
            persist()
        } catch {
            flash(userFacingError(error))
            consentRequest = nil
            return
        }
        consentRequest = nil
        await runAI(task: request.task, question: request.question, approved: true)
    }

    func cancelAI() {
        aiTask?.cancel()
        aiBusy = nil
        flash("已取消当前请求")
    }

    func saveAIConfig(
        name: String,
        baseURL: String,
        model: String,
        protocolName: String,
        auth: String,
        temperature: Double?,
        maxTokens: Int,
        timeout: Int,
        tokenField: String,
        allowLocalHTTP: Bool,
        mode: String,
        auto: Bool,
        dailyLimit: Int,
        modules: [String: Bool],
        scopes: [String: Bool],
        secret: String
    ) {
        do {
            var profileInput: [String: Any] = [
                "id": config.active,
                "name": name,
                "baseURL": baseURL,
                "protocol": protocolName,
                "model": model,
                "auth": auth,
                "maxTokens": maxTokens,
                "timeout": timeout,
                "tokenField": tokenField,
                "allowLocalHTTP": allowLocalHTTP
            ]
            if let temperature {
                profileInput["temperature"] = temperature
            }
            let profile = try cleanProfile(profileInput)
            if !secret.isEmpty {
                let normalized = try normalizeBase(profile.baseURL, allowLocalHTTP: profile.allowLocalHTTP)
                let recipient = credentialRecipient(normalizedEndpoint: normalized, authType: profile.auth)
                try credentials.save(
                    profileID: profile.id,
                    recipient: recipient,
                    fingerprint: credentialFingerprint(secret: secret),
                    secret: secret
                )
                secretDraft = ""
            }
            var profiles = config.profiles
            if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
                profiles[index] = profile
            } else {
                profiles.append(profile)
            }
            let old = config.activeProfile
            let destinationChanged = old.baseURL != profile.baseURL || old.protocolName != profile.protocolName || old.auth != profile.auth || old.model != profile.model || config.scopes != scopes
            state.aiConfig = config.replacing(
                profiles: profiles,
                mode: mode,
                auto: auto,
                dailyLimit: dailyLimit,
                modules: modules,
                scopes: scopes
            )
            if destinationChanged {
                state.consent = nil
                state.inferences = [:]
                state.generation += 1
            }
            persist()
            flash("AI 配置已保存；尚未发送健康摘要")
        } catch {
            flash(userFacingError(error))
        }
    }

    func currentSecret() -> String {
        if !secretDraft.isEmpty { return secretDraft }
        let profile = config.activeProfile
        guard !profile.baseURL.isEmpty else { return "" }
        guard let normalized = try? normalizeBase(profile.baseURL, allowLocalHTTP: profile.allowLocalHTTP) else { return "" }
        let recipient = credentialRecipient(normalizedEndpoint: normalized, authType: profile.auth)
        return (try? credentials.read(profileID: profile.id, recipient: recipient)?.secret) ?? ""
    }

    func testModels() async -> Result<(Int, [String]), Error> {
        do {
            let profile = config.activeProfile
            let urlString = try endpoint(for: profile, kind: "models")
            guard let url = URL(string: urlString) else { throw AIError.badURL("URL 无效") }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = TimeInterval(profile.timeout)
            request.httpShouldHandleCookies = false
            if profile.auth != "none" {
                let key = currentSecret()
                if key.isEmpty { throw AIError.unconfigured("请填写 API Key，或在保存后再测试") }
                if profile.auth == "bearer" {
                    request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                } else {
                    request.setValue(key, forHTTPHeaderField: "x-api-key")
                }
            }
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw AIError.transport("非 HTTP 响应") }
            if http.url != request.url { throw AIError.badURL("请求发生重定向") }
            guard (200..<300).contains(http.statusCode) else {
                throw AIError.transport("HTTP \(http.statusCode)")
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let array = json["data"] as? [[String: Any]] else {
                throw AIError.invalidJSON("接口返回格式不符")
            }
            let ids = array.compactMap { $0["id"] as? String }
            return .success((ids.count, Array(ids.prefix(8))))
        } catch {
            return .failure(error)
        }
    }

    func exportData() -> Data? {
        try? exportBackup(state: state, now: Date())
    }

    func importData(_ data: Data) {
        do {
            state = try importBackup(data)
            persist()
            Task { await refreshHealth() }
            flash("备份已恢复；AI 回到演示模式，需重新授权外发")
        } catch {
            flash(userFacingError(error))
        }
    }

    func resetRecords() {
        state.events = []
        state.feedback = []
        state.inferences = [:]
        state.chat = []
        state.contextNote = ""
        persist()
        flash("已清除本应用记录，健康库未改动")
    }

    private func currentFacts(task: String) -> [EvidenceFact] {
        factsForTask(
            task: task,
            snapshot: snapshot,
            preferences: state.preferences,
            events: state.events,
            contextNote: state.contextNote,
            allowedScopes: config.scopes,
            now: Date()
        )
    }

    private func currentPacket(task: String, facts: [EvidenceFact], question: String) -> EvidencePacket {
        buildEvidencePacket(
            task: task,
            window: TimeWindow(
                start: snapshot.lastNight?.mainStart ?? Date().addingTimeInterval(-24 * 3600),
                end: snapshot.lastNight?.mainEnd ?? Date(),
                timeZone: snapshot.timeZone
            ),
            baselineValidDays: snapshot.hrvValidDays,
            facts: facts,
            allowedScopes: Set(config.scopes.filter { $0.value }.map(\.key)),
            question: question.isEmpty ? nil : question,
            synthetic: false
        )
    }

    private func applyLocal(task: String, facts: [EvidenceFact], question: String) {
        let result = localInference(task: task, snapshot: snapshot, facts: facts, question: question.isEmpty ? nil : question)
        storeInference(task: task, result: result, facts: facts, mode: "local", model: "本地规则摘要")
    }

    private func performLive(task: String, facts: [EvidenceFact], question: String, automatic: Bool) async {
        let profile = config.activeProfile
        let packet = currentPacket(task: task, facts: facts, question: question)
        let key = makeCacheKey(task: task, facts: facts, question: question, profile: profile)
        if let cached = await cache.get(key) {
            storeInference(task: task, result: cached.result, facts: facts, mode: "live", model: profile.model)
            if task == "assistant", !question.isEmpty {
                state.chat.append(ChatTurn(role: "user", text: question, createdAt: Date()))
                state.chat.append(ChatTurn(role: "assistant", text: cached.result.summary, createdAt: Date()))
                persist()
            }
            if !automatic { flash("相同摘要已分析过，未重复调用模型") }
            return
        }
        aiBusy = task
        aiError = nil
        let started = Date()
        do {
            try accountCall()
            let secret = currentSecret()
            let payload = try encodePacket(packet)
            let text = try await provider.generate(
                profile: profile,
                key: secret.isEmpty ? nil : secret,
                system: systemPrompt,
                user: payload
            )
            try Task.checkCancellation()
            let parsed = try parseResult(text: text, facts: facts, hasContext: facts.contains { $0.scope == "context" })
            if parsed.uncertainties.isEmpty {
                throw AIValidationError.invalidField("缺少不确定性说明，分析结果未采纳")
            }
            if task == "mood" && parsed.emotion == nil {
                throw AIValidationError.invalidEmotion("情绪结果字段缺失")
            }
            await cache.put(
                InferenceRecord(result: parsed, evidenceIDs: Set(facts.map(\.id)), generation: state.generation),
                for: key
            )
            storeInference(task: task, result: parsed, facts: facts, mode: "live", model: profile.model)
            if task == "assistant", !question.isEmpty {
                state.chat.append(ChatTurn(role: "user", text: question, createdAt: Date()))
                state.chat.append(ChatTurn(role: "assistant", text: parsed.summary, createdAt: Date()))
            }
            log(kind: task, status: "success", model: profile.model, facts: facts, latency: Int(Date().timeIntervalSince(started) * 1000))
            if !automatic { flash("已收到模型分析") }
        } catch is CancellationError {
            aiError = "请求已取消"
        } catch {
            aiError = userFacingError(error)
            log(kind: task, status: "failed", model: profile.model, facts: facts, latency: nil)
            if task == "assistant", !question.isEmpty {
                state.chat.append(ChatTurn(role: "user", text: question, createdAt: Date()))
                state.chat.append(ChatTurn(role: "assistant", text: "本次没有得到有效回答：\(aiError ?? "")", createdAt: Date()))
            }
            if !automatic { flash(aiError ?? "分析失败") }
        }
        aiBusy = nil
        persist()
        pushWatch()
    }

    private func makeCacheKey(task: String, facts: [EvidenceFact], question: String, profile: AIProviderProfile) -> InferenceCacheKey {
        let window = TimeWindow(
            start: snapshot.lastNight?.mainStart ?? Date().addingTimeInterval(-24 * 3600),
            end: snapshot.lastNight?.mainEnd ?? Date(),
            timeZone: snapshot.timeZone
        )
        let endpoint = (try? normalizeBase(profile.baseURL, allowLocalHTTP: profile.allowLocalHTTP)) ?? profile.baseURL
        return InferenceCacheKey(
            task: task,
            inputHash: inputDigest(facts.map(\.id).joined(separator: ",") + "|" + question),
            window: window,
            model: profile.model,
            normalizedEndpoint: endpoint,
            promptVersion: promptVersion,
            sourcePolicyVersion: sourcePolicyVersion,
            consentVersion: state.consent?.scopeVersion ?? "",
            generation: state.generation
        )
    }

    private func storeInference(task: String, result: AIResult, facts: [EvidenceFact], mode: String, model: String) {
        let window = TimeWindow(
            start: snapshot.lastNight?.mainStart ?? Date().addingTimeInterval(-24 * 3600),
            end: snapshot.lastNight?.mainEnd ?? Date(),
            timeZone: snapshot.timeZone
        )
        state.inferences[task] = PersistedInference(
            task: task,
            result: result,
            facts: facts,
            model: model,
            mode: mode,
            generatedAt: Date(),
            observedEnd: snapshot.lastSampleAt ?? Date(),
            inputHash: inputDigest(facts.map(\.id).joined()),
            window: window
        )
        persist()
        pushWatch()
    }

    private func accountCall() throws {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        let day = formatter.string(from: Date())
        if state.usage.day != day {
            state.usage = UsageCounter(day: day, count: 0)
        }
        if state.usage.count >= config.dailyLimit {
            throw AIError.unconfigured("已达到今天的调用上限")
        }
        state.usage.count += 1
    }

    private func log(kind: String, status: String, model: String, facts: [EvidenceFact], latency: Int?) {
        let scopes = Array(Set(facts.compactMap(\.scope))).sorted().joined(separator: "、")
        state.logs.insert(
            AuditRecord(at: Date(), kind: kind, status: status, model: model, scope: scopes.isEmpty ? "无健康数值" : scopes, latencyMs: latency),
            at: 0
        )
        if state.logs.count > 80 { state.logs = Array(state.logs.prefix(80)) }
    }

    private func ingestWatch(_ event: WatchOutboundEvent) {
        state.events = addingEvent(state.events, event.asHabitEvent())
        persist()
        flash("手表已同步 \(event.kind == "water" ? "\(Int(event.amount)) ml 饮水" : "一次呼吸练习")")
    }

    private func pushWatch() {
        connectivityNote = connectivity.note
        let payload = makeWatchSnapshot(
            snapshot: snapshot,
            inferences: state.inferences,
            events: state.events,
            preferences: state.preferences,
            now: Date()
        )
        connectivity.push(payload)
    }
}
