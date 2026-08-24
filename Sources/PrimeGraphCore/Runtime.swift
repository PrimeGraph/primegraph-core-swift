//
// PrimeGraphCore
//
// The `Runtime` namespace and the members of it that cross a package boundary.
//
// `Runtime` stays a namespace enum rather than becoming the module itself
// because emitted code writes `Runtime.File`, `Runtime.jsonEncoder()` and
// `Runtime.validationError(...)` literally. A generated package adds its own
// private members — HTTP transport, Firebase, the pure expression helpers — as
// `extension Runtime` on this declaration, so both halves answer to the one
// spelling the emitter already produces.
//
// The bodies below are the ones the compiler used to emit into each package's
// own Runtime target.
//

import Foundation

public enum Runtime {
    public struct File: Codable, Hashable, Sendable {
        public let name: String
        public let mimeType: String
        public let data: Data
        public init(name: String, mimeType: String, data: Data) {
            self.name = name
            self.mimeType = mimeType
            self.data = data
        }
    }

    public struct FormPart: Equatable, Sendable {
        public let name: String
        public let value: String
        public let filename: String
        public let contentType: String
        public let data: Data
        public let isFile: Bool
        public init(
            name: String,
            value: String,
            filename: String,
            contentType: String,
            data: Data,
            isFile: Bool
        ) {
            self.name = name
            self.value = value
            self.filename = filename
            self.contentType = contentType
            self.data = data
            self.isFile = isFile
        }
    }

    public static func formField(_ name: String, _ value: String) -> FormPart {
        return FormPart(
            name: name,
            value: value,
            filename: "",
            contentType: "",
            data: Data(),
            isFile: false
        )
    }

    public static func jsonDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { inner in
            let text = try inner.singleValueContainer().decode(String.self)
            guard let date = parseInstant(text) else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: inner.codingPath,
                        debugDescription: "expected an RFC 3339 instant, got " + text
                    )
                )
            }
            return date
        }
        return decoder
    }

    public static func jsonEncoder() -> JSONEncoder {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .formatted(formatter)
        return encoder
    }

    public static func parseInstant(_ text: String) -> Date? {
        var normalized = text
        if let dot = normalized.firstIndex(of: ".") {
            var digits = ""
            var index = normalized.index(after: dot)
            while index < normalized.endIndex, normalized[index].isNumber {
                digits.append(normalized[index])
                index = normalized.index(after: index)
            }
            if digits.isEmpty {
                return nil
            }
            normalized = String(normalized[normalized.startIndex..<dot])
                + "." + String((digits + "000").prefix(3))
                + String(normalized[index...])
        } else if normalized.count > 19 {
            normalized = String(normalized.prefix(19)) + ".000" + String(normalized.dropFirst(19))
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSXXX"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: normalized)
    }

    // `Codable` so a catch can decide on the shape this payload carries: a
    // validation failure reaches a catch as JSON like every other raised payload.
    public struct ValidationIssue: Codable, Sendable {
        public let path: String
        public let expected: String
        public let actual: String
        public init(path: String, expected: String, actual: String) {
            self.path = path
            self.expected = expected
            self.actual = actual
        }
    }

    public static func validationError(
        path: String,
        expected: String,
        actual: String
    ) -> DslError<ValidationIssue> {
        return DslError(
            code: "VALIDATION_FAILED",
            payload: ValidationIssue(path: path, expected: expected, actual: actual)
        )
    }

    // The HTTP request/response value types, but not the transport that moves
    // them: `Runtime.fetch` and `Runtime.parseResponse` stay generated per
    // package. A function added twice by extension is not ambiguous, a nested
    // type declared twice is, and these are named at emitted call sites.

    public struct HttpAuth: Sendable {
        public let type: String
        public let scheme: String?
        public let `in`: String?
        public let name: String?
        public let value: String?
        public let username: String?
        public let password: String?
        public let token: String?
        public init(
            type: String,
            scheme: String? = nil,
            `in`: String? = nil,
            name: String? = nil,
            value: String? = nil,
            username: String? = nil,
            password: String? = nil,
            token: String? = nil
        ) {
            self.type = type
            self.scheme = scheme
            self.`in` = `in`
            self.name = name
            self.value = value
            self.username = username
            self.password = password
            self.token = token
        }
    }

    public struct HttpRequest: Sendable {
        public let url: String
        public let method: String
        public let headers: [String: String]
        public let query: [String: String]
        public let body: Data?
        public let auth: HttpAuth?
        public let timeout: Double?
        public init(
            url: String,
            method: String,
            headers: [String: String] = [:],
            query: [String: String] = [:],
            body: Data? = nil,
            auth: HttpAuth? = nil,
            timeout: Double? = nil
        ) {
            self.url = url
            self.method = method
            self.headers = headers
            self.query = query
            self.body = body
            self.auth = auth
            self.timeout = timeout
        }
    }

    public struct HttpResponse: Sendable {
        public let status: Int64
        public let headers: [String: String]
        public let body: Data
        public init(status: Int64, headers: [String: String], body: Data) {
            self.status = status
            self.headers = headers
            self.body = body
        }
    }

    public struct HttpValidationFailure: Sendable {
        public let status: Int64
        public let issue: String
        public init(status: Int64, issue: String) {
            self.status = status
            self.issue = issue
        }
    }
}
