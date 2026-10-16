import Foundation

/// How Vocabi Pro gates the app. Flip `ProGate.configuredPolicy` to change the business model.
enum ProPolicy {
    /// Bundled words, widgets, quiz and leaderboard are free; Pro unlocks AI packs and custom topics.
    /// Onboarding ends with a skippable "Try Vocabi Pro" screen.
    case freemium
    /// Paywall right after onboarding; the app is usable only with an active trial or subscription.
    case hardPaywall
}

enum ProGate {
    /// The one switch.
    static let configuredPolicy: ProPolicy = .freemium

    static var policy: ProPolicy {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-VocabiHardPaywall") { return .hardPaywall }
        #endif
        return configuredPolicy
    }

    /// True when the whole app must be covered by the paywall.
    static func requiresPaywall(isPro: Bool, hasCompletedOnboarding: Bool) -> Bool {
        policy == .hardPaywall && hasCompletedOnboarding && !isPro
    }
}

/// Debug-only bearer token so StoreKit-test / simulator builds can talk to the pack server.
/// Sources: `-VocabiDevToken <x>` launch argument, `VOCABI_DEV_TOKEN` environment variable, or a
/// `VOCABI_DEV_TOKEN` Info.plist value. Always `nil` in release builds.
enum DevToken {
    static var current: String? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-VocabiDevToken"), args.indices.contains(i + 1), !args[i + 1].isEmpty {
            return args[i + 1]
        }
        if let env = ProcessInfo.processInfo.environment["VOCABI_DEV_TOKEN"], !env.isEmpty { return env }
        if let plist = Bundle.main.object(forInfoDictionaryKey: "VOCABI_DEV_TOKEN") as? String,
           !plist.isEmpty, !plist.hasPrefix("$(") { return plist }
        #endif
        return nil
    }
}
