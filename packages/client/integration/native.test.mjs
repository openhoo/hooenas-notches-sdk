import test from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import { createInterface } from "node:readline";
import { fileURLToPath } from "node:url";
import { NotchClient } from "../dist/index.js";

const binary =
  process.env.HOOENAS_NOTCHES_HOST ??
  fileURLToPath(new URL("../../../.build/release/hooenas-notches-host", import.meta.url));
const options = { skip: process.platform !== "darwin" || !existsSync(binary), timeout: 15_000 };

function launch(t) {
  const child = spawn(binary, ["--stdio"], { stdio: ["pipe", "pipe", "pipe"] });
  child.stdout.setEncoding("utf8");
  let diagnostics = "";
  child.stderr.on("data", (chunk) => {
    diagnostics = (diagnostics + chunk).slice(-8_192);
  });
  // A pipe may report its error after the client has removed its subscribers.
  const ignoreStreamError = () => {};
  child.stdin.on("error", ignoreStreamError);
  child.on("error", ignoreStreamError);
  const exited = new Promise((resolve) => child.once("exit", (code) => resolve(code)));
  const closed = new Promise((resolve) => child.once("close", resolve));
  const transport = {
    write(chunk) {
      return new Promise((resolve, reject) =>
        child.stdin.write(chunk, (error) => (error ? reject(error) : resolve())),
      );
    },
    onData(listener) {
      child.stdout.on("data", listener);
      return () => {
        child.stdout.off("data", listener);
      };
    },
    onError(listener) {
      child.on("error", listener);
      child.stdin.on("error", listener);
      return () => {
        child.off("error", listener);
        child.stdin.off("error", listener);
      };
    },
    onClose(listener) {
      const close = (code, signal) => listener({ code, signal });
      child.on("close", close);
      return () => {
        child.off("close", close);
      };
    },
    async close() {
      if (child.exitCode === null && child.signalCode === null) child.kill();
      await closed;
      child.stdin.off("error", ignoreStreamError);
      child.off("error", ignoreStreamError);
    },
  };
  t.after(() => transport.close());
  return {
    child,
    transport,
    exited,
    get diagnostics() {
      return diagnostics;
    },
  };
}

function client(t) {
  const host = launch(t);
  const notch = new NotchClient(host.transport);
  t.after(() => notch.dispose());
  return Object.assign(host, { notch });
}

test(
  "TypeScript client exchanges real state patches with the Swift desktop host",
  options,
  async (t) => {
    const host = client(t);
    const { notch, exited } = host;
    await notch.ready;
    const shown = await notch.show({
      style: "glass",
      motion: "gentle",
      expanded: true,
      title: "Native SDK integration",
      subtitle: "TypeScript → SwiftUI",
      activity: "working",
      progress: 0.3,
      actions: [{ id: "cancel", label: "Cancel" }],
    });
    assert.equal(shown.visible, true);
    assert.equal(shown.state.title, "Native SDK integration");
    assert.equal(shown.state.progress, 0.3);
    const cleared = await notch.update({ progress: null, activity: "success" });
    assert.equal(cleared.state.progress, null);
    assert.equal(cleared.state.style, "glass");
    assert.equal(cleared.state.activity, "success");
    const results = await Promise.all(
      Array.from({ length: 32 }, (_, index) =>
        notch.update({ subtitle: `Concurrent patch ${index}` }),
      ),
    );
    results.forEach((result, index) =>
      assert.equal(result.state.subtitle, `Concurrent patch ${index}`),
    );
    assert.equal((await notch.hide()).visible, false);
    await notch.quit();
    assert.equal(await exited, 0, host.diagnostics);
  },
);

test("the real host rejects accumulated oversized Unicode state atomically", options, async (t) => {
  const { notch, exited } = client(t);
  await notch.ready;
  const clustered = "A" + "\u0301".repeat(17_000);
  const initial = await notch.update({ title: clustered });
  assert.equal(initial.visible, false);
  await assert.rejects(notch.update({ subtitle: clustered }), { code: "invalid_state" });
  const preserved = await notch.update({});
  assert.equal(preserved.state.title, clustered);
  assert.equal(preserved.state.subtitle, initial.state.subtitle);
  await notch.quit();
  assert.equal(await exited, 0);
});

test(
  "the real host recovers framing, preserves fragmented UTF-8, and flushes EOF",
  options,
  async (t) => {
    const host = launch(t);
    const lines = createInterface({ input: host.child.stdout, crlfDelay: Infinity });
    t.after(() => lines.close());
    const iterator = lines[Symbol.asyncIterator]();
    const next = async () => {
      const { value, done } = await iterator.next();
      assert.equal(done, false, host.diagnostics);
      assert.ok(Buffer.byteLength(value) <= 65_536);
      return JSON.parse(value);
    };
    assert.equal((await next()).event, "ready");
    host.child.stdin.write(Buffer.alloc(65_537, "x"));
    host.child.stdin.write("\n");
    assert.equal((await next()).code, "line_too_long");
    const invalid = "a" + "\u0301".repeat(1_000);
    host.child.stdin.write(JSON.stringify({ id: invalid, command: "unknown" }) + "\n");
    const unsafe = await next();
    assert.equal(unsafe.code, "invalid_request");
    assert.equal(unsafe.id, undefined);
    const title = "Gute Nacht 🌙";
    const message = Buffer.from(
      JSON.stringify({ id: "fragmented", command: "update", state: { title } }),
    );
    const split = message.indexOf(Buffer.from("🌙")) + 2;
    host.child.stdin.write(message.subarray(0, split));
    host.child.stdin.write(message.subarray(split));
    host.child.stdin.write("\r\n");
    const updated = await next();
    assert.equal(updated.id, "fragmented");
    assert.equal(updated.state.title, title);
    host.child.stdin.end(
      JSON.stringify({ id: "eof", command: "update", state: { subtitle: "Last request" } }),
    );
    const final = await next();
    assert.equal(final.id, "eof");
    assert.equal(final.state.subtitle, "Last request");
    assert.equal(await host.exited, 0, host.diagnostics);
  },
);

test("the real host exits cleanly when its parent closes stdout", options, async (t) => {
  const host = launch(t);
  const lines = createInterface({ input: host.child.stdout, crlfDelay: Infinity });
  t.after(() => lines.close());
  const { value } = await lines[Symbol.asyncIterator]().next();
  assert.equal(JSON.parse(value).event, "ready");
  lines.close();
  host.child.stdout.destroy();
  host.child.stdin.write(JSON.stringify({ id: "broken-output", command: "update" }) + "\n");
  assert.equal(await host.exited, 0, host.diagnostics);
});
