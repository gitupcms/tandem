import Foundation
import TandemKit

let args = CommandLine.arguments.dropFirst()
guard args.first == "probe" else {
    FileHandle.standardError.write(Data("unknown fixture set: \(args.first ?? "(none)"); this host only knows \"probe\"\n".utf8))
    exit(64)
}
let app = AppNode(AppModel())
Host.run(args.dropFirst()) { Session(root: app, platform: "swift") }
