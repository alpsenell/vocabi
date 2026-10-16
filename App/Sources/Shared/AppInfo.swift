import Foundation

enum AppInfo {
    static let privacyPolicyURL = URL(string: "https://alpsenell.github.io/vocabi/privacy")!
    /// Apple's standard licensed application end user license agreement.
    static let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    static let defaultPackServerURL = URL(string: "https://vocabi-packs.alpsenel.workers.dev")!

    /// AI word pack server. Override with the `-VocabiPackServer <url>` launch argument.
    static var packServerURL: URL {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-VocabiPackServer"), args.indices.contains(i + 1),
           let url = URL(string: args[i + 1]), url.scheme != nil {
            return url
        }
        return defaultPackServerURL
    }

    static var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
