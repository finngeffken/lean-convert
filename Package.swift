// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ImageDrop",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "ConversionKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "ImageDrop",
            dependencies: ["ConversionKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Not a `testTarget`: XCTest ships only with a full Xcode, and the
        // Testing.framework in the Command Line Tools is missing the
        // lib_TestingInterop.dylib it links against. The suite therefore runs
        // as a plain executable — see Tests/ConversionKitTests/TestRunner.swift.
        .executableTarget(
            name: "ConversionKitTests",
            dependencies: ["ConversionKit"],
            path: "Tests/ConversionKitTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
