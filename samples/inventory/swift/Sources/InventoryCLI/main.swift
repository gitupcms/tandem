import Foundation
import InventoryCore
import TandemKit

let env = ProcessInfo.processInfo.environment
let root = env["INVENTORY_FIXTURES"] ?? "samples/inventory/fixtures"
let name = CommandLine.arguments.dropFirst().first ?? ""
let dir = URL(fileURLWithPath: root).appendingPathComponent(name)
var isDir: ObjCBool = false
guard !name.isEmpty, FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else {
    FileHandle.standardError.write(Data("unknown fixture: \(name.isEmpty ? "(none)" : name) (looked in \(root))\n".utf8))
    exit(64)
}
let app = appNode(AppModel(service: FixtureService(dir: dir)))
Host.run(CommandLine.arguments.dropFirst(2)) { Session(root: app, platform: "swift") }
