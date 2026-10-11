# 本地多模态 AI

第一版使用 EmbeddingGemma 2 文字与视觉 440M，图片、视频和文档均在本机处理。向量提供检索与分类排序；生成名称、摘要与问答需要另行接入生成模型。

## 使用

1. 设置 → AI → 下载文字与视觉模型（387,710,976 字节），下载完成后选择 `.litertlm` 文件。支持的固定文件会校验 SHA-256。
2. 开启本地 AI，等待后台索引。设置中可暂停、继续、查看失败项或重建索引。处理失败的素材保留原件，仍可通过名称等关键词找到；点击更新会重试失败项。
3. 在搜索框描述画面、主题或文档内容；也可点击图片按钮选择参考图。相关 PDF 页码和视频时刻显示在结果上，预览会自动定位。
4. 选中素材 → AI 整理 → 本地分类 → 生成建议。确认标签和文件夹后应用；可撤销、重做。名称、备注与原件保留。

模型可存放在用户选定的目录；移动模型后需要重新选择。索引随 `.openeagle` 的 SQLite 数据库与完整备份保存，重启后复用；素材包导入使用新标识，会重新索引。升级模型或预处理版本会重新建立对应索引。

## 内容与搜索规则

- 图片：纠正方向并缩至 640 像素，建立视觉与本地 OCR 向量；名字、标签、备注等另建文字向量。
- PDF：按页建立文字及页面视觉向量；无可选文字的页尝试 OCR。正文按 1,000 字符分段，重叠 100 字符，保存页码。
- 视频：覆盖整个时长，每 5 秒抽一帧，记录实际帧时间。短于采样间隔的镜头可能遗漏；不识别对白或声音。
- 文档：支持 UTF-8 文本，以及系统可读取的 RTF、DOC、DOCX。其他格式会显示失败状态；音频、字体和书签目前只索引已有文字元数据。
- 关键词直接命中优先，其他结果按同一素材的最佳片段相似度排列；查询保留类型、标签、尺寸、日期、评分、文件夹及子文件夹筛选。锁定素材在索引、检索与分类候选中排除；已索引的回收站素材只在回收站范围出现。
- 返回最相关的前 500 项；排序分数不是概率，也不代表每个结果都相关。当前智能文件夹仍使用原有关键词规则。

向量以 768 维 Float32 BLOB 保存，不把不同模型或维度混用。原始文件不变；内容元数据变化时，使对应索引失效并重建，收藏与浏览记录变化不触发重建。取消时保留已完成素材的索引，正在处理的素材下一次重新处理。精确扫描随片段数量线性增加，大库的耗时还需要实测。

## 可复现验证

```sh
swift script/make_ai_test_media.swift test-output/ai-fixtures
swift run OpenEagleAIBenchmark /absolute/path/model.litertlm test-output/ai-fixtures cpu test-output/ai-benchmark-cpu.json
swift run OpenEagleAIBenchmark /absolute/path/model.litertlm test-output/ai-fixtures gpu test-output/ai-benchmark-gpu.json
swift test --filter Semantic
OPENEAGLE_TEST_MODEL=/absolute/path/model.litertlm swift test --filter LocalAIIntegrationTests
```

测试答案在生成脚本中预先指定，共 12 张中文主题海报、12 份两页 PDF、1 段含 12 个主题画面的 72 秒视频及 50 条中文查询。视频只有一个文件，因此必须检查匹配时间段；文档同时检查匹配页码。报告保存逐条结果、排名、定位、延迟、模型修订和校验值。模型与生成素材不提交到 Git。

真实模型集成测试另外验证了 6 个文件的 AppStore 后台索引：暂停后保留 1 个已完成文件，继续后完成全部；PDF 检索定位第 2 页，视频检索定位猫出现的 0:50；扫描 PDF 成功 OCR；分类推荐海洋标签与文件夹，并通过现有编辑流程应用。无模型环境变量时，此测试跳过，普通测试不要求下载权重。

独立 OpenEagleQA 应用的实际界面检查使用 4 个受控文件，验证了模型选择、中文检索、PDF 第 2 页预览、视频 0:50 定位、以图排序、分类预览与应用、撤销及设置页的完成状态；没有修改正式应用或个人资源库。重复打包和嵌入运行库的签名校验也已通过。

本机结果（2026-10-12，M5 Pro / 24 GiB，macOS 27.0.1，已有系统和 SDK 缓存）：

| 指标 | CPU，4 线程 | Metal GPU，视觉编码在 CPU |
| --- | --- | --- |
| 初始化含模型校验 | 0.33 秒 | 1.53 秒 |
| 25 文件 / 87 片段索引 | 19.07 秒 | 30.40 秒 |
| 查询中位数 | 33.70 毫秒 | 14.30 毫秒 |
| 查询 P95 | 36.58 毫秒 | 17.18 毫秒 |
| 进程峰值常驻内存 | 1.40 GB | 0.95 GB |
| 首位命中 / 前十命中 | 50/50 / 50/50 | 50/50 / 50/50 |
| 页码与视频时间等定位命中 | 50/50 | 50/50 |

这是受控的小样本功能验证，海报含清晰文字，搜索包含 OCR；不能推算真实照片、长视频、扫描件或大图库的准确率。首版默认 CPU：本轮索引更快，文字查询延迟已足够低；保留 GPU 基准以便后续校准。尚未测试 Intel Mac 或最低支持的 macOS 14。

## 固定模型与运行库

- 模型：[文字与视觉 440M LiteRT-LM](https://huggingface.co/litert-community/embeddinggemma-2-text-vision-440m-litert-lm)，修订 `e301f74d5551b0c2641bd5cb4652a76239d5c5f8`。
- 模型 SHA-256：`92dcbea108899e5d6e30d919b0744f90d9967e80c67a4ab5503ac16d54f62eb0`。
- 运行库：[Google LiteRT-LM v0.18.0](https://github.com/google-ai-edge/LiteRT-LM/tree/v0.18.0)。SwiftPM 校验 macOS 发布包，通过原生 C API 调用；无 Python 运行时或外部模型服务器。构建应用会嵌入并签名动态库。
- 上游能力说明：[Google 发布说明](https://blog.google/innovation-and-ai/technology/developers-tools/embeddinggemma-2/)、[官方模型卡](https://huggingface.co/google/embeddinggemma-2)。

后续评估：个人混合图库、短镜头抽取、语义智能文件夹与本地生成模型。它们不包含在本轮已验证功能中。
