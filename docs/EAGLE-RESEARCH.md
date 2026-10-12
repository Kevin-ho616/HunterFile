# Eagle 功能研究与 HunterFile 开发契约

研究日期：2026-09-06。来源：官方公开资料与本机 Eagle 界面观察；独立实现，不使用 Eagle 私有代码、图标或品牌素材。

## 产品模型

Eagle 是本地素材管理器。资源库拥有原始文件、缩略图和分类元数据。文件夹是逻辑分类，一个文件可以放在多个文件夹；智能文件夹保存筛选规则，不重复复制文件。左栏负责导航，中央区域负责浏览与多选，右栏负责编辑与批处理。空格/双击预览、键盘、右键菜单、拖入拖出是高频交互。

| 领域 | 官方能力 | 开发与验收目标 |
| --- | --- | --- |
| 资源库 | 多库、新建/切换、外置盘、同步工具配合 | 可移动本地资源库；SQLite 事务；进程互斥；备份与重新打开 |
| 采集 | 文件/目录拖入、剪贴板、截图、浏览器扩展、网页书签 | 原文件保留；递归目录；任务进度/取消/逐项错误；URL 下载；书签；浏览器采集 |
| 分类 | 嵌套/多文件夹、标签、自动标签、评分、智能文件夹 | 批处理；标签合并/重命名；组合筛选；规则持久化 |
| 搜索 | 名称、标签、备注、类型、颜色、尺寸、比例、大小、日期、评分 | SQLite 分页；中英文子串；筛选组合；搜索状态可保存 |
| 浏览 | 网格、瀑布流、列表、缩略图调节、预览、独立窗口 | 原比例缩略图；多选/快捷键；图片/GIF/视频/音频/PDF/字体/Quick Look |
| 编辑 | 重命名、备注、来源、标注、旋转、批量处理 | 原件保持；元数据编辑可撤销；图片区域标注；变换导出新文件 |
| 去重 | 重复扫描、相似搜索 | 流式 SHA-256 精确去重；图像特征相似度；合并分类元数据 |
| 工作流 | 监控文件夹、快捷动作、导出、eaglepack | 目录自动导入；批量动作；原件与元数据导出；Eagle 库只读迁移 |
| 扩展 | JavaScript/HTML 插件、Web API、MCP/Skill | 本地受认证 API、浏览器扩展与自动化接口；第三方 Eagle 插件兼容性单独列明 |
| AI | 视觉/语义搜索、命名/标签/备注、模型配置 | 本地 OCR/图像特征；可配置模型的显式操作；不自动上传素材 |
| 隐私 | 文件夹密码保护 | 锁定显示与加密须明确区分；不把界面锁称作文件加密 |

## 原生实现

macOS 14+；SwiftPM；SwiftUI 场景/菜单/侧栏/设置；AppKit 文件面板与桌面交互；ImageIO / Quick Look / PDFKit / AVKit / CoreText / Vision；SQLite + CryptoKit；无第三方运行依赖。

核心模块 `HunterFileCore` 负责值模型、查询与资源库事务；应用模块分为 App、Views、Stores、Services、Support。文件处理与查询在 actor 上串行执行，界面在主线程；缩略图按需生成、缓存。库的相对路径不得逃逸资源库；导入先复制到暂存区，完成后原子移动并提交索引；失败不影响源文件。首次启动不读取或迁移现有私人资源库。

## 核验

1. 核心测试：建库、导入、重开、重复文件、分类/搜索、批处理、回收站恢复、备份、路径校验与损坏库处理。
2. 本机 UI：新建/打开、导入多种文件、选择、预览、编辑、筛选、批量、导出与重启持久化。
3. 构建 `.app`、签名验证、通过项目 Run 脚本启动。分发公证和付费云服务没有凭据时如实记录。

## 官方来源

- [官网功能总览](https://en.eagle.cool/)
- [全部帮助主题](https://en.eagle.cool/support/all-articles)
- [智能文件夹](https://en.eagle.cool/support/article/smart-folders)
- [布局](https://en.eagle.cool/support/article/changing-layouts)
- [图片标注](https://en.eagle.cool/support/article/image-comments)
- [文件格式](https://en.eagle.cool/support/article/what-file-formats-does-eagle-support)
- [重复文件](https://en.eagle.cool/support/article/scanning-for-identical-files)
- [插件文档](https://developer.eagle.cool/)
- [Apple 图像特征](https://developer.apple.com/documentation/vision/vngenerateimagefeatureprintrequest)

部分帮助页面在文本抓取中只返回标题和导航。因此未把这些页面当作内部算法或存储格式的证明。具体迁移兼容性以样本测试为准。
