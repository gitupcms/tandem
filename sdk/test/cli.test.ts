import { expect, test } from "bun:test";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const bun = process.execPath;
const cli = join(import.meta.dir, "../src/cli.ts");
const fake = join(import.meta.dir, "fake-host.ts");
const tmp = mkdtempSync(join(tmpdir(), "tandem-cli-"));
const host = (platform: string, step?: number) => [bun, fake, platform, ...(step === undefined ? [] : [String(step)])];

let serial = 0;
function config(apps: Record<string, Record<string, string[]>>): string {
  const file = join(tmp, `config-${serial++}.json`);
  writeFileSync(file, JSON.stringify({ apps }));
  return file;
}

function run(cfg: string, ...args: string[]) {
  const p = Bun.spawnSync([bun, cli, ...args], {
    env: { ...process.env, TANDEM_CONFIG: cfg, TANDEM_PLATFORM: "" },
    stdout: "pipe",
    stderr: "pipe",
  });
  return { code: p.exitCode, out: p.stdout.toString(), err: p.stderr.toString() };
}

const fakeApp = (stepA = 1, stepB = 1) => config({ fake: { a: host("a", stepA), b: host("b", stepB) } });
const lines = (out: string) => out.split("\n").filter(Boolean);
const count = (line: string) => JSON.parse(line).screen.state.count;

test("no steps: one ls on the first app's first platform", () => {
  const r = run(fakeApp(1, 2), "run");
  expect(r.code).toBe(0);
  expect(r.err).toBe("");
  const out = lines(r.out);
  expect(out).toHaveLength(2);
  expect(out[0]).toBe("> ls");
  expect(count(out[1])).toBe(0);
});

test("do chain replays on one host, in order", () => {
  const r = run(fakeApp(1, 2), "run", "do", "Increment", "do", "Increment");
  expect(r.code).toBe(0);
  const out = lines(r.out);
  expect(out).toHaveLength(4);
  expect(out[0]).toBe("> do Increment");
  expect([count(out[1]), count(out[3])]).toEqual([1, 2]); // step 1, not platform b's 2 and 4
});

test("a step may be one argument, with or without input", () => {
  const single = run(fakeApp(), "run", 'do Increment {"n":1}', "ls");
  expect(single.code).toBe(0);
  expect(lines(single.out)[0]).toBe('> do Increment {"n":1}');
  expect(count(lines(single.out)[1])).toBe(1);

  const split = run(fakeApp(), "run", "do", "Increment", '{"n":1}');
  expect(split.code).toBe(0);
  expect(lines(split.out)[0]).toBe('> do Increment {"n":1}');
});

test("protocol error: reply is printed, the rest is not run, exit 1", () => {
  const r = run(fakeApp(), "run", "do", "Nope", "ls");
  expect(r.code).toBe(1);
  const out = lines(r.out);
  expect(out[0]).toBe("> do Nope");
  expect(JSON.parse(out[1]).error.code).toBe("action");
  expect(r.out).not.toContain("> ls");
});

test("usage errors exit 2", () => {
  const cases: string[][] = [
    ["run", "--app", "nope"],
    ["run", "--platform", "c"],
    ["run", "--nope"],
    ["run", "skip"],
    ["run", "do"],
    ["run", "do", "Increment", "{oops"],
    ["run", "--parity", "--platform", "a"],
    ["walk"],
  ];
  for (const args of cases) {
    const r = run(fakeApp(), ...args);
    expect({ args, code: r.code }).toEqual({ args, code: 2 });
    expect(r.err).toContain("tandem:");
  }
});

test("--fixture is handed to the host as its first argument", () => {
  const r = run(config({ fake: { a: host("a") } }), "run", "--fixture", "3", "do", "Increment");
  expect(r.code).toBe(0);
  expect(count(lines(r.out)[1])).toBe(3);
});

test("--platform picks another platform", () => {
  const r = run(fakeApp(1, 2), "run", "--platform", "b", "do", "Increment");
  expect(r.code).toBe(0);
  expect(count(lines(r.out)[1])).toBe(2);
});

test("--parity: equal platforms exit 0, each under its own heading", () => {
  const r = run(fakeApp(1, 1), "run", "--parity", "ls", "do", "Increment");
  expect(r.code).toBe(0);
  const out = lines(r.out);
  expect(out[0]).toBe("## a");
  expect(out[1]).toBe("> ls");
  expect(out[3]).toBe("> do Increment");
  expect(out[5]).toBe("## b");
  expect(out[6]).toBe("> ls");
  expect(r.out).not.toContain("differs");
});

test("--parity: a differing step exits 1 and prints the diff", () => {
  const r = run(fakeApp(1, 2), "run", "--parity", "do", "Increment");
  expect(r.code).toBe(1);
  expect(r.out).toContain("parity: step 1 differs");
  expect(r.out).toContain('"state":{"count":1}');
  expect(r.out).toContain('"state":{"count":2}');
});

test("help, with or without a command", () => {
  for (const args of [["help"], [], ["run", "--help"]]) {
    const r = run(fakeApp(), ...args);
    expect(r.code).toBe(0);
    expect(r.out).toContain("usage: tandem run");
  }
});
