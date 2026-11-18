# Tandem

Tests and AI agents read your app's screens as JSON state and press their actions, with no simulator. One shared test suite runs against both the iOS (Swift) and Android (Kotlin) cores and fails unless both give the same answer.

Status: early. See [PLAN.md](PLAN.md).

- Protocol: [spec/protocol.md](spec/protocol.md).
- Tooling and test SDK: Bun + TypeScript.
- Kits: Swift (Linux and macOS) and Kotlin (JVM).

Based on the architecture in Shopify Engineering's [Reflex](https://shopify.engineering/reflex) article. Not affiliated with Shopify. MIT licence, see [LICENSE](LICENSE).
