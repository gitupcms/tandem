---
name: tandem-check
description: Run a Tandem app's journeys on every platform and explain each failure - which platform, which step, and why. Use after changing app code, when CI fails on journeys, or when a parity test fails.
---

# Check the journeys

1. Build both headless hosts and the guard (the project's build commands; in the Tandem repo see `.github/workflows/ci.yml`).
2. `bun test journeys`. `TANDEM_PLATFORM=swift` or `kotlin` runs one side only.

## Read the failure

| Failure | Meaning | Look at |
| --- | --- | --- |
| `[swift]` or `[kotlin]` fails with `... not met after Nms; last screen: {...}` | that platform did not reach the expected state | the last screen in the message, then that platform's view model |
| protocol error (`action`, `input`) in a platform test | the screen does not offer that action, or its input schema differs | `tandem run ... ls` on the step before |
| `[parity]` fails with `step N differs` | both platforms ran, but answered differently | the two lines shown; the one that disagrees with the journey's intent is wrong |
| `[parity]` says `<platform> did not start` | that platform's test failed first | fix that test first |
| `network guard: denied ...` | the host tried to reach the network | the service it used; hosts must use fixtures |
| `host exited` / `did not answer` | the host crashed or hung | its stderr in the test output |

Reproduce with `tandem run --app <app> --fixture <f> --parity <steps>`.

## Fix

Fix the platform that is wrong. Change the shared journey only when the intended behaviour changed, and then say so. Report: failing test, cause, fix, and the final `bun test` result.
