package inventory.cli

import inventory.core.AppModel
import inventory.core.AppModel.StackEntry
import inventory.core.AppModel.Tab
import inventory.core.AppModelActionIntrospection
import inventory.core.toJson
import tandem.Node

/**
 * Adapts the view models to kit nodes. A node only reports state and forwards actions to its view
 * model; all rules stay in Core. The state JSON and the action schemas come from tandem-ksp, so this
 * file only wires the tree (which child) and picks which generated action belongs on which node.
 */
fun AppModel.toNode(): Node {
    val actions = AppModelActionIntrospection.actions { send(it) }
    fun pick(vararg names: String): List<tandem.Action> = actions.filter { it.name in names }
    return Node(
        name = "App",
        child = Node(
            name = "Tabs",
            actions = pick("SelectTab"),
            child = when (state.tab) {
                Tab.inventory -> Node(
                    name = "InventoryStack",
                    actions = pick("Back"),
                    child = when (val entry = state.stack.last()) {
                        StackEntry.List -> Node(
                            name = "ProductList",
                            state = list.state.toJson(),
                            actions = pick("Open", "Retry"),
                        )

                        is StackEntry.Detail -> Node(
                            name = "ProductDetail",
                            state = entry.model.state.toJson(),
                            actions = pick("Increment", "Decrement"),
                        )
                    },
                )

                Tab.settings -> Node(
                    name = "Settings",
                    state = settings.state.toJson(),
                    actions = pick("SetThreshold"),
                )
            },
        ),
    )
}
