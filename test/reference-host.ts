// Minimal Tandem reference host for the conformance probe (spec/protocol.md). Bytes in, response lines out.

type V = null | boolean | string | Num | V[] | Map<string, V>;
class Num { constructor(readonly raw: string) {} }
class Fail { constructor(readonly code: string, readonly message: string, readonly path?: string) {} }

const MAX_LINE = 1 << 20;
const MAX_DEPTH = 64;
const MAX_INT = 2n ** 53n - 1n;

// Strict JSON decoder: keeps number lexemes, rejects duplicate keys and nesting deeper than 64.
export function decode(text: string): V {
  let i = 0;
  const bad = (m: string): never => { throw new Fail("json", m); };
  const ws = () => { while (" \t\n\r".includes(text[i] ?? "x")) i++; };
  const str = (): string => {
    i++; let out = "";
    for (;;) {
      const c = text[i++];
      if (c === undefined) bad("unterminated string");
      if (c === '"') return out;
      if (c < " ") bad("raw control character in string");
      if (c !== "\\") { out += c; continue; }
      const e = text[i++];
      const simple: Record<string, string> = { '"': '"', "\\": "\\", "/": "/", b: "\b", f: "\f", n: "\n", r: "\r", t: "\t" };
      if (e in simple) { out += simple[e]; continue; }
      if (e !== "u" || !/^[0-9a-fA-F]{4}$/.test(text.slice(i, i + 4))) bad("bad escape");
      out += String.fromCharCode(parseInt(text.slice(i, i + 4), 16)); i += 4;
    }
  };
  const val = (depth: number): V => {
    ws();
    const c = text[i];
    if (c === "{" || c === "[") {
      if (depth > MAX_DEPTH) bad("nested too deep");
      i++; ws();
      const close = c === "{" ? "}" : "]";
      const arr: V[] = [], obj = new Map<string, V>();
      if (text[i] === close) { i++; return c === "{" ? obj : arr; }
      for (;;) {
        if (c === "{") {
          ws(); if (text[i] !== '"') bad("expected key");
          const k = str(); ws();
          if (text[i++] !== ":") bad("expected colon");
          if (obj.has(k)) bad("duplicate key");
          obj.set(k, val(depth + 1));
        } else arr.push(val(depth + 1));
        ws();
        const sep = text[i++];
        if (sep === close) return c === "{" ? obj : arr;
        if (sep !== ",") bad("expected comma");
      }
    }
    if (c === '"') return str();
    for (const [w, v] of [["true", true], ["false", false], ["null", null]] as const)
      if (text.startsWith(w, i)) { i += w.length; return v; }
    const re = /-?(0|[1-9]\d*)(\.\d+)?([eE][+-]?\d+)?/y;
    re.lastIndex = i;
    const m = re.exec(text);
    if (!m) bad("unexpected character");
    i = re.lastIndex;
    return new Num(m![0]);
  };
  const v = val(1);
  ws();
  if (i !== text.length) bad("trailing characters");
  // A lone surrogate escape is not a Unicode string; treat it as invalid JSON.
  if (!isWellFormed(v)) bad("lone surrogate");
  return v;
}

const isWellFormed = (v: V): boolean =>
  typeof v === "string" ? v.isWellFormed()
  : Array.isArray(v) ? v.every(isWellFormed)
  : v instanceof Map ? [...v].every(([k, x]) => k.isWellFormed() && isWellFormed(x))
  : true;

const intOf = (v: V | undefined): number | undefined =>
  v instanceof Num && /^-?(0|[1-9]\d*)$/.test(v.raw) && BigInt(v.raw) <= MAX_INT && BigInt(v.raw) >= -MAX_INT ? Number(v.raw) : undefined;

// Canonical writer: no whitespace, keys sorted by UTF-16 code units, minimal escaping.
export function canonical(v: unknown): string {
  if (v === null) return "null";
  if (typeof v === "boolean") return String(v);
  if (typeof v === "number") { if (!Number.isSafeInteger(v)) throw new Error("non-integer number"); return String(v); }
  if (typeof v === "string") {
    const esc: Record<string, string> = { '"': '\\"', "\\": "\\\\", "\b": "\\b", "\f": "\\f", "\n": "\\n", "\r": "\\r", "\t": "\\t" };
    return '"' + v.replace(/["\\\u0000-\u001f]/g, c => esc[c] ?? "\\u" + c.charCodeAt(0).toString(16).padStart(4, "0")) + '"';
  }
  if (Array.isArray(v)) return "[" + v.map(canonical).join(",") + "]";
  const o = v as Record<string, unknown>;
  return "{" + Object.keys(o).filter(k => o[k] !== undefined).sort().map(k => canonical(k) + ":" + canonical(o[k])).join(",") + "}";
}

// --- Input schema validation ---
type Schema = { type: string; properties?: Record<string, Schema>; required?: string[]; items?: Schema; enum?: string[] };

function check(s: Schema, v: V, path: string): unknown {
  const fail = (m: string): never => { throw new Fail("input", m, path); };
  if (v === null) fail("null is not allowed");
  switch (s.type) {
    case "object": {
      if (!(v instanceof Map)) fail("expected object");
      const props = s.properties ?? {};
      const m = v as Map<string, V>;
      for (const k of m.keys()) if (!Object.hasOwn(props, k)) throw new Fail("input", "unknown property", `${path}.${k}`);
      const out: Record<string, unknown> = {};
      for (const k of Object.keys(props).sort()) {
        if (m.has(k)) out[k] = check(props[k], m.get(k)!, `${path}.${k}`);
        else if (s.required?.includes(k)) throw new Fail("input", "missing required property", `${path}.${k}`);
      }
      return out;
    }
    case "array":
      if (!Array.isArray(v)) fail("expected array");
      return (v as V[]).map((x, n) => check(s.items!, x, `${path}[${n}]`));
    case "string":
      if (typeof v !== "string") fail("expected string");
      if (s.enum && !s.enum.includes(v as string)) fail("not an allowed value");
      return v;
    case "integer": {
      const n = intOf(v);
      if (n === undefined) fail("expected integer");
      return n;
    }
    case "boolean":
      if (typeof v !== "boolean") fail("expected boolean");
      return v;
  }
  throw new Error(`bad schema type ${s.type}`);
}

// --- Probe app ---
type ActionDef = { name: string; input: Schema | null; behavior: string };
type ScreenDef = { name: string; state: Record<string, unknown>; actions: ActionDef[] };
export type Probe = {
  root: { name: string; actions: ActionDef[]; child: { name: string; actions: ActionDef[]; screens: ScreenDef[] } };
};
type Screen = { def: ScreenDef; state: any };

const behaviors: Record<string, (s: Screen, input: any, host: Host) => void> = {
  increment: s => { s.state.count += 1; },
  add: (s, i) => { s.state.count += i.amount; },
  rename: (s, i) => { s.state.label = i.label ?? ""; },
  set_mode: (s, i) => { s.state.mode = i.mode; },
  set_tags: (s, i) => { s.state.tags = i.tags; },
  configure: (s, i) => { s.state.meta = { level: i.meta.level ?? 0, pinned: i.meta.pinned ?? false, tag: i.meta.tag }; },
  zero: s => { s.state.count = 0; },
  pop: (_s, _i, h) => { if (h.stack.length > 1) h.stack.pop(); },
  reset: (_s, _i, h) => h.reset(),
};

export class Host {
  stack: Screen[] = [];
  private greeted = false;
  constructor(private probe: Probe, private platform = "swift") { this.reset(); }

  reset() { this.stack = this.probe.root.child.screens.map(def => ({ def, state: structuredClone(def.state) })); }

  // Own actions first, then lent ones nearest container first; the nearest owner of a name wins.
  private actions() {
    const top = this.stack[this.stack.length - 1];
    const { root } = this.probe;
    const out: { from: string; def: ActionDef }[] = [];
    for (const [from, defs] of [[top.def.name, top.def.actions], [root.child.name, root.child.actions], [root.name, root.actions]] as const)
      for (const def of defs) if (!out.some(a => a.def.name === def.name)) out.push({ from, def });
    return out;
  }

  private screen() {
    const top = this.stack[this.stack.length - 1];
    const { root } = this.probe;
    return {
      actions: this.actions().map(a => ({ from: a.from, input: a.def.input, name: a.def.name })),
      name: top.def.name,
      path: [root.name, root.child.name, top.def.name],
      state: top.state,
    };
  }

  private request(line: Uint8Array): unknown {
    if (line.length > MAX_LINE) throw new Fail("json", "line too long");
    if (line[0] === 0xef && line[1] === 0xbb && line[2] === 0xbf) throw new Fail("json", "byte order mark");
    let text: string;
    try { text = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true }).decode(line); }
    catch { throw new Fail("json", "invalid UTF-8"); }
    const req = decode(text);
    if (!(req instanceof Map)) throw new Fail("request", "request must be an object");
    const op = req.get("op");
    if (typeof op !== "string") throw new Fail("request", "op must be a string", "$.op");
    const fields: Record<string, string[]> = { hello: ["version"], ls: [], do: ["action", "input"] };
    if (!Object.hasOwn(fields, op)) throw new Fail("request", "unknown op", "$.op");
    for (const k of req.keys()) if (k !== "op" && !fields[op].includes(k)) throw new Fail("request", "unknown field", `$.${k}`);
    const version = intOf(req.get("version"));
    if (op === "hello" && version === undefined) throw new Fail("request", "version must be an integer", "$.version");
    const action = req.get("action"), input = req.get("input");
    if (op === "do" && typeof action !== "string") throw new Fail("request", "action must be a string", "$.action");
    if (op === "do" && req.has("input") && !(input instanceof Map)) throw new Fail("request", "input must be an object", "$.input");

    if (op !== "hello" && !this.greeted) throw new Fail("handshake", "send hello first");
    if (op === "hello") {
      if (version !== 1) throw new Fail("version", "unsupported version", "$.version");
      this.greeted = true;
      return { ok: true, platform: this.platform, version: 1 };
    }
    if (op === "do") {
      const found = this.actions().find(a => a.def.name === action);
      if (!found) throw new Fail("action", "no such action on the focused screen", "$.action");
      if (!found.def.input && req.has("input")) throw new Fail("input", "action takes no input", "$.input");
      // Validate fully before touching state, so a failed request changes nothing. Omitted input counts as {}.
      const value = found.def.input ? check(found.def.input, input ?? new Map(), "$.input") : undefined;
      behaviors[found.def.behavior](this.stack[this.stack.length - 1], value, this);
    }
    return { ok: true, screen: this.screen() };
  }

  line(bytes: Uint8Array): string {
    try { return canonical(this.request(bytes)); }
    catch (e) {
      if (!(e instanceof Fail)) throw e;
      return canonical({
        error: { code: e.code, message: e.message, path: e.path },
        ok: false,
        supported: e.code === "version" ? [1] : undefined,
      });
    }
  }

  // Whole session: split on LF, drop one CR before it; bytes after the last LF are one more line.
  run(input: Uint8Array): string {
    let out = "", start = 0;
    while (start < input.length) {
      const lf = input.indexOf(0x0a, start);
      let end = lf < 0 ? input.length : lf;
      if (lf >= 0 && end > start && input[end - 1] === 0x0d) end--;
      out += this.line(input.subarray(start, end)) + "\n";
      start = lf < 0 ? input.length : lf + 1;
    }
    return out;
  }
}
