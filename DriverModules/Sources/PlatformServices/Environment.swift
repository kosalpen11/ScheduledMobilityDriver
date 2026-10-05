//
//  Environment.swift
//  ScheduledMobilityDriver
//
//  Created by Kosal Pen on 10/4/26.
//

import Foundation

public enum DriverEnvironment: String, CaseIterable, Sendable {
    case mock
    case local
    case staging
    case production
}

public struct APIConfiguration: Sendable {
    public let environment: DriverEnvironment
    public let originURL: URL?
    public let apiPrefix: String

    public init(environment: DriverEnvironment, originURL: URL?, apiPrefix: String = "") {
        self.environment = environment
        self.originURL = originURL
        self.apiPrefix = apiPrefix
    }

    public var baseURL: URL? {
        guard let originURL else { return nil }
        let normalizedPrefix = apiPrefix
            .split(separator: "/")
            .joined(separator: "/")
        guard normalizedPrefix.isEmpty == false else {
            return originURL
        }
        return originURL.appendingPathComponent(normalizedPrefix)
    }

    public static let mock = APIConfiguration(environment: .mock, originURL: nil)
    public static let local = APIConfiguration(environment: .local, originURL: URL(string: "http://localhost:8080"), apiPrefix: "/api/v1")
    public static let staging = APIConfiguration(environment: .staging, originURL: URL(string: "https://api.146-190-4-99.sslip.io"), apiPrefix: "/api/v1")
}
