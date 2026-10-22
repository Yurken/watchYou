# watch you · Logo

官方图形：**无边框、无名称、无手表元素**的蓝绿渐变标志。

## 仓库中的用法

- iPhone App Icon：`Apps/WatchYouiOS/WatchYouiOS/Assets.xcassets/AppIcon.appiconset/`（白底 1024，Single Size）
- Apple Watch App Icon：`Apps/WatchYouWatch/WatchYouWatch/Assets.xcassets/AppIcon.appiconset/`（白底 1024，Single Size）
- iPhone 应用内标志：`Apps/WatchYouiOS/WatchYouiOS/Assets.xcassets/BrandLogo.imageset/`（透明 512，引导页与关于）
- 浏览器原型：`prototype/brand-logo.png`、`prototype/favicon.ico`

不要预先裁圆角。系统会处理 App Icon 圆角。不要另做一套图标。

## 本目录内容

- `01_透明PNG/`：16–1088 px。界面、文档、透明背景。
- `02_白底应用图标PNG/`：同样尺寸，白色不透明底。
- `03_Xcode_直接使用/`：iPhone / Watch 的 `AppIcon.appiconset`，以及 watchOS 1088 视觉参考。
- `04_网站图标/`：favicon.ico、常用 favicon PNG 和 Apple Touch Icon。
- `原始设计_白底1254x1254.png`：生成原图。
- `原始元素_透明1254x1254.png`：从白底去底的透明版。
- `预览_尺寸对照.png`：深浅背景对照。

透明版由白底 RGB 去色生成，极浅边缘在深色背景上可能有轻微失真。白底 App Icon 与原色更一致。
