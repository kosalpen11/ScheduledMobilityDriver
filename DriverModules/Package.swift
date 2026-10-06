// swift-tools-version: 5.9

//
//  Package.swift
//  ScheduledMobilityDriver
//
//  Created by Kosal Pen on 10/4/26.
//


import PackageDescription

let package = Package(
    name: "DriverModules",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(name: "DriverDomain", targets: ["DriverDomain"]),
        .library(name: "DriverData", targets: ["DriverData"]),
        .library(name: "PlatformServices", targets: ["PlatformServices"]),
        .library(name: "FeatureContracts", targets: ["FeatureContracts"]),
        .library(name: "DriverPresentation", targets: ["DriverPresentation"]),
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
        .library(name: "DriverUIKit", targets: ["DriverUIKit"]),
        .library(name: "DriverSwiftUI", targets: ["DriverSwiftUI"])
    ],
    dependencies: [
        .package(url: "https://github.com/scenee/FloatingPanel", from: "3.2.4")
    ],
    targets: [
        .target(name: "DriverDomain"),
        .target(
            name: "PlatformServices",
            dependencies: ["DriverDomain"]
        ),
        .target(
            name: "DriverData",
            dependencies: ["DriverDomain", "PlatformServices"]
        ),
        .target(
            name: "FeatureContracts",
            dependencies: ["DriverDomain"]
        ),
        .target(
            name: "DriverPresentation",
            dependencies: ["DriverDomain"]
        ),
        .target(name: "DesignSystem"),
        .target(
            name: "DriverUIKit",
            dependencies: [
                "DesignSystem",
                "DriverPresentation",
                "FeatureContracts",
                .product(name: "FloatingPanel", package: "FloatingPanel")
            ]
        ),
        .target(
            name: "DriverSwiftUI",
            dependencies: [
                "DesignSystem",
                "DriverPresentation",
                "FeatureContracts",
                .product(name: "FloatingPanel", package: "FloatingPanel")
            ]
        ),
        .testTarget(
            name: "DriverDomainTests",
            dependencies: ["DriverDomain"]
        ),
        .testTarget(
            name: "DriverDataTests",
            dependencies: ["DriverData", "DriverDomain", "PlatformServices"]
        ),
        .testTarget(
            name: "DriverPresentationTests",
            dependencies: ["DriverPresentation", "DriverDomain"]
        ),
        .testTarget(
            name: "DriverUIKitTests",
            dependencies: ["DriverUIKit"]
        )
    ]
)
