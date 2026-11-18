package tandem.probe

import tandem.Action
import tandem.Json
import tandem.Node
import tandem.Schema

// --- View models: all business rules live in `update`. ---

data class Meta(val tag: String = "", val level: Long = 0, val pinned: Boolean = false)

class ProbeModel {
    var count = 0L; private set
    var label = ""; private set
    var mode = "off"; private set
    var tags = emptyList<String>(); private set
    var meta = Meta(); private set

    sealed interface Msg {
        data object Increment : Msg
        data class Add(val amount: Long) : Msg
        data class Rename(val label: String) : Msg
        data class SetMode(val mode: String) : Msg
        data class SetTags(val tags: List<String>) : Msg
        data class Configure(val meta: Meta) : Msg
        data object Zero : Msg
    }

    fun update(msg: Msg) {
        when (msg) {
            Msg.Increment -> count += 1
            is Msg.Add -> count += msg.amount
            is Msg.Rename -> label = msg.label
            is Msg.SetMode -> mode = msg.mode
            is Msg.SetTags -> tags = msg.tags
            is Msg.Configure -> meta = msg.meta
            Msg.Zero -> count = 0
        }
    }
}

sealed interface Screen {
    data object Home : Screen
    class Probe(val model: ProbeModel = ProbeModel()) : Screen
}

class AppModel {
    var stack: List<Screen> = initial(); private set

    sealed interface Msg {
        data object Back : Msg
        data object Reset : Msg
    }

    fun update(msg: Msg) {
        when (msg) {
            Msg.Back -> if (stack.size > 1) stack = stack.dropLast(1)
            Msg.Reset -> stack = initial()
        }
    }

    private fun initial() = listOf(Screen.Home, Screen.Probe())
}

// --- Kit adapters: report state, forward actions. ---

fun AppModel.node(): Node = Node(
    name = "App",
    actions = listOf(Action("Reset") { update(AppModel.Msg.Reset) }),
    child = Node(
        name = "Stack",
        actions = listOf(Action("Back") { update(AppModel.Msg.Back) }),
        child = when (val top = stack.last()) {
            Screen.Home -> homeNode()
            is Screen.Probe -> top.model.node()
        },
    ),
)

private fun homeNode() = Node(
    name = "Home",
    state = Json.obj(
        "a" to Json.Integer(1),
        "B" to Json.Integer(2),
        "é" to Json.Integer(3),
        "｡" to Json.Integer(4),
        "😀" to Json.Integer(5),
    ),
)

private fun ProbeModel.node(): Node {
    fun send(msg: ProbeModel.Msg): (Json?) -> Unit = { update(msg) }
    // Inputs reach `perform` already checked against the schema, so the casts below cannot fail.
    fun Json?.at(key: String) = (this as Json.Obj)[key]
    return Node(
        name = "Probe",
        state = Json.obj(
            "count" to Json.Integer(count),
            "label" to Json.Str(label),
            "meta" to Json.obj("level" to Json.Integer(meta.level), "pinned" to Json.Bool(meta.pinned), "tag" to Json.Str(meta.tag)),
            "mode" to Json.Str(mode),
            "tags" to Json.Arr(tags.map(Json::Str)),
        ),
        actions = listOf(
            Action("Increment", perform = send(ProbeModel.Msg.Increment)),
            Action("Add", Schema.obj("amount" to Schema.integer, required = listOf("amount"))) {
                update(ProbeModel.Msg.Add(it.at("amount")!!.long!!))
            },
            Action("Rename", Schema.obj("label" to Schema.string)) {
                update(ProbeModel.Msg.Rename(it.at("label")?.string ?: ""))
            },
            Action("SetMode", Schema.obj("mode" to Schema.enum("off", "on", "café"), required = listOf("mode"))) {
                update(ProbeModel.Msg.SetMode(it.at("mode")!!.string!!))
            },
            Action("Tag", Schema.obj("tags" to Schema.array(Schema.string), required = listOf("tags"))) {
                update(ProbeModel.Msg.SetTags((it.at("tags") as Json.Arr).items.map { t -> t.string!! }))
            },
            Action(
                "Configure",
                Schema.obj(
                    "meta" to Schema.obj(
                        "tag" to Schema.string,
                        "level" to Schema.integer,
                        "pinned" to Schema.boolean,
                        required = listOf("tag"),
                    ),
                    required = listOf("meta"),
                ),
            ) {
                val m = it.at("meta")
                update(ProbeModel.Msg.Configure(Meta(m.at("tag")!!.string!!, m.at("level")?.long ?: 0, m.at("pinned")?.bool ?: false)))
            },
            Action("Reset", perform = send(ProbeModel.Msg.Zero)),
        ),
    )
}
