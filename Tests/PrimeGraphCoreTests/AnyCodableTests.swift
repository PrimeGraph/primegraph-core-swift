import Foundation
import XCTest

@testable import PrimeGraphCore

final class AnyCodableTests: XCTestCase {
    // A bare top-level scalar has no container of its own in every Foundation
    // version this package supports, so the round-trip goes through a one-element
    // array — the same shape `AnyCodable.encodedValue` itself uses.
    private func roundTrip(_ value: AnyCodable) throws -> AnyCodable {
        let data = try JSONEncoder().encode([value])
        let decoded = try JSONDecoder().decode([AnyCodable].self, from: data)
        return try XCTUnwrap(decoded.first)
    }

    /// Names every case with an exhaustive switch, so adding a `JSONValue` case
    /// without extending the cases below stops compiling.
    private func caseName(_ value: AnyCodable.JSONValue) -> String {
        switch value {
        case .null: return "null"
        case .bool: return "bool"
        case .int: return "int"
        case .double: return "double"
        case .string: return "string"
        case .array: return "array"
        case .object: return "object"
        }
    }

    private var everyCase: [AnyCodable.JSONValue] {
        let nestedArray: AnyCodable.JSONValue = .array([
            AnyCodable(.int(1)),
            AnyCodable(.string("two")),
            AnyCodable(.null),
            AnyCodable(.array([AnyCodable(.bool(false)), AnyCodable(.double(2.5))])),
            AnyCodable(.object(["deep": AnyCodable(.int(9))])),
        ])
        let nestedObject: AnyCodable.JSONValue = .object([
            "flag": AnyCodable(.bool(true)),
            "count": AnyCodable(.int(3)),
            "ratio": AnyCodable(.double(1.5)),
            "text": AnyCodable(.string("hi")),
            "nothing": AnyCodable(.null),
            "list": AnyCodable(.array([AnyCodable(.int(1)), AnyCodable(.int(2))])),
            "inner": AnyCodable(.object(["a": AnyCodable(.string("b"))])),
        ])
        return [
            .null,
            .bool(true),
            .bool(false),
            .int(0),
            .int(-17),
            .double(1.5),
            .double(-0.25),
            .string(""),
            .string("with \"quotes\" and \u{1F600}"),
            nestedArray,
            nestedObject,
        ]
    }

    func testEveryJsonValueCaseRoundTrips() throws {
        for value in everyCase {
            let original = AnyCodable(value)
            let decoded = try roundTrip(original)
            XCTAssertEqual(decoded, original, "case \(caseName(value)) did not round-trip")
            XCTAssertEqual(caseName(decoded.value), caseName(value))
        }
    }

    func testEveryJsonValueCaseIsCovered() {
        let names = Set(everyCase.map { caseName($0) })
        XCTAssertEqual(names, ["null", "bool", "int", "double", "string", "array", "object"])
    }

    func testWholeDoubleDecodesAsInt() throws {
        // `init(from:)` tries Int before Double, so 2.0 comes back as an integer.
        // The wire carries no scale, and this is the behaviour every consumer sees.
        let decoded = try roundTrip(AnyCodable(.double(2.0)))
        XCTAssertEqual(decoded.value, .int(2))
    }

    func testNestedStructureSurvivesEncodeDecode() throws {
        let original = AnyCodable(.object([
            "items": AnyCodable(.array([
                AnyCodable(.object(["id": AnyCodable(.string("a")), "n": AnyCodable(.int(1))])),
                AnyCodable(.object(["id": AnyCodable(.string("b")), "n": AnyCodable(.null)])),
            ])),
        ]))
        XCTAssertEqual(try roundTrip(original), original)
    }

    func testDecodesFromRawJson() throws {
        let json = Data(#"[{"a":[1,true,null,"x",1.5]}]"#.utf8)
        let decoded = try JSONDecoder().decode([AnyCodable].self, from: json)
        XCTAssertEqual(
            try XCTUnwrap(decoded.first),
            AnyCodable(.object(["a": AnyCodable(.array([
                AnyCodable(.int(1)),
                AnyCodable(.bool(true)),
                AnyCodable(.null),
                AnyCodable(.string("x")),
                AnyCodable(.double(1.5)),
            ]))]))
        )
    }

    func testAnyInitializerMapsNull() {
        XCTAssertEqual(AnyCodable(nil as Any?).value, .null)
        XCTAssertEqual(AnyCodable(NSNull() as Any?).value, .null)
    }

    func testAnyInitializerTellsBoolFromNumber() {
        XCTAssertEqual(AnyCodable(NSNumber(value: true) as Any?).value, .bool(true))
        XCTAssertEqual(AnyCodable(NSNumber(value: false) as Any?).value, .bool(false))
        XCTAssertEqual(AnyCodable(true as Any?).value, .bool(true))
        // A numeric 1 satisfies `as? Bool`; only the CoreFoundation type id keeps
        // it an integer.
        XCTAssertEqual(AnyCodable(NSNumber(value: 1) as Any?).value, .int(1))
        XCTAssertEqual(AnyCodable(NSNumber(value: 0) as Any?).value, .int(0))
    }

    func testAnyInitializerMapsNumbers() {
        XCTAssertEqual(AnyCodable(NSNumber(value: 42) as Any?).value, .int(42))
        XCTAssertEqual(AnyCodable(NSNumber(value: -7) as Any?).value, .int(-7))
        XCTAssertEqual(AnyCodable(NSNumber(value: 1.5) as Any?).value, .double(1.5))
        XCTAssertEqual(AnyCodable(3 as Any?).value, .int(3))
        XCTAssertEqual(AnyCodable(2.25 as Any?).value, .double(2.25))
    }

    func testAnyInitializerMapsStrings() {
        XCTAssertEqual(AnyCodable("text" as Any?).value, .string("text"))
        XCTAssertEqual(AnyCodable(NSString(string: "ns") as Any?).value, .string("ns"))
    }

    func testAnyInitializerMapsNestedCollections() throws {
        let raw: [String: Any] = [
            "flag": true,
            "count": 3,
            "ratio": 1.5,
            "text": "hi",
            "nothing": NSNull(),
            "list": [1, "two", false] as [Any],
            "nested": ["deep": [10] as [Any]] as [String: Any],
        ]
        guard case let .object(mapped) = AnyCodable(raw as Any?).value else {
            return XCTFail("expected an object")
        }
        XCTAssertEqual(mapped["flag"]?.value, .bool(true))
        XCTAssertEqual(mapped["count"]?.value, .int(3))
        XCTAssertEqual(mapped["ratio"]?.value, .double(1.5))
        XCTAssertEqual(mapped["text"]?.value, .string("hi"))
        XCTAssertEqual(mapped["nothing"]?.value, .null)
        XCTAssertEqual(
            mapped["list"]?.value,
            .array([AnyCodable(.int(1)), AnyCodable(.string("two")), AnyCodable(.bool(false))])
        )
        XCTAssertEqual(
            mapped["nested"]?.value,
            .object(["deep": AnyCodable(.array([AnyCodable(.int(10))]))])
        )
    }

    func testAnyInitializerMapsTopLevelArray() {
        XCTAssertEqual(
            AnyCodable([1, NSNull()] as [Any] as Any?).value,
            .array([AnyCodable(.int(1)), AnyCodable(.null)])
        )
    }

    func testAnyInitializerRendersAnInstantFieldOnTheCanonicalFormat() {
        struct Stamped: Encodable {
            let at: Date
        }
        let boxed = AnyCodable(Stamped(at: Date(timeIntervalSince1970: 0)) as Any?)
        XCTAssertEqual(
            boxed.value,
            .object(["at": AnyCodable(.string("1970-01-01T00:00:00.000Z"))])
        )
    }

    func testAnyInitializerOnABareInstantCarriesTheReferenceInterval() {
        // A bare `Date` reaches the encoder through the `Encodable` existential
        // box, which calls `Date.encode(to:)` directly — and the date strategy
        // hangs off `SingleValueEncodingContainer.encode(_: Date)`, which that
        // path never enters. So a bare instant lands as its interval since the
        // reference date, while an instant held by a model field renders as text.
        // This is what every generated package's own copy already does.
        let boxed = AnyCodable(Date(timeIntervalSince1970: 0) as Any?)
        XCTAssertEqual(boxed.value, .int(-978_307_200))
    }

    func testAnyInitializerEncodesAModelStruct() {
        struct Model: Encodable {
            let id: String
            let n: Int
        }
        let boxed = AnyCodable(Model(id: "a", n: 2) as Any?)
        XCTAssertEqual(
            boxed.value,
            .object(["id": AnyCodable(.string("a")), "n": AnyCodable(.int(2))])
        )
    }

    func testAnyInitializerDescribesAValueThatEncodesToNothing() {
        final class Opaque {
            let tag = "opaque"
        }
        guard case let .string(text) = AnyCodable(Opaque() as Any?).value else {
            return XCTFail("expected a described string")
        }
        XCTAssertFalse(text.isEmpty)
    }

    func testHashableHolds() {
        let a = AnyCodable(.object(["k": AnyCodable(.array([AnyCodable(.int(1))]))]))
        let b = AnyCodable(.object(["k": AnyCodable(.array([AnyCodable(.int(1))]))]))
        let c = AnyCodable(.object(["k": AnyCodable(.array([AnyCodable(.int(2))]))]))
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.hashValue, b.hashValue)
        XCTAssertNotEqual(a, c)
        XCTAssertEqual(Set([a, b, c]).count, 2)
        XCTAssertNotEqual(AnyCodable(.int(1)), AnyCodable(.string("1")))
        XCTAssertNotEqual(AnyCodable(.int(1)), AnyCodable(.bool(true)))
        XCTAssertNotEqual(AnyCodable(.null), AnyCodable(.string("")))
    }

    func testUsableAsADictionaryKey() {
        var byValue: [AnyCodable: String] = [:]
        byValue[AnyCodable(.string("k"))] = "first"
        byValue[AnyCodable(.string("k"))] = "second"
        XCTAssertEqual(byValue.count, 1)
        XCTAssertEqual(byValue[AnyCodable(.string("k"))], "second")
    }

    func testSendableHolds() {
        // A compile-time assertion: these are the types that cross an async or
        // `@Sendable` boundary in generated code.
        requireSendable(AnyCodable.self)
        requireSendable(AnyCodable.JSONValue.self)
        requireSendable([String: AnyCodable].self)
    }

    func testCarriedAcrossAConcurrentBoundary() async {
        let boxed = AnyCodable(.object(["k": AnyCodable(.int(1))]))
        let echoed = await Task { boxed }.value
        XCTAssertEqual(echoed, boxed)
    }
}

func requireSendable<T: Sendable>(_: T.Type) {}
