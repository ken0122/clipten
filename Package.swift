// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClipTen",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "ClipTen", targets: ["ClipTen"]),
        .executable(name: "ClipTenIconGenerator", targets: ["ClipTenIconGenerator"])
    ],
    targets: [
        .target(
            name: "ClipTenDesign",
            path: "Sources/ClipTenDesign"
        ),
        .executableTarget(
            name: "ClipTen",
            dependencies: ["ClipTenDesign"],
            path: "Sources/ClipTen"
        ),
        .executableTarget(
            name: "ClipTenIconGenerator",
            dependencies: ["ClipTenDesign"],
            path: "Sources/ClipTenIconGenerator"
        ),
        .testTarget(
            name: "ClipTenTests",
            dependencies: ["ClipTen", "ClipTenDesign"],
            path: "Tests/ClipTenTests"
        )
    ]
)
