import Foundation

/// The configured CAPTCHA type is distinct from the per-account challenge decision.
enum CASLoginPolicy {
    static func captchaEnabled(in html: String) -> Bool {
        guard let mode = html.firstMatch(#"captchaSwitch\s*=\s*['"]?([A-Za-z0-9]+)"#)?.lowercased() else { return false }
        return mode != "0" && mode != "false"
    }

    static func explicitlyRequiresCaptcha(in html: String) -> Bool {
        guard captchaEnabled(in: html) else { return false }
        if let required = html.firstMatch(#"\bneedCaptcha\s*=\s*['"]?([A-Za-z0-9]+)"#)?.lowercased(), required == "true" || required == "1" { return true }
        return html.firstMatch(#"_badCredentialsCount\s*=\s*['"]?(\d+)"#) == "0"
    }

    static func captchaDecision(from data: Data) -> Bool? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let value = json["isNeed"] as? Bool { return value }
        if let value = json["isNeed"] as? String {
            switch value.lowercased() {
            case "true", "1": return true
            case "false", "0": return false
            default: return nil
            }
        }
        return nil
    }
}
