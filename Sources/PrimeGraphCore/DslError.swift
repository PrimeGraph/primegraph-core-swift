//
// PrimeGraphCore
//
// The DSL error carrier and everything a catch reads it through.
//
// The body below is the one the compiler used to emit into each package's own
// Runtime target. A protocol declared in two modules is two protocols, so an
// error raised in one generated package failed `as? AnyDslError` in another;
// declaring it once here is what makes the cast hold across a boundary.
//

import Foundation

public protocol AnyDslError: Error {
    var code: String { get }
    var anyPayload: Any? { get }
    /// The payload as JSON reads it. A catch decides on the SHAPE that arrived,
    /// and a nominal test says nothing about that shape: two blocks writing one
    /// and the same inline shape mint two unrelated types.
    var payloadJson: Any? { get }
}

public struct DslError<Payload: Sendable>: AnyDslError {
    public let code: String
    public let payload: Payload
    public init(code: String, payload: Payload) {
        self.code = code
        self.payload = payload
    }
    // Non-generic payload view so a broad `catch { }` can recover the payload
    // without knowing the concrete `Payload` (Swift generic structs are
    // invariant, so `as? DslError<Any?>` would fail).
    public var anyPayload: Any? { payload }
    // Built where `Payload` is still the very type the raise wrote.
    public var payloadJson: Any? { dslJsonWire(payload) }
}

extension DslError where Payload == Void {
    public init(code: String) {
        self.init(code: code, payload: ())
    }
}

/// A value that carries no `Encodable` conformance but does state a JSON object
/// form. `json.marshal` reaches it through this, so such a value renders the
/// same whether it is handed over directly or sits inside a map or a list.
public protocol DslJsonObjectConvertible {
    var jsonObject: [String: Any] { get }
}

/// The `{ code, payload }` a catch binds once the arrived payload has validated
/// against the type the catch declares.
public struct DslErrorView<Payload>: DslJsonObjectConvertible {
    public let code: String
    public let payload: Payload
    public init(code: String, payload: Payload) {
        self.code = code
        self.payload = payload
    }
    /// Foundation's JSON serializer only accepts collections at the top level,
    /// so `string()`/`json.marshal` on the error view routes through this map.
    public var jsonObject: [String: Any] {
        return ["code": code, "payload": (payload as Any?) ?? NSNull()]
    }
}

/// Default text of each error code. An error that reaches a catch from outside
/// the DSL has no message of its own — a foreign SDK's wording never reaches a
/// client — so the object it contributes is filled from here.
public let dslErrorMessages: [String: String] = [
    "AUTH_REQUIRED": "Authorization required",
    "VALIDATION_FAILED": "Request validation failed",
    "INTERNAL_ERROR": "Internal server error",
    "NOT_FOUND": "Resource not found",
    "METHOD_NOT_ALLOWED": "Method not allowed",
    "FORBIDDEN": "Access forbidden",
    "NO_RESPONSE": "Block did not produce a response",
    "invalid-argument": "Invalid argument",
    "failed-precondition": "Failed precondition",
    "out-of-range": "Value out of range",
    "unauthenticated": "Authorization required",
    "permission-denied": "Access forbidden",
    "not-found": "Resource not found",
    "already-exists": "Resource already exists",
    "resource-exhausted": "Resource exhausted",
    "cancelled": "Request cancelled",
    "data-loss": "Data loss",
    "unknown": "Unknown error",
    "internal": "Internal server error",
    "unavailable": "Service unavailable",
    "deadline-exceeded": "Deadline exceeded",
    "aborted": "Operation aborted",
    "UNSUPPORTED_MEDIA_TYPE": "Unsupported media type",
    "UTF8_DECODE_FAILED": "Input is not valid UTF-8",
    "BASE64_DECODE_FAILED": "Input is not valid base64",
    "HEX_DECODE_FAILED": "Input is not valid hex",
    "URL_DECODE_FAILED": "Input is not valid percent-encoded text",
    "ENUM_VALUE_NOT_A_MEMBER": "Value is not a member of the enumeration",
    "JSON_PARSE_FAILED": "Input is not valid JSON",
    "DECIMAL_PARSE_FAILED": "Input is not a decimal number",
    "DURATION_PARSE_FAILED": "Input is not a valid duration",
    "TIME_PARSE_FAILED": "Input does not match the expected time format",
]

public func defaultErrorMessage(_ code: String) -> String {
    return dslErrorMessages[code] ?? "Internal server error"
}

/// Wraps a value whose concrete type is only known at run time so the encoder
/// can reach its own `encode(to:)`.
private struct DslEncodableValue: Encodable {
    let value: Encodable
    func encode(to encoder: Encoder) throws {
        try value.encode(to: encoder)
    }
}

/// A value as JSON reads it. Anything the generated types encode goes through
/// the configured encoder — the one that pins the instant format — inside a
/// single-key container, since a bare top-level scalar has no container of its
/// own. A map or list of `Any` carries no encoding and already IS the wire form.
public func dslJsonWire(_ value: Any?) -> Any? {
    guard let x1 = value else {
        return NSNull()
    }
    guard let x2 = x1 as? Encodable else {
        return x1
    }
    guard let x3 = try? Runtime.jsonEncoder().encode(["value": DslEncodableValue(value: x2)]),
          let x4 = try? JSONSerialization.jsonObject(with: x3),
          let x5 = (x4 as? [String: Any])?["value"] else {
        return x1
    }
    return x5
}

/// What arrived at a catch, as JSON. A DSL raise contributes its payload's wire
/// form; anything else — a transport failure, an SDK exception — contributes the
/// standard error object, so a catch declaring `{ code, message }` handles it and
/// a catch declaring any other shape leaves it alone.
public func dslArrivedJson(_ e: Error) -> Any? {
    if let x1 = e as? AnyDslError {
        return x1.payloadJson
    }
    // A foreign error carries no typed payload, so its own text would be lost
    // here. It goes to the log instead of the value the catch sees.
    FileHandle.standardError.write(Data("[dsl] foreign error reached a catch: \(e)\n".utf8))
    return ["code": "INTERNAL_ERROR", "message": defaultErrorMessage("INTERNAL_ERROR")]
}

public func dslArrivedCode(_ e: Error) -> String {
    return (e as? AnyDslError)?.code ?? "INTERNAL_ERROR"
}

/// The arrived JSON read back as the type the catch declares. It has already
/// validated against that type's schema, so this is the step that rebuilds a
/// `uuid` / `date-time` / `date` as the instance the slot holds.
public func dslDecodedPayload<T: Decodable>(_ json: Any?, _ fallback: T) -> T {
    guard let x1 = json,
          let x2 = try? JSONSerialization.data(withJSONObject: x1, options: [.fragmentsAllowed]),
          let x3 = try? Runtime.jsonDecoder().decode(T.self, from: x2) else {
        return fallback
    }
    return x3
}
