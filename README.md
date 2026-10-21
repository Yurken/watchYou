# watch you

**iPhone + Apple Watch AI 健康助手 · v2.0 需求与交互原型**

情绪以 AI 自动推断为主，手动背景与纠正为可选；界面只呈现通用数据来源，不突出设备数量。AI 覆盖今日、睡眠、心率/HRV、恢复、运动、习惯、趋势报告与问答。设置支持自定义 URL、Model、API Key、协议、多组服务、调用参数和外发数据范围。

当前仓库包含 M0 原生平台探针（可构建的最小 iPhone/watchOS 配套工程），但不是完成的 App。所有健康观测均为合成示例，情绪推断未做真实效果或医学验证。

## 原生开发状态（M0）

已建立 `WatchYou.xcworkspace` 与 `Apps/WatchYouiOS`、`Apps/WatchYouWatch`、`Packages/WatchYouCore` 最小工程；模拟器上已验证 WatchConnectivity 双端往返、HealthKit 授权 sheet 真实弹出、Core 单元测试 6/6。真机签名、HealthKit 查询结果分支、覆盖重签与 Keychain 闭环未验证，明细见 [docs/M0_REPORT.md](docs/M0_REPORT.md)。

## 阅读与运行

完整需求见 [docs/watch_you_PRD.md](docs/watch_you_PRD.md)，原生开发顺序见 [docs/CODEX_HANDOFF.md](docs/CODEX_HANDOFF.md)，实际测试范围见 [tests/TEST_REPORT.md](tests/TEST_REPORT.md)。

克隆或下载整个仓库后，在根目录执行：

```bash
python3 prototype/build.py
```

然后用本机浏览器打开 `prototype/index.html`。构建无第三方依赖，会把分离源码合成单文件，便于离线使用。仓库中的初始 `index.html` 使用相邻的 CSS/JS 文件，不能只下载这一份文件；构建后则可以单独复制它。也可以运行 `python3 -m http.server 8000 --bind 127.0.0.1`，在浏览器访问 `http://127.0.0.1:8000/prototype/`。

默认离线演示，不发模型请求。进入“设置 → AI 服务”配置自己的接口，可选 Chat Completions、Responses 或 Messages。连接测试不含健康数据；真实分析前预览接收端与摘要。即使调用真实模型，输入仍然是合成健康数据，不代表接入了 HealthKit。

密钥只在网页内存中保留，不进入 localStorage、备份或源码；刷新后重填。更改接收端清理旧密钥绑定，修改服务/模型/范围撤销旧同意。请求受 CORS、TLS 和服务端能力约束，失败不会假装成功。请勿输入真实敏感健康资料、关闭浏览器安全防护或把此页面作为公开生产客户端使用。

## 文件结构

`docs/` 保存完整 28 章 PRD 与 Codex 原生任务书；`prototype/` 保存可编辑界面、领域逻辑、AI 请求与校验源码；`schemas/` 保存无凭据的契约示例；`tests/` 保存测试脚本与实际结果；`tools/render_prd.py` 用于生成 Word；`assets/` 是截图输出目录。

Word 和 PNG 是生成产物，本次不纳入 Git 历史，原始导出版保留在已交付的完整设计包中。PRD 第 28 章关于空仓库和未提交的描述是设计阶段快照；本仓库提交已建立，不代表原生实现完成。未替维护者选择代码许可证。

## 重跑检查

```bash
python3 prototype/build.py
node tests/core.test.cjs
node tests/ai-core.test.cjs
python3 -m pip install -r requirements-dev.txt
python3 -m playwright install chromium
# 指定已安装的 Chromium，或使用系统 chromium：
CHROMIUM_BIN=/path/to/chromium python3 tests/browser_test.py
```

浏览器测试会输出截图到 `assets/`，并写入 `tests/browser-results.json`。它使用 set_content 和内存存储适配器，所有供应商请求均被 mock 拦截，不验证真实浏览器重启持久化或真实 API。不要将这些检查解释为医疗准确率。

生成截图后可运行 `python3 tools/render_prd.py` 生成 `docs/watch_you_PRD.docx`；需安装 python-docx，中文字体与渲染环境会影响版式。仓库不包含字体文件。

原生开发从签名、HealthKit 最小读取、Watch 通信和 Keychain 模型配置探针开始。每阶段区分已实现、已测试、未验证和阻断项，不把浏览器演示写成实机成果。
