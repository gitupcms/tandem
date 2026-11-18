@_exported import TandemKit

/// Generates `IntrospectableValue` for a struct: every stored property is a state key with the same name.
/// Optional properties are left out of the JSON when nil, and are not required in input.
@attached(extension, conformances: IntrospectableValue,
          names: named(introspectionSchema), named(introspectionJSON), named(init(introspected:)))
public macro Introspectable() = #externalMacro(module: "TandemMacros", type: "IntrospectableMacro")

/// Generates `IntrospectableValue` for a `String` raw-value enum: the wire value is the raw value.
@attached(extension, conformances: IntrospectableValue,
          names: named(introspectionSchema), named(introspectionJSON), named(init(introspected:)))
public macro IntrospectableEnum() = #externalMacro(module: "TandemMacros", type: "IntrospectableEnumMacro")

/// Generates `static func actions(_ send:) -> [TandemKit.Action]` for an action enum: one action per case in
/// declaration order, named after the case with its first letter uppercased. Labeled associated values form the input.
@attached(member, names: named(actions))
public macro IntrospectableActions() = #externalMacro(module: "TandemMacros", type: "IntrospectableActionsMacro")

/// A type with a JSON form and an input schema. Conformances: String, Int, Int64, Bool, arrays of conforming
/// elements, and types marked `@Introspectable` or `@IntrospectableEnum`. Any other type is a compile error.
public protocol IntrospectableValue {
    static var introspectionSchema: Schema { get }
    var introspectionJSON: JSON { get }
    /// Decodes input the session already validated against `introspectionSchema`.
    init(introspected: JSON) throws
}

public struct IntrospectionError: Error {
    public let message: String
    public init(_ message: String) { self.message = message }
}

extension String: IntrospectableValue {
    public static var introspectionSchema: Schema { .string() }
    public var introspectionJSON: JSON { .string(self) }
    public init(introspected v: JSON) throws {
        guard let s = v.stringValue else { throw IntrospectionError("expected string") }
        self = s
    }
}

extension Bool: IntrospectableValue {
    public static var introspectionSchema: Schema { .boolean }
    public var introspectionJSON: JSON { .bool(self) }
    public init(introspected v: JSON) throws {
        guard let b = v.boolValue else { throw IntrospectionError("expected boolean") }
        self = b
    }
}

extension Int64: IntrospectableValue {
    public static var introspectionSchema: Schema { .integer }
    public var introspectionJSON: JSON { .integer(self) }
    public init(introspected v: JSON) throws {
        guard let n = JSON.int(v) else { throw IntrospectionError("expected integer") }
        self = n
    }
}

extension Int: IntrospectableValue {
    public static var introspectionSchema: Schema { .integer }
    public var introspectionJSON: JSON { .integer(Int64(self)) }
    public init(introspected v: JSON) throws {
        guard let n = JSON.int(v).flatMap(Int.init(exactly:)) else { throw IntrospectionError("expected integer") }
        self = n
    }
}

extension Array: IntrospectableValue where Element: IntrospectableValue {
    public static var introspectionSchema: Schema { .array(Element.introspectionSchema) }
    public var introspectionJSON: JSON { .array(map(\.introspectionJSON)) }
    public init(introspected v: JSON) throws {
        guard case .array(let items) = v else { throw IntrospectionError("expected array") }
        self = try items.map(Element.init(introspected:))
    }
}

/// Helpers the macros call. Optional versus required is picked by overload resolution, so property types may be inferred.
public enum Introspection {
    public static func put<T: IntrospectableValue>(_ o: inout [(String, JSON)], _ key: String, _ v: T) {
        o.append((key, v.introspectionJSON))
    }

    public static func put<T: IntrospectableValue>(_ o: inout [(String, JSON)], _ key: String, _ v: T?) {
        if let v { o.append((key, v.introspectionJSON)) }
    }

    public static func property<T: IntrospectableValue>(_ p: inout [(String, Schema)], _ r: inout [String], _ key: String, _: T.Type) {
        p.append((key, T.introspectionSchema))
        r.append(key)
    }

    public static func property<T: IntrospectableValue>(_ p: inout [(String, Schema)], _ r: inout [String], _ key: String, _: T?.Type) {
        p.append((key, T.introspectionSchema))
    }

    public static func property<Root, T: IntrospectableValue>(_ p: inout [(String, Schema)], _ r: inout [String], _ key: String, _: KeyPath<Root, T>) {
        property(&p, &r, key, T.self)
    }

    public static func property<Root, T: IntrospectableValue>(_ p: inout [(String, Schema)], _ r: inout [String], _ key: String, _: KeyPath<Root, T?>) {
        property(&p, &r, key, T?.self)
    }

    public static func field<T: IntrospectableValue>(_ o: JSON?, _ key: String) throws -> T {
        guard let v = o?[key] else { throw IntrospectionError("missing \(key)") }
        return try T(introspected: v)
    }

    public static func field<T: IntrospectableValue>(_ o: JSON?, _ key: String) throws -> T? {
        try o?[key].map(T.init(introspected:))
    }
}
