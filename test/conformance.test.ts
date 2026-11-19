import { describe, expect, test } from "bun:test";
import { once } from "node:events";
import { connect } from "node:net";
import { listeningPort } from "../sdk/src/index.ts";
import { Host, type Probe } from "./reference-host";

type Case = { id: string; rule: string; send?: string[]; sendHex?: string; padLine?: { index: number; bytes: number }; expect: string[] };
const suite: { version: number; about: string; probe: Probe; cases: Case[] } = await Bun.file(`${import.meta.dir}/../conformance/cases.json`).json();

const enc = new TextEncoder();
// TANDEM_HOST="<probe host command>" TANDEM_PLATFORM=swift|kotlin runs the suite against a real host process.
const HOST_CMD = process.env.TANDEM_HOST?.split(" ").filter(Boolean);
const PLATFORM = process.env.TANDEM_PLATFORM ?? "swift";
// TANDEM_SOCKET=1 sends each case over the host's debug socket (a debug build): write all, half-close, read to close.
const SOCKET = process.env.TANDEM_SOCKET === "1";
const run = (bytes: Uint8Array): string => {
  if (!HOST_CMD) return new Host(suite.probe, PLATFORM).run(bytes);
  const p = Bun.spawnSync(HOST_CMD, { stdin: bytes, stdout: "pipe", stderr: "inherit" });
  if (p.exitCode !== 0) throw new Error(`host exited ${p.exitCode}`);
  return p.stdout.toString();
};
async function runSocket(bytes: Uint8Array): Promise<string> {
  const proc = Bun.spawn([...HOST_CMD!, "--socket", "0"], { stdin: "pipe", stdout: "ignore", stderr: "pipe" });
  const sock = connect(await listeningPort(proc), "127.0.0.1");
  const chunks: Buffer[] = [];
  sock.on("data", d => chunks.push(d));
  sock.end(bytes); // node buffers the whole write, then half-closes
  await once(sock, "close");
  proc.stdin.end();
  if ((await proc.exited) !== 0) throw new Error(`host exited ${proc.exitCode}`);
  return Buffer.concat(chunks).toString();
}
const ignoreMessage = (line: string) => line.replace(/^\{"error":\{"code":"([a-z]+)","message":"(?:[^"\\]|\\.)*"/, '{"error":{"code":"$1","message":""');

function input(c: Case): Uint8Array {
  const lines = [...(c.send ?? [])];
  if (c.padLine) {
    const { index, bytes } = c.padLine;
    lines[index] += " ".repeat(bytes - enc.encode(lines[index]).length);
  }
  return Buffer.concat([enc.encode(lines.map(l => l + "\n").join("")), Buffer.from(c.sendHex ?? "", "hex")]);
}

test("cases.json structure", () => {
  expect(suite.version).toBe(1);
  expect(typeof suite.about).toBe("string");
  const ids = suite.cases.map(c => c.id);
  expect(new Set(ids).size).toBe(ids.length);
  for (const c of suite.cases) {
    const keys = Object.keys(c).filter(k => !["id", "rule", "send", "sendHex", "padLine", "expect"].includes(k));
    expect(keys, c.id).toEqual([]);
    expect(c.id).toMatch(/^[a-z0-9-]+\.[a-z0-9-]+$/);
    expect(typeof c.rule).toBe("string");
    expect(c.send === undefined || (Array.isArray(c.send) && c.send.every(s => typeof s === "string" && !s.includes("\n")))).toBe(true);
    expect(c.sendHex === undefined || /^([0-9a-f]{2})+$/.test(c.sendHex)).toBe(true);
    expect(Array.isArray(c.expect) && c.expect.every(s => typeof s === "string" && !s.includes("\n"))).toBe(true);
    if (c.padLine) expect(c.padLine.index).toBeLessThan(c.send!.length);
  }
});

describe("conformance", () => {
  for (const c of suite.cases) {
    test(c.id, async () => {
      const out = SOCKET ? await runSocket(input(c)) : run(input(c));
      const actual = out.split("\n");
      expect(actual.pop()).toBe(""); // every response ends with LF
      expect(actual.map(ignoreMessage)).toEqual(c.expect.map(l => l.replaceAll("{{platform}}", PLATFORM)));
    });
  }
});
