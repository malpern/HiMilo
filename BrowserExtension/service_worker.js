const POLL_INTERVAL_MS = 1000;
const STATUS_URL = "http://localhost:4140/status";

let wasReading = false;
let pausedTabs = [];
let pollTimer = null;

function log(...args) {
  console.log("[VoxClaw]", ...args);
}

async function pollStatus() {
  try {
    const response = await fetch(STATUS_URL, { signal: AbortSignal.timeout(2000) });
    const data = await response.json();
    const isReading = data.reading === true;

    chrome.action.setIcon({
      path: isReading
        ? { "16": "icons/icon16.png", "32": "icons/icon32.png" }
        : { "16": "icons/icon16.png", "32": "icons/icon32.png" }
    });
    chrome.action.setTitle({
      title: isReading ? "VoxClaw is speaking" : "VoxClaw"
    });

    if (isReading && !wasReading) {
      pausedTabs = await pauseYouTube();
      log(`Speaking started, paused ${pausedTabs.length} tab(s)`);
    } else if (!isReading && wasReading && pausedTabs.length > 0) {
      await resumeYouTube(pausedTabs);
      log(`Speaking finished, resumed ${pausedTabs.length} tab(s)`);
      pausedTabs = [];
    }

    wasReading = isReading;
  } catch {
    if (wasReading) {
      wasReading = false;
      if (pausedTabs.length > 0) {
        await resumeYouTube(pausedTabs);
        pausedTabs = [];
      }
    }
  }
}

async function pauseYouTube() {
  const tabs = await chrome.tabs.query({
    url: [
      "https://*.youtube.com/*",
      "https://youtube.com/*",
      "https://youtu.be/*",
      "https://*.youtube-nocookie.com/*"
    ]
  });

  const paused = [];
  for (const tab of tabs) {
    if (!tab.id || !tab.url) continue;
    try {
      const [{ result } = {}] = await chrome.scripting.executeScript({
        target: { tabId: tab.id },
        func: () => {
          const video = document.querySelector("video");
          if (!video || video.paused || video.ended || video.readyState < 2) {
            return false;
          }
          video.pause();
          return true;
        }
      });
      if (result) {
        paused.push({ tabId: tab.id, url: tab.url });
      }
    } catch {}
  }
  return paused;
}

async function resumeYouTube(tabs) {
  for (const { tabId, url } of tabs) {
    try {
      const tab = await chrome.tabs.get(tabId);
      if (!tab?.url || tab.url !== url) continue;
      await chrome.scripting.executeScript({
        target: { tabId },
        func: () => {
          const video = document.querySelector("video");
          if (video?.paused && !video.ended) {
            void video.play();
          }
        }
      });
    } catch {}
  }
}

function startPolling() {
  if (pollTimer) return;
  pollTimer = setInterval(pollStatus, POLL_INTERVAL_MS);
  pollStatus();
  log("Polling started");
}

function stopPolling() {
  if (pollTimer) {
    clearInterval(pollTimer);
    pollTimer = null;
  }
  log("Polling stopped");
}

chrome.storage.local.get("enabled", ({ enabled }) => {
  if (enabled !== false) startPolling();
});

chrome.storage.onChanged.addListener((changes) => {
  if (changes.enabled) {
    if (changes.enabled.newValue === false) {
      stopPolling();
    } else {
      startPolling();
    }
  }
});

chrome.runtime.onStartup.addListener(() => {
  chrome.storage.local.get("enabled", ({ enabled }) => {
    if (enabled !== false) startPolling();
  });
});

chrome.runtime.onInstalled.addListener(() => {
  chrome.storage.local.get("enabled", ({ enabled }) => {
    if (enabled !== false) startPolling();
  });
});
