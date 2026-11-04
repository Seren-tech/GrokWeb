import Foundation

struct Site {
    let name: String
    let url: URL
}

struct UAPreset {
    let name: String
    let value: String?   // nil = WebKit's native WebView UA
}

enum Config {
    // >>> CHANGE THE DEFAULT USER-AGENT HERE <<<
    static let defaultUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.6 Mobile/15E148 Safari/604.1"

    // Shown in the "User-Agent" menu. Index 0 is the startup default.
    static let userAgentPresets: [UAPreset] = [
        UAPreset(name: "Safari iOS 18 (default)", value: defaultUserAgent),
        UAPreset(name: "Safari iOS 17",
                 value: "Mozilla/5.0 (iPhone; CPU iPhone OS 17_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Mobile/15E148 Safari/604.1"),
        UAPreset(name: "Safari iOS 15",
                 value: "Mozilla/5.0 (iPhone; CPU iPhone OS 15_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.1 Mobile/15E148 Safari/604.1"),
        UAPreset(name: "Safari macOS (desktop)",
                 value: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.6 Safari/605.1.15"),
        UAPreset(name: "WebView native UA", value: nil)
    ]

    static let sites: [Site] = [
        Site(name: "grok.com", url: URL(string: "https://grok.com")!),
        Site(name: "x.com/i/grok", url: URL(string: "https://x.com/i/grok")!)
    ]

    // Injected into <meta name="viewport">
    static let viewportContent = "width=device-width, initial-scale=1, viewport-fit=cover"

    // Hosts that stay inside the app (suffix match). Everything else that the user
    // taps as a link opens in Safari. Add OAuth/IdP domains here if a login breaks.
    static let inAppHostSuffixes: [String] = [
        "grok.com", "x.ai", "x.com", "twitter.com", "twimg.com",
        "google.com", "gstatic.com", "googleusercontent.com",
        "apple.com", "icloud.com",
        "microsoftonline.com", "live.com", "microsoft.com",
        "cloudflare.com", "hcaptcha.com", "arkoselabs.com", "github.com"
    ]

    static func isInAppHost(_ host: String) -> Bool {
        let h = host.lowercased()
        return inAppHostSuffixes.contains { h == $0 || h.hasSuffix("." + $0) }
    }
}
