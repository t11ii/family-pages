// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "FamilyPublisher",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "FamilyPublisher", path: "Sources/FamilyPublisher")
    ]
)
