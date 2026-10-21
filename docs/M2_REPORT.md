# watch you · M2–M4 产品化报告

报告时间：2026-10-21。范围：`docs/CODEX_HANDOFF.md` 的 M2 自动情绪闭环、M3 全模块 AI、M4 手表与备份（P0，不含 M5 发布）。对照原型信息架构 `/Users/sen/Downloads/watch_you_Prototype.html` 与仓库 `prototype/`。所有结论只覆盖本机实际执行过的命令与结果。

## 环境（实测）

- Mac：Apple Silicon，macOS；Xcode 27.1 (27A9275)，路径 `/Applications/Xcode.app`。
- 工作区：`WatchYou.xcworkspace`；共享 scheme `WatchYouiOS`、`WatchYouWatch`。
- Bundle：`app.watchyou.ios` / `app.watchyou.ios.watch`；Team `6GGZTLFCD9`。
- 模拟器：iOS 26.5 `WatchYou-M0`（UDID `F5423FDB-0405-4AB8-8C34-4AE9BCAAF23F`，已启动）；watchOS 27.0 `WatchYou-M0-Watch`（UDID `BCD9CF53-040C-4363-972A-661CEEAB3877`）。

## 已实现

### 信息架构

- iPhone 底栏：**今日、睡眠、情绪、AI 助手、更多**。
- 更多：**心率与 HRV、恢复与压力、运动与活动、生活习惯、趋势与周报、设置**。
- **数据来源**从设置进入，不是更多的一级项。
- 展示名称 `CFBundleDisplayName` = **watch you**。首页与导航没有固定设备数量对照。
- Watch 五页：**概览、睡眠、情绪、饮水、呼吸**。

### 数据与分数

- iOS `HealthKitRepository` 只读：睡眠分期（含历史 asleep rawValue=1）、心率、静息心率、HRV、步数、活动能量、锻炼时间、训练。
- `WatchYouCore.aggregateHealth` 归一化；空目录 `isEmpty`，分数为 nil。主睡眠取当日结束的最长过夜段，日间小睡不计入评分。
- 睡眠 / 恢复分数在夜晚数或覆盖不足时弃权。
- 饮水 +150 / +250 / +500 ml 与一分钟不屏息呼吸写入本地 `HabitEvent`，可撤销。

### AI 管线

模块 today / mood / sleep / heart / recovery / activity / habits / trends / assistant 共用：质量门控 → EvidencePacket → 本地规则或实时模型 → `parseResult` 必须引用已有 evidence ID。

- Demo / auto：`localInference`，文案为「本地规则摘要」，情绪 valence 保持 unknown。
- 实时：需要 URL、Model、协议、Keychain 密钥与明确同意；缓存命中不重复请求。
- 失败、截断、未知证据、无依据成功结论不显示为成功。
- Watch 不导入 `AIProvider`，不发起模型请求。

### 手表与备份

- 手机 `makeWatchSnapshot` 经 WatchConnectivity applicationContext 下发标题、睡眠窗 `HH:mm–HH:mm`、饮水合计。
- 手表 outbox：`transferUserInfo` + `sendMessage`；合并 `mergingOutbound` / `removingOutbound`，id+revision 幂等。
- `exportBackup` 去掉 consent 与密钥并强制 demo；`importBackup` 拒绝疑似密钥字段。

## 已测试（附命令）

- Core：`swift test --package-path Packages/WatchYouCore` **连续两次**。
  - 每次：Executed 109 tests，1 skipped（CLI Keychain -34018），0 failures。
  - 覆盖：空目录 nil 分数；不足夜晚弃权；`makeWatchSnapshot` 空 / 过期 / 基线 / 洞察标题；outbox 幂等；备份去授权；`parseResult` 拒绝未知 ID；本地规则不是实时成功；value=0 日桶不产生 todaySteps/A1、lastSampleAt 不用桶结束时刻；饮水事件不填满健康空态；`displayedWater` 对已合并 id 不双计。
  - 摘要：`tests/core-m2-results.txt`。既有 Score / Source / Validator / Provider 套件仍通过。
- iOS：`xcodebuild -workspace WatchYou.xcworkspace -scheme WatchYouiOS -destination 'generic/platform=iOS Simulator' -configuration Debug build` **两次 BUILD SUCCEEDED**。
- Watch：同上 scheme `WatchYouWatch`、`generic/platform=watchOS Simulator` **两次 BUILD SUCCEEDED**。
- 启动：`simctl install` + `simctl launch` 于 `WatchYou-M0`。
  - 进程 pid 44612（引导页）、46502（今日页）均保持运行，无 WatchYou DiagnosticReport。
  - 已安装产品 `CFBundleDisplayName` = `watch you`（`simctl listapps` 与 Info.plist 一致）。
  - 今日页展示「等待你的第一份数据 / 暂无可读健康数据」，部分读取失败写明类型，没有合成心率当成功。
  - Watch 模拟器 `simctl launch` 返回 pid 47437，进程仍在；截图时表盘息屏，未拍到五页内容。五页以源码静态核对为准。

## 未验证

- 真机 HealthKit 授权弹窗后的各项读取分枝（模拟器返回部分读取未完成，已如实展示）。
- 真实模型 HTTP（Chat / Responses / Messages）与 Keychain 在带 entitlement 的 App 内往返。
- 手表与手机断连、进程终止、重复 transferUserInfo、旧消息到达的设备级往返。
- 备份文件在另一台设备上的人工导入。
- App Store / TestFlight、Widget、复杂功能、APNs、HealthKit 写入。

## 阻断项与降级

- 无编译阻断。iOS `Info.plist` 必须放在 `Apps/WatchYouiOS/Info.plist`（同步源码组外），否则会与 `ProcessInfoPlistFile` 重复产出 `Info.plist`。
- 本沙箱不能代替真机授权或付费模型调用。空数据与本地规则是预期降级，不是演示成功。

## 相对原型的边界

原生 App 实现原型的信息架构、数据/AI/手表/备份合同，不是 HTML 画框、场景下拉或像素级复制。浏览器 `prototype/` 仍可离线打开作对照。
