// SPDX-License-Identifier: Apache-2.0
import Foundation

/// The Core resource bundle. Exposed so the app layer can resolve Core-owned
/// strings (safety tiers, rule copy) against an explicit language sub-bundle
/// when the user overrides the system language (SPEC §8.5(6)).
public enum CoreResources {
    public static var bundle: Bundle { .module }
}

extension Safety {
    /// Localized tier name for UI display.
    public var localizedName: String {
        String(localized: .init("safety.\(rawValue).name"), bundle: .module)
    }

    /// Localized one-line explanation of what this tier means for the user.
    public var localizedExplanation: String {
        String(localized: .init("safety.\(rawValue).explanation"), bundle: .module)
    }
}

/// Localization bridge for rule-library copy (SPEC §8.5(5)).
/// Rule JSON stays English; the UI first looks up a catalog key
/// `rule.<ruleId>.<targetId>.description` / `.hint` and falls back to the
/// English text embedded in the rule file.
public enum RuleLocalization {
    public static func description(ruleID: String, target: Target) -> String {
        localized(key: "rule.\(ruleID).\(target.id).description", fallback: target.description)
    }

    public static func regenerateHint(ruleID: String, target: Target) -> String? {
        guard let hint = target.regenerateHint else { return nil }
        return localized(key: "rule.\(ruleID).\(target.id).hint", fallback: hint)
    }

    private static func localized(key: String, fallback: String) -> String {
        let value = Bundle.module.localizedString(forKey: key, value: key, table: "Localizable")
        return value == key ? fallback : value
    }
}
