import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import TandemIntrospection
import TandemMacros
import XCTest

@IntrospectableEnum
enum Color: String { case red, darkBlue = "dark-blue" }

@Introspectable
struct Point: Equatable {
    var x: Int
    var y: Int
}

@Introspectable
struct Sample: Equatable {
    var text = "a"
    var count: Int = 1
    var big: Int64 = 2
    var flag = true
    var color = Color.darkBlue
    var point = Point(x: 1, y: 2)
    var tags: [String] = ["t"]
    var note: String? = nil
    let fixed = "f"
    var computed: Int { count * 2 }
    static var shared = 0
}

@IntrospectableActions
enum Act: Equatable {
    case retry
    case open(id: String)
    case set(count: Int, big: Int64, flag: Bool, color: Color, point: Point, tags: [Color], note: String?)
}

// Case types that name a sibling nested type resolve in the enum's own scope.
enum Screen {
    @IntrospectableEnum
    enum Tab: String { case one }

    @IntrospectableActions
    enum Action { case pick(tab: Tab) }
}

final class IntrospectionTests: XCTestCase {
    func json(_ s: String) throws -> JSON { try JSON.decode(Array(s.utf8)) }

    func testStateJSONCoversEveryTypeRow() {
        XCTAssertEqual(Sample().introspectionJSON.canonical,
                       #"{"big":2,"color":"dark-blue","count":1,"fixed":"f","flag":true,"point":{"x":1,"y":2},"tags":["t"],"text":"a"}"#)
        var s = Sample()
        s.note = "n"
        XCTAssertEqual(s.introspectionJSON["note"]?.stringValue, "n")
    }

    func testStateSchema() {
        XCTAssertEqual(Sample.introspectionSchema.json.canonical, """
            {"properties":{"big":{"type":"integer"},"color":{"enum":["red","dark-blue"],"type":"string"},"count":{"type":"integer"},\
            "fixed":{"type":"string"},"flag":{"type":"boolean"},"note":{"type":"string"},\
            "point":{"properties":{"x":{"type":"integer"},"y":{"type":"integer"}},"required":["x","y"],"type":"object"},\
            "tags":{"items":{"type":"string"},"type":"array"},"text":{"type":"string"}},\
            "required":["text","count","big","flag","color","point","tags","fixed"],"type":"object"}
            """)
    }

    func testStateDecodes() throws {
        let s = try Sample(introspected: json(#"{"text":"b","count":3,"big":4,"flag":false,"color":"red","point":{"x":5,"y":6},"tags":[],"fixed":"g"}"#))
        XCTAssertEqual(s, Sample(text: "b", count: 3, big: 4, flag: false, color: .red, point: Point(x: 5, y: 6), tags: [], note: nil))
    }

    func testActions() throws {
        var got: [Act] = []
        let actions = Act.actions { got.append($0) }
        XCTAssertEqual(actions.map(\.name), ["Retry", "Open", "Set"])
        XCTAssertNil(actions[0].input)
        XCTAssertEqual(actions[1].input?.json.canonical, #"{"properties":{"id":{"type":"string"}},"required":["id"],"type":"object"}"#)
        let set = try XCTUnwrap(actions[2].input)
        XCTAssertEqual(set.json["required"]?.canonical, #"["count","big","flag","color","point","tags"]"#)
        XCTAssertEqual(set.json["properties"]?["tags"]?.canonical, #"{"items":{"enum":["red","dark-blue"],"type":"string"},"type":"array"}"#)

        actions[0].perform(nil)
        actions[1].perform(try json(#"{"id":"7"}"#))
        let input = try json(#"{"count":1,"big":9007199254740991,"flag":true,"color":"dark-blue","point":{"x":0,"y":-1},"tags":["red"]}"#)
        try set.validate(input, path: "$.input")
        actions[2].perform(input)
        actions[2].perform(try json(#"{"count":1,"big":2,"flag":true,"color":"red","point":{"x":0,"y":0},"tags":[],"note":"n"}"#))
        XCTAssertEqual(got, [
            .retry, .open(id: "7"),
            .set(count: 1, big: 9_007_199_254_740_991, flag: true, color: .darkBlue, point: Point(x: 0, y: -1), tags: [.red], note: nil),
            .set(count: 1, big: 2, flag: true, color: .red, point: Point(x: 0, y: 0), tags: [], note: "n"),
        ])
    }

    func testNestedSiblingType() throws {
        var got: Screen.Tab?
        let pick = Screen.Action.actions { if case .pick(let t) = $0 { got = t } }[0]
        pick.perform(try json(#"{"tab":"one"}"#))
        XCTAssertEqual(got, .one)
    }

    func testEnumMatchesExactCodeUnits() {
        XCTAssertNil(try? Color(introspected: .string("Red")))
        XCTAssertEqual(try? Color(introspected: .string("dark-blue")), .darkBlue)
    }

    let macros: [String: Macro.Type] = ["IntrospectableActions": IntrospectableActionsMacro.self, "IntrospectableEnum": IntrospectableEnumMacro.self]

    func testUnlabeledAssociatedValueIsAnError() {
        assertMacroExpansion("@IntrospectableActions\nenum A {\n    case set(Int)\n}", expandedSource: "enum A {\n    case set(Int)\n}",
                             diagnostics: [DiagnosticSpec(message: "@IntrospectableActions: associated values of 'set' need labels; the label is the input property name", line: 1, column: 1)],
                             macros: macros)
    }

    func testEnumNeedsStringRawValues() {
        assertMacroExpansion("@IntrospectableEnum\nenum E: Int {\n    case a\n}", expandedSource: "enum E: Int {\n    case a\n}",
                             diagnostics: [DiagnosticSpec(message: "@IntrospectableEnum applies to an enum with String raw values", line: 1, column: 1)],
                             macros: macros)
    }
}
