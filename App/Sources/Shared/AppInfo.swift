import Foundation

enum AppInfo {
    static let privacyPolicyURL = URL(string: "https://alpsenell.github.io/vocabi/privacy")!

    static var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
