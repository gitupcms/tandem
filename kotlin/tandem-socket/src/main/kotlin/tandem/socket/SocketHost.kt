package tandem.socket

import tandem.DebugTransport
import tandem.Session
import tandem.serveLines
import java.net.InetAddress
import java.net.ServerSocket
import kotlin.concurrent.thread

/** Debug-only loopback transport (spec "Transport"); registered for [java.util.ServiceLoader]. */
class SocketHost : DebugTransport {
    override fun serve(port: Int, newSession: () -> Session) {
        val server = ServerSocket(port, 50, InetAddress.getByName("127.0.0.1"))
        System.err.println("listening 127.0.0.1:${server.localPort}")
        // One connection at a time; later ones wait in the backlog. The app's state lives outside the session.
        thread(isDaemon = true, name = "tandem-socket") {
            while (true) {
                val socket = server.accept()
                try {
                    socket.use {
                        // Half-close by the client is end of input: the last line is answered, then we close.
                        serveLines(newSession(), it.getInputStream(), it.getOutputStream())
                    }
                } catch (e: java.io.IOException) {
                    System.err.println("connection dropped: ${e.message}")
                }
            }
        }
        // The host lives until its stdin ends.
        System.`in`.transferTo(java.io.OutputStream.nullOutputStream())
    }
}
