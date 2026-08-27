// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClipTen",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "ClipTen", targets: ["ClipTen"])
    ],
    targets: [
        .executableTarget(
            name: "ClipTen",
            path: "Sources/ClipTen"
        ),
        .testTarget(
            name: "ClipTenTests",
            dependencies: ["ClipTen"],
            path: "Tests/ClipTenTests"
        )
    ]
)
