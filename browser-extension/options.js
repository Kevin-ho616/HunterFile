import { api } from './client.js';
const token = document.getElementById('token'), status = document.getElementById('status');
const saved = await chrome.storage.local.get(['token', 'lastError']);
token.value = saved.token || '';
status.textContent = saved.lastError || '';
document.getElementById('save').onclick = async () => {
  await chrome.storage.local.set({ token: token.value.trim() });
  try { await api('/folders'); status.textContent = '连接成功，现在可以采集素材。'; }
  catch (error) { status.textContent = error.message; }
};
