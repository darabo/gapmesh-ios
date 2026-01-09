import SwiftUI

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
        
        // Force UI update via objectWillChange
        objectWillChange.send()
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
