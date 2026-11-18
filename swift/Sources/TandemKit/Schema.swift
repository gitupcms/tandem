/// Input schema: the JSON Schema subset in spec "Input schemas". Every object schema is closed.
public indirect enum Schema {
    case object([(String, Schema)], required: [String] = [])
    case array(Schema)
    case string(enum: [String]? = nil)
    case integer
    case boolean

    public static let maxInt: Int64 = 9_007_199_254_740_991

    public var json: JSON {
        switch self {
        case .object(let props, let required):
            var o: [(String, JSON)] = [("type", .string("object")), ("properties", .object(props.map { ($0.0, $0.1.json) }))]
            if !required.isEmpty { o.append(("required", .array(required.map(JSON.string)))) }
            return .object(o)
        case .array(let items): return .object([("type", .string("array")), ("items", items.json)])
        case .string(let values):
            var o: [(String, JSON)] = [("type", .string("string"))]
            if let values { o.append(("enum", .array(values.map(JSON.string)))) }
            return .object(o)
        case .integer: return .object([("type", .string("integer"))])
        case .boolean: return .object([("type", .string("boolean"))])
        }
    }

    /// Throws the first error: wrong fields in the value's own order, then missing required fields in sorted order.
    public func validate(_ v: JSON, path: String) throws {
        let fail = { (m: String) in ProtocolError(code: "input", message: m, path: path) }
        if case .null = v { throw fail("null is not allowed") }
        switch (self, v) {
        case (.object(let props, let required), .object(let pairs)):
            for (k, x) in pairs {
                guard let s = props.first(where: { same($0.0, k) })?.1 else {
                    throw ProtocolError(code: "input", message: "unknown property", path: "\(path).\(k)")
                }
                try s.validate(x, path: "\(path).\(k)")
            }
            let missing = required.filter { r in !pairs.contains { same($0.0, r) } }
            if let k = missing.min(by: { $0.utf16.lexicographicallyPrecedes($1.utf16) }) {
                throw ProtocolError(code: "input", message: "missing required property", path: "\(path).\(k)")
            }
        case (.object, _): throw fail("expected object")
        case (.array(let items), .array(let xs)):
            for (n, x) in xs.enumerated() { try items.validate(x, path: "\(path)[\(n)]") }
        case (.array, _): throw fail("expected array")
        case (.string(let values), .string(let s)):
            if let values, !values.contains(where: { same($0, s) }) { throw fail("not an allowed value") }
        case (.string, _): throw fail("expected string")
        case (.integer, _): if JSON.int(v) == nil { throw fail("expected integer") }
        case (.boolean, .bool): break
        case (.boolean, _): throw fail("expected boolean")
        }
    }
}

extension JSON {
    /// A protocol integer: no fraction, no exponent, within ±(2^53-1).
    public static func int(_ v: JSON?) -> Int64? {
        guard case .integer(let n)? = v, (-Schema.maxInt...Schema.maxInt).contains(n) else { return nil }
        return n
    }
}
