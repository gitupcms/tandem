package inventory.core

/**
 * ProductList view model. Owns the fetched catalog and projects it into the list state.
 * [update] is the only place state changes.
 */
class ProductListModel(
    private val service: InventoryService,
    threshold: Int,
) {
    /** One row of the list; [lowStock] is `quantity <= threshold` at projection time. */
    data class Row(val id: String, val title: String, val quantity: Int, val lowStock: Boolean)

    data class State(val status: String, val error: String, val products: List<Row>)

    sealed interface Action {
        data class Open(val id: String) : Action

        data object Retry : Action
    }

    internal sealed interface Message {
        data class View(val action: Action) : Message

        data class Fetched(val result: ServiceResult<List<Product>>) : Message

        data class ThresholdChanged(val value: Int) : Message

        data class QuantityChanged(val id: String, val quantity: Int) : Message
    }

    var state: State = State(LOADED, "", emptyList())
        private set

    private var catalog: List<Product> = emptyList()
    private var threshold: Int = threshold

    init {
        // Products are fetched once at start; the result still arrives as a message.
        state = update(state, Message.View(Action.Retry))
    }

    fun send(action: Action) {
        state = update(state, Message.View(action))
    }

    internal fun apply(message: Message) {
        state = update(state, message)
    }

    /** The catalog entry for [id], with its current quantity, or null when the list does not know it. */
    fun product(id: String): Product? = catalog.firstOrNull { it.id == id }

    private fun update(state: State, message: Message): State = when (message) {
        is Message.View -> when (val action = message.action) {
            is Action.Retry -> update(state, Message.Fetched(service.fetchProducts()))
            // Pushing the detail screen is navigation, so the App decides; the list itself is unchanged.
            is Action.Open -> state
        }

        is Message.Fetched -> when (val result = message.result) {
            is ServiceResult.Success -> {
                catalog = result.value
                project(LOADED, "")
            }

            is ServiceResult.Failure -> {
                catalog = emptyList()
                project(FAILED, result.error.message ?: "")
            }
        }

        is Message.ThresholdChanged -> {
            threshold = message.value
            project(state.status, state.error)
        }

        is Message.QuantityChanged -> {
            catalog = catalog.map { if (it.id == message.id) it.copy(quantity = message.quantity) else it }
            project(state.status, state.error)
        }
    }

    private fun project(status: String, error: String) = State(
        status = status,
        error = error,
        products = catalog.map { Row(it.id, it.title, it.quantity, it.quantity <= threshold) },
    )

    private companion object {
        const val LOADED = "loaded"
        const val FAILED = "failed"
    }
}
