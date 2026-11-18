package inventory.core

/**
 * Root view model: owns the tab and the inventory stack, forwards screen actions, and mirrors shared
 * facts (quantity, threshold) onto the list through messages. [update] is the only place its state changes.
 */
class AppModel(private val service: InventoryService) {

    enum class Tab(val wire: String) {
        Inventory("inventory"),
        Settings("settings"),
        ;

        companion object {
            fun fromWire(value: String): Tab? = entries.firstOrNull { it.wire == value }
        }
    }

    /** One level of the inventory stack; the detail level keeps its own view model. */
    sealed interface StackEntry {
        data object List : StackEntry

        data class Detail(val model: ProductDetailModel) : StackEntry
    }

    data class State(val tab: Tab, val stack: List<StackEntry>)

    /** Everything a screen can ask for, across the whole app. */
    sealed interface Action {
        data class Open(val id: String) : Action

        data object Retry : Action

        data object Increment : Action

        data object Decrement : Action

        data object Back : Action

        data class SelectTab(val tab: String) : Action

        data class SetThreshold(val value: Int) : Action
    }

    internal sealed interface Message {
        data class View(val action: Action) : Message
    }

    val settings = SettingsModel()

    val list = ProductListModel(service, settings.state.lowStockThreshold)

    var state: State = State(Tab.Inventory, listOf(StackEntry.List))
        private set

    fun send(action: Action) {
        state = update(state, Message.View(action))
    }

    private fun update(state: State, message: Message): State = when (message) {
        is Message.View -> view(state, message.action)
    }

    private fun view(state: State, action: Action): State = when (action) {
        is Action.Open -> {
            val product = list.product(action.id)
            if (product == null) state
            else state.copy(stack = state.stack + StackEntry.Detail(ProductDetailModel(product, service)))
        }

        Action.Retry -> {
            list.send(ProductListModel.Action.Retry)
            state
        }

        Action.Increment -> adjust(state, ProductDetailModel.Action.Increment)
        Action.Decrement -> adjust(state, ProductDetailModel.Action.Decrement)

        Action.Back -> if (state.stack.size > 1) state.copy(stack = state.stack.dropLast(1)) else state

        is Action.SelectTab -> Tab.fromWire(action.tab)?.let { state.copy(tab = it) } ?: state

        is Action.SetThreshold -> {
            val before = settings.state.lowStockThreshold
            settings.send(SettingsModel.Action.SetThreshold(action.value))
            val after = settings.state.lowStockThreshold
            if (after != before) list.apply(ProductListModel.Message.ThresholdChanged(after))
            state
        }
    }

    /** Sends [action] to the focused detail screen and mirrors its quantity back onto the list. */
    private fun adjust(state: State, action: ProductDetailModel.Action): State {
        val model = (state.stack.lastOrNull() as? StackEntry.Detail)?.model ?: return state
        model.send(action)
        list.apply(ProductListModel.Message.QuantityChanged(model.state.id, model.state.quantity))
        return state
    }
}
