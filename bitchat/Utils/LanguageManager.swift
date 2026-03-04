import SwiftUI
import UIKit

/// Manages in-app language selection and persistence.
/// Supports English and Farsi (Persian) languages with runtime switching.
final class LanguageManager: ObservableObject {
    static let shared = LanguageManager()
    
    private let languageKey = "selected_language"
    private let languageSetKey = "language_has_been_set"
    
    enum AppLanguage: String, CaseIterable, Identifiable {
        case english = "en"
        case farsi = "fa"
        
        var id: String { rawValue }
        
        var displayName: String {
            switch self {
            case .english: return "English"
            case .farsi: return "Farsi"
            }
        }
        
        var nativeDisplayName: String {
            switch self {
            case .english: return "English"
            case .farsi: return "فارسی"
            }
        }
        
        var locale: Locale {
            Locale(identifier: rawValue)
        }
        
        var layoutDirection: LayoutDirection {
            switch self {
            case .english: return .leftToRight
            case .farsi: return .rightToLeft
            }
        }
    }
    
    @Published var currentLanguage: AppLanguage {
        didSet {
            guard oldValue != currentLanguage else { return }
            UserDefaults.standard.set(currentLanguage.rawValue, forKey: languageKey)
            UserDefaults.standard.set(true, forKey: languageSetKey)
            applyLanguage()
        }
    }
    
    /// Unique ID that changes when language is switched, forcing SwiftUI to rebuild the view hierarchy
    @Published var refreshID = UUID()
    
    var isLanguageSet: Bool {
        UserDefaults.standard.bool(forKey: languageSetKey)
    }
    
    private init() {
        let savedCode = UserDefaults.standard.string(forKey: languageKey) ?? AppLanguage.english.rawValue
        self.currentLanguage = AppLanguage(rawValue: savedCode) ?? .english
        
        // Apply saved language on init if previously set
        if UserDefaults.standard.bool(forKey: languageSetKey) {
            applyLanguage()
        }
    }
    
    /// Apply the language override using UserDefaults.
    /// AppleLanguages takes effect on next app launch for system strings,
    /// but our custom locale modifier handles runtime switching for localized content.
    func applyLanguage() {
        UserDefaults.standard.set([currentLanguage.rawValue], forKey: "AppleLanguages")
        UserDefaults.standard.synchronize()
        
        // Force the semantic content attribute so UIKit navigation (back buttons,
        // swipe gestures) matches the selected language direction immediately.
        let semanticAttribute: UISemanticContentAttribute =
            currentLanguage == .farsi ? .forceRightToLeft : .forceLeftToRight
        UIView.appearance().semanticContentAttribute = semanticAttribute

        // Force complete view hierarchy refresh by changing the ID
        DispatchQueue.main.async {
            self.refreshID = UUID()
        }

        // Restart the Live Activity so it picks up the new localized strings.
        LiveActivityManager.shared.restartForLanguageChange()
    }
    
    /// Bundle for the current language, used for runtime translation lookup
    var localizedBundle: Bundle {
        guard let path = Bundle.main.path(forResource: currentLanguage.rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return .main
        }
        return bundle
    }
    
    /// Get a localized string for the current language
    func localizedString(_ key: String) -> String {
        localizedBundle.localizedString(forKey: key, value: nil, table: nil)
    }
    
    /// Set language and mark as explicitly selected by user.
    func setLanguage(_ language: AppLanguage) {
        currentLanguage = language
    }
}

// MARK: - SwiftUI Environment Modifier

extension View {
    /// Applies the current language locale and layout direction to the view hierarchy.
    func applyLanguageEnvironment(_ languageManager: LanguageManager) -> some View {
        self
            .environment(\.locale, languageManager.currentLanguage.locale)
            .environment(\.layoutDirection, languageManager.currentLanguage.layoutDirection)
    }
}

// MARK: - Text Field Locale Fix

extension View {
    /// Forces the text field's typing direction to match the current app language.
    /// Fixes an issue where switching from Farsi (RTL) to English (LTR) leaves
    /// the text cursor and alignment in RTL mode until the app is restarted.
    func forceLocaleForTextField(_ languageManager: LanguageManager) -> some View {
        self.environment(\.locale, languageManager.currentLanguage.locale)
    }
}
