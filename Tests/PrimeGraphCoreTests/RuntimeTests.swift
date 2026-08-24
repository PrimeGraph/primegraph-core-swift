import Foundation
import XCTest

@testable import PrimeGraphCore

private struct Stamped: Codable, Equatable {
    let at: Date
}

final class RuntimeTests: XCTestCase {
    /// An independent reader for the reference instant, so the expectation is not
    /// produced by the code under test.
    private func reference(_ text: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return try XCTUnwrap(formatter.date(from: text))
    }

    func testParseInstantOnTheCanonicalFormat() throws {
        let base = try reference("2024-03-05T06:07:08Z")
        let parsed = try XCTUnwrap(Runtime.parseInstant("2024-03-05T06:07:08.123Z"))
        XCTAssertEqual(
            parsed.timeIntervalSince1970,
            base.timeIntervalSince1970 + 0.123,
            accuracy: 0.0005
        )
    }

    func testParseInstantWithNoFraction() throws {
        let base = try reference("2024-03-05T06:07:08Z")
        let parsed = try XCTUnwrap(Runtime.parseInstant("2024-03-05T06:07:08Z"))
        XCTAssertEqual(parsed.timeIntervalSince1970, base.timeIntervalSince1970, accuracy: 0.0005)
    }

    func testParseInstantNormalizesTheFractionWidth() throws {
        let base = try reference("2024-03-05T06:07:08Z").timeIntervalSince1970
        let cases: [(String, Double)] = [
            ("2024-03-05T06:07:08.1Z", 0.100),
            ("2024-03-05T06:07:08.12Z", 0.120),
            ("2024-03-05T06:07:08.123Z", 0.123),
            ("2024-03-05T06:07:08.123456Z", 0.123),
            ("2024-03-05T06:07:08.123456789Z", 0.123),
        ]
        for (text, fraction) in cases {
            let parsed = try XCTUnwrap(Runtime.parseInstant(text), "failed on \(text)")
            XCTAssertEqual(
                parsed.timeIntervalSince1970,
                base + fraction,
                accuracy: 0.0005,
                "wrong instant for \(text)"
            )
        }
    }

    func testParseInstantHonoursANumericOffset() throws {
        let base = try reference("2024-03-05T06:07:08Z").timeIntervalSince1970
        let ahead = try XCTUnwrap(Runtime.parseInstant("2024-03-05T09:07:08.123+03:00"))
        XCTAssertEqual(ahead.timeIntervalSince1970, base + 0.123, accuracy: 0.0005)
        let behind = try XCTUnwrap(Runtime.parseInstant("2024-03-05T03:07:08-03:00"))
        XCTAssertEqual(behind.timeIntervalSince1970, base, accuracy: 0.0005)
    }

    func testParseInstantRejectsWhatIsNoInstant() {
        XCTAssertNil(Runtime.parseInstant(""))
        XCTAssertNil(Runtime.parseInstant("not a time"))
        XCTAssertNil(Runtime.parseInstant("2024-03-05"))
        // A dot with no digits after it names no fraction.
        XCTAssertNil(Runtime.parseInstant("2024-03-05T06:07:08.Z"))
    }

    func testJsonEncoderWritesTheOneInstantFormat() throws {
        let data = try Runtime.jsonEncoder().encode(Stamped(at: Date(timeIntervalSince1970: 0)))
        XCTAssertEqual(String(decoding: data, as: UTF8.self), #"{"at":"1970-01-01T00:00:00.000Z"}"#)
    }

    func testJsonDecoderReadsWhatTheEncoderWrote() throws {
        let original = Stamped(at: try reference("2024-03-05T06:07:08Z"))
        let data = try Runtime.jsonEncoder().encode(original)
        let decoded = try Runtime.jsonDecoder().decode(Stamped.self, from: data)
        XCTAssertEqual(
            decoded.at.timeIntervalSince1970,
            original.at.timeIntervalSince1970,
            accuracy: 0.0005
        )
    }

    func testJsonDecoderReadsWiderThanTheEncoderWrites() throws {
        let base = try reference("2024-03-05T06:07:08Z").timeIntervalSince1970
        for text in [
            "2024-03-05T06:07:08Z",
            "2024-03-05T06:07:08.000000Z",
            "2024-03-05T09:07:08+03:00",
        ] {
            let data = Data(#"{"at":"\#(text)"}"#.utf8)
            let decoded = try Runtime.jsonDecoder().decode(Stamped.self, from: data)
            XCTAssertEqual(
                decoded.at.timeIntervalSince1970,
                base,
                accuracy: 0.0005,
                "wrong instant for \(text)"
            )
        }
    }

    func testJsonDecoderRejectsTextThatNamesNoInstant() {
        let data = Data(#"{"at":"yesterday"}"#.utf8)
        XCTAssertThrowsError(try Runtime.jsonDecoder().decode(Stamped.self, from: data))
    }

    func testValidationError() throws {
        let error = Runtime.validationError(path: "$.a", expected: "string", actual: "integer")
        XCTAssertEqual(error.code, "VALIDATION_FAILED")
        XCTAssertEqual(error.payload.path, "$.a")
        XCTAssertEqual(error.payload.expected, "string")
        XCTAssertEqual(error.payload.actual, "integer")
    }

    func testValidationErrorErasesAndRendersAsJson() throws {
        let raised: Error = Runtime.validationError(
            path: "$.a",
            expected: "string",
            actual: "integer"
        )
        let erased = try XCTUnwrap(raised as? AnyDslError)
        XCTAssertEqual(erased.code, "VALIDATION_FAILED")
        let json = try XCTUnwrap(erased.payloadJson as? [String: Any])
        XCTAssertEqual(json["path"] as? String, "$.a")
        XCTAssertEqual(json["expected"] as? String, "string")
        XCTAssertEqual(json["actual"] as? String, "integer")
    }

    func testValidationIssueRoundTrips() throws {
        let issue = Runtime.ValidationIssue(path: "$", expected: "object", actual: "null")
        let data = try Runtime.jsonEncoder().encode(issue)
        let decoded = try Runtime.jsonDecoder().decode(Runtime.ValidationIssue.self, from: data)
        XCTAssertEqual(decoded.path, issue.path)
        XCTAssertEqual(decoded.expected, issue.expected)
        XCTAssertEqual(decoded.actual, issue.actual)
    }

    func testFileRoundTrips() throws {
        let file = Runtime.File(
            name: "a.txt",
            mimeType: "text/plain",
            data: Data("hello".utf8)
        )
        let data = try Runtime.jsonEncoder().encode(file)
        let decoded = try Runtime.jsonDecoder().decode(Runtime.File.self, from: data)
        XCTAssertEqual(decoded, file)
        XCTAssertEqual(String(decoding: decoded.data, as: UTF8.self), "hello")
    }

    func testFileIsHashable() {
        let a = Runtime.File(name: "a", mimeType: "text/plain", data: Data([1]))
        let b = Runtime.File(name: "a", mimeType: "text/plain", data: Data([1]))
        let c = Runtime.File(name: "a", mimeType: "text/plain", data: Data([2]))
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.hashValue, b.hashValue)
        XCTAssertEqual(Set([a, b, c]).count, 2)
    }

    func testFormField() {
        let part = Runtime.formField("token", "abc")
        XCTAssertEqual(part.name, "token")
        XCTAssertEqual(part.value, "abc")
        XCTAssertEqual(part.filename, "")
        XCTAssertEqual(part.contentType, "")
        XCTAssertEqual(part.data, Data())
        XCTAssertFalse(part.isFile)
    }

    func testFormPartEquality() {
        XCTAssertEqual(Runtime.formField("a", "1"), Runtime.formField("a", "1"))
        XCTAssertNotEqual(Runtime.formField("a", "1"), Runtime.formField("a", "2"))
    }

    func testHttpAuthKeepsOnlyWhatItWasGiven() {
        let auth = Runtime.HttpAuth(type: "apiKey", in: "header", name: "X-Key", value: "abc")
        XCTAssertEqual(auth.type, "apiKey")
        XCTAssertEqual(auth.in, "header")
        XCTAssertEqual(auth.name, "X-Key")
        XCTAssertEqual(auth.value, "abc")
        XCTAssertNil(auth.scheme)
        XCTAssertNil(auth.username)
        XCTAssertNil(auth.password)
        XCTAssertNil(auth.token)
    }

    func testHttpAuthCarriesEveryVariantsFields() {
        let basic = Runtime.HttpAuth(type: "http", scheme: "basic", username: "u", password: "p")
        XCTAssertEqual(basic.scheme, "basic")
        XCTAssertEqual(basic.username, "u")
        XCTAssertEqual(basic.password, "p")
        let bearer = Runtime.HttpAuth(type: "http", scheme: "bearer", token: "t")
        XCTAssertEqual(bearer.token, "t")
        XCTAssertNil(bearer.username)
    }

    func testHttpRequestNeedsOnlyUrlAndMethod() {
        let request = Runtime.HttpRequest(url: "https://example.test/a", method: "GET")
        XCTAssertEqual(request.url, "https://example.test/a")
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.headers, [:])
        XCTAssertEqual(request.query, [:])
        XCTAssertNil(request.body)
        XCTAssertNil(request.auth)
        XCTAssertNil(request.timeout)
    }

    func testHttpRequestKeepsTheFullShape() {
        let request = Runtime.HttpRequest(
            url: "https://example.test/a",
            method: "POST",
            headers: ["content-type": "application/json"],
            query: ["q": "1"],
            body: Data("{}".utf8),
            auth: Runtime.HttpAuth(type: "http", scheme: "bearer", token: "t"),
            timeout: 2500
        )
        XCTAssertEqual(request.headers["content-type"], "application/json")
        XCTAssertEqual(request.query["q"], "1")
        XCTAssertEqual(request.body, Data("{}".utf8))
        XCTAssertEqual(request.auth?.token, "t")
        XCTAssertEqual(request.timeout, 2500)
    }

    func testHttpResponse() {
        let response = Runtime.HttpResponse(
            status: 201,
            headers: ["location": "/a/1"],
            body: Data("ok".utf8)
        )
        XCTAssertEqual(response.status, 201)
        XCTAssertEqual(response.headers["location"], "/a/1")
        XCTAssertEqual(String(decoding: response.body, as: UTF8.self), "ok")
    }

    func testHttpValidationFailure() {
        let failure = Runtime.HttpValidationFailure(status: 200, issue: "$.a: expected string")
        XCTAssertEqual(failure.status, 200)
        XCTAssertEqual(failure.issue, "$.a: expected string")
    }

    func testHttpValidationFailureTravelsAsARaisedPayload() throws {
        let raised: Error = DslError(
            code: "HTTP_VALIDATION_FAILED",
            payload: Runtime.HttpValidationFailure(status: 500, issue: "boom")
        )
        let erased = try XCTUnwrap(raised as? AnyDslError)
        XCTAssertEqual(erased.code, "HTTP_VALIDATION_FAILED")
    }

    func testSharedBoxReturnsWhatItWasGiven() async {
        let box = Runtime.SharedBox<Int64>(7)
        let value = await box.get()
        XCTAssertEqual(value, 7)
    }

    func testSharedBoxUpdateReturnsTheNewValue() async throws {
        let box = Runtime.SharedBox<Int64>(1)
        let returned = try await box.update { $0 + 41 }
        XCTAssertEqual(returned, 42)
        let stored = await box.get()
        XCTAssertEqual(stored, 42)
    }

    func testSharedBoxLosesNoConcurrentUpdate() async throws {
        let box = Runtime.SharedBox<Int64>(0)
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<200 {
                group.addTask {
                    _ = try? await box.update { $0 + 1 }
                }
            }
        }
        let total = await box.get()
        XCTAssertEqual(total, 200)
    }

    func testSharedBoxPropagatesAThrowAndKeepsTheOldValue() async throws {
        let box = Runtime.SharedBox<Int64>(5)
        do {
            _ = try await box.update { _ in throw DslError(code: "BOOM", payload: "x") }
            XCTFail("update swallowed the raise")
        } catch let error as AnyDslError {
            XCTAssertEqual(error.code, "BOOM")
        }
        let stored = await box.get()
        XCTAssertEqual(stored, 5)
    }

    func testSharedBoxCarriesANonNumericValue() async throws {
        let box = Runtime.SharedBox<[String]>([])
        _ = try await box.update { $0 + ["a"] }
        _ = try await box.update { $0 + ["b"] }
        let stored = await box.get()
        XCTAssertEqual(stored, ["a", "b"])
    }

    func testSemaphoreHandsOutThePermitsItHas() async {
        let sema = Runtime.Semaphore(2)
        await sema.acquire()
        await sema.acquire()
        await sema.release()
        await sema.release()
        // Two more must still be free, or the count did not come back.
        await sema.acquire()
        await sema.acquire()
        await sema.release()
        await sema.release()
    }

    func testSemaphoreBoundsHowManyRunAtOnce() async {
        let limit = 3
        let sema = Runtime.Semaphore(limit)
        let peak = Runtime.SharedBox<Int64>(0)
        let inFlight = Runtime.SharedBox<Int64>(0)
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<40 {
                group.addTask {
                    await sema.acquire()
                    let now = (try? await inFlight.update { $0 + 1 }) ?? 0
                    _ = try? await peak.update { max($0, now) }
                    await Task.yield()
                    _ = try? await inFlight.update { $0 - 1 }
                    await sema.release()
                }
            }
        }
        let highWater = await peak.get()
        let left = await inFlight.get()
        XCTAssertLessThanOrEqual(highWater, Int64(limit))
        XCTAssertGreaterThan(highWater, 0)
        XCTAssertEqual(left, 0)
    }

    func testSemaphoreResumesAWaiter() async {
        let sema = Runtime.Semaphore(1)
        await sema.acquire()
        let waiter = Task {
            await sema.acquire()
            await sema.release()
            return true
        }
        await sema.release()
        let resumed = await waiter.value
        XCTAssertTrue(resumed)
    }

    func testSharedTypesAreSendable() {
        requireSendable(Runtime.File.self)
        requireSendable(Runtime.FormPart.self)
        requireSendable(Runtime.ValidationIssue.self)
        requireSendable(Runtime.HttpAuth.self)
        requireSendable(Runtime.HttpRequest.self)
        requireSendable(Runtime.HttpResponse.self)
        requireSendable(Runtime.HttpValidationFailure.self)
        requireSendable(Runtime.SharedBox<Int64>.self)
        requireSendable(Runtime.Semaphore.self)
    }
}
