import test from "node:test";
import assert from "node:assert/strict";
import { NotchClient } from "../dist/index.js";

const state = {
  style: "contour", motion: "spring", expanded: false,
  title: "Hooenas Notches", subtitle: "Ready", activity: "idle",
  progress: null, actions: [],
};

function harness(timeoutMs = 250) {
  const stdout = new Set(), errors = new Set(), exits = new Set();
  const writes = [];
  let closed = false;
  const transport = {
    async write(chunk) { writes.push(chunk); },
    onData(fn) { stdout.add(fn); return () => stdout.delete(fn); },
    onError(fn) { errors.add(fn); return () => errors.delete(fn); },
    onClose(fn) { exits.add(fn); return () => exits.delete(fn); },
    async close() { closed = true; },
  };
  const client = new NotchClient(transport, { timeoutMs });
  return {
    client, writes,
    data(chunk) { for (const fn of stdout) fn(chunk); },
    message(value) { this.data(JSON.stringify(value) + "\n"); },
    ready() { this.message({ event: "ready", protocolVersion: 1 }); },
    exit() { for (const fn of exits) fn({ code: 1 }); },
    get closed() { return closed; },
  };
}

const tick = () => new Promise(resolve => setImmediate(resolve));

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
  h.data(JSON.stringify({ event: "result", id: sent.id, ok: true, state, visible: true }) + "\n" + JSON.stringify({ event: "action", actionId: "cancel" }) + "\n");
  assert.equal((await shown).visible, true);
  await h.client.dispose();
});

test("correlates concurrent responses by id rather than arrival order", async () => {
  const h = harness(); h.ready();
  const first = h.client.update({ title: "First" });
  const second = h.client.hide();
  await tick();
  const a = JSON.parse(h.writes[0]), b = JSON.parse(h.writes[1]);
  h.message({ event: "result", id: b.id, ok: true, state, visible: false });
  h.message({ event: "result", id: a.id, ok: true, state, visible: true });
  assert.equal((await first).id, a.id);
  assert.equal((await second).id, b.id);
  await h.client.dispose();
});

test("forwards native actions and state while allowing unsubscribe", async () => {
  const h = harness(); h.ready();
  const actions = [], snapshots = [];
  const off = h.client.onAction(action => actions.push(action));
  h.client.onState(snapshot => snapshots.push(snapshot));
  h.message({ event: "action", actionId: "open" });
  off();
  h.message({ event: "action", actionId: "ignored" });
  h.message({ event: "state", state: { ...state, expanded: true }, visible: true });
  assert.deepEqual(actions, ["open"]);
  assert.equal(snapshots[0].state.expanded, true);
  await h.client.dispose();
});

test("preserves explicit null in a progress patch and surfaces host validation", async () => {
  const h = harness(); h.ready();
  const request = h.client.update({ progress: null });
  await tick();
  const sent = JSON.parse(h.writes[0]);
  assert.equal(sent.state.progress, null);
  h.message({ event: "error", id: sent.id, code: "invalid_state", message: "Bad state" });
  await assert.rejects(request, { code: "invalid_state", message: "Bad state" });
  await h.client.dispose();
});

test("rejects pending requests when the native host exits", async () => {
  const h = harness(); h.ready();
  const request = h.client.hide();
  await tick(); h.exit();
  await assert.rejects(request, { code: "host_closed" });
  await assert.rejects(h.client.show(), { code: "host_closed" });
  await h.client.dispose();
});

test("rejects unsupported versions and malformed host records", async () => {
  const h = harness();
  h.message({ event: "ready", protocolVersion: 2 });
  await assert.rejects(h.client.ready, /Unsupported notch protocol/);
  await h.client.dispose();
  const other = harness(); other.ready();
  const pending = other.client.hide();
  await tick(); other.data("not json\n");
  await assert.rejects(pending, { code: "invalid_message" });
  await other.client.dispose();
});

test("bounds both incoming and outgoing UTF-8 JSON lines", async () => {
  const h = harness(); h.ready();
  await assert.rejects(h.client.show({ title: "🌙".repeat(20_000) }), { code: "line_too_large" });
  assert.equal(h.writes.length, 0);
  const pending = h.client.hide();
  await tick(); h.data("x".repeat(65_537));
  await assert.rejects(pending, { code: "line_too_large" });
  await h.client.dispose();
});

test("has bounded readiness and request waits", async () => {
  const neverReady = harness(15);
  await assert.rejects(neverReady.client.ready, { code: "ready_timeout" });
  await neverReady.client.dispose();
  const h = harness(15); h.ready();
  await assert.rejects(h.client.hide(), { code: "request_timeout" });
  await h.client.dispose();
});
