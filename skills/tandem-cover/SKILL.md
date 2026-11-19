---
name: tandem-cover
description: Find what no Tandem journey checks yet and write shared journeys for it. Use when asked to add tests, raise coverage, or cover a new screen or action in a Tandem app.
---

# Cover the gaps

## 1. List what exists

- Screens and actions: run the `tandem-explore` walk, or read the app's map if one exists.
- What journeys use: `grep -rnoE 'do\("[A-Za-z]+"|precondition\("[A-Za-z]+"' journeys/`.

A gap is an action no journey performs, an outcome no journey asserts (each branch of a view model's update: success, refused, service failure), or a fixture no journey starts from.

## 2. Write journeys

One journey per user goal, not per action. Each one:
- picks a fixture (`{ app, fixture }`) and starts with `precondition`,
- drives with `do(action, input, expect)`: the predicate says what must be true after, and the SDK polls until it is,
- asserts exact state with `expect(...).toEqual(...)` at the points that matter,
- uses `expectError` for protocol errors only. A rule the app enforces is `ok:true` plus a message in state.

No sleeps, no platform checks inside a journey. If a step only works on one platform, that is a parity bug to report, not to work around.

## 3. Run

`bun test journeys/<file>`; every journey yields `[swift]`, `[kotlin]`, `[parity]`. A new journey that fails on one platform found a bug: report it with the `tandem-check` output instead of weakening the assertion.
