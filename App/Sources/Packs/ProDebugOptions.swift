#if DEBUG
import Foundation

/// Debug-only launch arguments for the Pro / packs screens (screenshots, manual QA):
///   -VocabiPaywall          presents the paywall sheet at launch
///   -VocabiCustomTopics     presents the custom topics editor at launch
///   -VocabiHardPaywall      forces `ProPolicy.hardPaywall`
///   -VocabiDevToken <x>     unlocks Pro and sends `Bearer dev:<x>` to the pack server
///   -VocabiPackServer <url> overrides `AppInfo.packServerURL`
enum ProDebugOptions {
    static var showPaywall: Bool { ProcessInfo.processInfo.arguments.contains("-VocabiPaywall") }
    static var showCustomTopics: Bool { ProcessInfo.processInfo.arguments.contains("-VocabiCustomTopics") }
}
#endif
