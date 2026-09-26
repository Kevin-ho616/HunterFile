#!/usr/bin/env python3
"""OpenEagle CLI and newline-delimited stdio MCP server; Python standard library only."""
import argparse
import json
import os
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request


def request(path, body=None):
    token = os.environ.get("OPENEAGLE_TOKEN")
    if not token:
        result = subprocess.run(
            ["/usr/bin/security", "find-generic-password", "-s", "com.kevin.OpenEagle", "-a", "api-token", "-w"],
            capture_output=True, text=True, check=False,
        )
        if result.returncode:
            raise RuntimeError("请在 OpenEagle 设置中启用本地 API，或设置 OPENEAGLE_TOKEN。")
        token = result.stdout.strip()
    data = json.dumps(body, ensure_ascii=False).encode() if body is not None else None
    req = urllib.request.Request("http://127.0.0.1:41596" + path, data=data,
                                 headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"})
    try:
        # The app is on loopback; system web proxies must not receive its token.
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        with opener.open(req, timeout=600) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        detail = json.loads(error.read()).get("error", str(error.code))
        raise RuntimeError(detail) from None
    except urllib.error.URLError:
        raise RuntimeError("无法连接 OpenEagle。请启动应用并启用本地 API。") from None


TOOLS = [
    {"name": "search_assets", "description": "搜索本机 OpenEagle 素材库，最多返回 500 个结果与总数。", "inputSchema": {"type": "object", "properties": {"query": {"type": "string"}}}},
    {"name": "list_folders", "description": "列出当前资源库文件夹。", "inputSchema": {"type": "object", "properties": {}}},
    {"name": "collect_url", "description": "将 HTTP(S) 图片/文件直链或书签保存到 OpenEagle。", "inputSchema": {"type": "object", "properties": {"url": {"type": "string"}, "name": {"type": "string"}, "download": {"type": "boolean"}, "tags": {"type": "array", "items": {"type": "string"}}, "folderIDs": {"type": "array", "items": {"type": "string"}}}, "required": ["url"]}},
    {"name": "update_assets", "description": "更新所选 ID 的名称、备注、评分，或追加标签。", "inputSchema": {"type": "object", "properties": {"ids": {"type": "array", "items": {"type": "string"}}, "name": {"type": "string"}, "note": {"type": "string"}, "rating": {"type": "integer", "minimum": 0, "maximum": 5}, "tags": {"type": "array", "items": {"type": "string"}}}, "required": ["ids"]}},
    {"name": "create_folder", "description": "新建本地逻辑文件夹。", "inputSchema": {"type": "object", "properties": {"name": {"type": "string"}, "parentID": {"type": "string"}}, "required": ["name"]}},
    {"name": "get_status", "description": "查看当前任务进度与逐项错误。", "inputSchema": {"type": "object", "properties": {}}},
]


def call(name, arguments):
    if name == "search_assets":
        return request("/items?" + urllib.parse.urlencode({"q": arguments.get("query", "")}))
    if name == "list_folders":
        return request("/folders")
    if name == "collect_url":
        return request("/collect", {"items": [{"url": arguments["url"], "name": arguments.get("name", ""), "download": arguments.get("download", True)}], "tags": arguments.get("tags", []), "folderIDs": arguments.get("folderIDs", [])})
    if name == "update_assets":
        return request("/items/update", arguments)
    if name == "create_folder":
        return request("/folders", arguments)
    if name == "get_status":
        return request("/status")
    raise ValueError("未知工具：" + name)


def mcp():
    for line in sys.stdin:
        message = None
        try:
            message = json.loads(line)
            if "id" not in message:
                continue
            method = message.get("method")
            if method == "initialize":
                result = {"protocolVersion": message.get("params", {}).get("protocolVersion", "2024-11-05"), "capabilities": {"tools": {}}, "serverInfo": {"name": "openeagle", "version": "1.0.0"}}
            elif method == "ping":
                result = {}
            elif method == "tools/list":
                result = {"tools": TOOLS}
            elif method == "tools/call":
                params = message.get("params", {})
                try:
                    value = call(params["name"], params.get("arguments", {}))
                    result = {"content": [{"type": "text", "text": json.dumps(value, ensure_ascii=False)}]}
                except Exception as error:
                    result = {"isError": True, "content": [{"type": "text", "text": str(error)}]}
            else:
                print(json.dumps({"jsonrpc": "2.0", "id": message["id"], "error": {"code": -32601, "message": "Method not found"}}), flush=True)
                continue
            print(json.dumps({"jsonrpc": "2.0", "id": message["id"], "result": result}, ensure_ascii=False), flush=True)
        except Exception:
            print(json.dumps({"jsonrpc": "2.0", "id": message.get("id") if isinstance(message, dict) else None, "error": {"code": -32700, "message": "Invalid JSON-RPC request"}}), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mcp", action="store_true", help="以 MCP stdio 服务运行")
    parser.add_argument("tool", nargs="?", choices=[tool["name"] for tool in TOOLS])
    parser.add_argument("arguments", nargs="?", default="{}", help="JSON 参数")
    args = parser.parse_args()
    if args.mcp:
        mcp()
    elif args.tool:
        try:
            print(json.dumps(call(args.tool, json.loads(args.arguments)), ensure_ascii=False, indent=2))
        except Exception as error:
            print(str(error), file=sys.stderr)
            return 1
    else:
        parser.print_help()
    return 0


if __name__ == "__main__":
    sys.exit(main())
