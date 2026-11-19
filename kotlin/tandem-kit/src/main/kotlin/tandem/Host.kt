package tandem

import java.util.ServiceLoader
import kotlin.system.exitProcess

/**
 * The debug-only socket transport (spec "Transport"). It lives in the separate `tandem-socket`
 * module and is found through [ServiceLoader], so a release classpath without that module has none.
 */
interface DebugTransport {
    /** Serves a fresh session from [newSession] per connection on 127.0.0.1:[port]; returns when stdin ends. */
    fun serve(port: Int, newSession: () -> Session)
}

/**
 * Runs a host given the arguments after the fixture name: none for stdio, or `--socket <port>`.
 * Exits with 64 on bad arguments or when no socket transport is on the classpath.
 */
fun runHost(args: List<String>, newSession: () -> Session) {
    if (args.isEmpty()) return serveLines(newSession())
    val port = args.getOrNull(1)?.toIntOrNull()
    if (args.size != 2 || args[0] != "--socket" || port == null || port !in 0..65535) {
        System.err.println("usage: <host> <fixture> [--socket <port>]")
        exitProcess(64)
    }
    val transport = ServiceLoader.load(DebugTransport::class.java).firstOrNull()
    if (transport == null) {
        System.err.println("--socket is only available in debug builds")
        exitProcess(64)
    }
    transport.serve(port, newSession)
}
