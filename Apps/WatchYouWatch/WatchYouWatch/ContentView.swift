import SwiftUI
import WatchConnectivity

// M0 probe counterpart on watchOS. Receives counter messages from the phone
// probe and replies, verifying the WatchConnectivity round trip.

@MainActor
final class WatchProbeModel: NSObject, ObservableObject {
    @Published var sessionNote = "WCSession 未激活"
    @Published var lastMessage = "尚未收到手机消息"
    @Published var replyNote = ""

    func activate() {
        guard WCSession.isSupported() else {
            sessionNote = "不支持 WCSession"
            return
        }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func pingPhone() {
        WCSession.default.sendMessage(["probe": "watch-to-ios", "n": Int(Date().timeIntervalSince1970) % 1000]) { [weak self] reply in
            Task { @MainActor in
                self?.replyNote = "手机回复：\(reply["echo"] as? String ?? "无内容")"
            }
        } errorHandler: { [weak self] error in
            Task { @MainActor in
                self?.replyNote = "发送失败：\(error.localizedDescription)"
            }
        }
    }
}

extension WatchProbeModel: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            sessionNote = "WCSession \(state == .activated ? "已激活" : "状态 \(state.rawValue)") · 配套 App 已安装：\(session.isCompanionAppInstalled)"
        }
    }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        let tag = message["probe"] as? String ?? "未知"
        let n = message["n"] as? Int ?? -1
        Task { @MainActor in
            lastMessage = "收到手机消息：\(tag) #\(n)"
        }
        replyHandler(["echo": "watch-ack #\(n)"])
    }
}

struct ContentView: View {
    @StateObject private var model = WatchProbeModel()

    var body: some View {
        List {
            Section("M0 · 手表探针") {
                Text(model.sessionNote).font(.footnote)
                Text(model.lastMessage).font(.footnote)
                Text(model.replyNote).font(.footnote)
            }
            Section {
                Button("激活会话") { model.activate() }
                Button("发消息给手机") { model.pingPhone() }
            }
        }
        .onAppear { model.activate() }
    }
}
