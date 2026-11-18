import XCTest
@testable import TandemKit

final class JSONTests: XCTestCase {
    func decode(_ s: String) throws -> JSON { try JSON.decode(Array(s.utf8)) }

    func testRoundTripCanonical() throws {
        let v = try decode(#" { "b" : [1, -0, true, null], "aA" : "x\/yé😀\u001f" } "#)
        XCTAssertEqual(v.canonical, #"{"aA":"x/yé😀\u001f","b":[1,0,true,null]}"#)
    }

    func testNumberLexemeKept() throws {
        XCTAssertEqual(try decode("[1.0,1e2,1E+2,0.5]").canonical, "[1.0,1e2,1E+2,0.5]")
        guard case .number = try decode("1.0") else { return XCTFail("1.0 must not be an integer") }
        XCTAssertNil(JSON.int(try decode("9007199254740992")))
        XCTAssertNil(JSON.int(try decode("-9223372036854775808")))
        XCTAssertEqual(JSON.int(try decode("-9007199254740991")), -9007199254740991)
    }

    func testRejects() {
        let bad: [[UInt8]] = [
            [], Array(" \t".utf8), [0xEF, 0xBB, 0xBF] + Array("{}".utf8), [0x22, 0xFF, 0x22], [0x22, 0xC0, 0xAF, 0x22],
            Array(#"{"a":1,"a":2}"#.utf8), Array(#""\ud800""#.utf8), Array(#""\udc00\ud800""#.utf8),
            Array(#""\u+123""#.utf8), Array("01".utf8), Array("[1,]".utf8), Array("\"\u{01}\"".utf8),
            Array(String(repeating: "[", count: 65).utf8) + Array(String(repeating: "]", count: 65).utf8),
        ]
        for b in bad { XCTAssertThrowsError(try JSON.decode(b), String(decoding: b, as: UTF8.self)) }
        XCTAssertNoThrow(try JSON.decode(Array((String(repeating: "[", count: 64) + String(repeating: "]", count: 64)).utf8)))
    }

    func testKeysAreCodeUnitsNotCanonicalEquivalence() throws {
        let v = try decode(#"{"café":1,"café":2}"#)
        XCTAssertEqual(JSON.int(v["caf\u{e9}"]), 2)
    }

    func testCanonicalKeyOrderAndEscapes() {
        let v = JSON.object([("😀", .integer(5)), ("｡", .integer(4)), ("a", .integer(1)), ("B", .string("\u{8}\u{c}\n\r\t\"\\\u{7f}"))])
        XCTAssertEqual(v.canonical, #"{"B":"\b\f\n\r\t\"\\"# + "\u{7f}" + #"","a":1,"😀":5,"｡":4}"#)
    }

    func testSchemaErrorOrderAndPaths() {
        let s = Schema.object([("a", .integer), ("b", .array(.string(enum: ["x"])))], required: ["b", "a"])
        func path(_ text: String) -> String? {
            do { try s.validate(try JSON.decode(Array(text.utf8)), path: "$.input"); return nil } catch {
                return (error as? ProtocolError)?.path
            }
        }
        XCTAssertEqual(path(#"{"b":["x","y"],"a":1.5}"#), "$.input.b[1]")
        XCTAssertEqual(path(#"{"z":1,"a":"1"}"#), "$.input.z")
        XCTAssertEqual(path("{}"), "$.input.a")
        XCTAssertEqual(path(#"{"a":null}"#), "$.input.a")
        XCTAssertNil(path(#"{"a":1,"b":[]}"#))
    }
}
