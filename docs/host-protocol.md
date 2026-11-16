# Native Host Protocol · v1

`hooenas-notches-host --stdio` runs the same native SwiftUI notch renderer used by Swift applications. A Tauri, Electron, Rust, Python or other desktop process can launch it and exchange UTF-8 JSON Lines over stdin and stdout. The host is macOS-only; its transport is independent of the parent framework.

Build it with `swift build --product hooenas-notches-host`. Keep stdin open for the lifetime of the notch. End-of-file closes the panel and ends the host. The host uses a nonactivating accessory panel and does not request screen recording, accessibility or automation access.

## Connection

The host emits this once its AppKit run loop is ready:

```json
{ "event": "ready", "protocolVersion": 1 }
```

Wait for `ready`, then write one complete JSON object followed by a newline. Writes may be split across reads; UTF-8 characters are preserved. Both LF and CRLF are accepted. A final line without a newline is processed before EOF. Empty lines are ignored. A line may contain at most 65,536 bytes before LF; longer lines are discarded and produce a `line_too_long` error. The next line can still be processed.

Stdout contains only protocol messages. Treat stderr as diagnostic text. No network listener or credentials are involved.

## Commands

Every request has a nonempty string `id` (maximum 128 characters and 512 UTF-8 bytes), which appears in its response. IDs contain no control characters.

| Command  | Behavior                                                                   |
| -------- | -------------------------------------------------------------------------- |
| `show`   | Apply the optional state patch and show the panel.                         |
| `update` | Apply the optional state patch. A hidden panel stays hidden.               |
| `hide`   | Hide the panel and preserve its state. Does not accept `state`.            |
| `quit`   | Hide the panel, acknowledge the request and exit. Does not accept `state`. |

```json
{
  "id": "show-1",
  "command": "show",
  "state": {
    "style": "contour",
    "title": "Upload läuft",
    "subtitle": "24 von 40 Dateien",
    "activity": "working",
    "progress": 0.6,
    "expanded": true,
    "actions": [{ "id": "cancel", "label": "Abbrechen" }]
  }
}
```

The host validates the complete resulting state before applying a patch, including its encoded size. A sequence of individually small patches cannot accumulate a state too large for a response. If validation fails, the prior state and visibility remain intact.

### State patch

All fields are optional. Missing fields preserve their previous value. `progress: null` clears progress. An empty `actions` array removes all actions.

| Field      | Values / limits                                          | Initial value              |
| ---------- | -------------------------------------------------------- | -------------------------- |
| `style`    | `contour`, `capsule`, `glass`                            | `contour`                  |
| `motion`   | `spring`, `gentle`, `snappy`                             | `spring`                   |
| `expanded` | Boolean                                                  | `false`                    |
| `title`    | 1–512 characters, contains non-whitespace                | `Hooenas Notches`          |
| `subtitle` | At most 2,048 characters                                 | `Bereit, wenn du es bist.` |
| `activity` | `idle`, `working`, `listening`, `success`                | `idle`                     |
| `progress` | `null` or a finite number from 0 to 1                    | `null`                     |
| `actions`  | At most four `{ "id": string, "label": string }` objects | `[]`                       |

Action ids must be unique, contain 1–64 characters and at most 256 UTF-8 bytes, and contain no control characters. Labels must contain 1–64 characters with non-whitespace content. Character limits count Swift extended grapheme clusters; encoded-size limits also bound combining sequences. Text is rendered as text, never as HTML, code or a shell command. Long text is visually truncated by the standard notch content.

## Results and events

A successful command returns a complete state snapshot, including `progress: null` when no progress is shown:

```json
{
  "event": "result",
  "id": "show-1",
  "ok": true,
  "visible": true,
  "state": {
    "style": "contour",
    "motion": "spring",
    "expanded": true,
    "title": "Upload läuft",
    "subtitle": "24 von 40 Dateien",
    "activity": "working",
    "progress": 0.6,
    "actions": [{ "id": "cancel", "label": "Abbrechen" }]
  }
}
```

Clicking an action returns its id. The parent app chooses what the action does:

```json
{ "event": "action", "actionId": "cancel" }
```

Hovering, clicking the notch or pressing Escape may change its expanded state. The host emits a full state event for those local changes:

```json
{
  "event": "state",
  "visible": true,
  "state": {
    "style": "contour",
    "motion": "spring",
    "expanded": false,
    "title": "Hooenas Notches",
    "subtitle": "Bereit, wenn du es bist.",
    "activity": "idle",
    "progress": null,
    "actions": []
  }
}
```

Errors include an id when it can be read safely:

```json
{
  "event": "error",
  "id": "bad-1",
  "code": "invalid_state",
  "message": "progress must be null or a finite number between 0 and 1."
}
```

Error codes are `invalid_request`, `invalid_state`, `line_too_long`, `input_error` and `session_closed`. An invalid JSON line does not end the host. A closed stdin or `quit` does.

## Parent process lifecycle

1. Spawn the macOS host with piped stdin/stdout and `--stdio`.
2. Attach stdout and process-exit listeners immediately; wait for `ready` before sending requests.
3. Match responses by id; handle action and state events independently.
4. Send `quit` when the owning app closes, and wait for the process to exit.
5. If the host exits unexpectedly, reject outstanding requests. Start a new host before showing another notch.

For distribution, bundle a host binary for the required macOS architecture, sign it alongside the parent app and include the project's license files. The repository includes a Tauri v2 client adapter and bundling example.
