# Tandem protocol, version 1

A Tandem host exposes an app's screens to a client (a test, the CLI, an agent). The client reads the focused screen's state and invokes its actions. A Swift host and a Kotlin host for the same app must answer the same requests with the same bytes.

## Transport

- Headless: the host is a process. Requests arrive on stdin, responses leave on stdout, logs go to stderr.
- In-app (debug builds only): the same lines over a loopback TCP socket. Release builds must not contain the socket server.
  - A headless host started with `--socket <port>` after the fixture name serves the socket instead of stdin. Port `0` picks a free port. When ready it writes one line `listening 127.0.0.1:<port>` to stderr.
  - It binds only 127.0.0.1. Each connection is its own session and starts with `hello`. The app's state carries over from one connection to the next. One connection is served at a time; others wait. When the client shuts down its sending side, that is end of input for the session (a final line that does not end in LF is still answered, like on stdin), and the host then closes the connection.
  - The host exits with code 0 when its stdin reaches end of input.
  - A release host given `--socket` exits with code 64 and a message on stderr.
- The host's first command-line argument names a fixture set. An unknown name exits with code 64 and a message on stderr.

## Framing

- One request per line, one response per line, in order. LF (0x0A) ends a line. A CR directly before the LF is dropped; any other CR stays in the line.
- Lines are UTF-8. A line with invalid UTF-8, a byte order mark, or an empty or blank line is answered with a `json` error.
- A line longer than 1 MiB (not counting the LF), or JSON nested deeper than 64 levels (the top-level value is level 1), is a `json` error.
- An escaped lone surrogate such as `"\ud800"` is a `json` error.
- Bytes after the last LF at end of input count as one more line.
- After an error the session continues with the next line.

## Requests

A request is a JSON object with an `op` string. Unknown fields are rejected.

| op | Fields | Answer |
| --- | --- | --- |
| `hello` | `version` (integer) | `{"ok":true,"platform":"swift"\|"kotlin","version":1}` |
| `ls` | none | the focused screen |
| `do` | `action` (string), optional `input` (object) | the focused screen after the action |
| `host.<name>` | host-defined | host-defined test controls, e.g. advancing a fake clock |

`hello` must be the first successful request. Anything else before it is a `handshake` error. A `hello` with a version the host does not speak is a `version` error and may be retried.

## The node tree

The app is a tree of nodes. The root owns navigators (tab, stack, modal), navigators own screens. Each node has:

- `name`: stable identifier, the same on both platforms.
- `state`: a JSON object with everything the user can see.
- `actions`: ordered list of actions it accepts, each with an optional input schema.
- `child`: the node it currently shows, or none.

The focused screen is the deepest node reached by following `child` from the root.

Every ancestor lends its actions to the focused screen: a stack lends `Back`, a tab bar lends `SelectTab`. Lent actions are listed after the screen's own actions, nearest ancestor first. If two nodes offer the same action name, the nearest one wins and the other is not listed.

Nodes hold no logic. They only report state and forward actions to the view model. Business rules live in the view model's `update`.

## Responses

Success:

```json
{"ok":true,"screen":{"actions":[{"from":"Counter","input":null,"name":"Increment"},{"from":"Stack","input":null,"name":"Back"}],"name":"Counter","path":["App","Stack","Counter"],"state":{"count":1}}}
```

- `path`: node names from the root to the focused screen.
- `actions[].from`: the node that owns the action.
- `actions[].input`: the input schema, or `null` when the action takes no input.

Failure:

```json
{"error":{"code":"input","message":"expected integer","path":"$.input.amount"},"ok":false}
```

- A failed request changes nothing.
- `path` points into the request, starting at `$`, with keys written as `.key` and array items as `[i]`. A missing or mistyped request field points at that field (`$.op`, `$.version`, `$.action`). An `action` error points at `$.action`. `path` is omitted when the error is about the whole line or the session (`json` on unreadable input, `handshake`).
- `op` is checked first, since it decides which fields are valid. After that, when several fields are wrong, the error names the first one in the request's own order. Missing required fields come after that, in sorted key order. The same rule applies inside each input object.
- `message` is for humans and is not compared between platforms. Everything else is.
- A rule the app rejects (decrement below zero, a declined payment) is not a protocol error. The app answers `ok:true` and shows the outcome in `state`.

## Error codes

Checked in this order; the first that applies wins.

| Code | When |
| --- | --- |
| `json` | Not valid UTF-8 JSON, blank line, too long, too deep, duplicate key at any level. |
| `request` | Not an object, `op` missing or not a string, unknown `op`, unknown or mistyped request field. |
| `handshake` | Any request other than `hello` before a successful `hello`. |
| `version` | `hello` with an unsupported version, at `$.version`. The response has a top-level `"supported":[1]` next to `ok`. |
| `action` | `do` names an action the focused screen does not offer. |
| `input` | The input does not match the action's schema, or `input` is given to an action without a schema. |

## Input schemas

A subset of JSON Schema. Every object schema is closed: unknown properties are an `input` error.

| Keyword | Meaning |
| --- | --- |
| `type` | `object`, `array`, `string`, `integer`, `boolean` |
| `properties`, `required` | object fields; fields not in `required` may be omitted |
| `items` | element schema for arrays |
| `enum` | allowed strings |

Rules:

- `null` is never a valid value. Leave an optional field out instead. `"input":null` in a request is a `request` error.
- A `do` without `input` on an action that has a schema is checked as `{}`.
- An integer is a JSON number with no fraction and no exponent, between -9007199254740991 and 9007199254740991. `1.0`, `1e2` and `"1"` are `input` errors.
- There is no float type. Decimals such as money travel as strings.
- Keys are compared by exact code units, without Unicode normalization.

## Canonical output

Both platforms must write byte-identical responses:

- No whitespace outside strings.
- Object keys sorted by UTF-16 code units.
- Integers in plain decimal. State must not contain non-integer numbers.
- Strings escape only `"`, `\` and characters below U+0020. Those use `\b \f \n \r \t`, else `\u00XX` with lowercase hex. Everything else is written as UTF-8.

## Versioning

The protocol version is one integer. Adding an op, an error code or a response field does not change it. Changing or removing anything does.
