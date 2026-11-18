package tandem

class ProtocolError(val code: String, message: String, val path: String? = null) : Exception(message)

/**
 * One client session (spec/protocol.md). [root] is called for every request, so the tree always
 * reflects the view models' current state.
 */
class Session(private val platform: String, private val root: () -> Node) {
    private var greeted = false

    /** One request line (without LF) in, one canonical response line (without LF) out. */
    fun handle(line: ByteArray): String = try {
        respond(line).canonical()
    } catch (e: ProtocolError) {
        Json.Obj(buildMap {
            put("error", Json.Obj(buildMap {
                put("code", Json.Str(e.code))
                put("message", Json.Str(e.message ?: ""))
                e.path?.let { put("path", Json.Str(it)) }
            }))
            put("ok", Json.Bool(false))
            if (e.code == "version") put("supported", Json.Arr(listOf(Json.Integer(1))))
        }).canonical()
    }

    private fun respond(line: ByteArray): Json {
        if (line.size > MAX_LINE) throw ProtocolError("json", "line too long")
        val req = try {
            Json.decode(line)
        } catch (e: JsonError) {
            throw ProtocolError("json", e.message ?: "invalid JSON")
        }
        val fields = (req as? Json.Obj ?: throw ProtocolError("request", "request must be an object")).fields
        val op = fields["op"]?.string ?: throw ProtocolError("request", "op must be a string", "$.op")
        val allowed = OPS[op] ?: throw ProtocolError("request", "unknown op", "$.op")
        for ((k, v) in fields) {
            if (k == "op") continue
            if (k !in allowed) throw ProtocolError("request", "unknown field", "$.$k")
            val ok = when (k) {
                "version" -> v.long?.let { it in -Json.MAX_SAFE..Json.MAX_SAFE } == true
                "action" -> v is Json.Str
                else -> v is Json.Obj
            }
            if (!ok) throw ProtocolError("request", "$k has the wrong type", "$.$k")
        }
        val missing = when (op) { "hello" -> "version"; "do" -> "action"; else -> null }
        if (missing != null && missing !in fields) throw ProtocolError("request", "$missing is required", "$.$missing")

        if (op != "hello" && !greeted) throw ProtocolError("handshake", "send hello first")
        when (op) {
            "hello" -> {
                if (fields.getValue("version").long != 1L) throw ProtocolError("version", "unsupported version", "$.version")
                greeted = true
                return Json.obj("ok" to Json.Bool(true), "platform" to Json.Str(platform), "version" to Json.Integer(1))
            }
            "do" -> {
                val name = fields.getValue("action").string
                val (_, action) = actions(focusChain()).firstOrNull { it.second.name == name }
                    ?: throw ProtocolError("action", "no such action on the focused screen", "$.action")
                val input = fields["input"]
                val schema = action.input
                if (schema == null) {
                    if (input != null) throw ProtocolError("input", "action takes no input", "$.input")
                    action.perform(null)
                } else {
                    // Check fully before acting, so a failed request changes nothing.
                    val value = input ?: Json.obj()
                    schema.check(value, "$.input")
                    action.perform(value)
                }
            }
        }
        return Json.obj("ok" to Json.Bool(true), "screen" to screen())
    }

    private fun focusChain(): List<Node> = generateSequence(root()) { it.child }.toList()

    // Own actions first, then lent ones nearest ancestor first; the nearest owner of a name wins.
    private fun actions(chain: List<Node>): List<Pair<Node, Action>> {
        val seen = HashSet<String>()
        return chain.asReversed().flatMap { node -> node.actions.map { node to it } }.filter { seen.add(it.second.name) }
    }

    private fun screen(): Json {
        val chain = focusChain()
        val focused = chain.last()
        return Json.obj(
            "actions" to Json.Arr(actions(chain).map { (from, a) ->
                Json.obj("from" to Json.Str(from.name), "input" to (a.input?.toJson() ?: Json.Null), "name" to Json.Str(a.name))
            }),
            "name" to Json.Str(focused.name),
            "path" to Json.Arr(chain.map { Json.Str(it.name) }),
            "state" to focused.state,
        )
    }

    companion object {
        const val MAX_LINE = 1 shl 20
        private val OPS = mapOf("hello" to setOf("version"), "ls" to emptySet(), "do" to setOf("action", "input"))
    }
}
