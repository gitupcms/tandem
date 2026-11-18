import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

// Expansions name kit types with their module (`TandemKit.Action`): the annotated types often have their own `Action`.

struct MacroError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

/// Swift string literal for a protocol key or action name.
private func literal(_ s: String) -> String { StringLiteralExprSyntax(content: s).description }

private func bare(_ token: TokenSyntax) -> String { String(token.trimmedDescription.filter { $0 != "`" }) }

private func conformance(_ protocols: [TypeSyntax]) -> String {
    protocols.isEmpty ? "" : ": TandemIntrospection.IntrospectableValue"
}

public struct IntrospectableMacro: ExtensionMacro {
    public static func expansion(of node: AttributeSyntax, attachedTo declaration: some DeclGroupSyntax,
                                 providingExtensionsOf type: some TypeSyntaxProtocol, conformingTo protocols: [TypeSyntax],
                                 in context: some MacroExpansionContext) throws -> [ExtensionDeclSyntax] {
        guard declaration.is(StructDeclSyntax.self) else { throw MacroError("@Introspectable applies to a struct") }
        // (name, settable): a `let` with an initial value is a state key but cannot be set from input.
        var stored: [(name: String, settable: Bool)] = []
        for member in declaration.memberBlock.members {
            guard let v = member.decl.as(VariableDeclSyntax.self),
                  !v.modifiers.contains(where: { ["static", "class"].contains($0.name.text) }) else { continue }
            let isLet = v.bindingSpecifier.tokenKind == .keyword(.let)
            for b in v.bindings {
                if let accessors = b.accessorBlock?.accessors {
                    // Only observers (willSet/didSet) keep a property stored.
                    guard case .accessors(let list) = accessors,
                          list.allSatisfy({ ["willSet", "didSet"].contains($0.accessorSpecifier.text) }) else { continue }
                }
                guard let id = b.pattern.as(IdentifierPatternSyntax.self) else {
                    throw MacroError("@Introspectable needs one name per stored property")
                }
                stored.append((bare(id.identifier), !(isLet && b.initializer != nil)))
            }
        }
        let t = type.trimmedDescription
        let puts = stored.map { "TandemIntrospection.Introspection.put(&o, \(literal($0.name)), self.\($0.name))" }
        let props = stored.map { "TandemIntrospection.Introspection.property(&p, &r, \(literal($0.name)), \\\(t).\($0.name))" }
        let sets = stored.filter(\.settable).map { "self.\($0.name) = try TandemIntrospection.Introspection.field(json, \(literal($0.name)))" }
        let ext: DeclSyntax = """
            extension \(raw: t)\(raw: conformance(protocols)) {
                public static var introspectionSchema: TandemKit.Schema {
                    var p: [(String, TandemKit.Schema)] = []
                    var r: [String] = []
                    \(raw: props.joined(separator: "\n"))
                    return .object(p, required: r)
                }
                public var introspectionJSON: TandemKit.JSON {
                    var o: [(String, TandemKit.JSON)] = []
                    \(raw: puts.joined(separator: "\n"))
                    return .object(o)
                }
                public init(introspected json: TandemKit.JSON) throws {
                    \(raw: sets.joined(separator: "\n"))
                }
            }
            """
        return [ext.cast(ExtensionDeclSyntax.self)]
    }
}

public struct IntrospectableEnumMacro: ExtensionMacro {
    public static func expansion(of node: AttributeSyntax, attachedTo declaration: some DeclGroupSyntax,
                                 providingExtensionsOf type: some TypeSyntaxProtocol, conformingTo protocols: [TypeSyntax],
                                 in context: some MacroExpansionContext) throws -> [ExtensionDeclSyntax] {
        guard let e = declaration.as(EnumDeclSyntax.self),
              e.inheritanceClause?.inheritedTypes.first?.type.trimmedDescription == "String" else {
            throw MacroError("@IntrospectableEnum applies to an enum with String raw values")
        }
        let cases = e.memberBlock.members.compactMap { $0.decl.as(EnumCaseDeclSyntax.self) }.flatMap(\.elements)
        let all = "[" + cases.map { "Self.\($0.name.trimmedDescription)" }.joined(separator: ", ") + "]"
        let ext: DeclSyntax = """
            extension \(raw: type.trimmedDescription)\(raw: conformance(protocols)) {
                public static var introspectionSchema: TandemKit.Schema { .string(enum: \(raw: all).map(\\.rawValue)) }
                public var introspectionJSON: TandemKit.JSON { .string(rawValue) }
                public init(introspected json: TandemKit.JSON) throws {
                    // Exact match, not Swift's canonical-equivalence `==` used by init(rawValue:).
                    guard let s = json.stringValue, let v = \(raw: all).first(where: { TandemKit.same($0.rawValue, s) }) else {
                        throw TandemIntrospection.IntrospectionError("not an allowed value")
                    }
                    self = v
                }
            }
            """
        return [ext.cast(ExtensionDeclSyntax.self)]
    }
}

// A member macro, not an extension: the case types are resolved in the enum's own scope (e.g. a sibling nested type).
public struct IntrospectableActionsMacro: MemberMacro {
    public static func expansion(of node: AttributeSyntax, providingMembersOf declaration: some DeclGroupSyntax,
                                 conformingTo protocols: [TypeSyntax], in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        guard let e = declaration.as(EnumDeclSyntax.self) else { throw MacroError("@IntrospectableActions applies to an enum") }
        var actions: [String] = []
        for c in e.memberBlock.members.compactMap({ $0.decl.as(EnumCaseDeclSyntax.self) }).flatMap(\.elements) {
            let name = bare(c.name)
            let wire = literal(name.prefix(1).uppercased() + name.dropFirst())
            guard let params = c.parameterClause?.parameters, !params.isEmpty else {
                actions.append("TandemKit.Action(\(wire)) { _ in send(Self.\(c.name.trimmed)) }")
                continue
            }
            var props: [String] = []
            var args: [String] = []
            for p in params {
                guard let label = p.firstName, label.tokenKind != .wildcard else {
                    throw MacroError("@IntrospectableActions: associated values of '\(name)' need labels; the label is the input property name")
                }
                let key = literal(bare(label))
                props.append("TandemIntrospection.Introspection.property(&p, &r, \(key), \(p.type.trimmedDescription).self)")
                args.append("\(label.trimmedDescription): TandemIntrospection.Introspection.field(i, \(key))")
            }
            actions.append("""
                TandemKit.Action(\(wire), input: {
                    var p: [(String, TandemKit.Schema)] = []
                    var r: [String] = []
                    \(props.joined(separator: "\n"))
                    return .object(p, required: r)
                }()) { i in
                    // The session validated the input against the schema, so decoding does not fail.
                    guard let a = try? Self.\(c.name.trimmed)(\(args.joined(separator: ", "))) else { return }
                    send(a)
                }
                """)
        }
        return ["""
            public static func actions(_ send: @escaping (Self) -> Void) -> [TandemKit.Action] {
                [
                    \(raw: actions.joined(separator: ",\n"))
                ]
            }
            """]
    }
}

@main
struct TandemMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [IntrospectableMacro.self, IntrospectableEnumMacro.self, IntrospectableActionsMacro.self]
}
