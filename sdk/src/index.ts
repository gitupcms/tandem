// Tandem test SDK: drive a Tandem host (spec/protocol.md) from bun:test, on every platform, with a parity check.
import { test } from "bun:test";
import { once } from "node:events";
import { existsSync, mkdtempSync, readFileSync } from "node:fs";
import { connect, type Socket } from "node:net";
import { tmpdir } from "node:os";
import { dirname, isAbsolute, join, resolve } from "node:path";

export type Action = { from: string; input: unknown; name: string };
export type Screen = { actions: Action[]; name: string; path: string[]; state: Record<string, any> };
export type Step = { request: string; response: string };
type Want = string | ((screen: Screen) => boolean);

const RESPONSE_MS = 10_000; // one reply; polling windows use timeoutMs
const POLL_MS = 20;

export class ProtocolError extends Error {
  constructor(readonly code: string, readonly path: string | undefined, message: string) {
    super(`${code}${path ? ` at ${path}` : ""}: ${message}`);
  }
}

export class Session {
  screen: Screen | undefined;
  readonly transcript: Step[] = [];
  private lines: string[] = [];
  private waiter: (() => void) | undefined;
  private ended = false;

  private dec = new TextDecoder();
  private buf = "";
  private socket: Socket | undefined;

  constructor(private proc: Bun.Subprocess<"pipe", any, any>, private timeoutMs: number, private guardLog?: string) {}

  /** Reads replies from the host's stdout. */
  async readStdout() {
    for await (const chunk of this.proc.stdout as ReadableStream<Uint8Array>) this.feed(chunk);
    this.end();
  }

  private feed(chunk: Uint8Array) {
    this.buf += this.dec.decode(chunk, { stream: true });
    const parts = this.buf.split("\n");
    this.buf = parts.pop()!;
    this.lines.push(...parts);
    this.waiter?.();
  }

  private end() {
    this.ended = true;
    this.waiter?.();
  }

  /** Talks over the host's debug socket instead of stdio. */
  async connect(port: number) {
    const socket = connect(port, "127.0.0.1");
    socket.on("data", d => this.feed(d)).on("close", () => this.end()).on("error", () => this.end());
    await once(socket, "connect");
    this.socket = socket;
  }

  private async nextLine(): Promise<string> {
    const deadline = Date.now() + RESPONSE_MS;
    while (!this.lines.length) {
      if (this.ended) throw new Error(this.socket ? "host closed the socket without answering" : `host exited (code ${await this.proc.exited}) without answering`);
      const left = deadline - Date.now();
      if (left <= 0) throw new Error(`host did not answer within ${RESPONSE_MS}ms`);
      await new Promise<void>(r => { this.waiter = r; setTimeout(r, left); });
      this.waiter = undefined;
    }
    return this.lines.shift()!;
  }

  /** Sends one request, records the reply, returns it parsed. Throws ProtocolError on ok:false. */
  async send(request: object): Promise<any> {
    const line = JSON.stringify(request);
    if (this.socket) this.socket.write(line + "\n");
    else {
      this.proc.stdin.write(line + "\n");
      this.proc.stdin.flush();
    }
    const response = await this.nextLine();
    this.transcript.push({ request: line, response });
    this.checkGuard();
    const reply = JSON.parse(response);
    if (!reply.ok) throw new ProtocolError(reply.error?.code, reply.error?.path, reply.error?.message);
    if (reply.screen) this.screen = reply.screen;
    return reply;
  }

  /** Polls `ls` until the focused screen matches (a name or a predicate). */
  async precondition(want: Want): Promise<Screen> {
    await this.send({ op: "ls" });
    return this.until(want, `precondition ${describe(want)}`);
  }

  /** Runs an action, then waits until `expect` holds (if given). */
  async do(action: string, input?: object, expect?: (screen: Screen) => boolean): Promise<Screen> {
    await this.send(input === undefined ? { op: "do", action } : { op: "do", action, input });
    return expect ? this.until(expect, `do ${action}: expectation`) : this.screen!;
  }

  /** Awaits fn, which must fail with a protocol error of this code. */
  async expectError(fn: () => Promise<unknown>, code: string): Promise<ProtocolError> {
    try {
      await fn();
    } catch (e) {
      if (e instanceof ProtocolError && e.code === code) return e;
      throw e;
    }
    throw new Error(`expected a "${code}" protocol error, but the request succeeded`);
  }

  async close() {
    this.socket?.end();
    this.proc.stdin.end();
    const code = await this.proc.exited;
    this.checkGuard();
    if (code !== 0) throw new Error(`host exited with code ${code}`);
  }

  private async until(want: Want, what: string): Promise<Screen> {
    const match = typeof want === "string" ? (s: Screen) => s.name === want : want;
    const deadline = Date.now() + this.timeoutMs;
    while (!match(this.screen!)) {
      if (Date.now() > deadline) throw new Error(`${what} not met after ${this.timeoutMs}ms; last screen: ${JSON.stringify(this.screen)}`);
      await Bun.sleep(POLL_MS);
      await this.send({ op: "ls" });
    }
    return this.screen!;
  }

  private checkGuard() {
    if (!this.guardLog) return;
    const denied = guardLines(this.guardLog).find(l => l.startsWith("denied"));
    if (denied) throw new Error(`network guard: ${denied}`);
  }
}

const describe = (want: Want) => (typeof want === "string" ? `screen "${want}"` : "predicate");
const guardLines = (log: string) => (existsSync(log) ? readFileSync(log, "utf8").split("\n") : []);

/** Waits for the `listening 127.0.0.1:<port>` line a host started with `--socket 0` writes to stderr; forwards the rest. */
export async function listeningPort(proc: Bun.Subprocess<any, any, "pipe">): Promise<number> {
  const reader = proc.stderr.getReader();
  const dec = new TextDecoder();
  let text = "";
  const timer = setTimeout(() => proc.kill(), RESPONSE_MS);
  try {
    for (;;) {
      const { value, done } = await reader.read();
      if (done) throw new Error(`host exited before listening (code ${await proc.exited}): ${text.trim()}`);
      text += dec.decode(value, { stream: true });
      const m = text.match(/^listening 127\.0\.0\.1:(\d+)$/m);
      if (m) {
        (async () => { for (;;) { const r = await reader.read(); if (r.done) break; process.stderr.write(r.value); } })();
        return Number(m[1]);
      }
    }
  } finally {
    clearTimeout(timer);
  }
}

export async function session(opts: { command: string[]; guard?: string; timeoutMs?: number; socket?: boolean }): Promise<Session> {
  const env: Record<string, string | undefined> = { ...process.env };
  let guardLog: string | undefined;
  if (opts.guard) {
    const lib = process.platform === "darwin" ? opts.guard.replace(/\.so$/, ".dylib") : opts.guard;
    if (!existsSync(lib)) throw new Error(`guard library not found: ${lib} (run \`bun run build:guard\`)`);
    guardLog = join(mkdtempSync(join(tmpdir(), "tandem-guard-")), "guard.log");
    env[process.platform === "darwin" ? "DYLD_INSERT_LIBRARIES" : "LD_PRELOAD"] = lib;
    env.TANDEM_GUARD_LOG = guardLog;
  }
  const command = opts.socket ? [...opts.command, "--socket", "0"] : opts.command;
  const proc = Bun.spawn(command, { stdin: "pipe", stdout: "pipe", stderr: opts.socket ? "pipe" : "inherit", env });
  const app = new Session(proc, opts.timeoutMs ?? 2000, guardLog);
  try {
    if (opts.socket) await app.connect(await listeningPort(proc as Bun.Subprocess<"pipe", "pipe", "pipe">));
    else app.readStdout();
    await app.send({ op: "hello", version: 1 });
    if (guardLog && !guardLines(guardLog).some(l => l.startsWith("loaded"))) throw new Error("guard did not load");
  } catch (e) {
    proc.kill();
    throw e;
  }
  return app;
}

// Parity ignores what the protocol lets differ: hello's platform and error messages.
const normalize = (line: string) =>
  line
    .replace(/^\{"ok":true,"platform":"[^"]*"/, '{"ok":true,"platform":""')
    .replace(/^\{"error":\{"code":"([a-z]+)","message":"(?:[^"\\]|\\.)*"/, '{"error":{"code":"$1","message":""');

/** Returns a description of the first differing step across platforms, or undefined when all match. */
export function parityDiff(transcripts: Record<string, Step[]>): string | undefined {
  const [[base, ref], ...rest] = Object.entries(transcripts);
  for (const [platform, steps] of rest) {
    for (let i = 0; i < Math.max(ref.length, steps.length); i++) {
      const a = ref[i], b = steps[i];
      if (a && b && a.request === b.request && normalize(a.response) === normalize(b.response)) continue;
      return `parity: step ${i} differs\n  ${base}: ${a ? `${a.request} -> ${a.response}` : "(no step)"}\n  ${platform}: ${b ? `${b.request} -> ${b.response}` : "(no step)"}`;
    }
  }
}

type Config = { apps: Record<string, Record<string, string[]>>; guard?: string };
let config: Config | undefined;

function loadConfig(): Config {
  if (config) return config;
  const file = process.env.TANDEM_CONFIG ?? resolve(import.meta.dir, "../../tandem.config.json");
  const dir = dirname(file);
  const raw: Config = JSON.parse(readFileSync(file, "utf8"));
  const local = (p: string) => (p.includes("/") && !isAbsolute(p) ? join(dir, p) : p);
  const only = process.env.TANDEM_PLATFORM;
  const apps = Object.fromEntries(
    Object.entries(raw.apps).map(([app, platforms]) => {
      const kept = Object.entries(platforms)
        .filter(([name]) => !only || name === only)
        .map(([name, [cmd, ...args]]) => [name, [local(cmd), ...args]]);
      if (!kept.length) throw new Error(`no platform "${only}" for app "${app}" in ${file}`);
      return [app, Object.fromEntries(kept)];
    }),
  );
  return (config = { apps, guard: raw.guard && local(raw.guard) });
}

export type JourneyOptions = { app?: string; fixture?: string; timeoutMs?: number; socket?: boolean };

/**
 * Registers one bun:test per platform of `app` (default: the first app in the config), then a parity test
 * comparing their transcripts. `fixture` is appended to the host command as its first argument. `socket` drives
 * the host over its debug socket (spec: Transport) instead of stdio; use a debug build.
 */
export function journey(name: string, fn: (app: Session) => Promise<void>, opts: JourneyOptions = {}) {
  const { apps, guard } = loadConfig();
  const appName = opts.app ?? Object.keys(apps)[0];
  const platforms = apps[appName];
  if (!platforms) throw new Error(`no app "${appName}" in config`);
  const transcripts: Record<string, Step[]> = {};
  for (const [platform, command] of Object.entries(platforms)) {
    test(`${name} [${platform}]`, async () => {
      const app = await session({ command: opts.fixture ? [...command, opts.fixture] : command, guard, socket: opts.socket });
      transcripts[platform] = app.transcript;
      try {
        await fn(app);
      } finally {
        await app.close();
      }
    }, opts.timeoutMs ?? 30_000);
  }
  if (Object.keys(platforms).length < 2) return;
  test(`${name} [parity]`, () => {
    const missing = Object.keys(platforms).filter(p => !transcripts[p]);
    if (missing.length) throw new Error(`parity: ${missing.join(", ")} did not start`);
    const diff = parityDiff(transcripts);
    if (diff) throw new Error(diff);
  });
}
