// Fake Tandem host for SDK tests: `bun fake-host.ts <platform> [step] [noload]`. step is how much Increment adds,
// "noload" skips the guard's "loaded" line, action "Net" logs a guard denial.
const platform = process.argv[2] ?? "fake";
const step = Number(process.argv[3] ?? 1);
const log = process.env.TANDEM_GUARD_LOG;
const append = (line: string) => log && require("node:fs").appendFileSync(log, line + "\n");
if (process.env.LD_PRELOAD || process.env.DYLD_INSERT_LIBRARIES) if (process.argv[4] !== "noload") append(`loaded ${process.pid}`);

let count = 0;
const screen = () => ({ ok: true, screen: { actions: [{ from: "Fake", input: null, name: "Increment" }], name: "Fake", path: ["Fake"], state: { count } } });
for await (const line of require("node:readline").createInterface({ input: process.stdin })) {
  const req = JSON.parse(line);
  let res: object;
  if (req.op === "hello") res = { ok: true, platform, version: 1 };
  else if (req.op === "ls") res = screen();
  else if (req.action === "Increment") (count += step), (res = screen());
  else if (req.action === "Net") append("denied ipv4 93.184.216.34 80"), (res = screen());
  else res = { error: { code: "action", message: `no ${req.action} on ${platform}`, path: "$.action" }, ok: false };
  console.log(JSON.stringify(res));
}
