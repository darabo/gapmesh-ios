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
    @ObservedObject private var iconManager = AppIconManager.shared
    #if os(iOS)
    @ObservedObject private var liveActivityManager = LiveActivityManager.shared
    #endif
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("appAppearanceMode") private var appearanceMode: Int = 0 // 0=System, 1=Light, 2=Dark
    @State private var showingNameEditSheet = false
    @State private var editingName = ""
    /// When true, programmatically navigate to the App Icon picker.
    /// Set by the decoy exit popup via UserDefaults flag.
    @State private var navigateToIconPicker = false    
    // Settings states
    @State private var torEnabled = SecureStorageManager.shared.object(forKey: "torEnabled") as? Bool ?? true // Default true on first launch
    @State private var proofOfWorkEnabled = SecureStorageManager.shared.bool(forKey: "proofOfWorkEnabled")
    @State private var legacyCompatibility = UserDefaults.standard.isLegacyCompatibilityEnabled
    
    // Slipstream (censorship bypass) states
    @ObservedObject private var slipstreamManager = SlipstreamManager.shared
    @State private var slipstreamEnabled = SecureStorageManager.shared.bool(forKey: "slipstreamEnabled")
    @State private var slipstreamDomain = SecureStorageManager.shared.object(forKey: "slipstreamDomain") as? String ?? "t.gapmesh.com"
    @State private var slipstreamResolver = SecureStorageManager.shared.object(forKey: "slipstreamResolver") as? String ?? "1.1.1.1"
    @State private var slipstreamShowAdvanced = false
    
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

    #if os(iOS)
    private var canToggleLiveActivities: Bool {
        liveActivityManager.areActivitiesAuthorized || liveActivityManager.isEnabled
    }
    #endif
    
    var body: some View {
        NavigationStack {
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
                    
                    // MARK: - Appearance Section
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeaderView(title: LanguageManager.shared.localizedString("settings.appearance").uppercased(), colorScheme: colorScheme)
                        
                        VStack(spacing: 1) {
                            HStack {
                                Image(systemName: "paintbrush.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(accentBlue)
                                    .frame(width: 24)
                                
                                Text(LanguageManager.shared.localizedString("settings.theme"))
                                    .font(.body)
                                    .fontWeight(.medium)
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                
                                Spacer()
                                
                                Picker("", selection: $appearanceMode) {
                                    Text(LanguageManager.shared.localizedString("settings.theme_system")).tag(0)
                                    Text(LanguageManager.shared.localizedString("settings.theme_light")).tag(1)
                                    Text(LanguageManager.shared.localizedString("settings.theme_dark")).tag(2)
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
                            .onChange(of: torEnabled) { _, newValue in
                                SecureStorageManager.shared.set(newValue, forKey: "torEnabled")
                                NetworkActivationService.shared.setUserTorEnabled(newValue)
                            }
                            
                            // Proof of Work Toggle
                            ToggleRow(
                                icon: "cpu",
                                title: LanguageManager.shared.localizedString("settings.proof_of_work"),
                                description: LanguageManager.shared.localizedString("settings.proof_of_work_description"),
                                isOn: $proofOfWorkEnabled,
                                accentColor: accentBlue
                            )
                            .onChange(of: proofOfWorkEnabled) { _, newValue in
                                SecureStorageManager.shared.set(newValue, forKey: "proofOfWorkEnabled")
                            }
                            
                            // Slipstream (Censorship Bypass) Toggle
                            ToggleRow(
                                icon: "globe.americas",
                                title: LanguageManager.shared.localizedString("settings.slipstream"),
                                description: LanguageManager.shared.localizedString("settings.slipstream_description"),
                                isOn: .constant(false),
                                accentColor: accentBlue
                            )
                            .disabled(true)
                            .opacity(0.5)
                            
                            // Slipstream status & advanced config (shown when enabled)
                            if slipstreamEnabled {
                                VStack(alignment: .leading, spacing: 8) {
                                    // Status indicator
                                    if !slipstreamManager.lastLogLine.isEmpty {
                                        Text(slipstreamManager.lastLogLine)
                                            .font(.caption2)
                                            .foregroundColor(
                                                slipstreamManager.state == .running ? .green :
                                                slipstreamManager.state == .error ? .red : .gray
                                            )
                                            .padding(.horizontal, 40)
                                    }

                                    // Advanced settings disclosure
                                    Button(action: {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            slipstreamShowAdvanced.toggle()
                                        }
                                    }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: slipstreamShowAdvanced ? "chevron.down" : "chevron.right")
                                                .font(.caption2)
                                            Text(LanguageManager.shared.localizedString("settings.slipstream_advanced"))
                                                .font(.caption)
                                        }
                                        .foregroundColor(.gray)
                                        .padding(.leading, 40)
                                    }

                                    if slipstreamShowAdvanced {
                                        // Tunnel Domain
                                        Text(LanguageManager.shared.localizedString("settings.slipstream_domain_label"))
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                            .padding(.leading, 40)

                                        TextField(
                                            LanguageManager.shared.localizedString("settings.slipstream_domain_hint"),
                                            text: $slipstreamDomain
                                        )
                                        .font(.system(.caption, design: .monospaced))
                                        .textFieldStyle(.roundedBorder)
                                        .autocapitalization(.none)
                                        .disableAutocorrection(true)
                                        .padding(.horizontal, 40)
                                        .onChange(of: slipstreamDomain) { _, newValue in
                                            slipstreamManager.domain = newValue
                                        }

                                        // DNS Resolver
                                        Text(LanguageManager.shared.localizedString("settings.slipstream_resolver_label"))
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                            .padding(.leading, 40)

                                        TextField("1.1.1.1", text: $slipstreamResolver)
                                            .font(.system(.caption, design: .monospaced))
                                            .textFieldStyle(.roundedBorder)
                                            .autocapitalization(.none)
                                            .disableAutocorrection(true)
                                            .keyboardType(.URL)
                                            .padding(.horizontal, 40)
                                            .onChange(of: slipstreamResolver) { _, newValue in
                                                slipstreamManager.resolver = newValue
                                            }
                                    }
                                }
                                .padding(.vertical, 4)
                                .background(surfaceColor)
                            }
                            
                            // Location Toggle
                            ToggleRow(
                                icon: "location.fill",
                                title: LanguageManager.shared.localizedString("settings.location"),
                                description: LanguageManager.shared.localizedString("settings.location_description"),
                                isOn: $locationManager.isLocationUserEnabled,
                                accentColor: accentBlue
                            )
                            .onChange(of: locationManager.isLocationUserEnabled) { _, newValue in
                                if newValue {
                                    if locationManager.permissionState == .denied {
                                        #if os(iOS)
                                        if let url = URL(string: UIApplication.openSettingsURLString) {
                                            UIApplication.shared.open(url)
                                        }
                                        #endif
                                        DispatchQueue.main.async { locationManager.isLocationUserEnabled = false }
                                    } else {
                                        locationManager.enableLocationChannels()
                                    }
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

                    // MARK: - App Icon Section (submenu)
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeaderView(title: LanguageManager.shared.localizedString("settings.app_icon_title").uppercased(), colorScheme: colorScheme)

                        VStack(spacing: 1) {
                            NavigationLink(destination: AppIconPickerView(iconManager: iconManager, accentBlue: accentBlue)) {
                                HStack(alignment: .center, spacing: 12) {
                                    Image(systemName: iconManager.currentIcon.sfSymbol)
                                        .font(.system(size: 20))
                                        .foregroundColor(accentBlue)
                                        .frame(width: 24)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(LanguageManager.shared.localizedString("settings.app_icon_title"))
                                            .font(.body)
                                            .fontWeight(.medium)
                                            .foregroundColor(colorScheme == .dark ? .white : .black)

                                        Text(iconManager.currentIcon.displayName)
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }

                                    Spacer()
                                }
                                .padding()
                                .background(surfaceColor)
                            }
                        }
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)

                    // MARK: - Live Activity Section
                    #if os(iOS)
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeaderView(title: LanguageManager.shared.localizedString("settings.live_activity_section").uppercased(), colorScheme: colorScheme)

                        VStack(spacing: 1) {
                            ToggleRow(
                                icon: "rectangle.stack.badge.play.fill",
                                title: LanguageManager.shared.localizedString("settings.live_activity_title"),
                                description: LanguageManager.shared.localizedString("settings.live_activity_description"),
                                isOn: $liveActivityManager.isEnabled,
                                accentColor: accentBlue
                            )
                            .disabled(!canToggleLiveActivities)
                            .opacity(canToggleLiveActivities ? 1.0 : 0.6)

                            if !liveActivityManager.areActivitiesAuthorized {
                                Text("Live Activities are disabled by iOS system settings. Enable Live Activities in iOS Settings to turn this on.")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                                    .padding(.horizontal)
                                    .padding(.vertical, 10)
                            }

                            #if DEBUG
                            Text("Debug: \(liveActivityManager.debugStatusLine)")
                                .font(.caption2.monospaced())
                                .foregroundColor(.gray)
                                .lineLimit(2)
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                            #endif
                        }
                        .background(surfaceColor)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    #endif

                    // MARK: - Features Section
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeaderView(title: LanguageManager.shared.localizedString("settings.features").uppercased(), colorScheme: colorScheme)
                        
                        VStack(spacing: 1) {
                            FeatureRow(
                                icon: "wifi.slash",
                                title: LanguageManager.shared.localizedString("app_info.features.offline.title"),
                                description: LanguageManager.shared.localizedString("app_info.features.offline.description"),
                                accentColor: accentBlue
                            )
                            
                            FeatureRow(
                                icon: "lock.shield",
                                title: LanguageManager.shared.localizedString("app_info.features.encryption.title"),
                                description: LanguageManager.shared.localizedString("app_info.features.encryption.description"),
                                accentColor: accentBlue
                            )
                            
                            FeatureRow(
                                icon: "antenna.radiowaves.left.and.right",
                                title: LanguageManager.shared.localizedString("app_info.features.extended_range.title"),
                                description: LanguageManager.shared.localizedString("app_info.features.extended_range.description"),
                                accentColor: accentBlue
                            )
                            
                            FeatureRow(
                                icon: "star.fill",
                                title: LanguageManager.shared.localizedString("app_info.features.favorites.title"),
                                description: LanguageManager.shared.localizedString("app_info.features.favorites.description"),
                                accentColor: accentBlue
                            )
                            
                            FeatureRow(
                                icon: "number",
                                title: LanguageManager.shared.localizedString("app_info.features.geohash.title"),
                                description: LanguageManager.shared.localizedString("app_info.features.geohash.description"),
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
                                title: LanguageManager.shared.localizedString("app_info.privacy.no_tracking.title"),
                                description: LanguageManager.shared.localizedString("app_info.privacy.no_tracking.description"),
                                accentColor: accentBlue
                            )
                            
                            FeatureRow(
                                icon: "shuffle",
                                title: LanguageManager.shared.localizedString("app_info.privacy.ephemeral.title"),
                                description: LanguageManager.shared.localizedString("app_info.privacy.ephemeral.description"),
                                accentColor: accentBlue
                            )
                            
                            FeatureRow(
                                icon: "hand.raised.fill",
                                title: LanguageManager.shared.localizedString("app_info.privacy.panic.title"),
                                description: LanguageManager.shared.localizedString("app_info.privacy.panic.description"),
                                accentColor: accentBlue
                            )
                            
                            // Decoy PIN management
                            DecoyPINRow(surfaceColor: surfaceColor)
                            
                            // Legacy Compatibility Toggle
                            ToggleRow(
                                icon: "antenna.radiowaves.left.and.right.circle",
                                title: LanguageManager.shared.localizedString("app_info.privacy.legacy_compat.title"),
                                description: LanguageManager.shared.localizedString("app_info.privacy.legacy_compat.description"),
                                isOn: $legacyCompatibility,
                                accentColor: accentBlue
                            )
                            .onChange(of: legacyCompatibility) { _, newValue in
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
                            
                            Text(LanguageManager.shared.localizedString("app_info.warning.message"))
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
                    
                    // MARK: - Contact & Support Section
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeaderView(title: LanguageManager.shared.localizedString("settings.contact").uppercased(), colorScheme: colorScheme)
                        
                        VStack(spacing: 1) {
                            // Report Abuse
                            Button(action: {
                                openReportAbuseEmail()
                            }) {
                                HStack {
                                    Image(systemName: "flag.fill")
                                        .font(.system(size: 20))
                                        .foregroundColor(.red)
                                        .frame(width: 24)
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(LanguageManager.shared.localizedString("settings.report_abuse"))
                                            .font(.body)
                                            .fontWeight(.medium)
                                            .foregroundColor(colorScheme == .dark ? .white : .black)
                                        
                                        Text(LanguageManager.shared.localizedString("settings.report_abuse_description"))
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "envelope")
                                        .foregroundColor(.gray)
                                }
                                .padding()
                                .background(surfaceColor)
                            }
                            .buttonStyle(.plain)
                        }
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    
                    #if os(iOS)
                    // MARK: - Share App Section
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeaderView(title: LanguageManager.shared.localizedString("settings.share_app").uppercased(), colorScheme: colorScheme)
                        
                        VStack(spacing: 1) {
                            // Description row
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 20))
                                    .foregroundColor(accentBlue)
                                    .frame(width: 24)
                                    .padding(.top, 2)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(LanguageManager.shared.localizedString("settings.share_app"))
                                        .font(.body)
                                        .fontWeight(.medium)
                                        .foregroundColor(colorScheme == .dark ? .white : .black)
                                    
                                    Text(LanguageManager.shared.localizedString("settings.share_app_description"))
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                
                                Spacer()
                            }
                            .padding()
                            .background(surfaceColor)
                            
                            // Share button
                            Button(action: {
                                APKShareHelper.shareAPK()
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 16))
                                    Text(LanguageManager.shared.localizedString("settings.share_app_button"))
                                        .fontWeight(.semibold)
                                }
                                .foregroundColor(textColor)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(surfaceColor)
                            }
                            .buttonStyle(.plain)
                            .disabled(!APKShareHelper.isAPKBundled)
                            .opacity(APKShareHelper.isAPKBundled ? 1.0 : 0.4)
                        }
                        .cornerRadius(12)
                        
                        if !APKShareHelper.isAPKBundled {
                            Text(LanguageManager.shared.localizedString("settings.share_app_not_bundled"))
                                .font(.caption2)
                                .foregroundColor(.gray)
                                .padding(.leading, 4)
                        } else {
                            Text(LanguageManager.shared.localizedString("settings.share_app_size_note"))
                                .font(.caption2)
                                .foregroundColor(.gray)
                                .padding(.leading, 4)
                        }
                    }
                    .padding(.horizontal)
                    #endif
                    
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
                            
                            // Privacy Policy
                            Button(action: {
                                if let url = URL(string: "https://github.com/darabo/gapmesh-ios/blob/main/PRIVACY_POLICY.md") {
                                    UIApplication.shared.open(url)
                                }
                            }) {
                                HStack {
                                    Image(systemName: "doc.text.fill")
                                        .font(.system(size: 20))
                                        .foregroundColor(accentBlue)
                                        .frame(width: 24)
                                    
                                    Text(LanguageManager.shared.localizedString("settings.privacy_policy"))
                                        .font(.body)
                                        .foregroundColor(colorScheme == .dark ? .white : .black)
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                                .padding()
                                .background(surfaceColor)
                            }
                            .buttonStyle(.plain)
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
            .navigationDestination(isPresented: $navigateToIconPicker) {
                AppIconPickerView(iconManager: iconManager, accentBlue: accentBlue)
            }
            .onAppear {
                // Check if the decoy exit popup requested opening the icon picker
                if UserDefaults.standard.bool(forKey: "shouldOpenAppIconPicker") {
                    UserDefaults.standard.removeObject(forKey: "shouldOpenAppIconPicker")
                    // Small delay to let NavigationView fully appear first
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        navigateToIconPicker = true
                    }
                }
            }
        }
        .sheet(isPresented: $showingNameEditSheet) {
            editNameSheet
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
                    .forceLocaleForTextField(LanguageManager.shared)
                }
                
                Section {
                    Button(action: saveNewName) {
                        Text(LanguageManager.shared.localizedString("common.save"))
                            .foregroundColor(.blue)
                    }
                }
            }
            .navigationTitle(LanguageManager.shared.localizedString("settings.change_username"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showingNameEditSheet = false }) {
                        Text(LanguageManager.shared.localizedString("common.cancel"))
                    }
                }
            }
            #else
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: { showingNameEditSheet = false }) {
                        Text(LanguageManager.shared.localizedString("common.cancel"))
                    }
                }
            }
            #endif
        }
        .applyLanguageEnvironment(LanguageManager.shared)
        .id(LanguageManager.shared.refreshID)
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
    
    private func openReportAbuseEmail() {
        let email = "support@gapmesh.com"  // Developer support email
        let subject = "Report Abuse - Gap Mesh"
        if let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: "mailto:\(email)?subject=\(encodedSubject)") {
            #if os(iOS)
            UIApplication.shared.open(url)
            #endif
        }
    }
    
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

// MARK: - Decoy PIN Management Row
private struct DecoyPINRow: View {
    let surfaceColor: Color
    @Environment(\.colorScheme) var colorScheme
    @State private var showingPINSheet = false
    @State private var newPIN = ""
    @State private var confirmPIN = ""
    @State private var pinMismatch = false
    @State private var pinSaved = false

    var body: some View {
        Button(action: { showingPINSheet = true }) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "number.square.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.orange)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 4) {
                    Text(LanguageManager.shared.localizedString("settings.decoy_pin_title"))
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(colorScheme == .dark ? .white : .black)

                    Text(LanguageManager.shared.localizedString("settings.decoy_pin_desc"))
                        .font(.caption)
                        .foregroundColor(.gray)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .padding()
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingPINSheet) {
            NavigationView {
                Form {
                    Section {
                        SecureField(
                            LanguageManager.shared.localizedString("settings.decoy_pin_new"),
                            text: $newPIN
                        )
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                        .onChange(of: newPIN) {
                            pinMismatch = false
                            pinSaved = false
                            newPIN = String(newPIN.filter { $0.isNumber }.prefix(8))
                        }

                        SecureField(
                            LanguageManager.shared.localizedString("settings.decoy_pin_confirm"),
                            text: $confirmPIN
                        )
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                        .onChange(of: confirmPIN) {
                            pinMismatch = false
                            pinSaved = false
                            confirmPIN = String(confirmPIN.filter { $0.isNumber }.prefix(8))
                        }
                    } header: {
                        Text(LanguageManager.shared.localizedString("settings.decoy_pin_new"))
                    } footer: {
                        if pinMismatch {
                            Text(LanguageManager.shared.localizedString("settings.decoy_pin_mismatch"))
                                .foregroundColor(.red)
                        } else if pinSaved {
                            Text(LanguageManager.shared.localizedString("settings.decoy_pin_saved"))
                                .foregroundColor(.green)
                        }
                    }
                }
                .navigationTitle(LanguageManager.shared.localizedString("settings.decoy_pin_title"))
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    #if os(iOS)
                    ToolbarItem(placement: .cancellationAction) {
                        Button(LanguageManager.shared.localizedString("settings.done")) {
                            showingPINSheet = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(LanguageManager.shared.localizedString("settings.save")) {
                            if newPIN.count >= 4 && newPIN == confirmPIN {
                                DecoyModeManager.shared.setPIN(newPIN)
                                pinSaved = true
                                pinMismatch = false
                            } else {
                                pinMismatch = true
                            }
                        }
                        .disabled(newPIN.count < 4)
                    }
                    #else
                    ToolbarItem(placement: .cancellationAction) {
                        Button(LanguageManager.shared.localizedString("settings.done")) {
                            showingPINSheet = false
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button(LanguageManager.shared.localizedString("settings.save")) {
                            if newPIN.count >= 4 && newPIN == confirmPIN {
                                DecoyModeManager.shared.setPIN(newPIN)
                                pinSaved = true
                                pinMismatch = false
                            } else {
                                pinMismatch = true
                            }
                        }
                        .disabled(newPIN.count < 4)
                    }
                    #endif
                }
            }
        }
    }
}

