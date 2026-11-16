#!/usr/bin/env python3
"""Check real host responses while stdin remains open between individual writes."""

import json
import os
import select
import subprocess
import time
from pathlib import Path


def main():
    root = Path(__file__).resolve().parent.parent
    executable = Path(os.environ.get("HOOENAS_NOTCHES_HOST", root / ".build/debug/hooenas-notches-host"))
    host = subprocess.Popen(
        [str(executable), "--stdio"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    pending = bytearray()
    events = []

    def receive(timeout=3):
        deadline = time.monotonic() + timeout
        while b"\n" not in pending:
            remaining = deadline - time.monotonic()
            if remaining <= 0 or not select.select([host.stdout], [], [], remaining)[0]:
                raise AssertionError("Host did not reply while stdin was kept open")
            chunk = os.read(host.stdout.fileno(), 65536)
            if not chunk:
                raise AssertionError("Host closed stdout unexpectedly")
            pending.extend(chunk)
        line, _, rest = pending.partition(b"\n")
        pending[:] = rest
        event = json.loads(line)
        events.append(event)
        return event

    def send(request):
        host.stdin.write(json.dumps(request).encode() + b"\n")
        host.stdin.flush()
        while True:
            event = receive()
            if event.get("id") == request["id"]:
                return event

    try:
        assert receive() == {"event": "ready", "protocolVersion": 1}
        shown = send(
            {
                "id": "show",
                "command": "show",
                "state": {
                    "title": "Offener Stream",
                    "expanded": True,
                    "progress": 0.3,
                },
            }
        )
        assert shown["visible"] is True
        updated = send({"id": "update", "command": "update", "state": {"progress": None}})
        assert updated["state"]["progress"] is None
        invalid = send({"id": "bad", "command": "update", "state": {"progress": 2}})
        assert invalid["event"] == "error" and invalid["code"] == "invalid_state"
        hidden = send({"id": "hide", "command": "hide"})
        assert hidden["visible"] is False
        quit_event = send({"id": "quit", "command": "quit"})
        assert quit_event["visible"] is False
        assert host.wait(timeout=3) == 0
        assert host.stderr.read() == b""
        report = {"open_stdin_roundtrip": "passed", "exit_code": host.returncode, "events": events}
        (root / "output").mkdir(exist_ok=True)
        (root / "output/host-open-stream-smoke.json").write_text(
            json.dumps(report, ensure_ascii=False, indent=2) + "\n"
        )
        print("Open stdin: ready → show → update → rejected patch → hide → quit; passed.")
    finally:
        if host.poll() is None:
            host.stdin.close()
            try:
                host.wait(timeout=3)
            except subprocess.TimeoutExpired:
                host.kill()
                host.wait()


if __name__ == "__main__":
    main()
