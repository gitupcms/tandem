---
name: tandem-explore
description: Explore a Tandem app through its headless host with the `tandem run` CLI and write down its screens, state and actions. Use before writing journeys, when asked what the app can do, or to reproduce a bug without a device.
---

# Explore an app

The host answers the same requests a journey sends. `tandem run` starts it, replays the steps you give, and prints each raw reply. Every call starts fresh, so pass the whole path from launch each time.

```sh
tandem run --app inventory --fixture default ls
tandem run --app inventory --fixture default ls 'do Open {"id":"gid://shop/Product/1"}' 'do Increment'
tandem run --app inventory --fixture default --parity 'do Open {"id":"gid://shop/Product/1"}'
```

Each reply shows `path` (where you are), `state` (what the user sees) and `actions` (what you can do here, with input schemas; lent actions like `Back` come last).

## How to walk

1. Start with `ls` on each fixture; fixtures are the app's starting worlds (empty, error, normal).
2. Breadth first: for every action on a screen, try it once with valid input and note where you land.
3. Then edges: input at the limits of its schema, actions that should be refused by the app (these answer `ok:true` with a message in state), and protocol errors (`action`, `input`).
4. Use `--parity` on any path that looks platform-sensitive (text, ordering, numbers).

## Write the map

Save it where the user wants (default `journeys/MAP.md`): one section per screen with its path, state keys, actions with inputs, and where each action leads. List anything surprising separately: differences between platforms, states with no way out, actions that do nothing.

Do not change app code while exploring.
