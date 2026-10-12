chrome.runtime.onInstalled.addListener(() => {
  chrome.contextMenus.create({ id: 'image', title: '保存图片到 HunterFiles', contexts: ['image'] });
  chrome.contextMenus.create({ id: 'bookmark', title: '保存书签到 HunterFiles', contexts: ['page', 'link'] });
});
chrome.contextMenus.onClicked.addListener(async (info, tab) => {
  try {
    const { token } = await chrome.storage.local.get('token');
    if (!token) throw new Error('请在扩展设置中填写采集令牌。');
    const image = info.menuItemId === 'image';
    const response = await fetch('http://127.0.0.1:41596/collect', {
      method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ items: [{ url: image ? info.srcUrl : (info.linkUrl || tab.url), name: image ? '' : tab.title, sourceURL: tab.url, download: image }] }),
    });
    const result = await response.json();
    if (!response.ok || result.errors?.length) throw new Error(result.error || result.errors.join('；'));
    await chrome.action.setBadgeText({ text: '✓' });
    await chrome.storage.local.set({ lastError: '' });
  } catch (error) {
    await chrome.action.setBadgeText({ text: '!' });
    await chrome.storage.local.set({ lastError: error.message });
  }
});
