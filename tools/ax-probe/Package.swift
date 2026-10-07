// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ax-probe",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "ax-probe")
    ]
)
