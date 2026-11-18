public struct ProtocolError: Error {
    public let code: String
    public let message: String
    public let path: String?

    public init(code: String, message: String, path: String? = nil) {
        self.code = code
        self.message = message
        self.path = path
    }
}

/// One client session: request line bytes in, response line out (without the LF).
public final class Session {
    public static let maxLine = 1 << 20
    public static let version: Int64 = 1

    let root: Node
    let platform: String
    var greeted = false

    public init(root: Node, platform: String) {
        self.root = root
        self.platform = platform
    }

    public func respond<C: Collection>(_ line: C) -> String where C.Element == UInt8 {
        do {
            return try request(line).canonical
        } catch let e as ProtocolError {
            var err: [(String, JSON)] = [("code", .string(e.code)), ("message", .string(e.message))]
            if let path = e.path { err.append(("path", .string(path))) }
            var out: [(String, JSON)] = [("error", .object(err)), ("ok", .bool(false))]
            if e.code == "version" { out.append(("supported", .array([.integer(Session.version)]))) }
            return JSON.object(out).canonical
        } catch {
            return JSON.object([("error", .object([("code", .string("json")), ("message", .string("\(error)"))])), ("ok", .bool(false))]).canonical
        }
    }

    private static let fields: [String: [String]] = ["hello": ["version"], "ls": [], "do": ["action", "input"]]

    private func request<C: Collection>(_ line: C) throws -> JSON where C.Element == UInt8 {
        if line.count > Session.maxLine { throw ProtocolError(code: "json", message: "line too long") }
        let req: JSON
        do { req = try JSON.decode(line) } catch let e as JSONError { throw ProtocolError(code: "json", message: e.message) }

        guard case .object(let pairs) = req else { throw ProtocolError(code: "request", message: "request must be an object") }
        guard case .string(let op)? = req["op"] else { throw ProtocolError(code: "request", message: "op must be a string", path: "$.op") }
        guard let known = Session.fields.first(where: { same($0.key, op) }) else {
            throw ProtocolError(code: "request", message: "unknown op", path: "$.op")
        }
        for (k, v) in pairs where !same(k, "op") {
            let bad = { (m: String) in ProtocolError(code: "request", message: m, path: "$.\(k)") }
            guard let field = known.value.first(where: { same($0, k) }) else { throw bad("unknown field") }
            switch (field, v) {
            case ("version", _): if JSON.int(v) == nil { throw bad("version must be an integer") }
            case ("action", .string), ("input", .object): break
            case ("action", _): throw bad("action must be a string")
            default: throw bad("input must be an object")
            }
        }
        // Each op has at most one required field, so sorted order is trivial.
        let required = known.key == "hello" ? "version" : known.key == "do" ? "action" : nil
        if let r = required, req[r] == nil { throw ProtocolError(code: "request", message: "missing \(r)", path: "$.\(r)") }

        if known.key != "hello" && !greeted { throw ProtocolError(code: "handshake", message: "send hello first") }
        switch known.key {
        case "hello":
            guard JSON.int(req["version"]) == Session.version else {
                throw ProtocolError(code: "version", message: "unsupported version", path: "$.version")
            }
            greeted = true
            return .object([("ok", .bool(true)), ("platform", .string(platform)), ("version", .integer(Session.version))])
        case "do":
            guard case .string(let name)? = req["action"],
                  let (_, action) = offered().first(where: { same($0.1.name, name) }) else {
                throw ProtocolError(code: "action", message: "no such action on the focused screen", path: "$.action")
            }
            let input = req["input"]
            if let schema = action.input {
                // Validate fully before acting, so a failed request changes nothing. Omitted input counts as {}.
                let value = input ?? .object([])
                try schema.validate(value, path: "$.input")
                action.perform(value)
            } else {
                if input != nil { throw ProtocolError(code: "input", message: "action takes no input", path: "$.input") }
                action.perform(nil)
            }
        default: break
        }
        return .object([("ok", .bool(true)), ("screen", screen())])
    }

    /// Root to focused screen.
    private func path() -> [Node] {
        var nodes = [root]
        while let c = nodes.last!.child { nodes.append(c) }
        return nodes
    }

    /// Own actions first, then lent ones nearest ancestor first; the nearest owner of a name wins.
    private func offered() -> [(Node, Action)] {
        var out: [(Node, Action)] = []
        for node in path().reversed() {
            for a in node.actions where !out.contains(where: { same($0.1.name, a.name) }) { out.append((node, a)) }
        }
        return out
    }

    private func screen() -> JSON {
        let nodes = path()
        return .object([
            ("actions", .array(offered().map { node, a in
                .object([("from", .string(node.name)), ("input", a.input?.json ?? .null), ("name", .string(a.name))])
            })),
            ("name", .string(nodes.last!.name)),
            ("path", .array(nodes.map { .string($0.name) })),
            ("state", nodes.last!.state),
        ])
    }
}
