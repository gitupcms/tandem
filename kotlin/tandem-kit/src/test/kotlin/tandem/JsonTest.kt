package tandem

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

class JsonTest {
    private fun decode(s: String) = Json.decode(s.toByteArray())

    @Test fun keepsNumberLexemes() {
        assertEquals(Json.Integer(-3), decode("-3"))
        assertEquals(Json.Num("1.0"), decode("1.0"))
        assertEquals(Json.Num("1e2"), decode("1e2"))
    }

    @Test fun rejectsInvalidInput() {
        for (s in listOf("", " ", "01", "{\"a\":1,\"a\":2}", "[\"\\ud800\"]", "\"\\udc00\\ud800\"", "\uFEFF{}", "[".repeat(65) + "]".repeat(65)))
            assertFailsWith<JsonError>(s) { decode(s) }
        assertEquals(Json.Str("\ud83d\ude00"), decode("\"\\ud83d\\ude00\""))
    }

    @Test fun canonicalSortsByUtf16AndEscapesMinimally() {
        val v = decode("{\"\uff61\":1,\"\ud83d\ude00\":2,\"b\":\"\\u0001/\\u007f\",\"B\":true}")
        assertEquals("{\"B\":true,\"b\":\"\\u0001/\u007f\",\"\ud83d\ude00\":2,\"\uff61\":1}", v.canonical())
    }

    @Test fun schemaReportsFirstErrorInRequestOrderThenMissingSorted() {
        val s = Schema.obj("z" to Schema.integer, "a" to Schema.string, "m" to Schema.boolean, required = listOf("z", "a"))
        fun path(input: String) = assertFailsWith<ProtocolError> { s.check(decode(input), "$") }.path
        assertEquals("$.m", path("{\"m\":1,\"a\":2}"))
        assertEquals("$.a", path("{\"m\":true}"))
    }
}
