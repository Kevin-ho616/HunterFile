# HunterFiles H icon

蓝色圆角方形，白色 H 的竖笔画借用文件叠页的形态。图标由 Codex 内置 imagegen 工具生成，未使用 CLI fallback；它是栅格原稿，不是可编辑矢量。

- 原稿：`hunterfiles-app-icon.png`，1254 × 1254，RGBA 透明背景。
- SHA-256：`4d0ac3bffe402aea3b014fc3a4c8e842c700d7ba4d94292facd1d6d11b43755a`。
- `script/make_icon.swift` 使用 AppKit 缩放生成 16–1024 像素的 macOS 图标与 `dist/AppIcon.icns`；应用侧栏复用应用图标。
- `browser-extension/icons/` 包含 16 / 32 / 48 / 128 像素的扩展图标。16、32、128 来自同一 AppKit 输出，48 由系统 sips 缩放；更新原稿后应同步这些文件。
- 旧 E 图标已移除，可通过 Git 历史恢复。

## Final generation prompt

```text
Use case: logo-brand. Create one finished production macOS application icon for HunterFiles, a local-first creative asset manager for images, videos and documents. The icon's only glyph must be an unmistakable capital letter H. Apple-style craft, simple confident geometry, softly rounded square tile, shallow polished dimensional relief, elegant restrained blue material, a cool luminous white H. Interpret the two upright strokes as clean file spines connected by a horizontal central bridge, but retain an instantly legible bold H silhouette at 16 and 32 pixels. Straight-on orthographic front view, perfectly centered, no tilt or perspective. One cobalt-to-azure rounded square occupies approximately 84 percent of the 1024 by 1024 square canvas, with balanced transparent margins outside; softly rounded chunky H has generous clear space around it. Subtle satin/glass edge light and soft internal shading, strong silhouette and contrast, smooth professionally finished surfaces. No sparkle, no eagle, no extra symbol, no extra lettering, no words, no Apple logo, no border outside the rounded square, no mockup device, no surrounding scene, no watermarks. Genuine transparent pixels outside the icon tile, no checkerboard painted into the image. Deliver a single crisp square icon, not a contact sheet.
```
