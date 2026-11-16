import { isTauri } from "@tauri-apps/api/core";
import { createTauriNotch } from "@hooenas-notches/client/tauri";
import type { NotchClient, NotchMotion, NotchStyle } from "@hooenas-notches/client";
import "./style.css";

const status = document.querySelector<HTMLParagraphElement>("#status")!;
const snapshot = document.querySelector<HTMLPreElement>("#snapshot")!;
const style = document.querySelector<HTMLSelectElement>("#style")!;
const motion = document.querySelector<HTMLSelectElement>("#motion")!;
let notch: NotchClient | undefined;
let expanded = false;
let progressTimer: ReturnType<typeof setInterval> | undefined;
const stopProgress = (): void => { clearInterval(progressTimer); progressTimer = undefined; };
const report = (error: unknown): void => { status.textContent = error instanceof Error ? error.message : String(error); };

async function connect(): Promise<void> {
  if (!isTauri()) {
    status.textContent = "Open this example with npm run tauri:dev to use the native macOS notch.";
    document.querySelectorAll<HTMLButtonElement | HTMLSelectElement>("button, select").forEach(control => { control.disabled = true; });
    return;
  }
  notch = await createTauriNotch({ onStderr: line => console.warn("notch:", line) });
  notch.onState(value => {
    expanded = value.state.expanded;
    snapshot.textContent = JSON.stringify(value, null, 2);
  });
  notch.onAction(actionId => {
    status.textContent = `Native action received: ${actionId}`;
    if (actionId === "cancel") {
      stopProgress();
      void notch?.update({ activity: "idle", progress: null, subtitle: "Task cancelled" }).catch(report);
    }
  });
  await notch.show({
    title: "Hooenas Notches", subtitle: "Connected from Tauri", style: "contour",
    actions: [{ id: "cancel", label: "Cancel" }, { id: "open", label: "Open app" }],
  });
  status.textContent = "Native host connected. Hover over the notch to expand it.";
}

document.querySelector("#show")!.addEventListener("click", () => {
  void notch?.show({ style: style.value as NotchStyle, motion: motion.value as NotchMotion }).catch(report);
});
document.querySelector("#hide")!.addEventListener("click", () => { void notch?.hide().catch(report); });
document.querySelector("#expand")!.addEventListener("click", () => { void notch?.update({ expanded: !expanded }).catch(report); });
style.addEventListener("change", () => { void notch?.update({ style: style.value as NotchStyle }).catch(report); });
motion.addEventListener("change", () => { void notch?.update({ motion: motion.value as NotchMotion }).catch(report); });
document.querySelector("#progress")!.addEventListener("click", () => {
  stopProgress();
  let progress = 0;
  void notch?.show({ expanded: true, activity: "working", progress, subtitle: "Building something good…" }).catch(report);
  progressTimer = setInterval(() => {
    progress = Math.min(1, progress + 0.1);
    void notch?.update({ progress, activity: progress === 1 ? "success" : "working", subtitle: progress === 1 ? "All done" : `Building · ${Math.round(progress * 100)}%` }).catch(report);
    if (progress === 1) stopProgress();
  }, 350);
});

void connect().catch(report);

if (import.meta.hot) {
  import.meta.hot.dispose(() => {
    stopProgress();
    void notch?.dispose();
  });
}
