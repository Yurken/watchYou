# watch you · M0 平台探针报告

报告时间：2026-10-21。范围对应 `docs/CODEX_HANDOFF.md` 的 M0 阶段。所有结论只覆盖本机实际执行过的命令与观察到的界面状态，未验证项如实列出。

## 环境（实测，非猜测）

- Mac：Apple Silicon，macOS（Xcode 27.1 所需版本已满足）。
- Xcode 27.1 (27A9275)；模拟器运行时：iOS 26.4/26.5、watchOS 27.0（本轮下载安装，约 3.83 GB）。
- 签名身份：`security find-identity -v` 显示 1 个 `Apple Development: yurken@163.com (ZVNZVKPDV2)`（个人团队）；`~/Library/MobileDevice/Provisioning Profiles` 为空。
- 模拟器设备（记录在 `/tmp/watchyou-m0-devices.txt`，属临时文件不入库）：
  - iPhone：`F5423FDB-0405-4AB8-8C34-4AE9BCAAF23F`
  - Apple Watch：`BCD9CF53-040C-4363-972A-661CEEAB3877`（配对：`E776B69A-052D-4B37-904F-0F7B91975F39`）
- 本机限制：Xcode 安装中**不含 Simulator.app GUI**（`open -a Simulator` 失败），全部模拟器交互通过 xcodebuildmcp（快照/点击/截图/等待 UI）与 `simctl` 完成；MCP 快照看不到系统弹窗内容（如 HealthKit 授权 sheet）。

## 已实现

- 工作区 `WatchYou.xcworkspace`（引用 iOS / watchOS 两个工程与本地包）。
- `Apps/WatchYouiOS/`：最小 iPhone 探针 App。含 `WatchYouiOS.entitlements`（`com.apple.developer.healthkit = true`）、`NSHealthShareUsageDescription`（「M0 探针仅读取步数以验证授权与查询流程，不做健康分析」）。界面按 FR-AUTH-02/03 建模六种授权状态（未请求 / 等待授权返回 / 正在查询 / 可读 / 无数据 / 失败），读取近 7 天步数聚合与最近样本，并实现 WCSession 发送与回执展示。
- `Apps/WatchYouWatch/`：最小 watchOS 探针 App（bundle id `app.watchyou.ios.watch`，被子 bundle 前缀规则约束），实现 WCSession 接收手机消息并回执。
- `Packages/WatchYouCore/`：纯 Swift 领域包，实现 PRD §14 的睡眠分 / 恢复分 / trainingLoad 计算，缺失输入返回 `nil` 而非补 0（弃权语义），不依赖 UI 与服务商。

## 已测试（附命令与证据）

- Core 单元测试：`swift test`（`Packages/WatchYouCore/`）**6/6 通过**，含 PRD 示例值（睡眠 92 / 恢复 83 等）。
- 构建命令（HealthKit 探针必须带签名，见「阻断项」）：

  ```bash
  xcodebuild -project WatchYouiOS.xcodeproj -scheme WatchYouiOS \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath .ios-build/derived-data CODE_SIGNING_ALLOWED=YES build
  ```

  直接产物 `.ios-build/derived-data/…/WatchYouiOS.app` 内 `-Simulated.xcent` 含 `com.apple.developer.healthkit`。若用仓库脚本（默认 `CODE_SIGNING_ALLOWED=NO`）构建，运行时报 `Missing com.apple.developer.healthkit entitlement`——该原始错误已复现并留档。
- WatchConnectivity 双端往返（模拟器）：
  1. `xcrun simctl install <WATCH_UDID> WatchYouWatch.app` 直接安装到手表并运行；
  2. `xcrun simctl shutdown <PHONE_UDID>` 后重新 `boot`，手机端探针显示「已安装手表 App：true」（此前直接安装手机端报 `Watch app is not installed`，嵌入 `Watch/` 目录亦不可见，最终以此法打通）；
  3. 手表端保持前台（若不在前台，发送方报 `not reachable`；先 `terminate` 再 `launch` 恢复可达）；
  4. 手机发送 `ios-to-watch #N`，手表收到并回执 `watch-ack #N`。
- 端到端证据：手机端界面显示「手表回复：watch-ack #3」，手表端界面显示「收到手机消息：ios-to-watch #3」（MCP 快照文本 + 截图存证）。
- HealthKit 授权流程：探针点击「请求授权」后，**系统授权 sheet 真实弹出**，截图可见「访问健康数据 / 步数 / App 说明：M0 探针仅读取步数…」；授权回调未返回前界面停在「正在查询…」，即 FR-AUTH-02 状态机实证。

## 未验证

- 真机 Personal Team 签名：本机仅有开发证书、无 Provisioning Profile，需在 Xcode 中登录/确认 Apple ID 后才能在真机构建运行。
- HealthKit 查询结果分支（可读 N 条 / 无数据）：授权 sheet 弹出后无法自动点击，App 停在等待状态，两个结果分支均未走到。
- 原标识覆盖重签（重签前后本地事件数量对比）：未执行。
- Keychain 模型配置最小闭环（M0 另一部分）：未开始。

## 阻断项与降级

1. **HealthKit 授权 sheet 无法自动点击。** 本机无 Simulator.app GUI；MCP 快照不含系统弹窗，`simctl` 无点击能力。已试过且失败：TCC 预授权（向 `kTCCServiceHealth` 插行 `auth_value=2` 并重启模拟器，iOS 26 模拟器下 sheet 仍弹出）；`simctl privacy grant health`（Operation not permitted）。降级方案：用户在 Xcode 中打开模拟器窗口，手动点「允许」，随后可验证查询结果分支。本项不伪造授权成功，也不把 sheet 弹出当作授权完成。
2. **手表 App 注册需经配对同步。** 直接 `simctl install` 到手表时手机端不可见（`isWatchAppInstalled=false`），嵌入 `Watch/` 目录亦无效；重启手机模拟器后恢复可见。属模拟器环境行为，真机配对时按常规 Watch 部署流程验证。

## 复现入口

```bash
open WatchYou.xcworkspace            # 或 xcodebuild 按上文命令
cd Packages/WatchYouCore && swift test
```
