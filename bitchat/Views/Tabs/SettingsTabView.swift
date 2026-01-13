//
//  SettingsTabView.swift
//  bitchat
//
//  Created by Unlicense
//

import SwiftUI
import Tor

struct SettingsTabView: View {
    @EnvironmentObject var viewModel: ChatViewModel
    @StateObject private var languageManager = LanguageManager.shared
    @ObservedObject private var locationManager = LocationChannelManager.shared
    @Environment(\.colorScheme) var colorScheme
    @State private var showingNameEditSheet = false
    @State private var editingName = ""
    
    // Settings states
    @State private var torEnabled = UserDefaults.standard.bool(forKey: "torEnabled")
    @State private var proofOfWorkEnabled = UserDefaults.standard.bool(forKey: "proofOfWorkEnabled")
    @State private var locationEnabled = true
    @State private var legacyCompatibility = UserDefaults.standard.isLegacyCompatibilityEnabled
    
    private var textColor: Color {
        colorScheme == .dark ? Color.green : Color(red: 0, green: 0.5, blue: 0)
    }
    
    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color.green.opacity(0.8) : Color(red: 0, green: 0.5, blue: 0).opacity(0.8)
    }
    
    private var backgroundColor: Color {
        colorScheme == .dark ? Color.black : Color.white
    }
    
    private var surfaceColor: Color {
        colorScheme == .dark ? Color(white: 0.1) : Color(white: 0.95)
    }
    
    private var accentBlue: Color {
        Color(hue: 0.60, saturation: 0.85, brightness: 0.82)
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    
                    // MARK: - Identity Section
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeaderView(title: LanguageManager.shared.localizedString("settings.identity").uppercased(), colorScheme: colorScheme)
                        
                        VStack(spacing: 1) {
                            // Username
                            HStack {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(accentBlue)
                                    .frame(width: 24)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(LanguageManager.shared.localizedString("settings.username"))
                                        .font(.body)
                                        .fontWeight(.medium)
                                        .foregroundColor(colorScheme == .dark ? .white : .black)
                                    
                                    Text(viewModel.nickname)
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            .padding()
                            .background(surfaceColor)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                editingName = viewModel.nickname
                                showingNameEditSheet = true
                            }
                        }
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    
                    // MARK: - Language Section
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeaderView(title: LanguageManager.shared.localizedString("settings.language").uppercased(), colorScheme: colorScheme)
                        
                        VStack(spacing: 1) {
                            HStack {
                                Image(systemName: "globe")
                                    .font(.system(size: 20))
                                    .foregroundColor(accentBlue)
                                    .frame(width: 24)
                                
                                Text(LanguageManager.shared.localizedString("settings.select_language"))
                                    .font(.body)
                                    .fontWeight(.medium)
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                
                                Spacer()
                                
                                Picker("", selection: $languageManager.currentLanguage) {
                                    Text("English").tag(LanguageManager.AppLanguage.english)
                                    Text("فارسی").tag(LanguageManager.AppLanguage.farsi)
                                }
                                .pickerStyle(.menu)
                                .tint(textColor)
                            }
                            .padding()
                            .background(surfaceColor)
                        }
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    
                    // MARK: - Network Section
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeaderView(title: LanguageManager.shared.localizedString("settings.network").uppercased(), colorScheme: colorScheme)
                        
                        VStack(spacing: 1) {
                            // Tor Toggle
                            ToggleRow(
                                icon: "network",
                                title: LanguageManager.shared.localizedString("settings.tor"),
                                description: LanguageManager.shared.localizedString("settings.tor_description"),
                                isOn: $torEnabled,
                                accentColor: accentBlue
                            )
                            .onChange(of: torEnabled) { newValue in
                                UserDefaults.standard.set(newValue, forKey: "torEnabled")
                            }
                            
                            // Proof of Work Toggle
                            ToggleRow(
                                icon: "cpu",
                                title: LanguageManager.shared.localizedString("settings.proof_of_work"),
                                description: LanguageManager.shared.localizedString("settings.proof_of_work_description"),
                                isOn: $proofOfWorkEnabled,
                                accentColor: accentBlue
                            )
                            .onChange(of: proofOfWorkEnabled) { newValue in
                                UserDefaults.standard.set(newValue, forKey: "proofOfWorkEnabled")
                            }
                            
                            // Location Toggle
                            ToggleRow(
                                icon: "location.fill",
                                title: LanguageManager.shared.localizedString("settings.location"),
                                description: LanguageManager.shared.localizedString("settings.location_description"),
                                isOn: $locationEnabled,
                                accentColor: accentBlue
                            )
                            .onChange(of: locationEnabled) { newValue in
                                if newValue {
                                    locationManager.enableLocationChannels()
                                } else {
                                    // Switch to mesh mode when disabling location
                                    locationManager.select(.mesh)
                                }
                            }
                        }
                        .background(surfaceColor)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    
                    // MARK: - Features Section
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeaderView(title: LanguageManager.shared.localizedString("settings.features").uppercased(), colorScheme: colorScheme)
                        
                        VStack(spacing: 1) {
                            FeatureRow(
                                icon: "wifi.slash",
                                title: String(localized: "app_info.features.offline.title"),
                                description: String(localized: "app_info.features.offline.description"),
                                accentColor: accentBlue
                            )
                            
                            FeatureRow(
                                icon: "lock.shield",
                                title: String(localized: "app_info.features.encryption.title"),
                                description: String(localized: "app_info.features.encryption.description"),
                                accentColor: accentBlue
                            )
                            
                            FeatureRow(
                                icon: "antenna.radiowaves.left.and.right",
                                title: String(localized: "app_info.features.extended_range.title"),
                                description: String(localized: "app_info.features.extended_range.description"),
                                accentColor: accentBlue
                            )
                            
                            FeatureRow(
                                icon: "star.fill",
                                title: String(localized: "app_info.features.favorites.title"),
                                description: String(localized: "app_info.features.favorites.description"),
                                accentColor: accentBlue
                            )
                            
                            FeatureRow(
                                icon: "number",
                                title: String(localized: "app_info.features.geohash.title"),
                                description: String(localized: "app_info.features.geohash.description"),
                                accentColor: accentBlue
                            )
                        }
                        .background(surfaceColor)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    
                    // MARK: - Privacy Section
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeaderView(title: LanguageManager.shared.localizedString("settings.privacy").uppercased(), colorScheme: colorScheme)
                        
                        VStack(spacing: 1) {
                            FeatureRow(
                                icon: "eye.slash",
                                title: String(localized: "app_info.privacy.no_tracking.title"),
                                description: String(localized: "app_info.privacy.no_tracking.description"),
                                accentColor: accentBlue
                            )
                            
                            FeatureRow(
                                icon: "shuffle",
                                title: String(localized: "app_info.privacy.ephemeral.title"),
                                description: String(localized: "app_info.privacy.ephemeral.description"),
                                accentColor: accentBlue
                            )
                            
                            FeatureRow(
                                icon: "hand.raised.fill",
                                title: String(localized: "app_info.privacy.panic.title"),
                                description: String(localized: "app_info.privacy.panic.description"),
                                accentColor: accentBlue
                            )
                            
                            // Legacy Compatibility Toggle
                            ToggleRow(
                                icon: "antenna.radiowaves.left.and.right.circle",
                                title: String(localized: "app_info.privacy.legacy_compat.title"),
                                description: String(localized: "app_info.privacy.legacy_compat.description"),
                                isOn: $legacyCompatibility,
                                accentColor: accentBlue
                            )
                            .onChange(of: legacyCompatibility) { newValue in
                                UserDefaults.standard.isLegacyCompatibilityEnabled = newValue
                            }
                        }
                        .background(surfaceColor)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    
                    // MARK: - Warning Section
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeaderView(title: LanguageManager.shared.localizedString("settings.warning").uppercased(), colorScheme: colorScheme, color: .red)
                        
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.red)
                            
                            Text("app_info.warning.message")
                                .font(.body)
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.red.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .padding(.horizontal)
                    
                    // MARK: - About Section
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeaderView(title: LanguageManager.shared.localizedString("settings.about").uppercased(), colorScheme: colorScheme)
                        
                        VStack(spacing: 1) {
                            HStack {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 20))
                                    .foregroundColor(accentBlue)
                                    .frame(width: 24)
                                
                                Text(LanguageManager.shared.localizedString("settings.app_version"))
                                    .font(.body)
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                Spacer()
                                Text(appVersion)
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            .padding()
                            .background(surfaceColor)
                            
                            // Creator credit
                            HStack {
                                Image(systemName: "heart.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(.red)
                                    .frame(width: 24)
                                
                                Text(LanguageManager.shared.localizedString("settings.created_by"))
                                    .font(.body)
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                Spacer()
                                Text("Dara Bonakdar")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            .padding()
                            .background(surfaceColor)
                        }
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    
                    Spacer(minLength: 40)
                }
                .padding(.top, 20)
            }
            .background(backgroundColor)
            .navigationTitle(LanguageManager.shared.localizedString("tabs.settings"))
        }
        .sheet(isPresented: $showingNameEditSheet) {
            editNameSheet
        }
        .onAppear {
            locationEnabled = locationManager.permissionState == .authorized
        }
    }
    
    // MARK: - Edit Name Sheet
    
    private var editNameSheet: some View {
        NavigationView {
            Form {
                Section(header: Text(LanguageManager.shared.localizedString("settings.change_username"))) {
                    TextField(
                        LanguageManager.shared.localizedString("settings.enter_username"),
                        text: $editingName
                    )
                    .autocorrectionDisabled()
                }
                
                Section {
                    Button(action: saveNewName) {
                        Text(LanguageManager.shared.localizedString("common.save"))
                            .foregroundColor(.blue)
                    }
                }
            }
            .navigationTitle(LanguageManager.shared.localizedString("settings.change_username"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showingNameEditSheet = false }) {
                        Text(LanguageManager.shared.localizedString("common.cancel"))
                    }
                }
            }
        }
    }
    
    private func saveNewName() {
        let newName = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty, newName != viewModel.nickname else {
            showingNameEditSheet = false
            return
        }
        viewModel.nickname = newName
        showingNameEditSheet = false
    }
    
    // MARK: - Helpers
    
    private var appVersion: String {
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
           let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
            return "\(version) (\(build))"
        }
        return "Unknown"
    }
}

// MARK: - Helper Views

private struct SectionHeaderView: View {
    let title: String
    let colorScheme: ColorScheme
    var color: Color? = nil
    
    var body: some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(color ?? (colorScheme == .dark ? .gray : .gray))
            .padding(.leading, 4)
    }
}

private struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    let accentColor: Color
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(accentColor)
                .frame(width: 24)
                .padding(.top, 2)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.gray)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
        }
        .padding()
    }
}

private struct ToggleRow: View {
    let icon: String
    let title: String
    let description: String
    @Binding var isOn: Bool
    let accentColor: Color
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(accentColor)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.gray)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
        .padding()
    }
}
