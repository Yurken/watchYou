import SwiftUI
import UniformTypeIdentifiers
import WatchYouCore

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var importer = false
    @State private var exportURL: URL?
    @State private var confirmReset = false
    @State private var pendingImport: Data?

    var body: some View {
        VStack(spacing: 12) {
            BackLink()
            WYCard {
                TitleRow(title: "个人偏好", systemImage: "gearshape")
                Stepper("睡眠目标 \(model.preferences.sleepGoalMinutes) 分钟", value: Binding(
                    get: { model.preferences.sleepGoalMinutes },
                    set: { model.setSleepGoal($0) }
                ), in: 360...600, step: 15)
                Button("健康数据接入") { Task { await model.requestHealthAccess() } }
                    .font(.system(size: 14))
                Button("数据来源") { model.morePath.append("sources") }
                    .font(.system(size: 14))
            }
            WYCard {
                TitleRow(title: "AI 服务与自动分析", systemImage: "book")
                Text(model.config.activeProfile.model.isEmpty ? "配置自己的模型" : model.config.activeProfile.model)
                    .font(.system(size: 16, weight: .semibold))
                Text(model.config.activeProfile.baseURL.isEmpty ? "填写 URL、Model 与 API Key。" : model.config.activeProfile.baseURL)
                    .font(.system(size: 12))
                    .foregroundStyle(WY.muted)
                Button("模型、URL 与密钥") { model.morePath.append("ai") }
                    .font(.system(size: 14))
                    .foregroundStyle(WY.blue)
            }
            WYCard {
                TitleRow(title: "签名与安装", systemImage: "clock", pill: "每周维护")
                Text("到期时间需人工确认")
                    .font(.system(size: 16, weight: .medium))
                Text("免费个人团队证书通常约 7 天。覆盖安装，不要先卸载。")
                    .font(.system(size: 12))
                    .foregroundStyle(WY.muted)
                if !model.connectivityNote.isEmpty {
                    Text(model.connectivityNote)
                        .font(.system(size: 11))
                        .foregroundStyle(WY.muted)
                }
            }
            WYCard {
                TitleRow(title: "本地数据", systemImage: "lock.fill")
                Button("导出应用备份") { exportBackup() }
                Button("导入应用备份") { importer = true }
                Button("清除本应用记录") { confirmReset = true }
            }
            .font(.system(size: 14))
            WYNotice(text: "备份不含密钥和外发授权。健康库中的原始记录不会被导出或覆盖。")
            about
        }
        .fileImporter(isPresented: $importer, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                do {
                    pendingImport = try Data(contentsOf: url)
                } catch {
                    model.flash("无法读取备份文件")
                }
            case .failure:
                model.flash("未选择备份文件")
            }
        }
        .alert("清除本应用记录？", isPresented: $confirmReset) {
            Button("清除", role: .destructive) { model.resetRecords() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("饮水、感受和聊天会删除。")
        }
        .alert("用备份替换当前记录？", isPresented: Binding(
            get: { pendingImport != nil },
            set: { if !$0 { pendingImport = nil } }
        )) {
            Button("替换", role: .destructive) {
                if let data = pendingImport {
                    model.importData(data)
                }
                pendingImport = nil
            }
            Button("取消", role: .cancel) { pendingImport = nil }
        } message: {
            Text("当前应用记录会被这份备份替换。")
        }
        .sheet(item: Binding(
            get: { exportURL.map { IdentifiedURL(url: $0) } },
            set: { exportURL = $0?.url }
        )) { item in
            ShareSheet(items: [item.url])
        }
    }

    private var about: some View {
        WYCard {
            Image("BrandLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 36, height: 36)
                .accessibilityHidden(true)
            TitleRow(title: "关于 watch you", systemImage: "info.circle")
            Text("把睡眠、心率与恢复汇总成可查看的洞察。分析供日常参考，不会改写健康库。")
                .font(.system(size: 12))
                .foregroundStyle(WY.muted)
                .lineSpacing(4)
        }
    }

    private func exportBackup() {
        guard let data = model.exportData() else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("watch-you-backup.json")
        try? data.write(to: url)
        exportURL = url
    }
}

private struct IdentifiedURL: Identifiable {
    var url: URL
    var id: String { url.absoluteString }
}

struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
