# Tandem

Tests and AI agents read your app's screens as JSON state and press their actions, with no simulator. One shared test suite runs against both the iOS (Swift) and Android (Kotlin) cores and fails unless both give the same answer.

Status: early. See [PLAN.md](PLAN.md).

- Protocol: [spec/protocol.md](spec/protocol.md).
- Tooling and test SDK: Bun + TypeScript.
- Kits: Swift (Linux and macOS) and Kotlin (JVM).

## CLI

`tandem` drives one host for one run, with no test file and no session: every call starts the host fresh and replays the steps. Fixtures are deterministic, so replaying them is safe.

```sh
bun sdk/src/cli.ts run --app inventory --fixture default ls 'do Open {"id":"gid://shop/Product/1"}'
bun sdk/src/cli.ts run --app inventory --parity do Increment   # every platform, diffed
```

Each step prints `> <step>` then the host's reply line, unchanged. Exit 0 when all steps pass, 1 on a protocol error or a parity difference, 2 on bad usage (`tandem help`).

Based on the architecture in Shopify Engineering's [Reflex](https://shopify.engineering/reflex) article. Not affiliated with Shopify. MIT licence, see [LICENSE](LICENSE).
