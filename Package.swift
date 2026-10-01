// swift-tools-version: 6.2
import PackageDescription

/// Asking for App Store ratings only through the system prompt, at moments the app declares, and
/// taking feedback through a separate door that is open at any time.
///
/// **No external dependencies.** SwiftPM resolves dependencies per package, so anything declared
/// here lands on every consumer, including ones that use only the decision rules. The bridge to
/// `swift-analytics` and an HTTP client both live in the app, in about twenty lines each
/// (see DESIGN.md).
let package = Package(
    name: "swift-review",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        // Vocabulary, the pure decision, the prompter, ports, the UserDefaults store, the
        // write-review link and feedback values. Foundation only: no StoreKit, no SwiftUI.
        .library(name: "ReviewCore", targets: ["ReviewCore"]),
        // The only target that imports StoreKit. Calls `RequestReviewAction` from the view tree,
        // and opens a feedback mail through `OpenURLAction`.
        .library(name: "ReviewSwiftUI", targets: ["ReviewSwiftUI"]),
        // Test doubles. **Never import this from a shipping target.**
        .library(name: "ReviewTesting", targets: ["ReviewTesting"])
    ],
    targets: [
        .target(name: "ReviewCore"),
        .target(name: "ReviewSwiftUI", dependencies: ["ReviewCore"]),
        .target(name: "ReviewTesting", dependencies: ["ReviewCore"]),

        .testTarget(name: "ReviewCoreTests", dependencies: ["ReviewCore", "ReviewTesting"]),
        .testTarget(name: "ReviewSwiftUITests", dependencies: ["ReviewSwiftUI", "ReviewTesting"])
    ]
)
