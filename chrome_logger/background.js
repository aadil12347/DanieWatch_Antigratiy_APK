let logs = [];

// Listen silently to all web requests in the background
chrome.webRequest.onBeforeRequest.addListener(
  (details) => {
    // We filter for XHR/Fetch (APIs) and Media files to keep the log clean
    if (
      details.type === 'xmlhttprequest' || 
      details.type === 'media' || 
      details.url.includes('.m3u8') || 
      details.url.includes('.mp4') || 
      details.url.includes('api')
    ) {
      logs.push({
        url: details.url,
        method: details.method,
        type: details.type,
        time: new Date().toISOString()
      });
      console.log("Captured:", details.url);
    }
  },
  { urls: ["<all_urls>"] }
);

// When you click the extension icon, it saves the logs to a file
chrome.action.onClicked.addListener((tab) => {
  const jsonString = JSON.stringify(logs, null, 2);
  
  // Convert to Data URL to trigger download
  const base64 = btoa(unescape(encodeURIComponent(jsonString)));
  const url = 'data:application/json;base64,' + base64;
  
  chrome.downloads.download({
      url: url,
      filename: "media_logs.json",
      saveAs: true
  });
  
  // Clear logs after saving
  logs = [];
});
