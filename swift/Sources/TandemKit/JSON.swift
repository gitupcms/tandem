/// A JSON value. Objects keep their key order; numbers that are not plain integers keep their lexeme.
public enum JSON {
    case object([(String, JSON)])
    case array([JSON])
    case string(String)
    case integer(Int64)
    case number(String)
    case bool(Bool)
    case null

    public subscript(key: String) -> JSON? {
        guard case .object(let pairs) = self else { return nil }
        return pairs.first { same($0.0, key) }?.1
    }

    public var stringValue: String? { if case .string(let s) = self { return s } else { return nil } }
    public var boolValue: Bool? { if case .bool(let b) = self { return b } else { return nil } }
}

/// Exact code-unit equality. Swift's `==` on String uses canonical equivalence, which the protocol forbids.
public func same(_ a: String, _ b: String) -> Bool { a.utf8.elementsEqual(b.utf8) }

public struct JSONError: Error { public let message: String }

public let maxDepth = 64

extension JSON {
    /// Strict decoder: valid UTF-8 only, no BOM, no duplicate keys, depth <= 64, no lone surrogates.
    public static func decode<C: Collection>(_ bytes: C) throws -> JSON where C.Element == UInt8 {
        let b = Array(bytes)
        if b.starts(with: [0xEF, 0xBB, 0xBF]) { throw JSONError(message: "byte order mark") }
        if transcode(b.makeIterator(), from: UTF8.self, to: UTF32.self, stoppingOnError: true, into: { _ in }) {
            throw JSONError(message: "invalid UTF-8")
        }
        var p = Parser(b: b)
        let v = try p.value(depth: 1)
        p.ws()
        if p.i != b.count { throw JSONError(message: "trailing characters") }
        return v
    }
}

private struct Parser {
    let b: [UInt8]
    var i = 0

    func bad(_ m: String) -> JSONError { JSONError(message: m) }
    var peek: UInt8? { i < b.count ? b[i] : nil }

    mutating func ws() {
        while let c = peek, c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D { i += 1 }
    }

    mutating func value(depth: Int) throws -> JSON {
        ws()
        guard let c = peek else { throw bad("unexpected end") }
        switch c {
        case UInt8(ascii: "{"), UInt8(ascii: "["):
            if depth > maxDepth { throw bad("nested too deep") }
            return try c == UInt8(ascii: "{") ? object(depth) : array(depth)
        case UInt8(ascii: "\""): return .string(try string())
        case UInt8(ascii: "t"): try word("true"); return .bool(true)
        case UInt8(ascii: "f"): try word("false"); return .bool(false)
        case UInt8(ascii: "n"): try word("null"); return .null
        default: return try number()
        }
    }

    mutating func word(_ w: String) throws {
        guard b[i...].starts(with: w.utf8) else { throw bad("unexpected character") }
        i += w.utf8.count
    }

    mutating func object(_ depth: Int) throws -> JSON {
        i += 1
        var pairs: [(String, JSON)] = []
        var seen = Set<[UInt8]>()
        ws()
        if peek == UInt8(ascii: "}") { i += 1; return .object(pairs) }
        while true {
            ws()
            guard peek == UInt8(ascii: "\"") else { throw bad("expected key") }
            let k = try string()
            ws()
            guard peek == UInt8(ascii: ":") else { throw bad("expected colon") }
            i += 1
            if !seen.insert(Array(k.utf8)).inserted { throw bad("duplicate key") }
            pairs.append((k, try value(depth: depth + 1)))
            ws()
            guard let sep = peek else { throw bad("unexpected end") }
            i += 1
            if sep == UInt8(ascii: "}") { return .object(pairs) }
            if sep != UInt8(ascii: ",") { throw bad("expected comma") }
        }
    }

    mutating func array(_ depth: Int) throws -> JSON {
        i += 1
        var items: [JSON] = []
        ws()
        if peek == UInt8(ascii: "]") { i += 1; return .array(items) }
        while true {
            items.append(try value(depth: depth + 1))
            ws()
            guard let sep = peek else { throw bad("unexpected end") }
            i += 1
            if sep == UInt8(ascii: "]") { return .array(items) }
            if sep != UInt8(ascii: ",") { throw bad("expected comma") }
        }
    }

    mutating func hex4() throws -> UInt32 {
        var n: UInt32 = 0
        for _ in 0..<4 {
            // Not UInt32(_:radix:): it accepts a leading sign.
            guard let c = peek, let d = Character(Unicode.Scalar(c)).hexDigitValue else { throw bad("bad \\u escape") }
            n = n << 4 | UInt32(d)
            i += 1
        }
        return n
    }

    mutating func string() throws -> String {
        i += 1
        var out: [UInt8] = []
        while true {
            guard let c = peek else { throw bad("unterminated string") }
            i += 1
            if c == UInt8(ascii: "\"") { return String(decoding: out, as: UTF8.self) }
            if c < 0x20 { throw bad("raw control character in string") }
            if c != UInt8(ascii: "\\") { out.append(c); continue }
            guard let e = peek else { throw bad("unterminated string") }
            i += 1
            let simple: [UInt8: UInt8] = [0x22: 0x22, 0x5C: 0x5C, 0x2F: 0x2F, 0x62: 0x08, 0x66: 0x0C, 0x6E: 0x0A, 0x72: 0x0D, 0x74: 0x09]
            if let s = simple[e] { out.append(s); continue }
            guard e == UInt8(ascii: "u") else { throw bad("bad escape") }
            var scalar = try hex4()
            if (0xDC00...0xDFFF).contains(scalar) { throw bad("lone surrogate") }
            if (0xD800...0xDBFF).contains(scalar) {
                guard b[i...].starts(with: "\\u".utf8) else { throw bad("lone surrogate") }
                i += 2
                let low = try hex4()
                guard (0xDC00...0xDFFF).contains(low) else { throw bad("lone surrogate") }
                scalar = 0x10000 + ((scalar - 0xD800) << 10) + (low - 0xDC00)
            }
            out.append(contentsOf: String(Unicode.Scalar(scalar)!).utf8)
        }
    }

    mutating func number() throws -> JSON {
        let start = i
        func digits(_ p: inout Parser) -> Int {
            let s = p.i
            while let c = p.peek, c >= 0x30 && c <= 0x39 { p.i += 1 }
            return p.i - s
        }
        if peek == UInt8(ascii: "-") { i += 1 }
        if peek == UInt8(ascii: "0") { i += 1 } else if digits(&self) == 0 { throw bad("unexpected character") }
        let intEnd = i
        if peek == UInt8(ascii: ".") { i += 1; if digits(&self) == 0 { throw bad("bad fraction") } }
        if peek == UInt8(ascii: "e") || peek == UInt8(ascii: "E") {
            i += 1
            if peek == UInt8(ascii: "+") || peek == UInt8(ascii: "-") { i += 1 }
            if digits(&self) == 0 { throw bad("bad exponent") }
        }
        let raw = String(decoding: b[start..<i], as: UTF8.self)
        if i == intEnd, let n = Int64(raw) { return .integer(n) }
        return .number(raw)
    }
}

extension JSON {
    /// Canonical form (spec "Canonical output"): no whitespace, keys sorted by UTF-16 code units, minimal escaping.
    public var canonical: String {
        var out = ""
        write(to: &out)
        return out
    }

    private func write(to out: inout String) {
        switch self {
        case .null: out += "null"
        case .bool(let v): out += v ? "true" : "false"
        case .integer(let n): out += String(n)
        case .number(let raw): out += raw
        case .string(let s): JSON.escape(s, into: &out)
        case .array(let items):
            out += "["
            for (n, v) in items.enumerated() {
                if n > 0 { out += "," }
                v.write(to: &out)
            }
            out += "]"
        case .object(let pairs):
            out += "{"
            for (n, (k, v)) in pairs.sorted(by: { $0.0.utf16.lexicographicallyPrecedes($1.0.utf16) }).enumerated() {
                if n > 0 { out += "," }
                JSON.escape(k, into: &out)
                out += ":"
                v.write(to: &out)
            }
            out += "}"
        }
    }

    private static func escape(_ s: String, into out: inout String) {
        out += "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case _ where u.value < 0x20:
                let h = String(u.value, radix: 16)
                out += "\\u" + String(repeating: "0", count: 4 - h.count) + h
            default: out.unicodeScalars.append(u)
            }
        }
        out += "\""
    }
}
