import Foundation
import SwiftUI
import WatchConnectivity
import WatchYouCore

@MainActor
final class WatchAppModel: NSObject, ObservableObject {
    @Published var snapshot: WatchSnapshot?
    @Published var pending: [WatchOutboundEvent] = []
    @Published var note = "尚未连接 iPhone"
    @Published var toast: String?
    @Published var breathing = false
    @Published var elapsed = 0

    private var breathTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private let storeURL: URL
    private var didActivate = false

    var waterMl: Int {
        displayedWater(snapshot: snapshot, pending: pending)
    }

    var waterGoal: Int { snapshot?.waterGoal ?? 2000 }

    override init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("watchyou", isDirectory: true)
        storeURL = directory.appendingPathComponent("watch-state.json")
        super.init()
        load()
    }

    func activate() {
        guard !didActivate else { return }
        didActivate = true
        guard WCSession.isSupported() else {
            note = "此手表不支持与 iPhone 通信"
            return
        }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        ingestContext(session.receivedApplicationContext)
        flushOutbox()
    }

    func addWater(_ amount: Double) {
        enqueue(kind: "water", amount: amount)
        flash("已记录 \(Int(amount)) ml")
    }

    func completeBreath() {
        enqueue(kind: "mindful", amount: 1)
        flash("已记录 1 分钟练习")
    }

    func startBreath() {
        breathing = true
        elapsed = 0
        breathTask?.cancel()
        breathTask = Task { @MainActor in
            for _ in 0..<60 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                elapsed += 1
            }
            if !Task.isCancelled {
                stopBreath(completed: true)
            }
        }
    }

    func stopBreath(completed: Bool) {
        breathTask?.cancel()
        breathTask = nil
        breathing = false
        elapsed = 0
        if completed { completeBreath() }
    }

    private func enqueue(kind: String, amount: Double) {
        let event = WatchOutboundEvent(
            id: UUID().uuidString,
            kind: kind,
            amount: amount,
            createdAt: Date()
        )
        pending = mergingOutbound(pending, event)
        persist()
        send(event)
    }

    private func send(_ event: WatchOutboundEvent) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        guard let data = encodeWatchPayload(event) else { return }
        let payload = [watchEventKey: data]
        WCSession.default.transferUserInfo(payload)
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(payload) { [weak self] reply in
                if let id = reply["ack"] as? String {
                    Task { @MainActor in self?.acknowledge(id) }
                }
            } errorHandler: { _ in }
        }
    }

    private func flushOutbox() {
        for event in pending {
            send(event)
        }
    }

    private func acknowledge(_ id: String) {
        pending = removingOutbound(pending, id: id)
        persist()
    }

    private func ingestContext(_ context: [String: Any]) {
        guard let data = context[watchContextKey] as? Data,
              let next = decodeWatchPayload(WatchSnapshot.self, from: data) else { return }
        snapshot = next
        persist()
    }

    private func ingestMessage(_ payload: [String: Any]) {
        if let data = payload[watchContextKey] as? Data,
           let next = decodeWatchPayload(WatchSnapshot.self, from: data) {
            snapshot = next
            persist()
        }
        if let id = payload["ack"] as? String {
            acknowledge(id)
        }
    }

    private func refreshNote(_ session: WCSession) {
        let installed = session.isCompanionAppInstalled
        note = session.activationState == .activated
            ? (session.isReachable ? "iPhone 已连接" : (installed ? "iPhone 未在近旁，事件会排队" : "请在 iPhone 安装 watch you"))
            : "正在连接 iPhone"
    }

    private func flash(_ text: String) {
        toast = text
        toastTask?.cancel()
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            if !Task.isCancelled { toast = nil }
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: storeURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let disk = try? decoder.decode(WatchDiskState.self, from: data) else { return }
        snapshot = disk.snapshot
        pending = disk.pending
    }

    private func persist() {
        let directory = storeURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let disk = WatchDiskState(snapshot: snapshot, pending: pending)
        guard let data = try? encoder.encode(disk) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }
}

private struct WatchDiskState: Codable {
    var snapshot: WatchSnapshot?
    var pending: [WatchOutboundEvent]
}

extension WatchAppModel: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            refreshNote(session)
            ingestContext(session.receivedApplicationContext)
            flushOutbox()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            refreshNote(session)
            if session.isReachable { flushOutbox() }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in ingestContext(applicationContext) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in ingestMessage(message) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        Task { @MainActor in ingestMessage(message) }
        replyHandler(["echo": "watch-ok"])
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in ingestMessage(userInfo) }
    }
}
