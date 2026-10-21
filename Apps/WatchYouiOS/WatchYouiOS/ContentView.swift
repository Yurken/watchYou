import SwiftUI
import HealthKit
import WatchConnectivity

// M0 platform probe only. Verifies: HealthKit authorization flow, one-type read
// with honest status states, and WatchConnectivity round trip on simulators.
// It is NOT the product UI and performs no analysis.

enum ProbeStatus: Equatable {
    case notRequested
    case authReturned // authorization sheet returned; per Apple this does NOT mean read grants
    case querying
    case readable(count: Int, lastSample: Date?)
    case empty          // zero records: several possible causes, not "denied"
    case failed(String)

    var label: String {
        switch self {
        case .notRequested: return "未请求授权"
        case .authReturned: return "授权弹窗已返回（不等于全部读取权限已授予）"
        case .querying: return "正在查询…"
        case .readable(let count, let last):
            let time = last.map(Self.formatTime) ?? "无时间"
            return "可读 \(count) 条记录 · 最近样本 \(time)"
        case .empty: return "暂无可读数据（未授权/无记录/未同步皆可能，不能判定为被拒绝）"
        case .failed(let message): return "查询发生错误：\(message)"
        }
    }

    static func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: date)
    }
}

@MainActor
final class ProbeModel: NSObject, ObservableObject {
    @Published var status: ProbeStatus = .notRequested
    @Published var sessionNote = "WCSession 未激活"
    @Published var lastReply = "尚未收到手表回复"
    private let store = HKHealthStore()
    private var sent = 0

    func requestAndRead() {
        status = .querying
        let steps = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        // FR-AUTH-01: explain purpose first, then call the system sheet.
        store.requestAuthorization(toShare: [], read: [steps]) { [weak self] _, _ in
            // FR-AUTH-02: completion only means the request flow finished.
            Task { @MainActor in
                self?.status = .authReturned
                self?.readSteps()
            }
        }
    }

    private func readSteps() {
        let steps = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -7, to: Date())!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())

        let stats = HKStatisticsQuery(quantityType: steps, quantitySamplePredicate: predicate, options: .cumulativeSum) { [weak self] _, result, error in
            if let error {
                Task { @MainActor in self?.status = .failed(error.localizedDescription) }
                return
            }
            let total = result?.sumQuantity()?.doubleValue(for: .count()) ?? 0
            let last = HKSampleQuery(sampleType: steps, predicate: predicate, limit: 1, sortDescriptors: [NSSortDescriptor(keyPath: \HKSample.startDate, ascending: false)]) { _, samples, _ in
                Task { @MainActor in
                    if total > 0 {
                        self?.status = .readable(count: Int(total), lastSample: samples?.first?.startDate)
                    } else {
                        self?.status = .empty
                    }
                }
            }
            self?.store.execute(last)
        }
        store.execute(stats)
    }

    func activateSession() {
        guard WCSession.isSupported() else {
            sessionNote = "此设备不支持 WCSession"
            return
        }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func pingWatch() {
        sent += 1
        let payload = ["probe": "ios-to-watch", "n": sent, "at": Date().timeIntervalSince1970] as [String: Any]
        WCSession.default.sendMessage(payload) { [weak self] reply in
            Task { @MainActor in
                self?.lastReply = "手表回复：\(reply["echo"] as? String ?? "无内容")"
            }
        } errorHandler: { [weak self] error in
            Task { @MainActor in
                self?.lastReply = "发送失败：\(error.localizedDescription)（可达性受配对与安装状态影响）"
            }
        }
    }
}

extension ProbeModel: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            sessionNote = "WCSession \(state == .activated ? "已激活" : "状态 \(state.rawValue)") · 配对手表：\(session.isPaired) · 已安装手表 App：\(session.isWatchAppInstalled)"
        }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            lastReply = "收到手表消息：\(message["probe"] as? String ?? "未知") #\(message["n"] as? Int ?? -1)"
        }
    }
}

struct ContentView: View {
    @StateObject private var model = ProbeModel()

    var body: some View {
        NavigationStack {
            List {
                Section("M0 · 平台探针（非产品界面）") {
                    Text("验证免费签名、HealthKit 读取与 Watch 通信；不展示真实健康结论。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("健康数据探针") {
                    Text(model.status.label)
                        .font(.callout)
                    Button("请求授权并读取步数（近 7 天）") {
                        model.requestAndRead()
                    }
                    Text("HealthKit 出于隐私不暴露逐项读取授权状态；空结果不等于权限被拒绝。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("WatchConnectivity 探针") {
                    Text(model.sessionNote).font(.callout)
                    Text(model.lastReply).font(.callout)
                    HStack {
                        Button("激活会话") { model.activateSession() }
                        Button("发送计数到手表") { model.pingWatch() }
                    }
                }
            }
            .navigationTitle("watch you")
        }
        .onAppear { model.activateSession() }
    }
}
