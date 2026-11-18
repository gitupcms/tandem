package inventory.core

import tandem.Introspectable
import tandem.IntrospectableActions

/**
 * ProductDetail view model. Starts from the list's copy of [product]; every adjustment goes through
 * the service and its result arrives as a message.
 */
class ProductDetailModel(product: Product, private val service: InventoryService) {
    @Introspectable
    data class State(
        val id: String,
        val title: String,
        val sku: String,
        val price: String,
        val quantity: Int,
        val message: String,
    )

    @IntrospectableActions
    sealed interface Action {
        data object Increment : Action

        data object Decrement : Action
    }

    internal sealed interface Message {
        data class View(val action: Action) : Message

        data class Adjusted(val delta: Int, val result: ServiceResult<Unit>) : Message

        data class Refused(val message: String) : Message
    }

    var state: State = State(product.id, product.title, product.sku, product.price, product.quantity, "")
        private set

    fun send(action: Action) {
        state = update(state, Message.View(action))
    }

    private fun update(state: State, message: Message): State = when (message) {
        is Message.View -> when (message.action) {
            Action.Increment -> update(state, Message.Adjusted(1, service.adjust(state.id, 1)))
            Action.Decrement -> if (state.quantity <= 0) {
                update(state, Message.Refused("Quantity cannot go below zero"))
            } else {
                update(state, Message.Adjusted(-1, service.adjust(state.id, -1)))
            }
        }

        is Message.Adjusted -> when (message.result) {
            is ServiceResult.Success -> state.copy(quantity = state.quantity + message.delta, message = "")
            is ServiceResult.Failure -> state.copy(message = message.result.error.message ?: "")
        }

        is Message.Refused -> state.copy(message = message.message)
    }
}
