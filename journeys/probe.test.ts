import { expect } from "bun:test";
import { journey } from "tandem-kit";

const PROBE = { app: "probe", fixture: "probe" };

journey("increment then add", async app => {
  await app.precondition("Probe");
  await app.do("Increment", undefined, s => s.state.count === 1);
  await app.do("Add", { amount: 2 }, s => s.state.count === 3);
}, PROBE);

journey("back to home and reset the app", async app => {
  await app.precondition("Probe");
  expect(app.screen!.path).toEqual(["App", "Stack", "Probe"]);
  await app.do("Back", undefined, s => s.name === "Home");
  expect(app.screen!.path).toEqual(["App", "Stack", "Home"]);
  await app.do("Reset", undefined, s => s.name === "Probe"); // App's Reset rebuilds the stack
  expect(app.screen!.path).toEqual(["App", "Stack", "Probe"]);
}, PROBE);

journey("reset zeroes the counter", async app => {
  await app.precondition("Probe");
  await app.do("Add", { amount: 5 }, s => s.state.count === 5);
  await app.do("Rename", { label: "kept" });
  await app.do("Reset", undefined, s => s.state.count === 0);
  expect(app.screen!.state.label).toBe("kept"); // Probe's own Reset shadows App's and only zeroes count
}, PROBE);

journey("invalid input leaves state alone", async app => {
  await app.precondition("Probe");
  await app.do("Add", { amount: 1 }, s => s.state.count === 1);
  const e = await app.expectError(() => app.do("Add", { amount: "2" }), "input");
  expect(e.path).toBe("$.input.amount");
  await app.precondition(s => s.state.count === 1);
}, PROBE);

journey("unknown action is an action error", async app => {
  await app.precondition("Probe");
  await app.expectError(() => app.do("Nope"), "action");
}, PROBE);
