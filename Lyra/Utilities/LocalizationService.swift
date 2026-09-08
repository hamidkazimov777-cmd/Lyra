import Foundation
import SwiftUI

/// Supported user interface languages for Lyra.
enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case russian = "ru"
    case spanish = "es"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english: return "English"
        case .russian: return "Русский"
        case .spanish: return "Español"
        }
    }
}

/// Dynamic localization service that switches languages at runtime without requiring an app restart.
final class LocalizationService: ObservableObject {
    static let shared = LocalizationService()

    @Published private(set) var currentLanguage: AppLanguage = .english
    private var bundle: Bundle?

    private init() {
        let savedRaw = UserDefaults.standard.string(forKey: "interfaceLanguage")
        let lang: AppLanguage
        if let savedRaw = savedRaw, let found = AppLanguage(rawValue: savedRaw) {
            lang = found
        } else {
            // Check system preferred language
            let preferred = Locale.preferredLanguages.first?.lowercased() ?? ""
            if preferred.hasPrefix("ru") {
                lang = .russian
            } else if preferred.hasPrefix("es") {
                lang = .spanish
            } else {
                lang = .english
            }
        }
        setLanguage(lang, notify: false)
    }

    /// Changes active interface language and loads the corresponding .lproj bundle.
    func setLanguage(_ language: AppLanguage, notify: Bool = true) {
        currentLanguage = language
        if let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"),
           let langBundle = Bundle(path: path) {
            self.bundle = langBundle
        } else {
            self.bundle = Bundle.main
        }

        UserDefaults.standard.set(language.rawValue, forKey: "interfaceLanguage")
        UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")

        if notify {
            objectWillChange.send()
        }
    }

    /// Looks up a localized string for the current language.
    func tr(_ key: String) -> String {
        guard let bundle = self.bundle else {
            return NSLocalizedString(key, comment: "")
        }
        return bundle.localizedString(forKey: key, value: nil, table: nil)
    }
}

/// Global helper shorthand for localization
enum L10n {
    static func tr(_ key: String) -> String {
        LocalizationService.shared.tr(key)
    }
}

extension String {
    /// Returns the localized version of this string in the current interface language.
    var localized: String {
        L10n.tr(self)
    }
}
