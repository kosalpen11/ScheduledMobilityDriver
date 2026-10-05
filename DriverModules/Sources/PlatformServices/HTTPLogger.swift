//
//  HTTPLogger.swift
//  ScheduledMobilityDriver
//
//  Created by Kosal Pen on 10/5/26.
//

import Foundation

public struct HTTPRequestContext: Sendable {
    public let requestID: String
    public let attempt: Int
    public let linkedRequestID: String?

    public init(
        requestID: String = UUID().uuidString,
        attempt: Int = 1,
        linkedRequestID: String? = nil
    ) {
        self.requestID = requestID
        self.attempt = attempt
        self.linkedRequestID = linkedRequestID
    }

    public func retryAttempt(_ attempt: Int) -> HTTPRequestContext {
        HTTPRequestContext(requestID: requestID, attempt: attempt, linkedRequestID: linkedRequestID)
    }
}

public protocol HTTPLogger: Sendable {
    func logRequest(_ request: URLRequest, context: HTTPRequestContext, body: HTTPLogBody) async
    func logResponse(_ response: HTTPURLResponse, context: HTTPRequestContext, duration: TimeInterval, body: Data) async
    func logError(_ error: Error, context: HTTPRequestContext, duration: TimeInterval) async
}

public enum HTTPLogBody: Sendable {
    case none
    case json(Data)
    case multipart([HTTPMultipartLogPart])
}

public struct HTTPMultipartLogPart: Sendable {
    public let name: String
    public let contentType: String?
    public let byteCount: Int
    public let isFile: Bool

    public init(name: String, contentType: String?, byteCount: Int, isFile: Bool) {
        self.name = name
        self.contentType = contentType
        self.byteCount = byteCount
        self.isFile = isFile
    }
}

public actor ConsoleHTTPLogger: HTTPLogger {
    private let maxBodyLength: Int

    public init(maxBodyLength: Int = 4_000) {
        self.maxBodyLength = maxBodyLength
    }

    public func logRequest(_ request: URLRequest, context: HTTPRequestContext, body: HTTPLogBody) async {
        var lines = [
            "[HTTP][REQUEST] id=\(context.requestID) attempt=\(context.attempt)\(linkedSuffix(context))",
            "\(request.httpMethod ?? "GET") \(sanitizedURL(request.url))",
            "Headers:"
        ]
        lines += sanitizedHeaders(request.allHTTPHeaderFields ?? [:])
        lines.append("Body:")
        lines += bodyLines(body)
        print(lines.joined(separator: "\n"))
    }

    public func logResponse(_ response: HTTPURLResponse, context: HTTPRequestContext, duration: TimeInterval, body: Data) async {
        var lines = [
            "[HTTP][RESPONSE] id=\(context.requestID) attempt=\(context.attempt)\(linkedSuffix(context))",
            "Status: \(response.statusCode)",
            "Duration: \(milliseconds(duration)) ms",
            "Body:"
        ]
        lines += dataLines(body)
        print(lines.joined(separator: "\n"))
    }

    public func logError(_ error: Error, context: HTTPRequestContext, duration: TimeInterval) async {
        let mapped = describe(error)
        let lines = [
            "[HTTP][ERROR] id=\(context.requestID) attempt=\(context.attempt)\(linkedSuffix(context))",
            "Type: \(mapped.type)",
            "Code: \(mapped.code)",
            "Message: \(sanitizeScalar(mapped.message))",
            "Duration: \(milliseconds(duration)) ms"
        ]
        print(lines.joined(separator: "\n"))
    }

    private func bodyLines(_ body: HTTPLogBody) -> [String] {
        switch body {
        case .none:
            return ["<empty>"]
        case .json(let data):
            return dataLines(data)
        case .multipart(let parts):
            guard parts.isEmpty == false else { return ["<empty multipart>"] }
            return parts.map { part in
                let kind = part.isFile ? "file" : "field"
                let contentType = part.contentType ?? "none"
                return "- \(part.name): kind=\(kind), contentType=\(contentType), bytes=\(part.byteCount)"
            }
        }
    }

    private func dataLines(_ data: Data) -> [String] {
        guard data.isEmpty == false else { return ["<empty>"] }
        if let object = try? JSONSerialization.jsonObject(with: data),
           JSONSerialization.isValidJSONObject(object),
           let pretty = try? JSONSerialization.data(
            withJSONObject: redactedJSON(object),
            options: [.prettyPrinted, .sortedKeys]
           ),
           let string = String(data: pretty, encoding: .utf8) {
            return limit(string).components(separatedBy: "\n")
        }
        let string = String(data: data, encoding: .utf8) ?? "<\(data.count) binary bytes>"
        return limit(sanitizeScalar(string)).components(separatedBy: "\n")
    }

    private func sanitizedHeaders(_ headers: [String: String]) -> [String] {
        guard headers.isEmpty == false else { return ["<none>"] }
        return headers
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            .map { key, value in
                sensitiveHeaderNames.contains(key.lowercased())
                    ? "\(key): <redacted>"
                    : "\(key): \(sanitizeScalar(value))"
            }
    }

    private func sanitizedURL(_ url: URL?) -> String {
        guard let url, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return "<invalid-url>"
        }
        components.queryItems = components.queryItems?.map { item in
            let value = sensitiveQueryNames.contains(item.name.lowercased()) ? "<redacted>" : item.value.map(sanitizeScalar)
            return URLQueryItem(name: item.name, value: value)
        }
        return components.string ?? "<invalid-url>"
    }

    private func redactedJSON(_ value: Any, key: String? = nil) -> Any {
        if let key, sensitiveJSONNames.contains(key.lowercased()) {
            return "<redacted>"
        }

        if let dictionary = value as? [String: Any] {
            return dictionary.reduce(into: [String: Any]()) { result, item in
                result[item.key] = redactedJSON(item.value, key: item.key)
            }
        }
        if let array = value as? [Any] {
            return array.map { redactedJSON($0, key: key) }
        }
        if let string = value as? String {
            return sanitizeScalar(string)
        }
        return value
    }

    private func sanitizeScalar(_ value: String) -> String {
        var sanitized = value
        sanitized = sanitized.replacingOccurrences(
            of: #"\+?855[0-9\s\-]{7,14}"#,
            with: "<redacted-phone>",
            options: .regularExpression
        )
        sanitized = sanitized.replacingOccurrences(
            of: #"\b[0-9]{4}\b"#,
            with: "<redacted-code>",
            options: .regularExpression
        )
        return sanitized
    }

    private func limit(_ value: String) -> String {
        guard value.count > maxBodyLength else { return value }
        let index = value.index(value.startIndex, offsetBy: maxBodyLength)
        return "\(value[..<index])\n<truncated \(value.count - maxBodyLength) chars>"
    }

    private func describe(_ error: Error) -> (type: String, code: String, message: String) {
        if let http = error as? HTTPClientError {
            switch http {
            case .invalidResponse:
                return ("response", "invalid-response", "The server response was not HTTP.")
            case .badStatus(let status, let problem):
                return ("http", problem?.code ?? "\(status)", problem?.detail ?? problem?.title ?? "HTTP \(status)")
            case .decoding:
                return ("decoding", "decode-failed", "The response body could not be decoded.")
            case .transport(let message):
                return ("transport", "network", message)
            }
        }
        return ("transport", String(describing: type(of: error)), error.localizedDescription)
    }

    private func linkedSuffix(_ context: HTTPRequestContext) -> String {
        guard let linkedRequestID = context.linkedRequestID else { return "" }
        return " linked=\(linkedRequestID)"
    }

    private func milliseconds(_ duration: TimeInterval) -> Int {
        Int((duration * 1_000).rounded())
    }
}

private let sensitiveHeaderNames: Set<String> = [
    "authorization",
    "cookie",
    "set-cookie",
    "x-api-key",
    "api-key"
]

private let sensitiveQueryNames: Set<String> = [
    "token",
    "access_token",
    "refresh_token",
    "api_key",
    "apikey",
    "phone",
    "code",
    "otp"
]

private let sensitiveJSONNames: Set<String> = [
    "phone",
    "code",
    "otp",
    "accessToken".lowercased(),
    "refreshToken".lowercased(),
    "token",
    "authorization",
    "fullName".lowercased(),
    "preferredLang".lowercased(),
    "nationalIdMasked".lowercased(),
    "plateNumber".lowercased(),
    "filename",
    "fileName".lowercased()
]
