import SwiftUI

struct AppInfoView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var languageManager: LanguageManager
    
    // MARK: - Constants
    private enum Strings {
        static let appName: LocalizedStringKey = "app_info.app_name"
        static let tagline: LocalizedStringKey = "app_info.tagline"

        enum Features {
            static let title: LocalizedStringKey = "app_info.features.title"
            static let offlineComm = AppInfoFeatureInfo(
                icon: "wifi.slash",
                title: "app_info.features.offline.title",
                description: "app_info.features.offline.description"
            )
            static let encryption = AppInfoFeatureInfo(
                icon: "lock.shield",
                title: "app_info.features.encryption.title",
                description: "app_info.features.encryption.description"
            )
            static let extendedRange = AppInfoFeatureInfo(
                icon: "antenna.radiowaves.left.and.right",
                title: "app_info.features.extended_range.title",
                description: "app_info.features.extended_range.description"
            )
            static let mentions = AppInfoFeatureInfo(
                icon: "at",
                title: "app_info.features.mentions.title",
                description: "app_info.features.mentions.description"
            )
            static let favorites = AppInfoFeatureInfo(
                icon: "star.fill",
                title: "app_info.features.favorites.title",
                description: "app_info.features.favorites.description"
            )
            static let geohash = AppInfoFeatureInfo(
                icon: "number",
                title: "app_info.features.geohash.title",
                description: "app_info.features.geohash.description"
            )
        }

        enum Privacy {
            static let title: LocalizedStringKey = "app_info.privacy.title"
            static let noTracking = AppInfoFeatureInfo(
                icon: "eye.slash",
                title: "app_info.privacy.no_tracking.title",
                description: "app_info.privacy.no_tracking.description"
            )
            static let ephemeral = AppInfoFeatureInfo(
                icon: "shuffle",
                title: "app_info.privacy.ephemeral.title",
                description: "app_info.privacy.ephemeral.description"
            )
            static let panic = AppInfoFeatureInfo(
                icon: "hand.raised.fill",
                title: "app_info.privacy.panic.title",
                description: "app_info.privacy.panic.description"
            )
        }

        enum HowToUse {
            static let title: LocalizedStringKey = "app_info.how_to_use.title"
            static let instructions: [LocalizedStringKey] = [
                "app_info.how_to_use.set_nickname",
                "app_info.how_to_use.change_channels",
                "app_info.how_to_use.open_sidebar",
                "app_info.how_to_use.start_dm",
                "app_info.how_to_use.clear_chat",
                "app_info.how_to_use.commands"
            ]
        }

        enum Warning {
            static let title: LocalizedStringKey = "app_info.warning.title"
            static let message: LocalizedStringKey = "app_info.warning.message"
        }
    }
    
    var body: some View {
        ZStack {
            Theme.background(colorScheme)
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: Theme.Spacing.xl) {
                    
                    // MARK: - Header
                    VStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "app.connected.to.app.below.fill") // Placeholder branding
                            .font(.system(size: 64))
                            .foregroundColor(Theme.accent(colorScheme))
                            .padding(.bottom, 8)
                        
                        Text(Strings.appName)
                            .font(Theme.titleFont(size: 28, weight: .bold))
                            .foregroundColor(Theme.primaryText(colorScheme))
                        
                        Text(Strings.tagline)
                            .font(Theme.bodyFont())
                            .foregroundColor(Theme.secondaryText(colorScheme))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding(.top, Theme.Spacing.xl)
                    
                    // MARK: - Language Settings
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        SectionHeader(title: "Language")
                        
                        HStack(spacing: Theme.Spacing.md) {
                            LanguageOptionButton(
                                title: "English",
                                isSelected: languageManager.currentLanguage == .english,
                                action: { languageManager.setLanguage(.english) }
                            )
                            
                            LanguageOptionButton(
                                title: "فارسی",
                                isSelected: languageManager.currentLanguage == .farsi,
                                action: { languageManager.setLanguage(.farsi) }
                            )
                        }
                    }
                    .padding(.horizontal)
                    
                    // MARK: - Features
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        SectionHeader(title: Strings.Features.title)
                        
                        VStack(spacing: 1) { // 1px spacing for divider effect
                            InfoRow(info: Strings.Features.offlineComm)
                            InfoRow(info: Strings.Features.encryption)
                            InfoRow(info: Strings.Features.extendedRange)
                            InfoRow(info: Strings.Features.favorites)
                            InfoRow(info: Strings.Features.geohash)
                        }
                        .background(Theme.surface(colorScheme))
                        .cornerRadius(Theme.CornerRadius.large)
                    }
                    .padding(.horizontal)
                    
                    // MARK: - Privacy
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        SectionHeader(title: Strings.Privacy.title)
                        
                        VStack(spacing: 1) {
                            InfoRow(info: Strings.Privacy.noTracking)
                            InfoRow(info: Strings.Privacy.ephemeral)
                            InfoRow(info: Strings.Privacy.panic)
                        }
                        .background(Theme.surface(colorScheme))
                        .cornerRadius(Theme.CornerRadius.large)
                    }
                    .padding(.horizontal)
                    
                    // MARK: - Warning
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        SectionHeader(title: Strings.Warning.title)
                            .foregroundColor(Theme.error)
                        
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(Theme.error)
                                
                                Text(Strings.Warning.message)
                                    .font(Theme.bodyFont())
                                    .foregroundColor(Theme.primaryText(colorScheme))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(Theme.Spacing.md)
                        .background(Theme.error.opacity(0.1))
                        .cornerRadius(Theme.CornerRadius.large)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                                .stroke(Theme.error.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .padding(.horizontal)
                    .padding(.bottom, Theme.Spacing.xxl)
                    
                }
                .padding(.bottom, 40)
            }
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { dismiss() }) {
                    Text("app_info.done")
                        .fontWeight(.semibold)
                }
            }
        }
        #endif
        #if os(macOS)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("app_info.done") { dismiss() }
            }
        }
        #endif
    }
}

// MARK: - Helper Components

struct AppInfoFeatureInfo {
    let icon: String
    let title: LocalizedStringKey
    let description: LocalizedStringKey
}

struct SectionHeader: View {
    let title: LocalizedStringKey
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Text(title)
            .font(Theme.titleFont(size: 18, weight: .semibold))
            .foregroundColor(Theme.primaryText(colorScheme))
            .padding(.leading, 4)
    }
}

struct InfoRow: View {
    let info: AppInfoFeatureInfo
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Image(systemName: info.icon)
                .font(.system(size: 20))
                .foregroundColor(Theme.accent(colorScheme))
                .frame(width: 24)
                .padding(.top, 2)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(info.title)
                    .font(Theme.bodyFont(size: 16).weight(.medium))
                    .foregroundColor(Theme.primaryText(colorScheme))
                
                Text(info.description)
                    .font(Theme.captionFont(size: 14))
                    .foregroundColor(Theme.secondaryText(colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(Theme.Spacing.md)
        .background(Theme.surface(colorScheme))
    }
}

struct LanguageOptionButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(Theme.bodyFont(size: 16).weight(isSelected ? .semibold : .regular))
                
                if isSelected {
                    Spacer()
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(isSelected ? Theme.accent(colorScheme).opacity(0.15) : Theme.surface(colorScheme))
            .foregroundColor(isSelected ? Theme.accent(colorScheme) : Theme.primaryText(colorScheme))
            .cornerRadius(Theme.CornerRadius.medium)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                    .stroke(isSelected ? Theme.accent(colorScheme) : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    AppInfoView()
        .environmentObject(LanguageManager.shared)
}
