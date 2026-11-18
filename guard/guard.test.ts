import { beforeAll, describe, expect, test } from "bun:test";
import { existsSync, mkdtempSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const root = join(import.meta.dir, "..");
const mac = process.platform === "darwin";
const lib = join(import.meta.dir, "build", `libtandemguard.${mac ? "dylib" : "so"}`);
const tmp = mkdtempSync(join(tmpdir(), "tandem-guard-"));
const canary = join(tmp, "canary");
let n = 0;

const sh = (cmd: string[], env: Record<string, string> = {}, stdin?: string) => {
  const p = Bun.spawnSync(cmd, { cwd: root, env: { ...process.env, ...env }, stdin: stdin === undefined ? "ignore" : Buffer.from(stdin), stdout: "pipe", stderr: "pipe" });
  if (p.exitCode !== 0) throw new Error(`${cmd.join(" ")} exited ${p.exitCode}: ${p.stderr}`);
  return p.stdout.toString();
};
// Runs cmd with the guard preloaded; returns stdout and the guard log lines.
const guarded = (cmd: string[], stdin?: string) => {
  const log = join(tmp, `log-${n++}`);
  const env = { TANDEM_GUARD_LOG: log, [mac ? "DYLD_INSERT_LIBRARIES" : "LD_PRELOAD"]: lib };
  const out = sh(cmd, env, stdin);
  return { out, log: existsSync(log) ? readFileSync(log, "utf8").split("\n").filter(Boolean) : [] };
};
const results = (out: string) => Object.fromEntries(out.trim().split("\n").map(l => { const [k, ...v] = l.split(" "); return [k, v.map(Number)]; }));

beforeAll(() => {
  sh(["bun", "run", "build:guard"]);
  sh(["cc", "-o", canary, join(import.meta.dir, "canary.c")]);
});

describe("canary", () => {
  test("guarded: non-loopback refused and logged, loopback allowed", () => {
    const { out, log } = guarded([canary]);
    const r = results(out);
    const refused = r.ECONNREFUSED[0];
    expect(r.tcp).toEqual([-1, refused]);
    expect(r.udp).toEqual([-1, refused]);
    expect(r.loopback).toEqual([0, 0]);
    expect(log).toHaveLength(3);
    expect(log[0]).toMatch(/^loaded \d+$/);
    expect(log.slice(1)).toEqual(["denied ipv4 1.1.1.1 80", "denied ipv4 8.8.8.8 53"]);
  });

  test("unguarded: no log, loopback allowed", () => {
    const log = join(tmp, "unguarded");
    const r = results(sh([canary], { TANDEM_GUARD_LOG: log }));
    expect(r.loopback).toEqual([0, 0]);
    expect(existsSync(log)).toBe(false);
  });
});

// Real probe hosts (built separately); skipped when not built.
const hosts: [string, string, string][] = [
  ["swift", join(root, "swift/.build/release/TandemProbe"), "swift"],
  ["kotlin", join(root, "kotlin/probe-host/build/install/probe-host/bin/probe-host"), "kotlin"],
];
for (const [name, bin, platform] of hosts) {
  test.skipIf(!existsSync(bin))(`${name} probe host runs guarded`, () => {
    const { out, log } = guarded([bin, "probe"], '{"op":"hello","version":1}\n');
    expect(out).toBe(`{"ok":true,"platform":"${platform}","version":1}\n`);
    expect(log.some(l => /^loaded \d+$/.test(l))).toBe(true);
    expect(log.filter(l => l.startsWith("denied"))).toEqual([]);
  }, 30_000);
}
