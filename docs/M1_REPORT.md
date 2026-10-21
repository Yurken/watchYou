# watch you · M1 数据与 AI 基础报告

报告时间：2026-10-21。范围：`docs/CODEX_HANDOFF.md` 的 M0 收尾 + M1 阶段。所有结论只覆盖本机实际执行过的命令与结果；语义移植以已通过 54/54 断言的原型 `prototype/ai-core.js` 为基准，逐条等价。

## 环境（实测，非猜测）

- Mac：Apple Silicon，macOS；Xcode 27.1 (27A9275)。
- 签名身份：`Apple Development: yurken@163.com (ZVNZVKPDV2)`，Team `6GGZTLFCD9`；真机描述文件 `iOS Team Provisioning Profile: app.watchyou.ios`（开发类型，含本机 iPhone UDID `00008150-00124D5222D0C01C`，2026-10-28 到期）。
- 真机：iPhone 17 Pro（physical，经 `devicectl` 安装）；模拟器：iOS 18.0 Simulator（CLI 构建验证）。

## 已实现

- `Packages/WatchYouCore` 新增 12 个源文件（现共 13 个），全部仅依赖 Foundation：
  - 时间/样本：`TimeTypes.swift`（TimeWindow 绝对时长 + 结束时区分桶，Clock/SystemClock/FixedClock）、`HealthSample.swift`（HealthSampleRef UUID 幂等合并，ReadOutcome 四分枝空结果不判拒绝）。
  - 来源/睡眠治理：`SourceProfile.swift`（unknown 合法、名称/型号/bundleID 不单独作永久 ID、心率冲突并列保留不跨来源平均）、`SleepMath.swift`（睡着并集、在床剔除、同来源分期冲突标 unknown、非法区间剔除）。
  - 证据包：`Evidence.swift`（EvidenceFact/EvidencePacket，scope 白名单构建，系统模板与用户文字分离）。
  - AI 配置与安全：`AIConfig.swift`（cleanProfile/sanitizeConfig 全量校验）、`EndpointSecurity.swift`（normalizeBase/isPrivateHost/endpoint）。
  - 凭据/授权：`CredentialStore.swift`（协议 + Keychain 实现 + 内存替身，凭据绑定 profile+recipient）、`ConsentStore.swift`（AIPermission 版本化，改目的地/模型/扩范围即失效）。
  - 供给/校验/缓存：`AIProvider.swift`（AIHTTPTransport 注入、Chat/Responses/Messages 三协议独立构建解析、能力集、401/403/429/超时/截断映射、拒绝重定向）、`ResultValidator.swift`（parseResult 全部规则）、`InferenceCache.swift`（键含版本五要素 + generation 失效 + 证据删除精准失效）。
- iOS 探针新增 `AISettingsView.swift`（M0 收尾：Keychain 模型配置最小闭环）：URL/Model/认证/密钥/私网开关输入 → 校验 → Keychain 保存（配置只存 credentialRef，密钥字段用完即置空）→ 「测试连接」向 `{规范化 endpoint}/models` 发**不含健康数据**的 GET → 按 200/401/429/超时/非 JSON 分态显示，失败不回退演示文案。`ContentView.swift` 加入口 NavigationLink；工程 pbxproj 补本地包引用。

## 已测试（附命令与证据）

- Core 单元测试：`cd Packages/WatchYouCore && swift test` → **88 tests, 1 skipped, 0 failures**（基线 ScoreTests 6 条保持通过）。完整输出存 `tests/core-m1-results.txt`。覆盖 M1 验收清单：部分授权/零记录/区间重叠/时区分桶/夏令时边界/未知来源/错误 URL 家族/密钥隔离/日志脱敏/三协议独立 mock/截断三形态/授权版本失效/缓存代次失效。
- iOS 模拟器构建：
  `xcodebuild -project Apps/WatchYouiOS/WatchYouiOS.xcodeproj -scheme WatchYouiOS -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/wy-m1-sim build` → **BUILD SUCCEEDED**。
- iOS 真机构建：
  `xcodebuild -project Apps/WatchYouiOS/WatchYouiOS.xcodeproj -scheme WatchYouiOS -destination 'generic/platform=iOS' -derivedDataPath /tmp/wy-m1-device -allowProvisioningUpdates build` → **BUILD SUCCEEDED**（签名生效，HealthKit entitlement 继承 M0 配置）。
- 真机安装：`xcrun devicectl device install app --device 00008150-00124D5222D0C01C /tmp/wy-m1-device/.../WatchYouiOS.app` → **App installed**（bundleID `app.watchyou.ios`，databaseSequenceNumber 2028）。M0 遗留的「真机签名」阻断项至此解除。
- 协议/校验测试为本地 mock transport，未访问任何外部模型服务（不伪造供应商实接通过）。

## 未验证

- **真机启动与 HealthKit 查询结果分枝**：安装已成功，`devicectl` 启动返回 `device was not, or could not be, unlocked`（设备锁屏，本机无法代点）。需用户解锁后在手机上启动；首次启动如需信任证书在 设置 → 通用 → VPN与设备管理 完成，再点「请求授权并读取步数」——可读 N 条 / 暂无可读数据两个分枝仍需真实观察。
- **Keychain 真机闭环**：命令行 `swift test` 中 Keychain 测试跳过（`SecItemUpdate` 返回 -34018，CLI 无 Data Protection entitlement，预期行为）；App 内 Keychain 保存/读取与「测试连接」真实网络往返未在真机走通（需解锁后人工操作）。
- 连接测试未对接任何真实 AI 服务端点（无任何已配置服务）；模型列表/生成解析仅经 mock 验证。
- 手表 target、WatchConnectivity 本轮未动；原标识覆盖重签核对（重签前后本地事件数量）未执行。

## 阻断项与降级

1. **设备锁屏阻断自动启动验证**：`devicectl` 无解锁能力。降级：全部构建/安装证据保留，启动、授权、连接测试交用户在手操作，操作结果回填本报告。
2. 签名描述文件 2026-10-28 到期（Personal Team 7 天规则），到期需重新构建安装；维护流程按 PRD §18。

## 复现入口

```bash
cd Packages/WatchYouCore && swift test
xcodebuild -project Apps/WatchYouiOS/WatchYouiOS.xcodeproj -scheme WatchYouiOS \
  -destination 'generic/platform=iOS' -derivedDataPath /tmp/wy-m1-device -allowProvisioningUpdates build
xcrun devicectl device install app --device 00008150-00124D5222D0C01C \
  /tmp/wy-m1-device/Build/Products/Debug-iphoneos/WatchYouiOS.app
```
