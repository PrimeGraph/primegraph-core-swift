import Foundation
import XCTest

@testable import PrimeGraphCore

private struct SamplePayload: Codable, Sendable, Equatable {
    let id: String
    let count: Int
}

private struct StampedPayload: Codable, Sendable, Equatable {
    let at: Date
}

private struct ForeignFailure: Error {
    let reason: String
}

final class DslErrorTests: XCTestCase {
    func testConstruction() {
        let error = DslError(code: "NOT_FOUND", payload: SamplePayload(id: "a", count: 1))
        XCTAssertEqual(error.code, "NOT_FOUND")
        XCTAssertEqual(error.payload, SamplePayload(id: "a", count: 1))
        XCTAssertEqual(error.anyPayload as? SamplePayload, SamplePayload(id: "a", count: 1))
    }

    func testVoidPayloadInit() {
        let error = DslError<Void>(code: "NO_RESPONSE")
        XCTAssertEqual(error.code, "NO_RESPONSE")
        XCTAssertNotNil(error.anyPayload)
    }

    func testMatchesAnyDslErrorWhenThrown() throws {
        func raising() throws {
            throw DslError(code: "FORBIDDEN", payload: SamplePayload(id: "x", count: 7))
        }
        do {
            try raising()
            XCTFail("expected a raise")
        } catch {
            let erased = try XCTUnwrap(error as? AnyDslError)
            XCTAssertEqual(erased.code, "FORBIDDEN")
            XCTAssertEqual(erased.anyPayload as? SamplePayload, SamplePayload(id: "x", count: 7))
            let json = try XCTUnwrap(erased.payloadJson as? [String: Any])
            XCTAssertEqual(json["id"] as? String, "x")
            XCTAssertEqual(json["count"] as? Int, 7)
        }
    }

    func testMatchesTheConcreteGenericWhenThrown() throws {
        func raising() throws {
            throw DslError(code: "VALIDATION_FAILED", payload: SamplePayload(id: "y", count: 2))
        }
        do {
            try raising()
            XCTFail("expected a raise")
        } catch let error as DslError<SamplePayload> {
            XCTAssertEqual(error.payload, SamplePayload(id: "y", count: 2))
        }
    }

    func testAnotherPayloadTypeDoesNotMatch() throws {
        let error: Error = DslError(code: "X", payload: SamplePayload(id: "a", count: 1))
        XCTAssertNil(error as? DslError<String>)
        XCTAssertNotNil(error as? AnyDslError)
    }

    func testScalarAndVoidPayloadsAlsoErase() throws {
        let scalar: Error = DslError(code: "OUT", payload: 5)
        XCTAssertEqual((scalar as? AnyDslError)?.anyPayload as? Int, 5)
        XCTAssertEqual(try XCTUnwrap(scalar as? AnyDslError).payloadJson as? Int, 5)

        let empty: Error = DslError<Void>(code: "NO_RESPONSE")
        XCTAssertEqual((empty as? AnyDslError)?.code, "NO_RESPONSE")
    }

    func testPayloadJsonUsesTheConfiguredInstantFormat() throws {
        let error = DslError(
            code: "X",
            payload: StampedPayload(at: Date(timeIntervalSince1970: 0))
        )
        let json = try XCTUnwrap(error.payloadJson as? [String: Any])
        XCTAssertEqual(json["at"] as? String, "1970-01-01T00:00:00.000Z")
    }

    func testDslJsonWireOnNil() {
        XCTAssertTrue(dslJsonWire(nil) is NSNull)
    }

    func testDslJsonWireOnScalars() {
        XCTAssertEqual(dslJsonWire("abc") as? String, "abc")
        XCTAssertEqual(dslJsonWire(42) as? Int, 42)
        XCTAssertEqual(dslJsonWire(true) as? Bool, true)
        XCTAssertEqual(dslJsonWire(1.5) as? Double, 1.5)
    }

    func testDslJsonWireOnAnEncodableStruct() throws {
        let wire = try XCTUnwrap(
            dslJsonWire(SamplePayload(id: "a", count: 1)) as? [String: Any]
        )
        XCTAssertEqual(wire.count, 2)
        XCTAssertEqual(wire["id"] as? String, "a")
        XCTAssertEqual(wire["count"] as? Int, 1)
    }

    func testDslJsonWireOnAnEncodableList() throws {
        let wire = try XCTUnwrap(dslJsonWire([1, 2, 3]) as? [Any])
        XCTAssertEqual(wire.compactMap { $0 as? Int }, [1, 2, 3])
    }

    func testDslJsonWireOnAnInstantHeldByAModel() throws {
        let wire = try XCTUnwrap(
            dslJsonWire(StampedPayload(at: Date(timeIntervalSince1970: 0))) as? [String: Any]
        )
        XCTAssertEqual(wire["at"] as? String, "1970-01-01T00:00:00.000Z")
    }

    func testDslJsonWireOnABareInstantCarriesTheReferenceInterval() {
        // The `Encodable` existential box calls `Date.encode(to:)` directly, and
        // the encoder's date strategy hangs off the single-value container's
        // `encode(_: Date)`, which that path never enters. A bare instant
        // therefore lands as its interval since the reference date; one held by
        // a model field renders as canonical text. Same as the copy inside every
        // generated package.
        XCTAssertEqual(dslJsonWire(Date(timeIntervalSince1970: 0)) as? Double, -978_307_200)
    }

    func testDslJsonWireLeavesAnUntypedMapAlone() throws {
        // `[String: Any]` carries no `Encodable` conformance and already IS the
        // wire form, so it is handed back unchanged rather than re-encoded.
        let raw: [String: Any] = ["k": 1, "n": NSNull()]
        let wire = try XCTUnwrap(dslJsonWire(raw) as? [String: Any])
        XCTAssertEqual(wire["k"] as? Int, 1)
        XCTAssertTrue(wire["n"] is NSNull)
    }

    func testDslArrivedCode() {
        XCTAssertEqual(dslArrivedCode(DslError(code: "NOT_FOUND", payload: 1)), "NOT_FOUND")
        XCTAssertEqual(dslArrivedCode(ForeignFailure(reason: "sdk")), "INTERNAL_ERROR")
    }

    func testDslArrivedJsonOnARaise() throws {
        let arrived = dslArrivedJson(
            DslError(code: "X", payload: SamplePayload(id: "a", count: 1))
        )
        let json = try XCTUnwrap(arrived as? [String: Any])
        XCTAssertEqual(json["id"] as? String, "a")
    }

    func testDslArrivedJsonOnAForeignError() throws {
        let json = try XCTUnwrap(dslArrivedJson(ForeignFailure(reason: "sdk")) as? [String: Any])
        XCTAssertEqual(json["code"] as? String, "INTERNAL_ERROR")
        XCTAssertEqual(json["message"] as? String, "Internal server error")
    }

    func testDslDecodedPayload() {
        let fallback = SamplePayload(id: "", count: 0)
        let decoded = dslDecodedPayload(["id": "z", "count": 9] as [String: Any], fallback)
        XCTAssertEqual(decoded, SamplePayload(id: "z", count: 9))
    }

    func testDslDecodedPayloadFallsBack() {
        let fallback = SamplePayload(id: "fb", count: -1)
        XCTAssertEqual(dslDecodedPayload(nil, fallback), fallback)
        XCTAssertEqual(dslDecodedPayload(["id": "z"] as [String: Any], fallback), fallback)
        XCTAssertEqual(dslDecodedPayload("not an object" as Any?, fallback), fallback)
    }

    func testDslDecodedPayloadRebuildsAnInstant() {
        let fallback = StampedPayload(at: Date(timeIntervalSince1970: 0))
        let decoded = dslDecodedPayload(
            ["at": "2024-03-05T06:07:08.123Z"] as [String: Any],
            fallback
        )
        XCTAssertEqual(decoded.at.timeIntervalSince1970, 1_709_618_828.123, accuracy: 0.0005)
    }

    func testDslErrorViewJsonObject() throws {
        let view = DslErrorView(code: "NOT_FOUND", payload: ["id": "a"])
        XCTAssertEqual(view.code, "NOT_FOUND")
        XCTAssertEqual(view.payload, ["id": "a"])
        let object = view.jsonObject
        XCTAssertEqual(object.count, 2)
        XCTAssertEqual(object["code"] as? String, "NOT_FOUND")
        XCTAssertEqual(object["payload"] as? [String: String], ["id": "a"])
    }

    func testDslErrorViewIsReachedThroughTheConvertibleProtocol() throws {
        let convertible: DslJsonObjectConvertible = DslErrorView(code: "X", payload: 1)
        XCTAssertEqual(convertible.jsonObject["code"] as? String, "X")
        XCTAssertEqual(convertible.jsonObject["payload"] as? Int, 1)
    }

    func testDslErrorViewSerializesAsJson() throws {
        let view = DslErrorView(code: "X", payload: ["n": 1])
        let data = try JSONSerialization.data(withJSONObject: view.jsonObject)
        let parsed = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(parsed["code"] as? String, "X")
    }

    func testDefaultErrorMessage() {
        XCTAssertEqual(defaultErrorMessage("NOT_FOUND"), "Resource not found")
        XCTAssertEqual(defaultErrorMessage("unauthenticated"), "Authorization required")
        XCTAssertEqual(defaultErrorMessage("VALIDATION_FAILED"), "Request validation failed")
        XCTAssertEqual(defaultErrorMessage("NOTHING_LIKE_IT"), "Internal server error")
    }

    func testDslErrorMessagesCoverTheCodesTheRuntimeItselfRaises() {
        for code in ["INTERNAL_ERROR", "VALIDATION_FAILED", "NO_RESPONSE", "TIME_PARSE_FAILED"] {
            XCTAssertNotNil(dslErrorMessages[code], "missing default text for \(code)")
        }
    }
}
