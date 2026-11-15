// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Noteboard",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Noteboard", targets: ["Noteboard"]),
    ],
    dependencies: [
        // 자동 업데이트. 번들의 Contents/Frameworks 에 함께 넣는다(scripts/bundle.sh).
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1"),
    ],
    targets: [
        // 화면과 무관한 로직. 테스트는 이 타깃만 본다.
        .target(name: "NoteboardCore"),
        .executableTarget(
            name: "Noteboard",
            dependencies: ["NoteboardCore", .product(name: "Sparkle", package: "Sparkle")],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("WebKit"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(name: "NoteboardCoreTests", dependencies: ["NoteboardCore"]),
    ]
)
