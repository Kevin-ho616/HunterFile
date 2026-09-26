import { api } from './client.js';
const $ = id => document.getElementById(id);
let images = [], tab, selected = new Set();
const status = text => { $('status').textContent = text; };
const tags = () => $('tags').value.split(/[,，;；]/).map(s => s.trim()).filter(Boolean);
const folderIDs = () => $('folder').value ? [$('folder').value] : [];
async function collect(items) {
  if (!items.length) return status('请先选择要保存的图片。');
  $('save').disabled = true;
  status(`正在采集 ${items.length} 项，请保持此面板打开…`);
  try {
    const result = await api('/collect', { items, tags: tags(), folderIDs: folderIDs() });
    status(`已保存 ${result.imported} 项${result.errors.length ? `；${result.errors.join('；')}` : '。'}`);
  } catch (error) { status(error.message + ' 请确认应用正在运行且本地 API 已启用。'); }
  finally { $('save').disabled = false; }
}
function render() {
  const minimum = Number($('min-width').value) || 0;
  const visible = images.filter(image => image.width >= minimum);
  const visibleURLs = new Set(visible.map(image => image.url));
  selected = new Set([...selected].filter(url => visibleURLs.has(url)));
  $('images').replaceChildren();
  $('count').textContent = `${visible.length} 张`;
  for (const item of visible) {
    const label = document.createElement('label'); label.className = 'tile';
    const checkbox = document.createElement('input'); checkbox.type = 'checkbox'; checkbox.checked = selected.has(item.url);
    checkbox.addEventListener('change', () => checkbox.checked ? selected.add(item.url) : selected.delete(item.url));
    const image = document.createElement('img'); image.src = item.url; image.alt = item.name; image.loading = 'lazy'; image.referrerPolicy = 'no-referrer';
    const size = document.createElement('small'); size.textContent = `${item.width} × ${item.height}`;
    label.append(checkbox, image, size); $('images').append(label);
  }
}
async function scan() {
  try {
    [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
    const results = await chrome.scripting.executeScript({ target: { tabId: tab.id }, func: () => {
      const map = new Map();
      for (const image of document.images) {
        const url = image.currentSrc || image.src;
        if (!/^https?:\/\//i.test(url) || map.has(url)) continue;
        map.set(url, { url, name: image.alt || '', width: image.naturalWidth, height: image.naturalHeight });
      }
      return [...map.values()].slice(0, 500);
    } });
    images = results[0]?.result || []; render(); status('选择图片后，点击保存。');
  } catch { status('此页面不允许扫描图片。请打开普通网页后重试。'); }
}
$('settings').onclick = () => chrome.runtime.openOptionsPage();
$('scan').onclick = scan;
$('min-width').oninput = render;
$('select-all').onchange = () => { selected = $('select-all').checked ? new Set(images.filter(image => image.width >= (Number($('min-width').value) || 0)).map(image => image.url)) : new Set(); render(); };
$('save').onclick = () => collect(images.filter(image => selected.has(image.url)).map(image => ({ url: image.url, name: image.name, sourceURL: tab.url, download: true })));
$('bookmark').onclick = async () => {
  let dataURL;
  try { dataURL = await chrome.tabs.captureVisibleTab(tab.windowId, { format: 'png' }); } catch { /* A bookmark can still be saved on restricted pages. */ }
  return collect([{ url: tab.url, name: tab.title, download: false, ...(dataURL ? { dataURL } : {}) }]);
};
$('screenshot').onclick = async () => {
  try { const dataURL = await chrome.tabs.captureVisibleTab(tab.windowId, { format: 'png' }); await collect([{ dataURL, name: tab.title + ' · 网页截图', sourceURL: tab.url }]); }
  catch (error) { status(error.message); }
};
try {
  const folders = await api('/folders');
  for (const folder of folders) { const option = document.createElement('option'); option.value = folder.id; option.textContent = folder.name; $('folder').append(option); }
} catch (error) { status(error.message); }
await scan();
