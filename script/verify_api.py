#!/usr/bin/env python3
"""Exercise the real API and MCP bridge, refusing to write outside OpenEagleQA."""
import base64
import json
import os
from pathlib import Path
import struct
import subprocess
import sys
import urllib.error
import urllib.request
import uuid
import zlib

ROOT = Path(__file__).resolve().parents[1]
listener = subprocess.run(['/usr/sbin/lsof', '-a', '-iTCP:41596', '-sTCP:LISTEN', '-F', 'c'], capture_output=True, text=True, check=False)
assert 'cOpenEagleQA\n' in listener.stdout, 'Start OpenEagleQA and enable its local API first.'
token = subprocess.check_output(['/usr/bin/security', 'find-generic-password', '-s', 'com.kevin.OpenEagle.QA', '-a', 'api-token', '-w'], text=True).strip()
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))


def request(path, body=None, credential=token):
    req = urllib.request.Request('http://127.0.0.1:41596' + path,
        data=json.dumps(body).encode() if body is not None else None,
        headers={'Authorization': 'Bearer ' + credential, 'Content-Type': 'application/json'})
    try:
        with opener.open(req, timeout=30) as response:
            return response.status, json.load(response)
    except urllib.error.HTTPError as error:
        return error.code, json.load(error)


def png_chunk(kind, data):
    return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))


assert request('/items', credential='invalid-test-token')[0] == 401
name = 'API QA ' + uuid.uuid4().hex[:8]
status, folder = request('/folders', {'name': name})
assert status == 200
pixels = b''.join(b'\0' + b'\x30\x70\xE0' * 16 for _ in range(12))
png = b'\x89PNG\r\n\x1a\n' + png_chunk(b'IHDR', struct.pack('>IIBBBBB', 16, 12, 8, 2, 0, 0, 0)) + png_chunk(b'IDAT', zlib.compress(pixels)) + png_chunk(b'IEND', b'')
data_url = 'data:image/png;base64,' + base64.b64encode(png).decode()
status, imported = request('/collect', {'items': [
    {'url': 'https://example.com/' + uuid.uuid4().hex, 'name': name, 'download': False, 'dataURL': data_url},
    {'name': name + ' screenshot', 'dataURL': data_url}
], 'folderIDs': [folder['id']], 'tags': [name]})
assert status == 200 and imported['imported'] == 2 and not imported['errors'], imported
ids = imported['ids']
assert request('/items/update', {'ids': [ids[0]], 'rating': 99})[0] == 400
assert request('/items/update', {'ids': ids, 'rating': 4, 'note': name + ' persisted', 'tags': ['接口验证']})[1]['updated'] == 2
status, rejected = request('/collect', {'items': [{'url': 'file:///etc/hosts'}]})
assert rejected['imported'] == 0 and rejected['errors']
env = {**os.environ, 'OPENEAGLE_TOKEN': token, 'HTTP_PROXY': 'http://127.0.0.1:9', 'http_proxy': 'http://127.0.0.1:9'}
cli = json.loads(subprocess.check_output([sys.executable, str(ROOT / 'script/openeagle.py'), 'search_assets', json.dumps({'query': name})], env=env, text=True))
assert cli['total'] == 2
bookmark = next(item for item in cli['items'] if item['id'] == ids[0])
assert bookmark['rating'] == 4 and bookmark['width'] == 16 and bookmark['height'] == 12
assert (ROOT / 'test-output/QA.openeagle/assets' / ids[0] / 'thumbnail.png').is_file()
messages = [
    {'jsonrpc': '2.0', 'id': 1, 'method': 'initialize', 'params': {'protocolVersion': '2024-11-05'}},
    {'jsonrpc': '2.0', 'id': 2, 'method': 'tools/list'},
    {'jsonrpc': '2.0', 'id': 3, 'method': 'tools/call', 'params': {'name': 'search_assets', 'arguments': {'query': name}}},
    {'jsonrpc': '2.0', 'id': 4, 'method': 'ping'}
]
run = subprocess.run([sys.executable, str(ROOT / 'script/openeagle.py'), '--mcp'], input='\n'.join(map(json.dumps, messages)) + '\n', capture_output=True, text=True, env=env, check=True)
responses = list(map(json.loads, run.stdout.splitlines()))
assert len(responses[1]['result']['tools']) == 6
assert json.loads(responses[2]['result']['content'][0]['text'])['total'] == 2
report = {'authentication': 'passed', 'folder_creation': 'passed', 'visual_bookmark': 'passed', 'screenshot': 'passed', 'transaction_validation': 'passed', 'local_path_rejection': 'passed', 'CLI_proxy_bypass': 'passed', 'MCP_search': 'passed', 'asset_ids': ids}
(ROOT / 'test-output/api-verification.json').write_text(json.dumps(report, ensure_ascii=False, indent=2))
print(json.dumps({k: v for k, v in report.items() if k != 'asset_ids'}, ensure_ascii=False, indent=2))
