package tandem

import java.nio.ByteBuffer
import java.nio.charset.CharacterCodingException
import java.nio.charset.CodingErrorAction

/** A JSON value. Objects keep key order; numbers that are not plain integers keep their lexeme. */
sealed interface Json {
    data class Obj(val fields: Map<String, Json>) : Json {
        operator fun get(key: String): Json? = fields[key]
    }
    data class Arr(val items: List<Json>) : Json
    data class Str(val value: String) : Json
    data class Integer(val value: Long) : Json
    /** A number with a fraction, an exponent or outside Long range, e.g. `1.0` or `1e2`. */
    data class Num(val raw: String) : Json
    data class Bool(val value: Boolean) : Json
    data object Null : Json

    val string get() = (this as? Str)?.value
    val long get() = (this as? Integer)?.value
    val bool get() = (this as? Bool)?.value

    companion object {
        const val MAX_SAFE = 9007199254740991L
        const val MAX_DEPTH = 64

        fun obj(vararg fields: Pair<String, Json>) = Obj(linkedMapOf(*fields))
        fun arr(items: List<Json>) = Arr(items)

        /** Strict decode of one UTF-8 line; throws [JsonError]. */
        fun decode(bytes: ByteArray): Json {
            if (bytes.size >= 3 && bytes[0] == 0xEF.toByte() && bytes[1] == 0xBB.toByte() && bytes[2] == 0xBF.toByte())
                throw JsonError("byte order mark")
            val text = try {
                Charsets.UTF_8.newDecoder()
                    .onMalformedInput(CodingErrorAction.REPORT)
                    .onUnmappableCharacter(CodingErrorAction.REPORT)
                    .decode(ByteBuffer.wrap(bytes)).toString()
            } catch (_: CharacterCodingException) {
                throw JsonError("invalid UTF-8")
            }
            return Parser(text).document()
        }
    }
}

class JsonError(message: String) : Exception(message)

private class Parser(val text: String) {
    var i = 0

    fun bad(message: String): Nothing = throw JsonError(message)

    fun document(): Json {
        val v = value(1)
        ws()
        if (i != text.length) bad("trailing characters")
        return v
    }

    fun ws() {
        while (i < text.length && text[i] in " \t\n\r") i++
    }

    fun value(depth: Int): Json {
        ws()
        val c = text.getOrNull(i) ?: bad("unexpected end")
        return when {
            c == '{' || c == '[' -> container(c, depth)
            c == '"' -> Json.Str(string())
            text.startsWith("true", i) -> { i += 4; Json.Bool(true) }
            text.startsWith("false", i) -> { i += 5; Json.Bool(false) }
            text.startsWith("null", i) -> { i += 4; Json.Null }
            else -> number()
        }
    }

    fun container(open: Char, depth: Int): Json {
        if (depth > Json.MAX_DEPTH) bad("nested too deep")
        i++
        val close = if (open == '{') '}' else ']'
        val fields = LinkedHashMap<String, Json>()
        val items = ArrayList<Json>()
        ws()
        if (text.getOrNull(i) == close) i++
        else while (true) {
            if (open == '{') {
                ws()
                if (text.getOrNull(i) != '"') bad("expected key")
                val key = string()
                ws()
                if (text.getOrNull(i++) != ':') bad("expected colon")
                if (key in fields) bad("duplicate key")
                fields[key] = value(depth + 1)
            } else items += value(depth + 1)
            ws()
            val sep = text.getOrNull(i++)
            if (sep == close) break
            if (sep != ',') bad("expected comma")
        }
        return if (open == '{') Json.Obj(fields) else Json.Arr(items)
    }

    fun string(): String {
        i++
        val out = StringBuilder()
        while (true) {
            val c = text.getOrNull(i++) ?: bad("unterminated string")
            when {
                c == '"' -> break
                c < ' ' -> bad("raw control character in string")
                c != '\\' -> out.append(c)
                else -> when (val e = text.getOrNull(i++)) {
                    '"', '\\', '/' -> out.append(e)
                    'b' -> out.append('\b')
                    'f' -> out.append('\u000C')
                    'n' -> out.append('\n')
                    'r' -> out.append('\r')
                    't' -> out.append('\t')
                    'u' -> {
                        val hex = text.substring(i, minOf(i + 4, text.length))
                        if (hex.length != 4 || !hex.all { it.isHexDigit() }) bad("bad escape")
                        out.append(hex.toInt(16).toChar())
                        i += 4
                    }
                    else -> bad("bad escape")
                }
            }
        }
        // Raw text came from valid UTF-8, so only \u escapes can leave a lone surrogate.
        var k = 0
        while (k < out.length) {
            val ch = out[k]
            if (ch.isHighSurrogate() && out.getOrNull(k + 1)?.isLowSurrogate() == true) k += 2
            else if (ch.isSurrogate()) bad("lone surrogate")
            else k++
        }
        return out.toString()
    }

    fun number(): Json {
        val m = NUMBER.matchAt(text, i) ?: bad("unexpected character")
        i = m.range.last + 1
        val raw = m.value
        if (m.groups[2] == null && m.groups[3] == null) raw.toLongOrNull()?.let { return Json.Integer(it) }
        return Json.Num(raw)
    }

    companion object {
        val NUMBER = Regex("-?(0|[1-9][0-9]*)(\\.[0-9]+)?([eE][+-]?[0-9]+)?")
    }
}

private fun Char.isHexDigit() = this in '0'..'9' || this in 'a'..'f' || this in 'A'..'F'

/** Canonical form from spec "Canonical output": no whitespace, keys sorted by UTF-16 code units. */
fun Json.canonical(): String = StringBuilder().also { write(this, it) }.toString()

private fun write(v: Json, out: StringBuilder) {
    when (v) {
        Json.Null -> out.append("null")
        is Json.Bool -> out.append(v.value)
        is Json.Integer -> out.append(v.value)
        is Json.Num -> throw IllegalArgumentException("non-integer number in output: ${v.raw}")
        is Json.Str -> writeString(v.value, out)
        is Json.Arr -> {
            out.append('[')
            v.items.forEachIndexed { n, x -> if (n > 0) out.append(','); write(x, out) }
            out.append(']')
        }
        is Json.Obj -> {
            out.append('{')
            // String.compareTo compares UTF-16 code units, which is what the spec asks for.
            v.fields.keys.sorted().forEachIndexed { n, k ->
                if (n > 0) out.append(',')
                writeString(k, out)
                out.append(':')
                write(v.fields.getValue(k), out)
            }
            out.append('}')
        }
    }
}

private fun writeString(s: String, out: StringBuilder) {
    out.append('"')
    for (c in s) when (c) {
        '"' -> out.append("\\\"")
        '\\' -> out.append("\\\\")
        '\b' -> out.append("\\b")
        '\u000C' -> out.append("\\f")
        '\n' -> out.append("\\n")
        '\r' -> out.append("\\r")
        '\t' -> out.append("\\t")
        else -> if (c < ' ') out.append("\\u%04x".format(c.code)) else out.append(c)
    }
    out.append('"')
}
