package tandem.codegen.fixtures

import tandem.Introspectable
import tandem.IntrospectableActions
import tandem.IntrospectableEnum

/** An introspectable enum: the constant's name is the wire value. */
@IntrospectableEnum
enum class Colour { red, green }

/** A state type used both as a state field and as an action input. */
@Introspectable
data class Inner(val label: String, val count: Int)

/** One row inside a state list. */
@Introspectable
data class Row(val id: String, val active: Boolean)

/** One property per row of the mapping table in `.orkestra/f7-ortak.md`. */
@Introspectable
data class State(
    val text: String,
    val count: Int,
    val total: Long,
    val active: Boolean,
    val colour: Colour,
    val inner: Inner,
    val rows: List<Row>,
    val notes: List<String>,
    val maybeText: String?,
    val maybeInner: Inner?,
    val maybeCount: Int?,
)

/** One action per row of the mapping table, plus a parameterless one. */
@IntrospectableActions
sealed interface Action {
    data class Rename(val text: String) : Action

    data class Resize(val count: Int, val total: Long) : Action

    data class Paint(val colour: Colour) : Action

    data class Nest(val inner: Inner) : Action

    data class Tag(val tags: List<String>, val rows: List<Row>) : Action

    data class Note(val maybeText: String?) : Action

    data object Reset : Action
}
