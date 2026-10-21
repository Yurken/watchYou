# Changelog

## v2.4 · 2026-10-21

把原型信息架构做成可安装的 iPhone + Apple Watch 产品（M2–M4 P0）。展示名称 **watch you**。

- iOS：底栏今日 / 睡眠 / 情绪 / AI 助手 / 更多；更多含心率与 HRV、恢复与压力、运动与活动、生活习惯、趋势与周报、设置。数据来源在设置内，首页无设备数量对照。
- HealthKit 只读聚合；空 / 未知 / 过期如实显示。睡眠与恢复分数在夜晚数或覆盖不足时弃权。饮水 +150/+250/+500 与一分钟不屏息呼吸本地持久化。
- 九个模块共用质量门控 → 证据包 → 本地规则或实时模型 → 引用证据 ID 的校验。实时调用需要 BYOK 与明确同意；失败或无效输出不标成功。Demo 本地规则摘要与实时成功分开。
- Watch：概览 / 睡眠 / 情绪 / 饮水 / 呼吸。手机推送 `makeWatchSnapshot`；outbox 按 id+revision 幂等。手表不调用模型。
- 备份导出去掉密钥与授权，导入强制 demo 并丢弃 consent。共享 scheme `WatchYouiOS` / `WatchYouWatch` 可从工作区直接 `xcodebuild`。

验证：`swift test --package-path Packages/WatchYouCore` 两次均为 109 执行、1 跳过（CLI Keychain -34018）、0 失败；iOS 与 Watch 模拟器 `xcodebuild` 各两次 BUILD SUCCEEDED；模拟器安装后进程启动，`CFBundleDisplayName` 为 `watch you`，今日页展示空数据态而非合成成功。未验证：真机 HealthKit 授权分枝、真实模型 HTTP、手表断连重连。明细见 `docs/M2_REPORT.md`。

空的 HealthKit 日桶不再写成 0 或把区间结束时刻当样本时间；活动页把缺失的能量/锻炼显示为 —；健康空态不因饮水记录而消失。手表饮水用 `displayedWater`，快照已含的事件 id 不再累加。

## v2.3 · 2026-10-21

进入原生 M1 并收尾 M0。`WatchYouCore` 新增 12 个纯 Foundation 模块：时间窗/时钟、样本 UUID 幂等与 ReadOutcome 四分枝、来源治理（unknown 合法、冲突不平均）、睡眠并集（在床剔除、冲突标 unknown）、EvidencePacket 白名单构建、AI 配置校验、端点安全（HTTPS 默认/私网开关/危险形态拒绝）、Keychain 凭据绑定 recipient、授权版本化失效、Chat/Responses/Messages 三协议供给（注入式 transport、错误映射、拒绝重定向）、结果校验（无 context 不输出确定正负向）、推断缓存（generation 与证据删除失效）。语义逐条等价移植已通过 54/54 断言的原型 `prototype/ai-core.js`。

iOS 探针新增 AISettingsView：URL/Model/认证/密钥 → Keychain 保存 → 不含健康数据的 `/models` 连接测试 → 分态错误，失败不回退演示文案。

验证：`swift test` 88/88（1 项 Keychain 用例因 CLI 无 entitlement 跳过）；模拟器与真机 xcodebuild 均 BUILD SUCCEEDED；真机 `devicectl` 安装成功（M0 真机签名阻断解除）。未验证：真机启动（设备锁屏）、HealthKit 查询分枝、真实服务端连接。明细见 `docs/M1_REPORT.md`。

## v2.2 · 2026-10-21

进入原生开发 M0：新增 `WatchYou.xcworkspace`、`Apps/WatchYouiOS`（HealthKit 步数探针 + 六态授权状态机）、`Apps/WatchYouWatch`（WCSession 接收/回执）、`Packages/WatchYouCore`（睡眠分/恢复分/训练负荷纯 Swift 实现，缺失输入弃权，6 个 XCTest）。

验证（仅限本机模拟器）：Core 6/6 通过；WatchConnectivity 双端编号往返打通（`ios-to-watch #3` ↔ `watch-ack #3`）；HealthKit 授权 sheet 真实弹出。未验证：真机签名、查询结果分支、覆盖重签、Keychain 闭环。明细见 `docs/M0_REPORT.md`。

## v2.1 · 2026-10-21

按 PRD 补齐原型差距：饮水支持自定义目标（500–4000 ml）与撤销/恢复上一次记录；运动 RPE 持久化，训练负荷 = 分钟 × RPE（无 RPE 不生成数字）；睡眠页新增日间小睡卡（不计入主睡眠评分）；恢复参考展示基线窗口、有效日、样本时间与缺失输入；提醒治理支持分类开关、静默时段与每日上限。新增 `trainingLoad` / `validateReminderPrefs` 领域函数，演示备份格式向后兼容（新字段缺省回填）。

验证：领域逻辑 26/26、AI 配置与协议 45/45、Chromium 交互 93/93 通过；所有供应商请求仍为本地 mock。

## v2.0 · 2026-10-21

产品名称统一为 watch you，仓库标识 Yurken/watchYou。情绪默认自动推断，自愿补充仅为可选；首页不展示设备数量或固定来源对照，数据来源下沉到设置/详情。AI 成为各模块共用能力，新增 AI 助手与多服务配置。

增加 URL/Model/认证/密钥/协议、参数、模型列表、连接测试、范围同意、自动调用去重、请求上限、取消与错误处理。三个协议独立构建和解析；真实请求失败不回退演示答案。密钥限内存，导出不含密钥和授权；变更目标撤销外发同意。

保留睡眠、HRV、恢复、运动、饮水、呼吸、来源治理与重签维护。文档更新为 28 章，新增详细 AI 设置、契约、调度和开发任务书。新增 AI helper 与模拟协议回归测试。

当前仅交付产品规范和浏览器原型；真实 HealthKit、Keychain、WatchConnectivity、签名、耗电与情绪效果仍待原生验证。
