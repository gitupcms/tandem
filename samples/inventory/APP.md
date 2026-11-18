# Inventory sample

A small store-inventory app, built twice: Swift (`swift/`) and Kotlin (`kotlin/`). This file is the contract both follow. The shared journeys in `journeys/inventory.test.ts` check it, and the parity test checks that both answer byte for byte the same.

## Layers

- **Core** (Swift package library / Kotlin JVM module): view models, reducer (`update`), navigation state, domain types. No UI, no host, no stdio, no I/O. Core may depend on the Tandem kit only for the introspection annotations and the code they generate (state JSON, action input schemas and decoding). Services are constructor-injected interfaces.
- **CLI** (executable): depends on Core and TandemKit. Implements the services from fixture files, adapts view models to kit `Node`s, runs the stdio host.
- Each view model: `State`, public `Action` enum dispatched with `send(action)`, internal `Message` (`.view(Action)` plus service results), `update(state, message)` as the only place state changes.

## Services

```
InventoryService
  fetchProducts() -> Result<[Product], ServiceError>
  adjust(productId, delta) -> Result<Unit, ServiceError>   // ServiceError(message)
```

Synchronous in this sample. Results still enter the view model as messages through `update`.

The CLI's fixture service reads `fixtures/<name>/`:
- `products.json`: `{"data":{"products":{"nodes":[Product...]}}}` or `{"errors":[{"message":"..."}]}`. Product: `id`, `title`, `sku`, `price` (string), `quantity` (integer).
- `adjust.json`: `{"data":{"inventoryAdjust":{"userErrors":[{"message":"..."}...]}}}`. Empty `userErrors` means success. A failed fetch or adjust uses the first message.

The fixtures root is `$INVENTORY_FIXTURES` if set, else `samples/inventory/fixtures` relative to the working directory. The CLI's first argument is the fixture name; a missing directory exits 64 with a message on stderr.

## Tree

```
App
└─ Tabs                         lends SelectTab {tab: "inventory"|"settings"} (required)
   ├─ InventoryStack (tab "inventory")   lends Back
   │   ├─ ProductList
   │   └─ ProductDetail  (pushed by Open)
   └─ Settings (tab "settings")
```

Start: tab `inventory`, stack `[ProductList]`, products fetched once at start. Paths: `["App","Tabs","InventoryStack","ProductList"]`, `["App","Tabs","Settings"]`. Switching tabs keeps each tab's state and stack. `App` lends nothing.

Lent action order after the screen's own actions: `Back` (stack, only on the inventory tab), then `SelectTab`.

## Screens

State keys are listed exactly; the canonical encoder sorts them.

### ProductList

State:
- `status`: `"loaded"` or `"failed"`
- `error`: failure message, `""` when loaded
- `products`: array of `{"id","lowStock","quantity","title"}` in fixture order; `lowStock` is `quantity <= settings threshold`. Empty when failed.

Actions, in this order:
1. `Open` `{id: string}` (required): push `ProductDetail` for that product. Unknown id: no change.
2. `Retry` (no input): fetch again and replace `status`, `error`, `products`.

### ProductDetail

State: `id`, `title`, `sku`, `price`, `quantity`, `message` (`""` unless the last action failed).

Actions, in this order:
1. `Increment` (no input): `adjust(id, +1)`. Success: quantity +1, message `""`. Failure: quantity unchanged, message = the error message.
2. `Decrement` (no input): at quantity 0, no service call, message `"Quantity cannot go below zero"`. Otherwise like Increment with -1.

Quantity changes are shared: after `Back`, `ProductList` shows the new quantity and `lowStock`. Opening the same product again shows the current quantity and an empty message.

### Settings

State: `lowStockThreshold` (integer, starts at 3), `message` (`""` unless the last action failed).

Actions:
1. `SetThreshold` `{value: integer}` (required): `0...1000` sets it and clears message. Otherwise unchanged, message `"Threshold must be between 0 and 1000"`.

`Back` at the stack root does nothing.

## Fixtures

| Name | products.json | adjust.json |
| --- | --- | --- |
| `default` | Mug (5), Tote (2), Cap (0) | success |
| `empty` | no products | success |
| `fetch-error` | error `Service unavailable` | success |
| `adjust-locked` | same as default | error `Inventory is locked` |
