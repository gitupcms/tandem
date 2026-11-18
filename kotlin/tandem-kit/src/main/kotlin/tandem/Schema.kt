package tandem

/** The input-schema subset from spec "Input schemas". Object schemas are always closed. */
class Schema private constructor(
    val type: String,
    val properties: Map<String, Schema> = emptyMap(),
    val required: List<String> = emptyList(),
    val items: Schema? = null,
    val enum: List<String>? = null,
) {
    companion object {
        val string = Schema("string")
        val integer = Schema("integer")
        val boolean = Schema("boolean")
        fun enum(vararg values: String) = Schema("string", enum = values.toList())
        fun array(items: Schema) = Schema("array", items = items)
        fun obj(vararg properties: Pair<String, Schema>, required: List<String> = emptyList()) =
            Schema("object", linkedMapOf(*properties), required)
    }

    fun toJson(): Json = Json.Obj(buildMap {
        put("type", Json.Str(type))
        if (type == "object") put("properties", Json.Obj(properties.mapValues { it.value.toJson() }))
        if (required.isNotEmpty()) put("required", Json.Arr(required.map(Json::Str)))
        items?.let { put("items", it.toJson()) }
        enum?.let { values -> put("enum", Json.Arr(values.map(Json::Str))) }
    })

    /** Throws [ProtocolError] with code `input` at the first wrong spot, in the value's own key order. */
    fun check(value: Json, path: String) {
        fun fail(message: String, at: String = path): Nothing = throw ProtocolError("input", message, at)
        if (value == Json.Null) fail("null is not allowed")
        when (type) {
            "object" -> {
                val obj = value as? Json.Obj ?: fail("expected object")
                for ((k, v) in obj.fields) (properties[k] ?: fail("unknown property", "$path.$k")).check(v, "$path.$k")
                required.sorted().firstOrNull { it !in obj.fields }?.let { fail("missing required property", "$path.$it") }
            }
            "array" -> (value as? Json.Arr ?: fail("expected array")).items.forEachIndexed { n, x -> items!!.check(x, "$path[$n]") }
            "string" -> {
                val s = value.string ?: fail("expected string")
                if (enum != null && s !in enum) fail("not an allowed value")
            }
            "integer" -> value.long?.takeIf { it in -Json.MAX_SAFE..Json.MAX_SAFE } ?: fail("expected integer")
            "boolean" -> value.bool ?: fail("expected boolean")
            else -> error("bad schema type $type")
        }
    }
}
