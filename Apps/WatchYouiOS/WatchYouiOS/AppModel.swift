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
    private var liveRequestID: UUID?
    private var waterUndo: HabitEvent?
    private var toastTask: Task<Void, Never>?
    private var didLoad = false
    private var healthRefreshGeneration = 0
    private var lastCatalog = HealthCatalog()
    private var lastLiveHash: [String: String] = [:]
    private var lastLiveAt: [String: Date] = [:]
    private var pendingLive: [String: PendingLiveWork] = [:]
    private var pendingDrainTask: Task<Void, Never>?
    private var drainingPending = false

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
        guard commit({ $0.preferences.hasCompletedOnboarding = true }) else { return }
        showOnboarding = false
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
        healthRefreshGeneration += 1
        let generation = healthRefreshGeneration
        isRefreshing = true
        defer {
            if shouldApplyHealthRefresh(startedGeneration: generation, currentGeneration: healthRefreshGeneration) {
                isRefreshing = false
            }
        }
        let incoming = await health.load(now: Date(), timeZone: .current, rpe: state.rpeByWorkout)
        guard shouldApplyHealthRefresh(startedGeneration: generation, currentGeneration: healthRefreshGeneration) else { return }
        lastCatalog = mergeHealthCatalog(previous: lastCatalog, incoming: incoming)
        snapshot = aggregateHealth(
            catalog: lastCatalog,
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

    @discardableResult
    func persist() -> Bool {
        commit { _ in }
    }

    @discardableResult
    func commit(_ update: (inout AppPersistedState) -> Void) -> Bool {
        do {
            state = try committingAppState(current: state, update: update, save: store.save)
            pushWatch()
            return true
        } catch {
            flash("本地保存失败")
            return false
        }
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
        let event = HabitEvent(id: UUID().uuidString, kind: "water", amount: amount, createdAt: Date())
        if commit({ next in
            let merged = addingEvent(next.events, event, tombstones: next.eventTombstones)
            next.events = merged.events
            next.eventTombstones = merged.tombstones
        }) {
            waterUndo = nil
            flash("已记录 \(Int(amount)) ml")
        }
    }

    func undoWater() {
        if let restored = waterUndo {
            if commit({ next in
                let merged = addingEvent(next.events, restored, tombstones: next.eventTombstones)
                next.events = merged.events
                next.eventTombstones = merged.tombstones
            }) {
                waterUndo = nil
                flash("已恢复 \(Int(restored.amount)) ml")
            }
            return
        }
        guard let index = state.events.lastIndex(where: { $0.kind == "water" }) else {
            flash("没有可撤销的饮水记录")
            return
        }
        let current = state.events[index]
        let deletedRevision = current.revision + 1
        let restored = HabitEvent(
            id: current.id,
            kind: current.kind,
            amount: current.amount,
            createdAt: current.createdAt,
            pending: current.pending,
            revision: deletedRevision + 1,
            source: current.source
        )
        if commit({ next in
            let removed = deletingEvent(next.events, id: current.id, revision: deletedRevision, tombstones: next.eventTombstones)
            next.events = removed.events
            next.eventTombstones = removed.tombstones
        }) {
            waterUndo = restored
            flash("已撤销 \(Int(current.amount)) ml，再次点击可恢复")
        }
    }

    func completeBreath() {
        let event = HabitEvent(id: UUID().uuidString, kind: "mindful", amount: 1, createdAt: Date())
        if commit({ next in
            let merged = addingEvent(next.events, event, tombstones: next.eventTombstones)
            next.events = merged.events
            next.eventTombstones = merged.tombstones
        }) {
            flash("已记录 1 分钟练习")
        }
    }

    func setWaterGoal(_ value: Int) {
        _ = commit { $0.preferences.waterGoalMl = min(4000, max(500, value)) }
    }

    func setSleepGoal(_ value: Int) {
        guard commit({ $0.preferences.sleepGoalMinutes = min(600, max(360, value)) }) else { return }
        Task { await refreshHealth() }
    }

    func setRPE(workoutID: UUID, value: Int?) {
        let saved = commit { next in
            if let value, (0...10).contains(value) {
                next.rpeByWorkout[workoutID.uuidString] = value
            } else {
                next.rpeByWorkout.removeValue(forKey: workoutID.uuidString)
            }
        }
        guard saved else { return }
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
        guard commit({ $0.feedback.insert(item, at: 0) }) else { return }
        flash("感受已保存")
        if config.auto {
            Task { await runAI(task: "mood", automatic: true, force: true) }
        }
    }

    @discardableResult
    func saveContextNote(_ text: String) -> Bool {
        guard commit({ $0 = applyingContextNote($0, text: text, at: Date()) }) else { return false }
        if config.auto {
            Task {
                await runAI(task: "today", automatic: true, force: true)
                await runAI(task: "mood", automatic: true, force: true)
            }
        }
        return true
    }

    func deleteFeedback(_ id: String) {
        guard commit({ $0.feedback.removeAll { $0.id == id } }) else { return }
        if config.auto {
            Task { await runAI(task: "mood", automatic: true, force: true) }
        }
    }

    func todayWater() -> Double {
        waterTotal(events: state.events, day: Date(), timeZone: snapshot.timeZone)
    }

    func inference(_ task: String) -> PersistedInference? {
        let facts = currentFacts(task: task)
        let blocked = qualityGate(
            task: task,
            snapshot: snapshot,
            config: config,
            facts: facts,
            hasContext: hasSendableContext(facts),
            now: Date()
        ) != nil
        return displayedInference(
            stored: state.inferences[task],
            currentInputHash: currentDisplayHash(task),
            analysisDay: snapshot.analysisDay ?? Date(),
            timeZone: snapshot.timeZone,
            snapshotEmpty: snapshot.isEmpty && task != "assistant" && task != "habits",
            moduleEnabled: config.modules[task] != false,
            qualityBlocked: blocked
        )
    }

    func runAI(task: String, question: String = "", automatic: Bool = false, approved: Bool = false, force: Bool = false) async {
        guard AIModules.contains(task), config.modules[task] != false else {
            if !automatic { flash("此 AI 功能已关闭") }
            return
        }
        if aiBusy != nil {
            rememberPendingLive(task: task, question: question, force: force)
            if !automatic { flash("已有请求进行中") }
            return
        }

        let facts = currentFacts(task: task)
        let hasContext = hasSendableContext(facts)
        if let gate = qualityGate(task: task, snapshot: snapshot, config: config, facts: facts, hasContext: hasContext, now: Date()) {
            if !automatic { flash(gate) }
            return
        }

        if config.mode != "live" {
            applyLocal(task: task, facts: facts, question: question)
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

        if automatic {
            let key = liveCacheKey(task: task, facts: facts, question: question, profile: profile)
            let now = Date()
            if !shouldStartAutomaticLive(
                task: task,
                inputHash: key.inputHash,
                previousHash: lastLiveHash[task],
                lastAttemptAt: lastLiveAt[task],
                now: now,
                moduleEnabled: config.modules[task] != false,
                consentValid: consentMatches(state.consent, profile: profile, scopes: config.scopes),
                force: force
            ) {
                if lastLiveHash[task] != key.inputHash {
                    rememberPendingLive(task: task, question: question, force: true)
                    let remaining = lastLiveAt[task].map { automaticLiveDebounceSeconds - now.timeIntervalSince($0) } ?? automaticLiveDebounceSeconds
                    schedulePendingDrain(after: max(remaining, 0.5))
                }
                return
            }
            lastLiveAt[task] = now
        }

        aiTask?.cancel()
        liveRequestID = nil
        aiTask = Task { await performLive(task: task, facts: facts, question: question, automatic: automatic) }
        await aiTask?.value
    }

    func approveConsent() async {
        guard let request = consentRequest else { return }
        do {
            let permission = try makePermission(profile: config.activeProfile, scopes: config.scopes, now: Date())
            guard commit({ $0.consent = permission }) else {
                consentRequest = nil
                return
            }
        } catch {
            flash(userFacingError(error))
            consentRequest = nil
            return
        }
        consentRequest = nil
        await runAI(task: request.task, question: request.question, approved: true)
    }

    func cancelAI() {
        liveRequestID = nil
        aiTask?.cancel()
        aiBusy = nil
        flash("已停止等待本次结果。已发出的请求无法撤回。")
    }

    private func invalidateLiveWork() {
        liveRequestID = nil
        aiTask?.cancel()
        aiBusy = nil
        lastLiveHash = [:]
        lastLiveAt = [:]
        pendingLive = [:]
        pendingDrainTask?.cancel()
        pendingDrainTask = nil
        Task { await cache.removeAll() }
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
            let old = config.activeProfile
            let destinationChanged = old.baseURL != profile.baseURL || old.protocolName != profile.protocolName || old.auth != profile.auth || old.model != profile.model || config.scopes != scopes
            guard commit({ next in
                var profiles = next.aiConfig.profiles
                if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
                    profiles[index] = profile
                } else {
                    profiles.append(profile)
                }
                next.aiConfig = next.aiConfig.replacing(
                    profiles: profiles,
                    mode: mode,
                    auto: auto,
                    dailyLimit: dailyLimit,
                    modules: modules,
                    scopes: scopes
                )
                next.generation += 1
                if destinationChanged {
                    next.consent = nil
                    next.inferences = [:]
                }
            }) else { return }
            invalidateLiveWork()
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
            let secret = currentSecret()
            let ids = try await provider.listModels(
                profile: config.activeProfile,
                key: secret.isEmpty ? nil : secret
            )
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
            let imported = try importBackup(data)
            guard commit({ $0 = applyingImportedBackup(current: $0, imported: imported) }) else { return }
            invalidateLiveWork()
            waterUndo = nil
            Task { await refreshHealth() }
            flash("备份已恢复")
        } catch {
            flash(userFacingError(error))
        }
    }

    func resetRecords() {
        guard commit({ $0 = resettingAppRecords($0) }) else { return }
        invalidateLiveWork()
        waterUndo = nil
        flash("已清除本应用记录")
    }

    private func currentFacts(task: String) -> [EvidenceFact] {
        factsForTask(
            task: task,
            snapshot: snapshot,
            preferences: state.preferences,
            events: state.events,
            contextNote: state.contextNote,
            contextRecordedAt: state.contextNoteRecordedAt,
            feedback: state.feedback,
            allowedScopes: config.scopes,
            now: Date()
        )
    }

    private func currentDisplayHash(_ task: String) -> String? {
        let question = task == "assistant"
            ? (state.chat.last(where: { $0.role == "user" })?.text ?? "")
            : ""
        return liveCacheKey(
            task: task,
            facts: currentFacts(task: task),
            question: question,
            profile: config.activeProfile
        ).inputHash
    }

    private func rememberPendingLive(task: String, question: String, force: Bool) {
        let key = liveCacheKey(
            task: task,
            facts: currentFacts(task: task),
            question: question,
            profile: config.activeProfile
        )
        pendingLive = enqueuePendingLive(pendingLive, task: task, inputHash: key.inputHash, question: question, force: force)
    }

    private func schedulePendingDrain(after seconds: TimeInterval) {
        pendingDrainTask?.cancel()
        pendingDrainTask = Task { @MainActor in
            let delay = UInt64(max(seconds, 0) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            await drainPendingLive()
        }
    }

    private func drainPendingLive() async {
        guard shouldDrainPendingLive(isBusy: aiBusy != nil, isDraining: drainingPending) else { return }
        drainingPending = true
        defer { drainingPending = false }
        while shouldDrainPendingLive(isBusy: aiBusy != nil, isDraining: false),
              let task = pendingLive.keys.sorted().first {
            let taken = takePendingLive(pendingLive, task: task)
            pendingLive = taken.remaining
            guard let work = taken.work else { continue }
            await runAI(task: work.task, question: work.question, automatic: true, force: true)
        }
    }

    private func stillCurrent(_ context: InferenceRequestContext, question: String) -> Bool {
        let latest = liveCacheKey(
            task: context.task,
            facts: currentFacts(task: context.task),
            question: question,
            profile: config.activeProfile
        )
        return shouldCommitInference(
            context: context,
            currentGeneration: state.generation,
            currentRequestID: liveRequestID ?? context.requestID,
            currentInputHash: latest.inputHash
        )
    }

    private func currentPacket(task: String, facts: [EvidenceFact], question: String) -> EvidencePacket {
        let window = inferenceObservationWindow(
            facts: facts,
            lastNight: snapshot.lastNight,
            timeZone: snapshot.timeZone
        )
        return buildEvidencePacket(
            task: task,
            window: window,
            baselineValidDays: snapshot.hrvValidDays,
            facts: facts,
            allowedScopes: Set(config.scopes.filter { $0.value }.map(\.key)),
            question: question.isEmpty ? nil : question,
            synthetic: false
        )
    }

    private func liveCacheKey(task: String, facts: [EvidenceFact], question: String, profile: AIProviderProfile) -> InferenceCacheKey {
        let packet = currentPacket(task: task, facts: facts, question: question)
        return makeInferenceCacheKey(
            packet: packet,
            contextText: sentContextText(facts),
            profile: profile,
            promptVersion: promptVersion,
            sourcePolicyVersion: sourcePolicyVersion,
            consentVersion: state.consent?.scopeVersion ?? "",
            generation: state.generation
        )
    }

    private func applyLocal(task: String, facts: [EvidenceFact], question: String) {
        let result = localInference(task: task, snapshot: snapshot, facts: facts, question: question.isEmpty ? nil : question)
        let key = liveCacheKey(task: task, facts: facts, question: question, profile: config.activeProfile)
        storeInference(
            task: task,
            result: result,
            facts: facts,
            mode: "local",
            model: "本地规则摘要",
            originalGeneratedAt: Date(),
            cacheHit: false,
            inputHash: key.inputHash,
            window: key.window,
            extra: { next in
                guard task == "assistant", !question.isEmpty else { return }
                next.chat.append(ChatTurn(role: "user", text: question, createdAt: Date()))
                next.chat.append(ChatTurn(
                    role: "assistant",
                    text: "【本地规则摘要，并非对你的问题进行模型推理】\n" + result.summary,
                    createdAt: Date()
                ))
            }
        )
    }

    private func performLive(task: String, facts: [EvidenceFact], question: String, automatic: Bool) async {
        let profile = config.activeProfile
        let packet = currentPacket(task: task, facts: facts, question: question)
        let key = liveCacheKey(task: task, facts: facts, question: question, profile: profile)
        let now = Date()
        let requestID = UUID()
        let context = InferenceRequestContext(
            requestID: requestID,
            generation: state.generation,
            task: task,
            profileID: profile.id,
            model: profile.model,
            normalizedEndpoint: key.normalizedEndpoint,
            protocolName: profile.protocolName,
            authType: profile.auth,
            consentVersion: key.consentVersion,
            inputHash: key.inputHash,
            window: key.window,
            createdAt: now
        )

        if let cached = await cache.get(key, now: now) {
            if stillCurrent(context, question: question) {
                storeInference(
                    task: task,
                    result: cached.result,
                    facts: facts,
                    mode: "live",
                    model: profile.model,
                    originalGeneratedAt: cached.originalGeneratedAt,
                    cacheHit: true,
                    inputHash: key.inputHash,
                    window: key.window,
                    extra: { next in
                        guard task == "assistant", !question.isEmpty else { return }
                        next.chat.append(ChatTurn(role: "user", text: question, createdAt: Date()))
                        next.chat.append(ChatTurn(role: "assistant", text: cached.result.summary, createdAt: Date()))
                    }
                )
                if !automatic { flash("相同摘要已分析过，未重复调用模型") }
            }
            await drainPendingLive()
            return
        }

        guard context.generation == state.generation else { return }
        liveRequestID = requestID
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
            if stillCurrent(context, question: question) {
                let parsed = try parseResult(text: text, facts: facts)
                if parsed.uncertainties.isEmpty {
                    throw AIValidationError.invalidField("缺少不确定性说明，分析结果未采纳")
                }
                if task == "mood" && parsed.emotion == nil {
                    throw AIValidationError.invalidEmotion("情绪结果字段缺失")
                }
                let original = Date()
                await cache.put(
                    InferenceRecord(
                        result: parsed,
                        evidenceIDs: Set(facts.map(\.id)),
                        generation: context.generation,
                        originalGeneratedAt: original
                    ),
                    for: key,
                    now: original
                )
                if stillCurrent(context, question: question) {
                    storeInference(
                        task: task,
                        result: parsed,
                        facts: facts,
                        mode: "live",
                        model: profile.model,
                        originalGeneratedAt: original,
                        cacheHit: false,
                        inputHash: key.inputHash,
                        window: key.window,
                        extra: { next in
                            guard task == "assistant", !question.isEmpty else { return }
                            next.chat.append(ChatTurn(role: "user", text: question, createdAt: Date()))
                            next.chat.append(ChatTurn(role: "assistant", text: parsed.summary, createdAt: Date()))
                        }
                    )
                    log(kind: task, status: "success", model: profile.model, facts: facts, latency: Int(Date().timeIntervalSince(started) * 1000))
                    if !automatic { flash("已收到模型分析") }
                }
            }
        } catch {
            if stillCurrent(context, question: question) {
                if error is CancellationError {
                    aiError = "请求已取消"
                } else {
                    aiError = userFacingError(error)
                    log(kind: task, status: "failed", model: profile.model, facts: facts, latency: nil)
                    if task == "assistant", !question.isEmpty {
                        let message = "本次没有得到有效回答：\(aiError ?? "")"
                        _ = commit { next in
                            next.chat.append(ChatTurn(role: "user", text: question, createdAt: Date()))
                            next.chat.append(ChatTurn(role: "assistant", text: message, createdAt: Date()))
                        }
                    }
                    if !automatic { flash(aiError ?? "分析失败") }
                }
            }
        }
        if shouldClearBusy(finishing: requestID, currentRequestID: liveRequestID) {
            aiBusy = nil
            liveRequestID = nil
        }
        persist()
        pushWatch()
        await drainPendingLive()
    }

    private func storeInference(
        task: String,
        result: AIResult,
        facts: [EvidenceFact],
        mode: String,
        model: String,
        originalGeneratedAt: Date,
        cacheHit: Bool,
        inputHash: String,
        window: TimeWindow,
        extra: ((inout AppPersistedState) -> Void)? = nil
    ) {
        let saved = commit { next in
            next.inferences[task] = applyCachedInference(
                result: result,
                facts: facts,
                model: model,
                mode: mode,
                originalGeneratedAt: originalGeneratedAt,
                servedAt: Date(),
                cacheHit: cacheHit,
                inputHash: inputHash,
                window: window,
                observedAt: inferenceObservedAt(facts: facts) ?? originalGeneratedAt,
                task: task
            )
            extra?(&next)
        }
        if saved {
            lastLiveHash[task] = inputHash
        }
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

    private func ingestWatch(_ event: WatchOutboundEvent) -> WatchAck? {
        let ack = ingestWatchEvent(
            events: state.events,
            tombstones: state.eventTombstones,
            event: event
        ) { events, tombs in
            var next = state
            next.events = events
            next.eventTombstones = tombs
            next.watchSnapshotRevision += 1
            try store.save(next)
            state = next
        }
        if ack != nil {
            pushWatch()
        } else {
            flash("本地保存失败")
        }
        return ack
    }

    private func pushWatch() {
        connectivityNote = connectivity.note
        var shown: [String: PersistedInference] = [:]
        if let today = inference("today") { shown["today"] = today }
        if let mood = inference("mood") { shown["mood"] = mood }
        let payload = makeWatchSnapshot(
            snapshot: snapshot,
            inferences: shown,
            events: state.events,
            preferences: state.preferences,
            now: Date(),
            tombstones: state.eventTombstones,
            snapshotRevision: state.watchSnapshotRevision
        )
        connectivity.push(payload)
    }
}
