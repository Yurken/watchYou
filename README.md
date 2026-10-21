# watch you

**iPhone + Apple Watch 健康助手**

情绪以 AI 自动推断为主，无需每日打卡。本地先汇总睡眠、心率、HRV、活动与习惯；模型只在你配置并同意的范围内解释证据。界面不展示固定设备数量对照。展示名称为 **watch you**。

当前可运行的产品是原生 App（`WatchYou.xcworkspace`），不再依赖浏览器原型作为运行时。浏览器原型仍可作为信息架构对照。分数、推断与空状态都是实验性启发式，不是医学诊断。

## 原生 App

打开仓库根目录的 `WatchYou.xcworkspace`，选择共享 scheme：

- `WatchYouiOS`：iPhone，底栏 **今日 / 睡眠 / 情绪 / AI 助手 / 更多**。更多含心率与 HRV、恢复与压力、运动与活动、生活习惯、趋势与周报、设置；数据来源在设置内。
- `WatchYouWatch`：手表 **概览 / 睡眠 / 情绪 / 饮水 / 呼吸**。只显示手机生成的摘要；离线饮水与一分钟呼吸写入 outbox，按 id+revision 幂等合并。手表不独立调用模型。

```bash
# 领域逻辑
swift test --package-path Packages/WatchYouCore

# iPhone / Apple Watch（模拟器）
xcodebuild -workspace WatchYou.xcworkspace -scheme WatchYouiOS \
  -destination 'generic/platform=iOS Simulator' -configuration Debug build
xcodebuild -workspace WatchYou.xcworkspace -scheme WatchYouWatch \
  -destination 'generic/platform=watchOS Simulator' -configuration Debug build
```

Bundle：`app.watchyou.ios` / `app.watchyou.ios.watch`。HealthKit 只读；密钥进 Keychain，备份不含凭据与外发授权。自定义模型需填写 URL、Model、协议与密钥，并在发送前确认摘要。Demo / 本地规则摘要不会被标成实时模型成功。

未授权、无记录或样本过旧时显示空 / 未知 / 过期，不编造成功心率或成功推断。睡眠与恢复分数在夜晚数或覆盖不足时弃权。

## 需求与阶段

完整需求见 [docs/watch_you_PRD.md](docs/watch_you_PRD.md)，原生任务见 [docs/CODEX_HANDOFF.md](docs/CODEX_HANDOFF.md)。

- M0 平台探针：[docs/M0_REPORT.md](docs/M0_REPORT.md)
- M1 数据与 AI 基础：[docs/M1_REPORT.md](docs/M1_REPORT.md)
- M2–M4 产品界面、模块推断与手表：[docs/M2_REPORT.md](docs/M2_REPORT.md)

未在本机实测的项目（真机 HealthKit 授权分枝、真实模型 HTTP、手表断连重连）写在各报告的「未验证」节，不写成已通过。

## 浏览器原型（设计对照）

```bash
python3 prototype/build.py
```

用浏览器打开 `prototype/index.html`。构建无第三方依赖。默认离线演示，不发模型请求。原型使用合成健康数据，不能代替原生 HealthKit。

## 文件结构

`Apps/WatchYouiOS`、`Apps/WatchYouWatch` 为可安装应用；`Packages/WatchYouCore` 为仅依赖 Foundation 的领域包（聚合、分数、证据、校验、备份、手表快照）。`docs/` 为 PRD 与阶段报告；`prototype/` 为可编辑的 HTML 对照；`schemas/` 为无凭据契约示例；`tests/` 为脚本与结果。

未替维护者选择代码许可证。请勿把真实健康资料或长期密钥写入仓库、日志或 Issue。
