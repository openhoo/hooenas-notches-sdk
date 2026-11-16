import test, { afterEach } from "node:test";
import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import { Command } from "@tauri-apps/plugin-shell";
import { createTauriNotch } from "../dist/tauri.js";

const originalSidecar = Command.sidecar;
afterEach(() => {
  Command.sidecar = originalSidecar;
});
const tick = () => new Promise((resolve) => setImmediate(resolve));
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

function sidecar() {
  const command = new EventEmitter();
  command.stdout = new EventEmitter();
  command.stderr = new EventEmitter();
  let kills = 0;
  const child = {
    async write(chunk) {
      const request = JSON.parse(chunk);
      command.stdout.emit(
        "data",
        JSON.stringify({
          event: "result",
          id: request.id,
          ok: true,
          state,
          visible: request.command === "show",
        }),
      );
    },
    async kill() {
      kills++;
    },
  };
  command.spawn = async () => {
    command.stdout.emit("data", '{"event":"ready","protocolVersion":1}');
    return child;
  };
  Command.sidecar = (program, args) => {
    assert.equal(program, "binaries/hooenas-notches-host");
    assert.deepEqual(args, ["--stdio"]);
    return command;
  };
  return {
    command,
    child,
    get kills() {
      return kills;
    },
    assertDetached() {
      assert.equal(command.listenerCount("close"), 0);
      assert.equal(command.listenerCount("error"), 0);
      assert.equal(command.stdout.listenerCount("data"), 0);
      assert.equal(command.stderr.listenerCount("data"), 0);
    },
  };
}

test("Tauri adapter retains early ready lines and detaches all process listeners on dispose", async () => {
  const fake = sidecar();
  const notch = await createTauriNotch();
  assert.equal((await notch.show()).visible, true);
  assert.equal((await notch.hide()).visible, false);
  await Promise.all([notch.dispose(), notch.dispose()]);
  fake.assertDetached();
  assert.equal(fake.kills, 1);
});

test("invalid client options never leave command listeners attached", async () => {
  const fake = sidecar();
  await assert.rejects(createTauriNotch({ timeoutMs: Number.NaN }), RangeError);
  fake.assertDetached();
  assert.equal(fake.kills, 0);
});

test("startup timeout detaches and kills a child whose spawn resolves late", async () => {
  const fake = sidecar();
  let finishSpawn;
  fake.command.spawn = () =>
    new Promise((resolve) => {
      finishSpawn = resolve;
    });
  await assert.rejects(createTauriNotch({ timeoutMs: 15 }), { code: "ready_timeout" });
  fake.assertDetached();
  finishSpawn(fake.child);
  await tick();
  assert.equal(fake.kills, 1);
});

test("a process that announces ready then exits before spawn resolves is rejected", async () => {
  const fake = sidecar();
  fake.command.spawn = async () => {
    fake.command.stdout.emit("data", '{"event":"ready","protocolVersion":1}');
    fake.command.emit("close", { code: 0 });
    return fake.child;
  };
  await assert.rejects(createTauriNotch(), { code: "host_closed" });
  fake.assertDetached();
  assert.equal(fake.kills, 0);
});

test("protocol failure kills and detaches a running Tauri sidecar", async () => {
  const fake = sidecar();
  const notch = await createTauriNotch();
  fake.child.write = async () => {};
  const pending = notch.hide();
  await tick();
  fake.command.stdout.emit("data", "not JSON");
  await assert.rejects(pending, { code: "invalid_message" });
  fake.assertDetached();
  assert.equal(fake.kills, 1);
  await notch.dispose();
});

test("stderr consumer failures are isolated from native protocol output", async () => {
  const fake = sidecar(),
    errors = [];
  const notch = await createTauriNotch({
    onStderr: async () => {
      throw new Error("Diagnostic consumer failed");
    },
    onListenerError: (error) => errors.push(error),
  });
  fake.command.stderr.emit("data", "Diagnostic");
  await tick();
  assert.equal(errors[0]?.message, "Diagnostic consumer failed");
  assert.equal((await notch.show()).visible, true);
  await notch.dispose();
});
