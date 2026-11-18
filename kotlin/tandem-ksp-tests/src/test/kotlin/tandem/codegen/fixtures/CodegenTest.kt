package tandem.codegen.fixtures

import tandem.Json
import tandem.Schema
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/**
 * Drives the code `tandem-ksp` generated for [Fixtures.kt], one case per row of the type-mapping
 * table in `.orkestra/f7-ortak.md`.
 */
class CodegenTest {

    private val inner = Inner("x", 2)

    private val state = State(
        text = "hello",
        count = 3,
        total = 9007199254740991L,
        active = true,
        colour = Colour.green,
        inner = inner,
        rows = listOf(Row("a", true)),
        notes = listOf("n1", "n2"),
        maybeText = null,
        maybeInner = null,
        maybeCount = null,
    )

    @Test
    fun `state writes every property with its own name`() {
        assertEquals(
            Json.obj(
                "text" to Json.Str("hello"),
                "count" to Json.Integer(3),
                "total" to Json.Integer(9007199254740991L),
                "active" to Json.Bool(true),
                "colour" to Json.Str("green"),
                "inner" to Json.obj("label" to Json.Str("x"), "count" to Json.Integer(2)),
                "rows" to Json.arr(listOf(Json.obj("id" to Json.Str("a"), "active" to Json.Bool(true)))),
                "notes" to Json.arr(listOf(Json.Str("n1"), Json.Str("n2"))),
            ),
            state.toJson(),
        )
    }

    @Test
    fun `null state properties are omitted, not written as null`() {
        val empty = state.toJson() as Json.Obj
        assertNull(empty["maybeText"])
        assertNull(empty["maybeInner"])
        assertNull(empty["maybeCount"])

        val filled = state.copy(maybeText = "t", maybeInner = Inner("i", 7), maybeCount = 9).toJson() as Json.Obj
        assertEquals(Json.Str("t"), filled["maybeText"])
        assertEquals(Json.obj("label" to Json.Str("i"), "count" to Json.Integer(7)), filled["maybeInner"])
        assertEquals(Json.Integer(9), filled["maybeCount"])
    }

    @Test
    fun `actions keep declaration order and name each subclass as it is`() {
        val sent = mutableListOf<Action>()
        val actions = ActionIntrospection.actions { sent += it }
        assertEquals(
            listOf("Rename", "Resize", "Paint", "Nest", "Tag", "Note", "Reset"),
            actions.map { it.name },
        )
    }

    @Test
    fun `input schemas follow the mapping table`() {
        val actions = ActionIntrospection.actions {}.associateBy { it.name }

        assertEquals(
            Schema.obj("text" to Schema.string, required = listOf("text")).toJson(),
            actions.getValue("Rename").input?.toJson(),
        )
        assertEquals(
            Schema.obj("count" to Schema.integer, "total" to Schema.integer, required = listOf("count", "total")).toJson(),
            actions.getValue("Resize").input?.toJson(),
        )
        assertEquals(
            Schema.obj("colour" to Schema.enum("red", "green"), required = listOf("colour")).toJson(),
            actions.getValue("Paint").input?.toJson(),
        )
        assertEquals(
            Schema.obj(
                "inner" to Schema.obj("label" to Schema.string, "count" to Schema.integer, required = listOf("label", "count")),
                required = listOf("inner"),
            ).toJson(),
            actions.getValue("Nest").input?.toJson(),
        )
        assertEquals(
            Schema.obj(
                "tags" to Schema.array(Schema.string),
                "rows" to Schema.array(
                    Schema.obj("id" to Schema.string, "active" to Schema.boolean, required = listOf("id", "active")),
                ),
                required = listOf("tags", "rows"),
            ).toJson(),
            actions.getValue("Tag").input?.toJson(),
        )
        assertEquals(
            Schema.obj("maybeText" to Schema.string).toJson(),
            actions.getValue("Note").input?.toJson(),
        )
        assertNull(actions.getValue("Reset").input)
    }

    /** Runs one action the way the kit does after checking its input, and returns what was sent. */
    private fun perform(name: String, input: Json?): Action? {
        var sent: Action? = null
        ActionIntrospection.actions { sent = it }.first { it.name == name }.perform(input)
        return sent
    }

    @Test
    fun `string and integer inputs are read back`() {
        assertEquals(Action.Rename("hi"), perform("Rename", Json.obj("text" to Json.Str("hi"))))
        assertEquals(
            Action.Resize(Int.MAX_VALUE, 9007199254740991L),
            perform(
                "Resize",
                Json.obj("count" to Json.Integer(Int.MAX_VALUE.toLong()), "total" to Json.Integer(9007199254740991L)),
            ),
        )
        assertEquals(Action.Note(null), perform("Note", Json.obj()))
        assertEquals(Action.Note("t"), perform("Note", Json.obj("maybeText" to Json.Str("t"))))
    }

    @Test
    fun `boolean, enum and state inputs are built back into values`() {
        assertEquals(Action.Paint(Colour.red), perform("Paint", Json.obj("colour" to Json.Str("red"))))
        assertEquals(
            Action.Nest(Inner("n", 4)),
            perform("Nest", Json.obj("inner" to Json.obj("label" to Json.Str("n"), "count" to Json.Integer(4)))),
        )
        assertEquals(
            Action.Tag(listOf("a"), listOf(Row("r", false))),
            perform(
                "Tag",
                Json.obj(
                    "tags" to Json.arr(listOf(Json.Str("a"))),
                    "rows" to Json.arr(listOf(Json.obj("id" to Json.Str("r"), "active" to Json.Bool(false)))),
                ),
            ),
        )
        assertEquals(Action.Reset, perform("Reset", null))
    }
}
