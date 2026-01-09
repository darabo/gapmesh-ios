import SwiftUI

/// Language selection screen shown on first app launch.
/// Allows user to choose between English and Farsi.
struct LanguageSelectionView: View {
    @EnvironmentObject var languageManager: LanguageManager
    var onLanguageSelected: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    
    private var primaryColor: Color {
        Theme.legacyGreen(colorScheme)
    }
    
    private var backgroundColor: Color {
        Theme.background(colorScheme)
    }
    
    private var textColor: Color {
        Theme.legacyGreen(colorScheme)
    }
    
    var body: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()
            
            VStack(spacing: 32) {
                Spacer()
                
                // App logo/title
                Text("Gap Mesh/")
                    .font(.bitchatSystem(size: 32, weight: .bold, design: .monospaced))
                    .foregroundColor(primaryColor)
                
                // Bilingual title
                VStack(spacing: 8) {
                    Text("Choose Language")
                        .font(.bitchatSystem(size: 24, weight: .medium, design: .monospaced))
                        .foregroundColor(textColor)
                    
                    Text("زبان را انتخاب کنید")
                        .font(.bitchatSystem(size: 24, weight: .medium, design: .monospaced))
                        .foregroundColor(textColor)
                }
                
                Spacer().frame(height: 24)
                
                // Language buttons
                VStack(spacing: 16) {
                    LanguageButton(
                        nativeName: "English",
                        languageName: "English",
                        primaryColor: primaryColor
                    ) {
                        languageManager.setLanguage(.english)
                        onLanguageSelected()
                    }
                    
                    LanguageButton(
                        nativeName: "فارسی",
                        languageName: "Farsi",
                        primaryColor: primaryColor
                    ) {
                        languageManager.setLanguage(.farsi)
                        onLanguageSelected()
                    }
                }
                .padding(.horizontal, 32)
                
                Spacer()
            }
        }
    }
}

private struct LanguageButton: View {
    let nativeName: String
    let languageName: String
    let primaryColor: Color
    let action: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    
    private var surfaceColor: Color {
        Theme.surface(colorScheme)
    }
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(nativeName)
                    .font(.bitchatSystem(size: 22, weight: .bold, design: .monospaced))
                    .foregroundColor(primaryColor)
                
                if languageName != nativeName {
                    Text(languageName)
                        .font(.bitchatSystem(size: 14, design: .monospaced))
                        .foregroundColor(primaryColor.opacity(0.7))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(surfaceColor)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(primaryColor, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    LanguageSelectionView {
        print("Language selected")
    }
    .environmentObject(LanguageManager.shared)
}
