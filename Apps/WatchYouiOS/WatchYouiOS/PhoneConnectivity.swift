import Foundation
import WatchConnectivity
import WatchYouCore

@MainActor
final class PhoneConnectivity: NSObject, ObservableObject {
    @Published var note = "尚未激活手表会话"
    @Published var reachable = false

    var onEvent: ((WatchOutboundEvent) -> WatchAck?)?
    var onNoteChange: ((String) -> Void)?

    func activate() {
        guard WCSession.isSupported() else {
            note = "此设备不支持 WatchConnectivity"
            onNoteChange?(note)
            return
        }
        let session = WCSession.default
        session.delegate = self
        if session.activationState != .activated {
            session.activate()
        }
        refreshNote()
    }

    func push(_ snapshot: WatchSnapshot) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        guard let data = encodeWatchPayload(snapshot) else { return }
        let payload = [watchContextKey: data]
        try? WCSession.default.updateApplicationContext(payload)
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        }
    }

    func ack(_ ack: WatchAck) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        let payload = watchAckPayload(ack)
        WCSession.default.transferUserInfo(payload)
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        }
    }

    private func refreshNote() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        reachable = session.isReachable
        note = "手表 \(session.activationState == .activated ? "已连接通道" : "未激活") · 配对 \(session.isPaired ? "是" : "否") · App \(session.isWatchAppInstalled ? "已安装" : "未安装")"
        onNoteChange?(note)
    }

    @discardableResult
    private func ingest(_ payload: [String: Any]) -> WatchAck? {
        guard let data = payload[watchEventKey] as? Data,
              let event = decodeWatchPayload(WatchOutboundEvent.self, from: data) else {
            return nil
        }
        guard let ack = onEvent?(event) else { return nil }
        self.ack(ack)
        return ack
    }
}

extension PhoneConnectivity: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            refreshNote()
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in refreshNote() }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in ingest(message) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        Task { @MainActor in
            if let ack = ingest(message) {
                replyHandler(watchAckPayload(ack))
            } else {
                replyHandler([:])
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in ingest(userInfo) }
    }
}
