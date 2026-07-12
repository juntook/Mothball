// SPDX-License-Identifier: Apache-2.0
import Core
import Foundation
import Observation

/// User-selectable UI language (SPEC §8.5(6)).
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    var id: String { rawValue }
}

/// Resolves strings against explicit language sub-bundles so an in-app
/// language override takes effect immediately, without relying on
/// process-level AppleLanguages mutation (SPEC §8.5(6), §9.12).
@MainActor
@Observable
final class LocalizationModel {
    var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: "appLanguage")
            recompute()
        }
    }

    /// Locale injected into the SwiftUI environment for FormatStyles.
    private(set) var locale: Locale = .current
    /// Bundle for app-target strings; the main module bundle when following
    /// the system, a language sub-bundle when overridden.
    private(set) var appBundle: Bundle = .module
    /// Same for Core-owned strings (safety tiers, rule copy).
    private(set) var coreBundle: Bundle = CoreResources.bundle

    init() {
        let stored = UserDefaults.standard.string(forKey: "appLanguage")
        language = stored.flatMap(AppLanguage.init(rawValue:)) ?? .system
        recompute()
    }

    private func recompute() {
        switch language {
        case .system:
            locale = .current
            appBundle = .module
            coreBundle = CoreResources.bundle
        case .english, .simplifiedChinese:
            locale = Locale(identifier: language.rawValue)
            appBundle = Self.subBundle(of: .module, language: language.rawValue)
            coreBundle = Self.subBundle(of: CoreResources.bundle, language: language.rawValue)
        }
    }

    /// The `<lang>.lproj` sub-bundle, falling back to the parent bundle when
    /// the localization is missing (strings then resolve via normal lookup).
    private static func subBundle(of bundle: Bundle, language: String) -> Bundle {
        guard let path = bundle.path(forResource: language, ofType: "lproj"),
              let sub = Bundle(path: path) else { return bundle }
        return sub
    }

    // MARK: String lookup

    /// App-target string for contexts that need a plain String (help text,
    /// window titles). SwiftUI views pass `bundle: appBundle` to Text instead.
    func string(_ key: String) -> String {
        appBundle.localizedString(forKey: key, value: key, table: "Localizable")
    }

    func string(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), locale: locale, arguments: arguments)
    }

    private func coreString(key: String, fallback: String) -> String {
        let value = coreBundle.localizedString(forKey: key, value: key, table: "Localizable")
        return value == key ? fallback : value
    }

    // MARK: Core-owned copy resolved against the selected language

    func safetyName(_ safety: Safety) -> String {
        coreString(key: "safety.\(safety.rawValue).name", fallback: safety.localizedName)
    }

    func safetyExplanation(_ safety: Safety) -> String {
        coreString(key: "safety.\(safety.rawValue).explanation", fallback: safety.localizedExplanation)
    }

    func ruleDescription(ruleID: String, target: Target) -> String {
        coreString(key: "rule.\(ruleID).\(target.id).description", fallback: target.description)
    }

    func regenerateHint(ruleID: String, target: Target) -> String? {
        guard let hint = target.regenerateHint else { return nil }
        return coreString(key: "rule.\(ruleID).\(target.id).hint", fallback: hint)
    }
}
