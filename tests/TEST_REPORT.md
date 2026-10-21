# watch you · 提交前测试报告

重新执行时间：2026-10-21T11:40:00Z（UTC）。全部健康数据与模型响应均为合成夹具。

## 实际结果

领域逻辑 26/26（新增训练负荷、饮水目标钳制、RPE 校验、提醒治理默认值与边界），通过记录见 `core-results.txt`。AI 配置、协议与校验 45/45，见 `ai-core-results.txt`。Chromium 交互、模拟协议与布局 93/93（新增饮水撤销/恢复、自定义目标、RPE 持久化、午睡分开展示、恢复基线透明信息、提醒分类/静默时段/上限），见 `browser-results.json` 与 `browser-console.txt`。合计 164 项检查通过；没有未捕获浏览器脚本错误。供应商请求全部被 Playwright mock 拦截，没有调用外部模型或使用真实密钥。

执行命令：`python3 prototype/build.py`、`node tests/core.test.cjs`、`node tests/ai-core.test.cjs`、`python3 tests/browser_test.py`。源码重建的单文件 HTML 与此前交付版本一致。仓库初始 HTML 为引用相邻 CSS/JS 的入口，运行构建后生成被测试的单文件版本。

## 覆盖与环境

覆盖重叠区间、睡眠来源和在床排除、分数示例、缺失值、基线不足、事件幂等、备份校验、训练负荷（无 RPE 不生成数字）、饮水目标钳制、RPE 边界、提醒治理默认值与静默时段校验；URL 安全、密钥排除、三种协议、证据引用及情绪字段校验；页面路由、自动情绪界面、数据来源、范围授权、离线队列、失败处理、HTML 转义、导出恢复、计时、饮水撤销/恢复、自定义饮水目标、RPE 持久化、午睡分开展示、恢复基线透明信息与提醒分类/静默时段/上限。

布局检查覆盖 375、390、768、1440 像素下的今日、情绪、AI 设置、助手和数据来源。Node.js v22.16.0、Python 3.13.5、Chromium 144.0.7559.96、Linux、Playwright。

当前环境限制页面导航，测试使用 `set_content` 与内存 localStorage 适配器；验证了序列化往返，未验证浏览器关闭/重启后的实际存储保留。脚本可重新生成截图；PNG 与 Word 导出版不纳入本次 Git 提交。

## 未验证

Safari/iOS WebKit、真实供应商认证/CORS/额度与参数兼容、Xcode、原生 HealthKit/Keychain/WatchConnectivity、Personal Team 签名、手表安装、后台调度、系统通知、加密备份、耗电和真实情绪识别效果均未验证。142 项是检查数量，不是覆盖率、医学准确率或全部产品需求完成比例。
