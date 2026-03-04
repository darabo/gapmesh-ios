//
//  AppIconPickerView.swift
//  bitchat
//
//  Submenu view for selecting the app's alternate icon.
//

import SwiftUI

struct AppIconPickerView: View {
    @ObservedObject var iconManager: AppIconManager
    let accentBlue: Color
    @Environment(\.colorScheme) var colorScheme

    private var surfaceColor: Color {
        colorScheme == .dark ? Color(white: 0.1) : Color(white: 0.95)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Description
                Text(LanguageManager.shared.localizedString("settings.app_icon_description"))
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, 8)

                // Icon list
                VStack(spacing: 1) {
                    ForEach(AppIconManager.AppIcon.allCases) { icon in
                        Button(action: {
                            iconManager.switchToIcon(icon)
                        }) {
                            HStack(spacing: 14) {
                                // Icon preview
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(iconManager.currentIcon == icon
                                            ? accentBlue.opacity(0.15)
                                            : Color.gray.opacity(0.1))
                                        .frame(width: 48, height: 48)

                                    Image(systemName: icon.sfSymbol)
                                        .font(.title3)
                                        .foregroundColor(iconManager.currentIcon == icon
                                            ? accentBlue
                                            : .gray)
                                }
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(iconManager.currentIcon == icon
                                            ? accentBlue
                                            : Color.clear, lineWidth: 2)
                                )

                                // Label
                                Text(icon.displayName)
                                    .font(.body)
                                    .fontWeight(.medium)
                                    .foregroundColor(colorScheme == .dark ? .white : .black)

                                Spacer()

                                // Checkmark for selected
                                if iconManager.currentIcon == icon {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.title3)
                                        .foregroundColor(accentBlue)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(surfaceColor)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .cornerRadius(12)
                .padding(.horizontal)

                // Note
                Text(LanguageManager.shared.localizedString("settings.app_icon_note"))
                    .font(.caption)
                    .foregroundColor(.gray.opacity(0.7))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
            }
            .padding(.bottom, 20)
        }
        .background(colorScheme == .dark ? Color.black : Color.white)
        .navigationTitle(LanguageManager.shared.localizedString("settings.app_icon_title"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
