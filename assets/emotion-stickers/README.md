# 情绪贴纸

独立小团子角色，与 Logo 无关。六种姿势：开心、平静、低落、生气、紧张、困倦。

应用内使用裁切后的 PNG 关键帧循环播放（2 秒，顺序 0-1-2-3-4-0）。源 zip 里部分帧曾损坏，已从 1536×1024 精灵图重新裁切。

## 仓库中的用法

- iPhone：`Assets.xcassets/Emotion-<kind>-<frame>.imageset`（256 px）
- Apple Watch：同样命名（192 px）
- 浏览器原型：`prototype/stickers/*.gif`
- 映射：`emotionStickerKind`（WatchYouCore）

只在情绪相关界面使用。不要做成吉祥物导航或新页面。

## 本目录

- `frames/<状态>/`：512 px 关键帧
- `gif_256/`：预览用 GIF
- `character_reference.png`：角色设定
- `overview.gif`：六宫格总览
- `assemble_stickers.sh`：原始裁切与编码脚本
