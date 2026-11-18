import TandemKit

// Node adapters: map view model state to JSON and validated input to messages. No business rules here.

final class AppNode: Node {
    let app: AppModel
    init(_ app: AppModel) { self.app = app }

    let name = "App"
    var actions: [Action] { [Action("Reset") { [app] _ in app.update(.reset) }] }
    var child: Node? { StackNode(app) }
}

final class StackNode: Node {
    let app: AppModel
    init(_ app: AppModel) { self.app = app }

    let name = "Stack"
    var actions: [Action] { [Action("Back") { [app] _ in app.update(.back) }] }
    var child: Node? {
        switch app.stack.last! {
        case .home(let m): return HomeNode(m)
        case .probe(let m): return ProbeNode(m)
        }
    }
}

final class HomeNode: Node {
    let model: HomeModel
    init(_ model: HomeModel) { self.model = model }

    let name = "Home"
    var state: JSON { .object(model.values.map { ($0.0, .integer($0.1)) }) }
}

final class ProbeNode: Node {
    let model: ProbeModel
    init(_ model: ProbeModel) { self.model = model }

    let name = "Probe"

    var state: JSON {
        .object([
            ("count", .integer(model.count)),
            ("label", .string(model.label)),
            ("meta", .object([
                ("tag", .string(model.meta.tag)),
                ("level", .integer(model.meta.level)),
                ("pinned", .bool(model.meta.pinned)),
            ])),
            ("mode", .string(model.mode)),
            ("tags", .array(model.tags.map(JSON.string))),
        ])
    }

    var actions: [Action] {
        let m = model
        return [
            Action("Increment") { _ in m.update(.increment) },
            Action("Add", input: .object([("amount", .integer)], required: ["amount"])) { i in
                m.update(.add(JSON.int(i?["amount"]) ?? 0))
            },
            Action("Rename", input: .object([("label", .string())])) { i in
                m.update(.rename(i?["label"]?.stringValue ?? ""))
            },
            Action("SetMode", input: .object([("mode", .string(enum: ["off", "on", "café"]))], required: ["mode"])) { i in
                m.update(.setMode(i?["mode"]?.stringValue ?? ""))
            },
            Action("Tag", input: .object([("tags", .array(.string()))], required: ["tags"])) { i in
                guard case .array(let xs)? = i?["tags"] else { return }
                m.update(.setTags(xs.compactMap(\.stringValue)))
            },
            Action("Configure", input: .object([
                ("meta", .object([("tag", .string()), ("level", .integer), ("pinned", .boolean)], required: ["tag"])),
            ], required: ["meta"])) { i in
                let meta = i?["meta"]
                m.update(.configure(Meta(tag: meta?["tag"]?.stringValue ?? "", level: JSON.int(meta?["level"]) ?? 0, pinned: meta?["pinned"]?.boolValue ?? false)))
            },
            Action("Reset") { _ in m.update(.zero) },
        ]
    }
}
