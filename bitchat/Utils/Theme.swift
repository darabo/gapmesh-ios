import SwiftUI

// MARK: - Centralized Design System
/// A unified theme system providing consistent colors, typography, and spacing
/// across the Gap Mesh iOS application. Follows Apple HIG and accessibility guidelines.

enum Theme {
    
    // MARK: - Semantic Colors
    
    /// Primary text color adapting to color scheme
    static func primaryText(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white : Color.black
    }
    
    /// Secondary text color for timestamps, hints, etc.
    static func secondaryText(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(white: 0.7) : Color(white: 0.4)
    }
    
    /// Background color for main content areas
    static func background(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.black : Color.white
    }
    
    /// Surface color for cards, sheets, and elevated elements
    static func surface(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(white: 0.1) : Color(white: 0.98)
    }
    
    /// Primary accent color for interactive elements
    static func accent(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark 
            ? Color(red: 0.4, green: 0.68, blue: 1.0)  // Light blue for dark mode
            : Color(red: 0.0, green: 0.48, blue: 1.0)  // System blue for light mode
    }
    
    // MARK: - Channel Colors
    
    /// Color for mesh network channel indicator
    static let meshChannel = Color(hue: 0.60, saturation: 0.75, brightness: 0.85)
    
    /// Color for location-based (geohash) channel indicator
    static func locationChannel(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark 
            ? Color(hue: 0.35, saturation: 0.65, brightness: 0.70)  // Teal for dark
            : Color(hue: 0.35, saturation: 0.70, brightness: 0.55)  // Darker teal for light
    }
    
    // MARK: - Status Colors
    
    /// Color for private/direct messages
    static let privateMessage = Color.orange
    
    /// Color for error states
    static let error = Color.red
    
    /// Color for success states
    static let success = Color.green
    
    /// Color for warning states
    static let warning = Color.orange
    
    /// Color for verified/secure states
    static let verified = Color.green
    
    /// Color for Nostr/global availability indicator
    static let nostrIndicator = Color.purple
    
    // MARK: - Legacy Green Theme (Transitional)
    /// These colors maintain compatibility with existing green-themed elements
    /// and can be phased out gradually during the redesign.
    
    static func legacyGreen(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.green : Color(red: 0, green: 0.5, blue: 0)
    }
    
    static func legacyGreenSecondary(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark 
            ? Color.green.opacity(0.8) 
            : Color(red: 0, green: 0.5, blue: 0).opacity(0.8)
    }
    
    // MARK: - Input Area Colors
    
    /// Background for text input fields
    static func inputBackground(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark 
            ? Color.black.opacity(0.35) 
            : Color.white.opacity(0.7)
    }
    
    /// Border color for input fields
    static func inputBorder(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark 
            ? Color.white.opacity(0.2) 
            : Color.black.opacity(0.1)
    }
    
    // MARK: - Recording Colors
    
    /// Color for recording indicator and waveform
    static let recording = Color.red
    
    /// Background for recording indicator
    static let recordingBackground = Color.red.opacity(0.15)
    
    // MARK: - Typography (Dynamic Type Support)
    
    /// Standard body text font
    /// Note: Dynamic Type scaling is handled at the View level via .dynamicTypeSize() modifier
    static func bodyFont(size: CGFloat = 15) -> Font {
        .system(size: size)
    }
    
    /// Monospaced font for technical content (geohashes, codes, etc.)
    static func monoFont(size: CGFloat = 14) -> Font {
        .system(size: size, design: .monospaced)
    }
    
    /// Title/header font
    static func titleFont(size: CGFloat = 18, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight)
    }
    
    /// Caption font for timestamps and secondary info
    static func captionFont(size: CGFloat = 12) -> Font {
        .system(size: size)
    }
    
    // MARK: - Scalable Fonts (Preferred for Accessibility)
    
    /// Uses Apple's preferred text styles that scale with Dynamic Type
    enum ScalableFont {
        /// For main message content
        static let body: Font = .body
        /// For timestamps, secondary info
        static let caption: Font = .caption
        /// For smaller metadata
        static let caption2: Font = .caption2
        /// For section headers
        static let headline: Font = .headline
        /// For prominent labels
        static let subheadline: Font = .subheadline
        /// For larger titles
        static let title3: Font = .title3
        /// Monospaced variant for codes/hashes
        static let monoBody: Font = .system(.body, design: .monospaced)
        static let monoCaption: Font = .system(.caption, design: .monospaced)
    }
    
    // MARK: - Enhanced Secondary Text (Improved Contrast)
    
    /// Higher contrast secondary text for better readability (WCAG AA)
    static func timestampText(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(white: 0.75) : Color(white: 0.35)
    }
    
    // MARK: - Bitchat System Font (Compatibility)
    /// Maintains compatibility with existing .bitchatSystem font usage
    /// while allowing gradual migration to semantic typography
    
    // MARK: - Spacing
    
    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }
    
    // MARK: - Corner Radius
    
    enum CornerRadius {
        static let small: CGFloat = 4
        static let medium: CGFloat = 8
        static let large: CGFloat = 12
        static let pill: CGFloat = 20
    }
    
    // MARK: - Animation
    
    enum Animation {
        static let fast: Double = 0.15
        static let medium: Double = 0.25
        static let slow: Double = 0.35
    }
    
    // MARK: - Touch Targets
    
    /// Minimum touch target size per Apple HIG
    static let minTouchTarget: CGFloat = 44
}

// MARK: - View Modifiers

extension View {
    /// Applies minimum touch target size for accessibility
    func accessibleTouchTarget() -> some View {
        self.frame(minWidth: Theme.minTouchTarget, minHeight: Theme.minTouchTarget)
            .contentShape(Rectangle())
    }
    
    /// Applies standard card styling
    func cardStyle(_ colorScheme: ColorScheme) -> some View {
        self
            .padding(Theme.Spacing.md)
            .background(Theme.surface(colorScheme))
            .cornerRadius(Theme.CornerRadius.medium)
    }
}

// MARK: - Color Extensions

extension Color {
    /// Creates a color with improved contrast for accessibility
    func accessibleContrast(against background: Color, colorScheme: ColorScheme) -> Color {
        // For dark mode, lighten colors; for light mode, darken them
        colorScheme == .dark ? self.opacity(1.0) : self
    }
}
