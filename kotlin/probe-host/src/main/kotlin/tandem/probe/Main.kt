package tandem.probe

import tandem.Session
import tandem.runHost
import kotlin.system.exitProcess

fun main(args: Array<String>) {
    val fixture = args.firstOrNull()
    if (fixture != "probe") {
        System.err.println("unknown fixture: ${fixture ?: "(none)"}; this host only knows \"probe\"")
        exitProcess(64)
    }
    val app = AppModel()
    runHost(args.drop(1)) { Session("kotlin") { app.node() } }
}
