import { isTauri } from "@tauri-apps/api/core";
import { createTauriNotch } from "@hooenas-notches/client/tauri";
import type {
  NotchClient,
  NotchMotion,
  NotchSize,
  NotchSnapshot,
  NotchStyle,
} from "@hooenas-notches/client";
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
const size = requiredElement<HTMLSelectElement>("#size");
const dimensions: Record<string, NotchSize> = {
  compact: { width: 360, height: 170 },
  wide: { width: 760, height: 300 },
};
const expand = requiredElement<HTMLButtonElement>("#expand");
const hide = requiredElement<HTMLButtonElement>("#hide");
const reconnect = requiredElement<HTMLButtonElement>("#reconnect");
const customSize = requiredElement<HTMLOptionElement>("#custom-size");
const controls = document.querySelectorAll<HTMLButtonElement | HTMLSelectElement>(
  ".controls button, .controls select",
);
controls.forEach((control) => {
  control.disabled = true;
});
let notch: NotchClient | undefined;
let disposed = false;
let lastSnapshot: NotchSnapshot | undefined;
let progressTimer: ReturnType<typeof setInterval> | undefined;
const stopProgress = (): void => {
  clearInterval(progressTimer);
  progressTimer = undefined;
};
const render = (value: NotchSnapshot): void => {
  lastSnapshot = value;
  style.value = value.state.style;
  motion.value = value.state.motion;
  const requested = value.state.expandedSize;
  const preset = Object.entries(dimensions).find(
    ([, dimensions]) =>
      requested?.width === dimensions.width && requested.height === dimensions.height,
  );
  size.value = requested ? (preset?.[0] ?? "custom") : "default";
  if (requested && !preset)
    customSize.textContent = `Custom (${requested.width} × ${requested.height})`;
  controls.forEach((control) => {
    control.disabled = false;
  });
  size.disabled = !notch?.capabilities.includes("expanded-size");
  hide.disabled = expand.disabled = !value.visible;
  expand.textContent = value.state.expanded ? "Collapse" : "Expand";
  expand.setAttribute("aria-pressed", String(value.state.expanded));
  snapshot.textContent = JSON.stringify(value, null, 2);
};
const message = (error: unknown): string =>
  error instanceof Error ? error.message : String(error);
const report = (error: unknown): void => {
  if (!notch || disposed) return;
  if (lastSnapshot) render(lastSnapshot);
  status.textContent = message(error);
};
const disconnected = (error: unknown): void => {
  if (disposed) return;
  stopProgress();
  notch = undefined;
  lastSnapshot = undefined;
  controls.forEach((control) => {
    control.disabled = true;
  });
  snapshot.textContent = "";
  reconnect.hidden = false;
  status.textContent = `Native host disconnected: ${message(error)}`;
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
  reconnect.hidden = true;
  status.textContent = "Connecting to the native host…";
  let connected: NotchClient;
  try {
    connected = await createTauriNotch({ onStderr: (line) => console.warn("notch:", line) });
  } catch (error) {
    disconnected(error);
    return;
  }
  // Startup may finish after Vite has replaced this module.
  if (disposed) {
    await connected.dispose().catch((error) => console.warn("Notch cleanup failed:", error));
    return;
  }
  notch = connected;
  void connected.closed.then((reason) => {
    if (notch === connected) disconnected(reason);
  });
  connected.onState(render);
  connected.onAction((actionId) => {
    status.textContent = `Native action received: ${actionId}`;
    if (actionId === "cancel") {
      stopProgress();
      void notch
        ?.update({ activity: "idle", progress: null, subtitle: "Task cancelled" })
        .catch(report);
    }
  });
  try {
    await connected.show({
      title: "Hooenas Notches",
      subtitle: "Connected from Tauri",
      style: "contour",
      actions: [
        { id: "cancel", label: "Cancel" },
        { id: "ping", label: "Ping Tauri" },
      ],
    });
    if (notch === connected)
      status.textContent = "Native host connected. Hover over the notch to expand it.";
  } catch (error) {
    if (notch === connected) disconnected(error);
    void connected.dispose().catch((error) => console.warn("Notch cleanup failed:", error));
  }
}

requiredElement<HTMLButtonElement>("#show").addEventListener("click", () => {
  void notch
    ?.show({ style: style.value as NotchStyle, motion: motion.value as NotchMotion })
    .catch(report);
});
hide.addEventListener("click", () => {
  if (progressTimer !== undefined) {
    stopProgress();
    void notch
      ?.update({ activity: "idle", progress: null, subtitle: "Progress stopped" })
      .catch(report);
  }
  void notch?.hide().catch(report);
});
expand.addEventListener("click", () => {
  void notch?.update({ expanded: !lastSnapshot?.state.expanded }).catch(report);
});
style.addEventListener("change", () => {
  void notch?.update({ style: style.value as NotchStyle }).catch(report);
});
motion.addEventListener("change", () => {
  void notch?.update({ motion: motion.value as NotchMotion }).catch(report);
});
size.addEventListener("change", () => {
  void notch?.update({ expandedSize: dimensions[size.value] ?? null }).catch(report);
});
requiredElement<HTMLButtonElement>("#progress").addEventListener("click", () => {
  stopProgress();
  const failed = (error: unknown): void => {
    stopProgress();
    report(error);
  };
  let step = 0;
  void notch
    ?.show({
      expanded: true,
      activity: "working",
      progress: 0,
      subtitle: "Building something good…",
    })
    .catch(failed);
  progressTimer = setInterval(() => {
    const progress = Math.min(1, ++step / 10);
    void notch
      ?.update({
        progress,
        activity: progress === 1 ? "success" : "working",
        subtitle: progress === 1 ? "All done" : `Building · ${Math.round(progress * 100)}%`,
      })
      .catch(failed);
    if (progress === 1) stopProgress();
  }, 350);
});

reconnect.addEventListener("click", () => void connect());
void connect();
window.addEventListener("pagehide", teardown, { once: true });

if (import.meta.hot) {
  import.meta.hot.dispose(() => {
    window.removeEventListener("pagehide", teardown);
    teardown();
  });
}
