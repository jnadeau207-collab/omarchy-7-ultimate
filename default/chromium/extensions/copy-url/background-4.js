
function copyUrl(url) {
  if (!url) return;

  chrome.runtime.sendNativeMessage('com.omarchy.copy_url', { url }, () => {
    void chrome.runtime.lastError;
  });
}

chrome.commands.onCommand.addListener((command) => {
  if (command !== 'copy-url') return;

  chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => {
    copyUrl(tabs[0] && tabs[0].url);
  });
});

chrome.action.onClicked.addListener((tab) => {
  copyUrl(tab && tab.url);
});
