import test from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { NotchClient } from "../dist/index.js";

const binary = process.env.HOOENAS_NOTCHES_HOST
  ?? fileURLToPath(new URL("../../../.build/release/hooenas-notches-host", import.meta.url));

test("TypeScript client exchanges real state patches with the Swift desktop host", {
  skip: process.platform !== "darwin" || !existsSync(binary),
  timeout: 15_000,
}, async () => {
  const child = spawn(binary, ["--stdio"], { stdio: ["pipe", "pipe", "pipe"] });
  child.stdout.setEncoding("utf8");
  const exit = new Promise(resolve => child.once("exit", code => resolve(code)));
  let diagnostics = "";
  child.stderr.on("data", chunk => { diagnostics += chunk; });
  const transport = {
    write(chunk) { return new Promise((resolve, reject) => child.stdin.write(chunk, error => error ? reject(error) : resolve())); },
    onData(listener) { child.stdout.on("data", listener); return () => child.stdout.off("data", listener); },
    onError(listener) { child.on("error", listener); return () => child.off("error", listener); },
    onClose(listener) {
      const close = (code, signal) => listener({ code, signal });
      child.on("close", close);
      return () => child.off("close", close);
    },
    async close() { if (child.exitCode === null && child.signalCode === null) child.kill(); },
  };
  const notch = new NotchClient(transport);
  try {
    await notch.ready;
    const shown = await notch.show({
      style: "glass", motion: "gentle", expanded: true,
      title: "Native SDK integration", subtitle: "TypeScript → SwiftUI",
      activity: "working", progress: 0.3,
      actions: [{ id: "cancel", label: "Cancel" }],
    });
    assert.equal(shown.visible, true);
    assert.equal(shown.state.title, "Native SDK integration");
    assert.equal(shown.state.progress, 0.3);
    const cleared = await notch.update({ progress: null, activity: "success" });
    assert.equal(cleared.state.progress, null);
    assert.equal(cleared.state.style, "glass");
    assert.equal(cleared.state.activity, "success");
    assert.equal((await notch.hide()).visible, false);
    await notch.quit();
    assert.equal(await exit, 0, diagnostics);
  } finally {
    await notch.dispose();
  }
});
