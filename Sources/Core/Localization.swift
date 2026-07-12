// SPDX-License-Identifier: Apache-2.0
import Foundation

/// The Core resource bundle. Exposed so the app layer can resolve Core-owned
/// strings (safety tiers, rule copy) against an explicit language sub-bundle
/// when the user overrides the system language (SPEC §8.5(6)).
///
/// Resolution is explicit because the generated `Bundle.module` accessor only
/// checks the enclosing bundle's root and the original build directory —
/// a relocated .app keeps its resource bundles under Contents/Resources.
public enum CoreResources {
    public static var bundle: Bundle { resolved }

    private static let resolved: Bundle = {
        let name = "Mothball_Core.bundle"
        for base in [Bundle.main.resourceURL, Bundle.main.bundleURL] {
            if let url = base?.appendingPathComponent(name),
               let bundle = Bundle(url: url) {
                return bundle
            }
        }
        // Development builds (swift run / swift test) resolve next to the
        // executable via the generated accessor.
        return .module
    }()
}

extension Safety {
    /// Localized tier name for UI display.
    public var localizedName: String {
        String(localized: .init("safety.\(rawValue).name"), bundle: CoreResources.bundle)
    }

    /// Localized one-line explanation of what this tier means for the user.
    public var localizedExplanation: String {
        String(localized: .init("safety.\(rawValue).explanation"), bundle: CoreResources.bundle)
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
        let value = CoreResources.bundle.localizedString(forKey: key, value: key, table: "Localizable")
        return value == key ? fallback : value
    }
}
