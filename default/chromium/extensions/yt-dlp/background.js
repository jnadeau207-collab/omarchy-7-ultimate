function sendUrl(url) {
  if (!url || !/^https?:/i.test(url)) return;

  chrome.runtime.sendNativeMessage('com.omarchy.ytdlp', { url }, () => {
    void chrome.runtime.lastError;
  });
}

function triggerDownload(tab) {
  if (!tab) return;

  if (tab.url) {
    sendUrl(tab.url);
    return;
  }

  if (tab.id === undefined) return;
  chrome.scripting
    .executeScript({ target: { tabId: tab.id }, func: () => location.href })
    .then((results) => sendUrl(results && results[0] && results[0].result))
    .catch(() => {});
}

chrome.commands.onCommand.addListener((command) => {
  if (command === 'download-video') {
    chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => {
      triggerDownload(tabs[0]);
    });
  }
});

chrome.action.onClicked.addListener((tab) => {
  triggerDownload(tab);
});
