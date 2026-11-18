import { expect, test } from "bun:test";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { session } from "tandem-kit";

const bun = process.execPath;
const fake = join(import.meta.dir, "fake-host.ts");
const tmp = mkdtempSync(join(tmpdir(), "tandem-sdk-"));
const fakeLib = join(tmp, "libfake.so"); // only has to exist: the fake host writes the guard log itself
writeFileSync(fakeLib, "");
const host = (platform: string, ...args: string[]) => [bun, fake, platform, ...args];

function runParity(stepB: number) {
  const cfg = join(tmp, `config-${stepB}.json`);
  writeFileSync(cfg, JSON.stringify({ platforms: { a: host("a"), b: host("b", String(stepB)) } }));
  const p = Bun.spawnSync([bun, "test", join(import.meta.dir, "fixtures/parity.journey.ts")], {
    env: { ...process.env, TANDEM_CONFIG: cfg, TANDEM_PLATFORM: "" },
    stdout: "pipe",
    stderr: "pipe",
  });
  return { code: p.exitCode, out: p.stdout.toString() + p.stderr.toString() };
}

test("parity passes when only platform and error messages differ", () => {
  const r = runParity(1);
  expect(r.out).toContain("3 pass");
  expect(r.code).toBe(0);
});

test("parity fails on the first differing step", () => {
  const r = runParity(2);
  expect(r.code).not.toBe(0);
  expect(r.out).toMatch(/\(fail\) increment \[parity\]/);
  expect(r.out).toContain("parity: step 1 differs");
  expect(r.out).toContain('"state":{"count":2}');
});

test("guard: loads, then a denial fails the step", async () => {
  const app = await session({ command: host("g"), guard: fakeLib });
  await app.do("Increment");
  await expect(app.do("Net")).rejects.toThrow("network guard: denied ipv4 93.184.216.34 80");
  await app.close().catch(() => {});
});

test("guard: missing library and missing loaded line are errors", async () => {
  await expect(session({ command: host("g"), guard: join(tmp, "nope.so") })).rejects.toThrow("guard library not found");
  await expect(session({ command: host("g", "1", "noload"), guard: fakeLib })).rejects.toThrow("guard did not load");
});

test("protocol errors, expectError and precondition timeout", async () => {
  const app = await session({ command: host("p"), timeoutMs: 100 });
  await expect(app.do("Nope")).rejects.toThrow("action at $.action");
  const e = await app.expectError(() => app.do("Nope"), "action");
  expect(e.path).toBe("$.action");
  await expect(app.expectError(() => app.do("Increment"), "action")).rejects.toThrow("request succeeded");
  await expect(app.precondition("Elsewhere")).rejects.toThrow(/precondition screen "Elsewhere" not met after 100ms; last screen: .*"count":1/);
  await app.close();
});
