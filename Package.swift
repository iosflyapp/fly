// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "SwiftIDE",
    platforms: [.iOS(.v16)],
    products: [.executable(name: "SwiftIDE", targets: ["SwiftIDE"])],
    targets: [.executableTarget(name: "SwiftIDE", path: ".", sources: ["main.swift"])]
)