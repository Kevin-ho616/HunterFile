# 本地 API、CLI 与 MCP

在应用设置中启用 API。接口固定为 `http://127.0.0.1:41596`，请求头为 `Authorization: Bearer <采集令牌>`。所有写入作用于当前打开的资源库。应用不能同时执行两个采集任务；忙碌时返回 409。

| 方法 | 路径 | 作用 |
| --- | --- | --- |
| GET | /health | 无认证的应用/版本探测 |
| GET | /items?q=关键词 | 最多 500 个素材与总数 |
| GET | /folders | 文件夹列表 |
| GET | /status | 忙碌状态、进度、最近错误 |
| POST | /collect | 批量采集 HTTP(S) 文件直链、书签或 PNG data URL |
| POST | /folders | 新建文件夹：name、可选 parentID |
| POST | /items/update | ids 与可选 name、note、rating、tags；tags 追加合并 |

`/collect` 示例：

```json
{
  "items": [{"url": "https://en.eagle.cool/", "name": "Eagle", "download": false}],
  "tags": ["工具"],
  "folderIDs": []
}
```

单次最多 500 项、请求上限 16 MB、截图上限 12 MB；网页下载完成后校验不超过 2 GB。接口不会接受远端传来的任意本地文件路径。不要把令牌发给不受信任的网页或程序。

## Python CLI

仅使用 Python 3 标准库。默认从 macOS 钥匙串读取 OpenEagle 的令牌，也可通过环境变量 `OPENEAGLE_TOKEN` 注入。不会打印令牌。

```sh
python3 script/openeagle.py search_assets '{"query":"海报"}'
python3 script/openeagle.py list_folders
python3 script/openeagle.py collect_url '{"url":"https://en.eagle.cool/","download":false,"tags":["工具"]}'
```

## MCP stdio

```sh
python3 /absolute/path/OpenEagle/script/openeagle.py --mcp
```

提供 `search_assets`、`list_folders`、`collect_url`、`update_assets`、`create_folder`、`get_status` 六个工具。支持 JSON-RPC 初始化、ping、tools/list 和 tools/call，采用每行一个 JSON 的 stdio 传输。可配置到支持 stdio MCP 的客户端；项目不会自动修改用户的全局 MCP 配置。

## 插件

插件目录内包含 `plugin.json` 与 HTML 文件：

```json
{"name":"我的插件","version":"1.0.0","entry":"index.html"}
```

插件运行于隔离的 WKWebView，原生桥仅接受插件主页面的请求，并提供 `getSelection()`、`getLibrary()`、`saveText(name,text)`。文件写入通过用户选择的保存面板进行。内置示例是素材统计与 CSV 清单导出。

这不是 Eagle 官方 API 的二进制或协议替代品；第三方客户端需要按上述接口适配。
