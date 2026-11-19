package tandem

import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.io.OutputStream

/**
 * The line reader every transport shares: splits [input] into lines per spec "Framing", answers each
 * through [session], and returns at end of input (stdin EOF or a socket half-close).
 */
fun serveLines(session: Session, input: InputStream = System.`in`, output: OutputStream = System.out) {
    val src = input.buffered()
    val out = output.buffered()
    val line = ByteArrayOutputStream()
    // Room for a full line plus one CR; anything beyond is already too long, so stop buffering it.
    val keep = Session.MAX_LINE + 2
    var pending = false

    fun answer() {
        var bytes = line.toByteArray()
        if (bytes.size <= Session.MAX_LINE + 1 && bytes.lastOrNull() == '\r'.code.toByte()) bytes = bytes.copyOf(bytes.size - 1)
        out.write(session.handle(bytes).toByteArray(Charsets.UTF_8))
        out.write('\n'.code)
        out.flush()
        line.reset()
        pending = false
    }

    while (true) {
        val b = src.read()
        if (b < 0) break
        if (b == '\n'.code) answer()
        else {
            pending = true
            if (line.size() < keep) line.write(b)
        }
    }
    if (pending) answer()
}
