# OpenEagle

原生 macOS 素材管理器，使用 SwiftUI / AppKit、SQLite、ImageIO、Quick Look、AVKit、PDFKit、CoreText 与 Vision。无第三方运行依赖。

需要 macOS 14 或更新版本、Xcode 和 Swift 6。已在 Apple Silicon Mac 上验证；Intel Mac 尚未实测。

```sh
swift test
./script/build_and_run.sh --install
```

安装脚本会将应用放到 `~/Applications/OpenEagle.app`。也可运行 `./script/build_and_run.sh --verify` 构建并验证启动，或使用 `--release` 构建优化版本。Codex 项目 Run 按钮会构建并启动应用。

- [使用说明](docs/USER-GUIDE.md)
- [Eagle 功能研究与验收契约](docs/EAGLE-RESEARCH.md)
- [本地 API、CLI 与 MCP](docs/AUTOMATION.md)
- [验收记录](docs/VERIFICATION.md)

`OpenEagleCore` 负责资源库事务、查询、迁移与元数据；应用层按场景、视图、状态和服务划分。`.openeagle` 是可移动的本地资源库。导入复制原件，备份复制完整数据库与素材，UI 编辑可撤销，回收站可恢复。

项目是独立实现，与 Eagle 官方无关联。当前功能与已知差异以使用说明、验收记录为准。

代码采用 [MIT 许可证](LICENSE)。
