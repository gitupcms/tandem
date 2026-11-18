package inventory.core

import tandem.Introspectable
import tandem.IntrospectableActions

/** Settings view model. The threshold itself is shared by mirroring it onto the list through a message. */
class SettingsModel {
    @Introspectable
    data class State(val lowStockThreshold: Int, val message: String)

    @IntrospectableActions
    sealed interface Action {
        data class SetThreshold(val value: Int) : Action
    }

    internal sealed interface Message {
        data class View(val action: Action) : Message

        data class Applied(val value: Int) : Message

        data class Rejected(val message: String) : Message
    }

    var state: State = State(DEFAULT_THRESHOLD, "")
        private set

    fun send(action: Action) {
        state = update(state, Message.View(action))
    }

    private fun update(state: State, message: Message): State = when (message) {
        is Message.View -> when (val action = message.action) {
            is Action.SetThreshold -> if (action.value in MIN..MAX) {
                update(state, Message.Applied(action.value))
            } else {
                update(state, Message.Rejected("Threshold must be between 0 and 1000"))
            }
        }

        is Message.Applied -> state.copy(lowStockThreshold = message.value, message = "")
        is Message.Rejected -> state.copy(message = message.message)
    }

    companion object {
        const val DEFAULT_THRESHOLD = 3
        private const val MIN = 0
        private const val MAX = 1000
    }
}
