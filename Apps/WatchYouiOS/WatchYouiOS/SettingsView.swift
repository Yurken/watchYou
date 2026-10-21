import SwiftUI
import UniformTypeIdentifiers
import WatchYouCore

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var importer = false
    @State private var exportURL: URL?

    var body: some View {
        VStack(spacing: 12) {
            BackLink()
            WYCard {
                TitleRow(title: "个人偏好", systemImage: "gearshape")
                Stepper("睡眠目标 \(model.preferences.sleepGoalMinutes) 分钟", value: Binding(
                    get: { model.preferences.sleepGoalMinutes },
                    set: { model.setSleepGoal($0) }
                ), in: 360...600, step: 15)
                Toggle("轻量提醒总开关（仅保存偏好，不创建系统通知）", isOn: Binding(
                    get: { model.preferences.remindersEnabled },
                    set: {
                        model.state.preferences.remindersEnabled = $0
                        model.persist()
                    }
                ))
                .font(.system(size: 13))
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
                Text("不假装自动读到证书。免费个人团队描述文件通常约 7 天。覆盖安装，不要先卸载。")
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
                Button("清除本应用记录") { model.resetRecords() }
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
                    model.importData(try Data(contentsOf: url))
                } catch {
                    model.flash("无法读取备份文件")
                }
            case .failure:
                model.flash("未选择备份文件")
            }
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
            TitleRow(title: "关于 watch you", systemImage: "info.circle")
            Text("watch you 把睡眠、心率与恢复汇总为可解释的洞察。本地分数是实验性启发式。AI 输出不是诊断，也不会在未确认时改写你的目标或健康库。")
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
