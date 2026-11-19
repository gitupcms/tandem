---
name: tandem-start
description: Add Tandem to an app that exists in Swift and Kotlin, so one Bun journey drives both platforms and checks they answer the same. Use when a project has no tandem.config.json yet, or the user asks to set up shared tests, Tandem, or parity tests.
---

# Start Tandem in an app

Goal: one journey in `journeys/` that runs green on both platforms plus its parity test. Do the smallest slice first (one screen, one action), then stop and report.

## 1. Check the shape of the app

Tandem needs business logic that runs without UI. For each platform, find:
- the view models (state + actions + an update function), and
- where they call services (network, storage, clock).

If logic lives in views or controllers, tell the user. Moving it into view models comes first; do not hide it behind the node layer.

## 2. Add the kits

Until Tandem 0.1.0 is published, use the repository directly (git submodule or a local checkout):
- Swift: depend on the `swift/` package by path; products `TandemKit` (host) and `TandemIntrospection` (macros).
- Kotlin: `includeBuild("<tandem>/kotlin")` in `settings.gradle.kts`; `dev.tandem:tandem-kit`, `dev.tandem:tandem-annotations`, and `ksp("dev.tandem:tandem-ksp")`.
- Bun: add the repo as a dev dependency so `import { journey } from "tandem-kit"` resolves.

## 3. Make one screen introspectable, on both platforms

- Annotate the screen's view state (`@Introspectable`) and its action type (`@IntrospectableActions`). Names must match across platforms: Swift case `increment` becomes `Increment`; the Kotlin subclass must be called `Increment`.
- Build the tree: root node, any navigators (they lend `Back`, `SelectTab`), the screen. Nodes hold no logic. See `samples/inventory/*/cli` in the Tandem repo.

## 4. Add a headless host per platform

An executable that builds the app with fake services, then runs the kit host. The first argument is a fixture name; load fixture data from files so both platforms read the same data. Unknown fixture: exit 64. No network: the guard will fail the test if anything connects out.

## 5. Config and the first journey

`tandem.config.json` at the project root:

```json
{ "apps": { "app": { "swift": ["path/to/swift/host"], "kotlin": ["path/to/kotlin/host"] } }, "guard": "path/to/libtandemguard.so" }
```

`journeys/first.test.ts`:

```ts
import { expect } from "bun:test";
import { journey } from "tandem-kit";

journey("first screen loads", async app => {
  await app.precondition("Home");
  expect(app.screen!.state).toEqual({ /* what the user sees */ });
}, { fixture: "default" });
```

## 6. Run it

Build both hosts and the guard, then `bun test journeys`. Expect three tests: `[swift]`, `[kotlin]`, `[parity]`. If one fails, use the `tandem-check` skill.

Report: what you added per platform, the test output, and what logic you found outside view models.
