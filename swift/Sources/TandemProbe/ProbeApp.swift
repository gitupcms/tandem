// The probe app from conformance/cases.json, written the way a real app would: view models own state and
// business rules in `update`; TandemKit only sees them through the node adapters in ProbeNodes.swift.

struct Meta {
    var tag = ""
    var level: Int64 = 0
    var pinned = false
}

final class ProbeModel {
    enum Msg {
        case increment
        case add(Int64)
        case rename(String)
        case setMode(String)
        case setTags([String])
        case configure(Meta)
        case zero
    }

    var count: Int64 = 0
    var label = ""
    var meta = Meta()
    var mode = "off"
    var tags: [String] = []

    func update(_ msg: Msg) {
        switch msg {
        case .increment: count += 1
        case .add(let n): count += n
        case .rename(let s): label = s
        case .setMode(let m): mode = m
        case .setTags(let t): tags = t
        case .configure(let m): meta = m
        case .zero: count = 0
        }
    }
}

/// Home has fixed state chosen to exercise canonical key order.
final class HomeModel {
    let values: [(String, Int64)] = [("a", 1), ("B", 2), ("é", 3), ("｡", 4), ("😀", 5)]
}

enum Screen {
    case home(HomeModel)
    case probe(ProbeModel)
}

final class AppModel {
    enum Msg {
        case back
        case reset
    }

    private(set) var stack: [Screen] = []

    init() { update(.reset) }

    func update(_ msg: Msg) {
        switch msg {
        case .back: if stack.count > 1 { stack.removeLast() }
        case .reset: stack = [.home(HomeModel()), .probe(ProbeModel())]
        }
    }
}
