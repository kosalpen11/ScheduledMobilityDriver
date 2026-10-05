//
//  HTTPClient.swift
//  ScheduledMobilityDriver
//
//  Created by Kosal Pen on 10/4/26.
//

import Foundation

public protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionHTTPTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw HTTPClientError.invalidResponse
        }
        return (data, http)
    }
}

public struct ProblemDetails: Error, Equatable, Sendable, Decodable {
    public let type: String?
    public let title: String?
    public let status: Int?
    public let detail: String?
    public let instance: String?
    public let code: String?

    public init(type: String?, title: String?, status: Int?, detail: String?, instance: String?, code: String?) {
        self.type = type
        self.title = title
        self.status = status
        self.detail = detail
        self.instance = instance
        self.code = code
    }
}

public enum HTTPClientError: Error, Equatable, Sendable {
    case invalidResponse
    case badStatus(Int, ProblemDetails?)
    case decoding
    case transport(String)
}

public struct MultipartFormPart: Sendable {
    public let name: String
    public let filename: String?
    public let contentType: String?
    public let data: Data

    public init(name: String, filename: String? = nil, contentType: String? = nil, data: Data) {
        self.name = name
        self.filename = filename
        self.contentType = contentType
        self.data = data
    }
}

public final class HTTPClient: Sendable {
    private let baseURL: URL
    private let transport: any HTTPTransport
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let logger: (any HTTPLogger)?

    public init(
        baseURL: URL,
        transport: any HTTPTransport = URLSessionHTTPTransport(),
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder(),
        logger: (any HTTPLogger)? = nil
    ) {
        self.baseURL = baseURL
        self.transport = transport
        self.encoder = encoder
        self.decoder = decoder
        self.logger = logger
    }

    public func send<Response: Decodable, Body: Encodable>(
        _ method: String,
        path: String,
        body: Body?,
        headers: [String: String] = [:],
        authenticatedBy accessToken: String? = nil,
        context: HTTPRequestContext = HTTPRequestContext()
    ) async throws -> Response {
        let data = try await sendData(method, path: path, body: body, headers: headers, authenticatedBy: accessToken, context: context)
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw HTTPClientError.decoding
        }
    }

    public func sendEmpty<Body: Encodable>(
        _ method: String,
        path: String,
        body: Body?,
        headers: [String: String] = [:],
        authenticatedBy accessToken: String? = nil,
        context: HTTPRequestContext = HTTPRequestContext()
    ) async throws {
        _ = try await sendData(method, path: path, body: body, headers: headers, authenticatedBy: accessToken, context: context)
    }

    public func sendMultipart<Response: Decodable>(
        _ method: String,
        path: String,
        parts: [MultipartFormPart],
        headers: [String: String] = [:],
        authenticatedBy accessToken: String? = nil,
        context: HTTPRequestContext = HTTPRequestContext()
    ) async throws -> Response {
        let boundary = "Boundary-\(UUID().uuidString)"
        let body = makeMultipartBody(parts: parts, boundary: boundary)
        var request = URLRequest(url: endpointURL(path: path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("en", forHTTPHeaderField: "Accept-Language")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }

        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        request.httpBody = body

        let logParts = parts.map {
            HTTPMultipartLogPart(
                name: $0.name,
                contentType: $0.contentType,
                byteCount: $0.data.count,
                isFile: $0.filename != nil
            )
        }
        let data = try await perform(request, context: context, body: .multipart(logParts))
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw HTTPClientError.decoding
        }
    }

    private func sendData<Body: Encodable>(
        _ method: String,
        path: String,
        body: Body?,
        headers: [String: String],
        authenticatedBy accessToken: String?,
        context: HTTPRequestContext
    ) async throws -> Data {
        var request = URLRequest(url: endpointURL(path: path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("en", forHTTPHeaderField: "Accept-Language")
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }

        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        let requestBody: HTTPLogBody
        if let body {
            let data = try encoder.encode(body)
            request.httpBody = data
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            requestBody = .json(data)
        } else {
            requestBody = .none
        }

        return try await perform(request, context: context, body: requestBody)
    }

    private func perform(_ request: URLRequest, context: HTTPRequestContext, body: HTTPLogBody) async throws -> Data {
        let startedAt = Date()
        await logger?.logRequest(request, context: context, body: body)
        do {
            let (data, response) = try await transport.data(for: request)
            guard (200..<300).contains(response.statusCode) else {
                let error = HTTPClientError.badStatus(response.statusCode, decodeProblem(from: data))
                await logger?.logResponse(response, context: context, duration: Date().timeIntervalSince(startedAt), body: data)
                await logger?.logError(error, context: context, duration: Date().timeIntervalSince(startedAt))
                throw error
            }
            await logger?.logResponse(response, context: context, duration: Date().timeIntervalSince(startedAt), body: data)
            return data.isEmpty ? Data("{}".utf8) : data
        } catch let error as HTTPClientError {
            if case .badStatus = error {
                throw error
            }
            await logger?.logError(error, context: context, duration: Date().timeIntervalSince(startedAt))
            throw error
        } catch {
            let mapped = HTTPClientError.transport(error.localizedDescription)
            await logger?.logError(mapped, context: context, duration: Date().timeIntervalSince(startedAt))
            throw mapped
        }
    }

    private func endpointURL(path: String) -> URL {
        let basePrefix = baseURL.path
            .split(separator: "/")
            .joined(separator: "/")
        var normalizedPath = path
            .split(separator: "/")
            .joined(separator: "/")

        if basePrefix.isEmpty == false {
            if normalizedPath == basePrefix {
                normalizedPath = ""
            } else if normalizedPath.hasPrefix("\(basePrefix)/") {
                normalizedPath.removeFirst(basePrefix.count + 1)
            }
        }

        guard normalizedPath.isEmpty == false else {
            return baseURL
        }
        return baseURL.appendingPathComponent(normalizedPath)
    }

    private func makeMultipartBody(parts: [MultipartFormPart], boundary: String) -> Data {
        var data = Data()
        for part in parts {
            data.appendString("--\(boundary)\r\n")
            if let filename = part.filename {
                data.appendString("Content-Disposition: form-data; name=\"\(part.name)\"; filename=\"\(filename)\"\r\n")
            } else {
                data.appendString("Content-Disposition: form-data; name=\"\(part.name)\"\r\n")
            }
            if let contentType = part.contentType {
                data.appendString("Content-Type: \(contentType)\r\n")
            }
            data.appendString("\r\n")
            data.append(part.data)
            data.appendString("\r\n")
        }
        data.appendString("--\(boundary)--\r\n")
        return data
    }

    private func decodeProblem(from data: Data) -> ProblemDetails? {
        guard data.isEmpty == false else { return nil }
        return try? decoder.decode(ProblemDetails.self, from: data)
    }
}

public struct EmptyBody: Encodable, Sendable {
    public init() {}
}

private extension Data {
    mutating func appendString(_ string: String) {
        append(Data(string.utf8))
    }
}
