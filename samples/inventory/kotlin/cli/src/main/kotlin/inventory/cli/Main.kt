package inventory.cli

import inventory.core.AppModel
import tandem.Session
import tandem.runHost
import java.nio.file.Files
import java.nio.file.Path
import kotlin.system.exitProcess

fun main(args: Array<String>) {
    val fixture = args.firstOrNull()
    if (fixture == null) {
        System.err.println("usage: cli <fixture> [--socket <port>]   (e.g. default, empty, fetch-error, adjust-locked)")
        exitProcess(64)
    }
    val root = System.getenv("INVENTORY_FIXTURES")?.let(Path::of)
        ?: Path.of("samples", "inventory", "fixtures")
    val directory = root.resolve(fixture)
    if (!Files.isDirectory(directory)) {
        System.err.println("unknown fixture \"$fixture\": no directory at $directory")
        exitProcess(64)
    }
    val app = AppModel(FixtureInventoryService(directory))
    runHost(args.drop(1)) { Session("kotlin") { app.toNode() } }
}
