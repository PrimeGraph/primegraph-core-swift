//
// PrimeGraphCore
//
// The type-erased JSON carrier every generated package shares.
//
// The body below is the one the compiler used to emit into each package's own
// Runtime target. It lives here instead so a value built in one package still
// satisfies a slot declared in another: two copies of this struct are two
// unrelated nominal types, and a cast between them cannot be written.
//

import Foundation

/// The one wire format an instant is written on, matching what `timeNow`
/// produces: UTC, exactly three fractional digits, `Z`.
let canonicalInstantFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
    f.timeZone = TimeZone(identifier: "UTC")
    return f
}()

/// Type-erased JSON value that conforms to Codable, Equatable and Hashable.
public struct AnyCodable: Codable, Hashable, Sendable {
    public enum JSONValue: Hashable, Sendable {
        case null
        case bool(Bool)
        case int(Int)
        case double(Double)
        case string(String)
        indirect case array([AnyCodable])
        indirect case object([String: AnyCodable])
    }

    public let value: JSONValue

    public init(_ value: JSONValue) {
        self.value = value
    }

    /// Boxes an untyped JSON-shaped value — what an SDK read hands back as
    /// `Any` / `[String: Any]` — into the codable representation an untyped
    /// schema slot stores. Mirrors the initializer of the external package.
    public init(_ value: Any?) {
        self.value = AnyCodable.jsonValue(of: value)
    }

    private static func jsonValue(of value: Any?) -> JSONValue {
        guard let value = value, !(value is NSNull) else {
            return .null
        }
        if let number = value as? NSNumber {
            return numberValue(number)
        }
        if let text = value as? String {
            return .string(text)
        }
        if let list = value as? [Any] {
            return .array(list.map { AnyCodable($0) })
        }
        if let object = value as? [String: Any] {
            return .object(object.mapValues { AnyCodable($0) })
        }
        return encodedValue(value)
    }

    // A boolean bridges to NSNumber like every other number, so the CoreFoundation
    // type id is what tells 1 apart from true.
    private static func numberValue(_ number: NSNumber) -> JSONValue {
        if CFGetTypeID(number) == CFBooleanGetTypeID() {
            return .bool(number.boolValue)
        }
        if let integer = Int(exactly: number) {
            return .int(integer)
        }
        return .double(number.doubleValue)
    }

    // A value outside the JSON set (a Date, an SDK timestamp, a model struct)
    // lands as whatever JSON it encodes to; anything not encodable at all is
    // described rather than dropped.
    private static func encodedValue(_ value: Any) -> JSONValue {
        guard let encodable = value as? Encodable else {
            return .string(String(describing: value))
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .formatted(canonicalInstantFormatter)
        guard let data = try? encoder.encode([AnyCodableEncodableBox(value: encodable)]),
              let decoded = try? JSONDecoder().decode([AnyCodable].self, from: data),
              let first = decoded.first else {
            return .string(String(describing: value))
        }
        return first.value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = .null
        } else if let boolValue = try? container.decode(Bool.self) {
            value = .bool(boolValue)
        } else if let intValue = try? container.decode(Int.self) {
            value = .int(intValue)
        } else if let doubleValue = try? container.decode(Double.self) {
            value = .double(doubleValue)
        } else if let stringValue = try? container.decode(String.self) {
            value = .string(stringValue)
        } else if let arrayValue = try? container.decode([AnyCodable].self) {
            value = .array(arrayValue)
        } else if let objectValue = try? container.decode([String: AnyCodable].self) {
            value = .object(objectValue)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "AnyCodable: unsupported JSON value"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case .null:
            try container.encodeNil()
        case let .bool(boolValue):
            try container.encode(boolValue)
        case let .int(intValue):
            try container.encode(intValue)
        case let .double(doubleValue):
            try container.encode(doubleValue)
        case let .string(stringValue):
            try container.encode(stringValue)
        case let .array(arrayValue):
            try container.encode(arrayValue)
        case let .object(objectValue):
            try container.encode(objectValue)
        }
    }
}

private struct AnyCodableEncodableBox: Encodable {
    let value: Encodable
    func encode(to encoder: Encoder) throws {
        try value.encode(to: encoder)
    }
}
