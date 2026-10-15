import Foundation

enum AppInfo {
    /// Placeholder until the hosted privacy policy is published.
    static let privacyPolicyURL = URL(string: "https://alpsenel.github.io/vocabi/privacy")!

    static var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
