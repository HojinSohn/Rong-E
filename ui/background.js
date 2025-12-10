// background.js
chrome.action.onClicked.addListener((tab) => {
  // Send a message to the active tab
  chrome.tabs.sendMessage(tab.id, { action: "toggle_overlay" });
});