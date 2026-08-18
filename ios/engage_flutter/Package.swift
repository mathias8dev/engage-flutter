// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import Foundation
import PackageDescription

let manifestDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let localEngageConfiguration = manifestDirectory.appendingPathComponent(".engage-local")
let engageIosSdkVersion: Version = "2.1.1"
let engageIosDependency: Package.Dependency

if FileManager.default.fileExists(atPath: localEngageConfiguration.path) {
    let localPath = (try? String(contentsOf: localEngageConfiguration, encoding: .utf8))?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    precondition(!localPath.isEmpty, ".engage-local must contain the Engage iOS SDK path")
    precondition(
        FileManager.default.fileExists(atPath: URL(fileURLWithPath: localPath).appendingPathComponent("Package.swift").path),
        "The Engage iOS SDK path does not contain Package.swift: \(localPath)"
    )
    engageIosDependency = .package(name: "engage-ios", path: localPath)
} else {
    engageIosDependency = .package(
        url: "https://github.com/mathias8dev/engage-ios.git",
        exact: engageIosSdkVersion
    )
}

let package = Package(
    name: "engage_flutter",
    platforms: [
        .iOS("15.0")
    ],
    products: [
        .library(name: "engage-flutter", targets: ["engage_flutter"])
    ],
    dependencies: [
        engageIosDependency
    ],
    targets: [
        .target(
            name: "engage_flutter",
            dependencies: [
                .product(name: "EngageSDK", package: "engage-ios")
            ]
        )
    ]
)
