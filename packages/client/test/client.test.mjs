import test from "node:test";
import assert from "node:assert/strict";
import { NotchClient } from "../dist/index.js";

const state = {
  style: "contour",
  motion: "spring",
  expanded: false,
  title: "Hooenas Notches",
  subtitle: "Ready",
  activity: "idle",
  progress: null,
  actions: [],
};

function harness(timeoutMs = 250, options = {}) {
  const stdout = new Set(),
    errors = new Set(),
    exits = new Set();
  const writes = [];
  let closed = false;
  const transport = {
    async write(chunk) {
      writes.push(chunk);
    },
    onData(fn) {
      stdout.add(fn);
      return () => stdout.delete(fn);
    },
    onError(fn) {
      errors.add(fn);
      return () => errors.delete(fn);
    },
    onClose(fn) {
      exits.add(fn);
      return () => exits.delete(fn);
    },
    async close() {
      closed = true;
    },
  };
  const client = new NotchClient(transport, { timeoutMs, ...options });
  return {
    client,
    writes,
    transport,
    data(chunk) {
      for (const fn of stdout) fn(chunk);
    },
    message(value) {
      this.data(JSON.stringify(value) + "\n");
    },
    ready() {
      this.message({ event: "ready", protocolVersion: 1 });
    },
    exit() {
      for (const fn of exits) fn({ code: 1 });
    },
    get closed() {
      return closed;
    },
  };
}

const tick = () => new Promise((resolve) => setImmediate(resolve));

test("waits for ready and frames fragmented/coalesced records", async () => {
  const h = harness();
  const shown = h.client.show({ title: "Compiling", progress: 0.25 });
  assert.equal(h.writes.length, 0);
  h.data('{"event":"rea');
  h.data('dy","protocolVersion":1}\n');
  await tick();
  const sent = JSON.parse(h.writes[0]);
  assert.equal(sent.command, "show");
  assert.equal(sent.state.progress, 0.25);
  h.data(
    JSON.stringify({ event: "result", id: sent.id, ok: true, state, visible: true }) +
      "\n" +
      JSON.stringify({ event: "action", actionId: "cancel" }) +
      "\n",
  );
  assert.equal((await shown).visible, true);
  await h.client.dispose();
});

test("correlates concurrent responses by id rather than arrival order", async () => {
  const h = harness();
  h.ready();
  const first = h.client.update({ title: "First" });
  const second = h.client.hide();
  await tick();
  const a = JSON.parse(h.writes[0]),
    b = JSON.parse(h.writes[1]);
  h.message({ event: "result", id: b.id, ok: true, state, visible: false });
  h.message({ event: "result", id: a.id, ok: true, state, visible: true });
  assert.equal((await first).id, a.id);
  assert.equal((await second).id, b.id);
  await h.client.dispose();
});

test("forwards native actions and state while allowing unsubscribe", async () => {
  const h = harness();
  h.ready();
  const actions = [],
    snapshots = [];
  const off = h.client.onAction((action) => actions.push(action));
  h.client.onState((snapshot) => snapshots.push(snapshot));
  h.message({ event: "action", actionId: "open" });
  off();
  h.message({ event: "action", actionId: "ignored" });
  h.message({ event: "state", state: { ...state, expanded: true }, visible: true });
  assert.deepEqual(actions, ["open"]);
  assert.equal(snapshots[0].state.expanded, true);
  await h.client.dispose();
});

test("preserves explicit null in a progress patch and surfaces host validation", async () => {
  const h = harness();
  h.ready();
  const request = h.client.update({ progress: null });
  await tick();
  const sent = JSON.parse(h.writes[0]);
  assert.equal(sent.state.progress, null);
  h.message({ event: "error", id: sent.id, code: "invalid_state", message: "Bad state" });
  await assert.rejects(request, { code: "invalid_state", message: "Bad state" });
  await h.client.dispose();
});

test("rejects pending requests when the native host exits", async () => {
  const h = harness();
  h.ready();
  const request = h.client.hide();
  await tick();
  h.exit();
  await assert.rejects(request, { code: "host_closed" });
  await assert.rejects(h.client.show(), { code: "host_closed" });
  await h.client.dispose();
});

test("rejects unsupported versions and malformed host records", async () => {
  const h = harness();
  h.message({ event: "ready", protocolVersion: 2 });
  await assert.rejects(h.client.ready, /Unsupported notch protocol/);
  await h.client.dispose();
  const other = harness();
  other.ready();
  const pending = other.client.hide();
  await tick();
  other.data("not json\n");
  await assert.rejects(pending, { code: "invalid_message" });
  await other.client.dispose();
});

test("bounds both incoming and outgoing UTF-8 JSON lines", async () => {
  const h = harness();
  h.ready();
  await assert.rejects(h.client.show({ title: "🌙".repeat(20_000) }), { code: "line_too_large" });
  assert.equal(h.writes.length, 0);
  const pending = h.client.hide();
  await tick();
  h.data("x".repeat(65_537));
  await assert.rejects(pending, { code: "line_too_large" });
  await h.client.dispose();
});

test("has bounded readiness and request waits", async () => {
  const neverReady = harness(15);
  await assert.rejects(neverReady.client.ready, { code: "ready_timeout" });
  await neverReady.client.dispose();
  const h = harness(15);
  h.ready();
  await assert.rejects(h.client.hide(), { code: "request_timeout" });
  await h.client.dispose();
});

test("fatal input failures close the transport without requiring dispose", async () => {
  const h = harness();
  h.ready();
  const request = h.client.hide();
  await tick();
  h.data("not json\n");
  await assert.rejects(request, { code: "invalid_message" });
  assert.equal(h.closed, true);
  await h.client.dispose();
});

test("rejects coerced enum values in native snapshots", async () => {
  const h = harness();
  h.ready();
  const pending = h.client.hide();
  await tick();
  const sent = JSON.parse(h.writes[0]);
  h.message({
    event: "result",
    id: sent.id,
    ok: true,
    visible: false,
    state: { ...state, style: ["contour"] },
  });
  await assert.rejects(pending, { code: "invalid_message" });
  await h.client.dispose();
});

test("isolates throwing listeners so coalesced acknowledgements still resolve", async () => {
  const failures = [];
  const h = harness(250, { onListenerError: (error) => failures.push(error) });
  h.ready();
  const first = h.client.show(),
    second = h.client.hide();
  await tick();
  const [a, b] = h.writes.map(JSON.parse);
  h.client.onAction(() => {
    throw new Error("Consumer failed");
  });
  h.data(
    [
      { event: "action", actionId: "cancel" },
      { event: "result", id: a.id, ok: true, state, visible: true },
      { event: "result", id: b.id, ok: true, state, visible: false },
    ]
      .map((value) => JSON.stringify(value) + "\n")
      .join(""),
  );
  assert.equal((await first).visible, true);
  assert.equal((await second).visible, false);
  assert.equal(failures[0]?.message, "Consumer failed");
  await h.client.dispose();
});

test("serializes transport writes and stops queued commands after a timeout", async () => {
  const h = harness(25);
  h.ready();
  let release;
  h.transport.write = (chunk) => {
    h.writes.push(chunk);
    return new Promise((resolve) => {
      release = resolve;
    });
  };
  const first = h.client.show(),
    second = h.client.hide();
  const firstFailure = assert.rejects(first, { code: "request_timeout" });
  const secondFailure = assert.rejects(second, { code: "request_timeout" });
  await tick();
  assert.equal(h.writes.length, 1);
  await Promise.all([firstFailure, secondFailure]);
  assert.equal(h.closed, true);
  release();
  await tick();
  assert.equal(h.writes.length, 1);
  await h.client.dispose();
});

test("a synchronous write failure closes the session and rejects concurrent work", async () => {
  const h = harness();
  h.ready();
  h.transport.write = () => {
    throw new Error("Broken stdin");
  };
  const first = h.client.show(),
    second = h.client.hide();
  await assert.rejects(first, /Broken stdin/);
  await assert.rejects(second, /Broken stdin/);
  assert.equal(h.closed, true);
  await h.client.dispose();
});

test("counts a CR before LF in the native 64 KiB frame limit", async () => {
  const h = harness();
  h.ready();
  const pending = h.client.hide();
  await tick();
  const event = { event: "error", code: "test", message: "" };
  event.message = "x".repeat(65_536 - JSON.stringify(event).length);
  h.data(JSON.stringify(event) + "\r\n");
  await assert.rejects(pending, { code: "line_too_large" });
  await h.client.dispose();
});

test("quit is terminal and disposal closes the transport only once", async () => {
  const h = harness();
  h.ready();
  let closes = 0;
  h.transport.close = async () => {
    closes++;
  };
  const quit = h.client.quit();
  await assert.rejects(h.client.show(), { code: "session_closed" });
  await tick();
  const sent = JSON.parse(h.writes[0]);
  h.message({ event: "result", id: sent.id, ok: true, state, visible: false });
  await quit;
  await Promise.all([h.client.dispose(), h.client.dispose()]);
  assert.equal(closes, 1);
});

test("nonfinite progress cannot silently serialize into a clear-progress patch", async () => {
  const h = harness();
  h.ready();
  for (const progress of [Number.NaN, Number.POSITIVE_INFINITY, Number.NEGATIVE_INFINITY]) {
    await assert.rejects(h.client.update({ progress }), { code: "invalid_state" });
  }
  assert.equal(h.writes.length, 0);
  await h.client.dispose();
});

test("synchronous buffered input failure during subscription releases listeners", async () => {
  let detached = 0,
    closed = 0,
    extraSubscriptions = 0;
  const client = new NotchClient({
    async write() {},
    onData(listener) {
      listener("not json\n");
      return () => {
        detached++;
      };
    },
    onError() {
      extraSubscriptions++;
      return () => {};
    },
    onClose() {
      extraSubscriptions++;
      return () => {};
    },
    async close() {
      closed++;
    },
  });
  await assert.rejects(client.ready, { code: "invalid_message" });
  assert.equal(detached, 1);
  assert.equal(closed, 1);
  assert.equal(extraSubscriptions, 0);
  await client.dispose();
});

test("an acknowledged quit gets time to exit and is force closed if it does not", async () => {
  const h = harness(15);
  h.ready();
  const quit = h.client.quit();
  await tick();
  const request = JSON.parse(h.writes[0]);
  h.message({ event: "result", id: request.id, ok: true, state, visible: false });
  await quit;
  assert.equal(h.closed, false);
  await new Promise((resolve) => setTimeout(resolve, 25));
  assert.equal(h.closed, true);
  await assert.rejects(h.client.show(), { code: "host_exit_timeout" });
  await h.client.dispose();
});

test("asynchronous callback rejection is reported without closing the session", async () => {
  const failures = [];
  const h = harness(250, { onListenerError: (error) => failures.push(error) });
  h.ready();
  h.client.onAction(async () => {
    throw new Error("Async consumer failed");
  });
  h.message({ event: "action", actionId: "cancel" });
  await tick();
  assert.equal(failures[0]?.message, "Async consumer failed");
  assert.equal(h.closed, false);
  await h.client.dispose();
});
