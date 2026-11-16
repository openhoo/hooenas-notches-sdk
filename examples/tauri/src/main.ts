import { isTauri } from "@tauri-apps/api/core";
import { createTauriNotch } from "@hooenas-notches/client/tauri";
import type { NotchClient, NotchMotion, NotchStyle } from "@hooenas-notches/client";
import "./style.css";

function requiredElement<T extends HTMLElement>(selector: string): T {
  const element = document.querySelector<T>(selector);
  if (!element) throw new Error(`Missing example element: ${selector}`);
  return element;
}

const status = requiredElement<HTMLParagraphElement>("#status");
const snapshot = requiredElement<HTMLPreElement>("#snapshot");
const style = requiredElement<HTMLSelectElement>("#style");
const motion = requiredElement<HTMLSelectElement>("#motion");
const expand = requiredElement<HTMLButtonElement>("#expand");
const controls = document.querySelectorAll<HTMLButtonElement | HTMLSelectElement>("button, select");
controls.forEach((control) => {
  control.disabled = true;
});
let notch: NotchClient | undefined;
let disposed = false;
let expanded = false;
let progressTimer: ReturnType<typeof setInterval> | undefined;
const stopProgress = (): void => {
  clearInterval(progressTimer);
  progressTimer = undefined;
};
const report = (error: unknown): void => {
  stopProgress();
  if (!disposed) status.textContent = error instanceof Error ? error.message : String(error);
};
const teardown = (): void => {
  disposed = true;
  stopProgress();
  const current = notch;
  notch = undefined;
  void current?.dispose().catch((error) => console.warn("Notch cleanup failed:", error));
};

async function connect(): Promise<void> {
  if (!isTauri()) {
    status.textContent = "Open this example with npm run tauri:dev to use the native macOS notch.";
    return;
  }
  const connected = await createTauriNotch({ onStderr: (line) => console.warn("notch:", line) });
  // Startup may finish after Vite has replaced this module.
  if (disposed) {
    await connected.dispose();
    return;
  }
  notch = connected;
  connected.onState((value) => {
    expanded = value.state.expanded;
    expand.textContent = expanded ? "Collapse" : "Expand";
    expand.setAttribute("aria-pressed", String(expanded));
    snapshot.textContent = JSON.stringify(value, null, 2);
  });
  connected.onAction((actionId) => {
    status.textContent = `Native action received: ${actionId}`;
    if (actionId === "cancel") {
      stopProgress();
      void notch
        ?.update({ activity: "idle", progress: null, subtitle: "Task cancelled" })
        .catch(report);
    }
  });
  await connected.show({
    title: "Hooenas Notches",
    subtitle: "Connected from Tauri",
    style: "contour",
    actions: [
      { id: "cancel", label: "Cancel" },
      { id: "ping", label: "Ping Tauri" },
    ],
  });
  if (!disposed) {
    controls.forEach((control) => {
      control.disabled = false;
    });
    status.textContent = "Native host connected. Hover over the notch to expand it.";
  }
}

requiredElement<HTMLButtonElement>("#show").addEventListener("click", () => {
  void notch
    ?.show({ style: style.value as NotchStyle, motion: motion.value as NotchMotion })
    .catch(report);
});
requiredElement<HTMLButtonElement>("#hide").addEventListener("click", () => {
  void notch?.hide().catch(report);
});
expand.addEventListener("click", () => {
  void notch?.update({ expanded: !expanded }).catch(report);
});
style.addEventListener("change", () => {
  void notch?.update({ style: style.value as NotchStyle }).catch(report);
});
motion.addEventListener("change", () => {
  void notch?.update({ motion: motion.value as NotchMotion }).catch(report);
});
requiredElement<HTMLButtonElement>("#progress").addEventListener("click", () => {
  stopProgress();
  let step = 0;
  void notch
    ?.show({
      expanded: true,
      activity: "working",
      progress: 0,
      subtitle: "Building something good…",
    })
    .catch(report);
  progressTimer = setInterval(() => {
    const progress = Math.min(1, ++step / 10);
    void notch
      ?.update({
        progress,
        activity: progress === 1 ? "success" : "working",
        subtitle: progress === 1 ? "All done" : `Building · ${Math.round(progress * 100)}%`,
      })
      .catch(report);
    if (progress === 1) stopProgress();
  }, 350);
});

void connect().catch(report);
window.addEventListener("pagehide", teardown, { once: true });

if (import.meta.hot) {
  import.meta.hot.dispose(() => {
    window.removeEventListener("pagehide", teardown);
    teardown();
  });
}
