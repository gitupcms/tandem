package inventory.cli

import inventory.core.AppModel
import inventory.core.AppModel.StackEntry
import inventory.core.AppModel.Tab
import inventory.core.ProductDetailModel
import tandem.Action as KitAction
import tandem.Json
import tandem.Node
import tandem.Schema

/**
 * Adapts the view models to kit nodes. A node only reports state and forwards actions to its view
 * model; all rules stay in Core.
 */
fun AppModel.toNode(): Node = Node(
    name = "App",
    child = Node(
        name = "Tabs",
        actions = listOf(
            KitAction(
                "SelectTab",
                Schema.obj(
                    "tab" to Schema.enum(Tab.Inventory.wire, Tab.Settings.wire),
                    required = listOf("tab"),
                ),
            ) { input -> send(AppModel.Action.SelectTab(input.field("tab")!!.string!!)) },
        ),
        child = when (state.tab) {
            Tab.Inventory -> inventoryNode()
            Tab.Settings -> settingsNode()
        },
    ),
)

private fun AppModel.inventoryNode(): Node = Node(
    name = "InventoryStack",
    actions = listOf(KitAction("Back") { send(AppModel.Action.Back) }),
    child = when (val entry = state.stack.last()) {
        StackEntry.List -> Node(
            name = "ProductList",
            state = productListState(),
            actions = listOf(
                KitAction("Open", Schema.obj("id" to Schema.string, required = listOf("id"))) {
                    send(AppModel.Action.Open(it.field("id")!!.string!!))
                },
                KitAction("Retry") { send(AppModel.Action.Retry) },
            ),
        )

        is StackEntry.Detail -> Node(
            name = "ProductDetail",
            state = detailState(entry.model),
            actions = listOf(
                KitAction("Increment") { send(AppModel.Action.Increment) },
                KitAction("Decrement") { send(AppModel.Action.Decrement) },
            ),
        )
    },
)

private fun AppModel.settingsNode(): Node = Node(
    name = "Settings",
    state = Json.obj(
        "lowStockThreshold" to Json.Integer(settings.state.lowStockThreshold.toLong()),
        "message" to Json.Str(settings.state.message),
    ),
    actions = listOf(
        KitAction("SetThreshold", Schema.obj("value" to Schema.integer, required = listOf("value"))) {
            send(AppModel.Action.SetThreshold(it.field("value")!!.long!!.toInt()))
        },
    ),
)

private fun AppModel.productListState(): Json = Json.obj(
    "error" to Json.Str(list.state.error),
    "products" to Json.Arr(
        list.state.products.map {
            Json.obj(
                "id" to Json.Str(it.id),
                "lowStock" to Json.Bool(it.lowStock),
                "quantity" to Json.Integer(it.quantity.toLong()),
                "title" to Json.Str(it.title),
            )
        },
    ),
    "status" to Json.Str(list.state.status),
)

private fun detailState(model: ProductDetailModel): Json = Json.obj(
    "id" to Json.Str(model.state.id),
    "message" to Json.Str(model.state.message),
    "price" to Json.Str(model.state.price),
    "quantity" to Json.Integer(model.state.quantity.toLong()),
    "sku" to Json.Str(model.state.sku),
    "title" to Json.Str(model.state.title),
)
