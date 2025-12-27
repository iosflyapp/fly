// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "SwiftIDE",
    platforms: [.iOS(.v16)],
    products: [.library(name: "SwiftIDE", targets: ["SwiftIDE"])],
    targets: [.target(name: "SwiftIDE", path: ".", sources: ["main.swift"])]
)