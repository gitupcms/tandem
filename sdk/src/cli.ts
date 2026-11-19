#!/usr/bin/env bun
// `tandem`: drive one Tandem host for one run, from a shell or an agent. No session is kept: every call starts the
// host fresh and replays the steps in order. Fixtures are deterministic, so replaying them is safe.
import { loadConfig, parityDiff, ProtocolError, session, type Step } from "./index.ts";

const USAGE = `tandem — drive a Tandem host once, without writing a test

usage: tandem run [--app A] [--platform P | --parity] [--fixture F] [--socket] [step ...]
  step: ls | do <Action> [<json input>]        e.g. tandem run do Open '{"id":"x"}'

  --app A        app from tandem.config.json (default: the first one)
  --platform P   platform to run (default: the app's first one)
  --parity       run every platform of the app and diff their answers
  --fixture F    fixture set handed to the host as its first argument
  --socket       drive the host over its debug socket instead of stdio
  --help         this text`;

class UsageError extends Error {}

type Options = { app?: string; platform?: string; parity: boolean; fixture?: string; socket: boolean };
type StepSpec = { label: string; request: object };

const out = (line: string) => process.stdout.write(line + "\n");
const isStepStart = (token: string) => token === "ls" || token === "do";

/** Splits `do Open {"id":"x"}` given as one shell argument into "do", "Open", '{"id":"x"}'. */
function expand(arg: string): string[] {
  const m = arg.match(/^do\s+([\s\S]*)$/);
  if (!m) return [arg];
  const rest = m[1].trimStart();
  const space = rest.search(/\s/);
  if (space < 0) return ["do", rest];
  const input = rest.slice(space).trim();
  return input ? ["do", rest.slice(0, space), input] : ["do", rest.slice(0, space)];
}

function parseJson(text: string, action: string): unknown {
  try {
    return JSON.parse(text);
  } catch (e) {
    throw new UsageError(`invalid JSON for "do ${action}": ${(e as Error).message}`);
  }
}

function parseSteps(tokens: string[]): StepSpec[] {
  const steps: StepSpec[] = [];
  for (let i = 0; i < tokens.length; i++) {
    const token = tokens[i];
    if (token === "ls") {
      steps.push({ label: "ls", request: { op: "ls" } });
      continue;
    }
    if (token !== "do") throw new UsageError(`unknown step "${token}" (expected "ls" or "do <Action> [<json input>]")`);
    const action = tokens[++i];
    if (action === undefined || isStepStart(action)) throw new UsageError(`"do" needs an action name`);
    let input: unknown;
    const next = tokens[i + 1];
    if (next !== undefined && !isStepStart(next)) {
      input = parseJson(next, action);
      i++;
    }
    steps.push({
      label: input === undefined ? `do ${action}` : `do ${action} ${JSON.stringify(input)}`,
      request: input === undefined ? { op: "do", action } : { op: "do", action, input },
    });
  }
  return steps;
}

function parseArgv(argv: string[]): { options: Options; steps: StepSpec[] } {
  const options: Options = { parity: false, socket: false };
  let i = 0;
  for (; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "--") {
      i++;
      break;
    }
    if (!arg.startsWith("--")) break;
    const eq = arg.indexOf("=");
    const flag = eq < 0 ? arg : arg.slice(0, eq);
    const inline = eq < 0 ? undefined : arg.slice(eq + 1);
    const value = () => {
      if (inline !== undefined) return inline;
      const v = argv[++i];
      if (v === undefined) throw new UsageError(`${flag} needs a value`);
      return v;
    };
    if (flag === "--parity" || flag === "--socket") {
      if (inline !== undefined) throw new UsageError(`${flag} takes no value`);
      if (flag === "--parity") options.parity = true;
      else options.socket = true;
      continue;
    }
    if (flag === "--app") options.app = value();
    else if (flag === "--platform") options.platform = value();
    else if (flag === "--fixture") options.fixture = value();
    else throw new UsageError(`unknown option "${flag}"`);
  }
  return { options, steps: parseSteps(argv.slice(i).flatMap(expand)) };
}

/** Runs the steps against a fresh host, printing each step and the host's raw reply line. */
async function drive(
  command: string[],
  guard: string | undefined,
  steps: StepSpec[],
  socket: boolean,
): Promise<{ transcript: Step[]; protocolError: boolean }> {
  const app = await session({ command, guard, socket });
  let protocolError = false;
  try {
    for (const step of steps) {
      out(`> ${step.label}`);
      const before = app.transcript.length;
      let error: unknown;
      try {
        await app.send(step.request);
      } catch (e) {
        error = e;
      }
      if (app.transcript.length > before) out(app.transcript[before].response);
      if (error) {
        if (!(error instanceof ProtocolError)) throw error;
        protocolError = true;
        break;
      }
    }
  } catch (e) {
    await app.close().catch(() => {});
    throw e;
  }
  try {
    await app.close();
  } catch (e) {
    if (!protocolError) throw e;
  }
  return { transcript: app.transcript, protocolError };
}

async function main(argv: string[]): Promise<number> {
  const { options, steps } = parseArgv(argv);
  const { apps, guard } = loadConfig();
  const appName = options.app ?? Object.keys(apps)[0];
  if (!appName) throw new UsageError("the config has no apps");
  const platforms = apps[appName];
  if (!platforms) throw new UsageError(`no app "${appName}" (apps: ${Object.keys(apps).join(", ")})`);
  if (options.parity && options.platform) throw new UsageError("--parity runs every platform; drop --platform");
  const names = options.parity ? Object.keys(platforms) : [options.platform ?? Object.keys(platforms)[0]];
  for (const name of names) {
    if (!platforms[name]) throw new UsageError(`no platform "${name}" for app "${appName}" (platforms: ${Object.keys(platforms).join(", ")})`);
  }

  const wanted = steps.length ? steps : [{ label: "ls", request: { op: "ls" } }];
  const command = (name: string) => (options.fixture ? [...platforms[name], options.fixture] : platforms[name]);
  const transcripts: Record<string, Step[]> = {};
  let failed = false;
  for (const name of names) {
    if (options.parity) out(`## ${name}`);
    const run = await drive(command(name), guard, wanted, options.socket);
    transcripts[name] = run.transcript;
    if (run.protocolError) failed = true;
  }
  if (options.parity) {
    const diff = parityDiff(transcripts);
    if (diff) {
      out(diff);
      failed = true;
    }
  }
  return failed ? 1 : 0;
}

const argv = process.argv.slice(2);
if (!argv.length || argv[0] === "help" || argv.includes("--help") || argv.includes("-h")) {
  out(USAGE);
} else if (argv[0] !== "run") {
  process.stderr.write(`tandem: unknown command "${argv[0]}" (try "tandem help")\n`);
  process.exitCode = 2;
} else {
  main(argv.slice(1)).then(
    code => {
      process.exitCode = code;
    },
    e => {
      process.stderr.write(`tandem: ${e instanceof Error ? e.message : e}\n`);
      process.exitCode = e instanceof UsageError ? 2 : 1;
    },
  );
}
