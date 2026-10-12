export async function api(path, body) {
  const { token } = await chrome.storage.local.get('token');
  if (!token) throw new Error('请先在扩展设置中粘贴 HunterFile 采集令牌。');
  const response = await fetch(`http://127.0.0.1:41596${path}`, {
    method: body === undefined ? 'GET' : 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
  const result = await response.json();
  if (!response.ok) throw new Error(result.error || `HTTP ${response.status}`);
  return result;
}
