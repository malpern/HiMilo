const toggle = document.getElementById("enabled");
const status = document.getElementById("status");

chrome.storage.local.get("enabled", ({ enabled }) => {
  toggle.checked = enabled !== false;
});

toggle.addEventListener("change", () => {
  chrome.storage.local.set({ enabled: toggle.checked });
});

fetch("http://localhost:4140/status", { signal: AbortSignal.timeout(2000) })
  .then(r => r.json())
  .then(data => {
    status.textContent = data.reading ? "Speaking now" : "Connected — idle";
    status.style.color = data.reading ? "#34c759" : "#86868b";
  })
  .catch(() => {
    status.textContent = "VoxClaw not running";
    status.style.color = "#ff3b30";
  });
