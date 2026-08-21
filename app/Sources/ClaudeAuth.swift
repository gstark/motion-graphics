import Foundation
import Security

// Decides how the design agent authenticates to Claude.
//
// Preferred: the claude.ai subscription login that Claude Code stores when
// the user signs in with `claude`. The Agent SDK spawns that same logged-in
// CLI; with no ANTHROPIC_API_KEY in the environment, it uses the stored
// subscription token. HOME must stay intact so the CLI can reach the login
// keychain.
//
// Fallback: an API key in the Keychain, billed per token on the user's own
// Anthropic account.
enum ClaudeAuth {
    private static let assumeKey = "MotionGraphics.assumeSubscription"

    private static var credentialsFile: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
    }

    private static var oauth: [String: Any]? {
        guard let data = try? Data(contentsOf: credentialsFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any]
        else { return nil }
        return oauth
    }

    // Claude Code stores the login either in ~/.claude/.credentials.json or,
    // on newer versions, in the macOS Keychain under this service. Detecting
    // existence (not reading the secret) needs no permission prompt.
    private static func keychainHasClaudeLogin() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        return SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess
    }

    // The user pressed "I've signed in" — trust them even when detection
    // could not confirm it. If they were wrong, the design step reports a
    // clear "not signed in" message.
    static var assumeSubscription: Bool {
        get { UserDefaults.standard.bool(forKey: assumeKey) }
        set { UserDefaults.standard.set(newValue, forKey: assumeKey) }
    }

    static var hasSubscriptionLogin: Bool {
        oauth?["accessToken"] != nil || keychainHasClaudeLogin()
    }

    static var subscriptionLabel: String? {
        guard let type = oauth?["subscriptionType"] as? String else { return nil }
        switch type.lowercased() {
        case "max": return "Max"
        case "pro": return "Pro"
        case "team": return "Team"
        case "enterprise": return "Enterprise"
        case "free": return "Free"
        default: return type.capitalized
        }
    }

    static var apiKey: String? { Keychain.loadAPIKey() }

    static var isConfigured: Bool { hasSubscriptionLogin || assumeSubscription || apiKey != nil }

    enum Mode {
        case subscription
        case apiKey(String)
    }

    // Subscription wins when present or asserted; an API key is the fallback.
    static var mode: Mode? {
        if hasSubscriptionLogin || assumeSubscription { return .subscription }
        if let key = apiKey { return .apiKey(key) }
        return nil
    }
}
