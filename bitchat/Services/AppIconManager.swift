import Foundation
#if os(iOS)
import UIKit
#endif

/// Manages dynamic app icon switching on iOS.
///
/// Uses `UIApplication.shared.setAlternateIconName()` to change the launcher icon.
///
/// **iOS Limitation:** Only the icon changes — iOS does NOT allow changing
/// the app display name at runtime. The name under the icon is always
/// the CFBundleDisplayName from Info.plist.
///
/// Alternate icons must be declared in Info.plist under `CFBundleIcons` →
/// `CFBundleAlternateIcons` and included in the asset catalog.
final class AppIconManager: ObservableObject {
    static let shared = AppIconManager()

    /// Available app icon options.
    enum AppIcon: String, CaseIterable, Identifiable {
        case `default` = "AppIcon"           // Primary Gap Mesh icon
        case calculator = "AppIconCalculator"
        case notes = "AppIconNotes"
        case weather = "AppIconWeather"
        case clock = "AppIconClock"
        case flashlight = "AppIconFlashlight"
        case music = "AppIconMusic"

        var id: String { rawValue }

        /// Localized display name for the settings picker (uses LanguageManager)
        var displayName: String {
            let key: String
            switch self {
            case .default: key = "icon.default"
            case .calculator: key = "icon.calculator"
            case .notes: key = "icon.notes"
            case .weather: key = "icon.weather"
            case .clock: key = "icon.clock"
            case .flashlight: key = "icon.flashlight"
            case .music: key = "icon.music"
            }
            return LanguageManager.shared.localizedString(key)
        }

        /// SF Symbol for the icon picker
        var sfSymbol: String {
            switch self {
            case .default: return "message.fill"
            case .calculator: return "plusminus.circle.fill"
            case .notes: return "note.text"
            case .weather: return "cloud.sun.fill"
            case .clock: return "clock.fill"
            case .flashlight: return "flashlight.on.fill"
            case .music: return "music.note"
            }
        }

        /// The value to pass to `setAlternateIconName`. nil means default.
        var alternateIconName: String? {
            self == .default ? nil : rawValue
        }
    }

    @Published var currentIcon: AppIcon

    private init() {
        #if os(iOS)
        if let currentName = UIApplication.shared.alternateIconName,
           let icon = AppIcon(rawValue: currentName) {
            currentIcon = icon
        } else {
            currentIcon = .default
        }
        #else
        currentIcon = .default
        #endif
    }

    /// Switch to a specific icon.
    func switchToIcon(_ icon: AppIcon) {
        #if os(iOS)
        guard UIApplication.shared.supportsAlternateIcons else {
            #if DEBUG
            print("[AppIconManager] Alternate icons not supported")
            #endif
            return
        }
        guard icon != currentIcon else { return }

        UIApplication.shared.setAlternateIconName(icon.alternateIconName) { [weak self] error in
            if let error = error {
                #if DEBUG
                print("[AppIconManager] Failed to set icon '\(icon.rawValue)': \(error.localizedDescription)")
                print("[AppIconManager] Error details: \(error)")
                #endif
            } else {
                DispatchQueue.main.async {
                    self?.currentIcon = icon
                }
                #if DEBUG
                print("[AppIconManager] Switched to icon: \(icon.rawValue)")
                #endif
            }
        }
        #endif
    }

    /// Switch to calculator decoy icon. Called when entering decoy mode.
    func switchToDecoyIcon() {
        switchToIcon(.calculator)
    }

    /// Restore the default Gap Mesh icon.
    func switchToDefault() {
        switchToIcon(.default)
    }
}
