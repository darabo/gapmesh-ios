import SwiftUI
import CoreBluetooth
import CoreLocation
import UserNotifications

/// Onboarding view shown to first-time users
/// Presents a 5-step tutorial: Language, Identity, Mesh, Features, Permissions
struct OnboardingView: View {
    @EnvironmentObject var viewModel: ChatViewModel
    @EnvironmentObject var languageManager: LanguageManager
    @Environment(\.colorScheme) var colorScheme
    @Binding var isPresented: Bool
    
    @State private var currentStep = 0
    private let totalSteps = 5
    
    // Hoisted state for Identity Step to fix "Next" button persistence bug
    @State private var isIdentityEditing = false
    @State private var identityEditedName = ""
    
    // Localized strings
    private enum Strings {
        static let next: LocalizedStringKey = "onboarding.next"
        static let getStarted: LocalizedStringKey = "onboarding.get_started"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Page indicators
            HStack(spacing: 8) {
                ForEach(0..<totalSteps, id: \.self) { index in
                    Circle()
                        .fill(index == currentStep ? Theme.legacyGreen(colorScheme) : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.top, 20)
            
            // Content
            TabView(selection: $currentStep) {
                LanguageStep(languageManager: languageManager)
                    .tag(0)
                
                IdentityStep(
                    viewModel: viewModel,
                    isEditing: $isIdentityEditing,
                    editedName: $identityEditedName
                )
                .tag(1)
                
                MeshStep()
                    .tag(2)
                
                FeaturesStep()
                    .tag(3)
                
                PermissionsStep()
                    .tag(4)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            
            // Navigation button
            Button(action: {
                // Critical Fix: Save nickname if editing when clicking Next
                if currentStep == 1 && isIdentityEditing {
                    if !identityEditedName.trimmingCharacters(in: .whitespaces).isEmpty {
                        viewModel.nickname = identityEditedName
                    }
                    isIdentityEditing = false
                    // Dismiss keyboard explicitly before transition to avoid constraint errors
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
                
                if currentStep < totalSteps - 1 {
                    withAnimation { currentStep += 1 }
                } else {
                    completeOnboarding()
                }
            }) {
                HStack {
                    Text(currentStep < totalSteps - 1 ? Strings.next : Strings.getStarted)
                        .fontWeight(.semibold)
                    Image(systemName: currentStep < totalSteps - 1 ? "arrow.right" : "checkmark")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Theme.legacyGreen(colorScheme))
                .foregroundColor(.white)
                .cornerRadius(Theme.CornerRadius.medium)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .background(Theme.background(colorScheme))
    }
    
    private func completeOnboarding() {
        // Mark onboarding as complete
        UserDefaults.standard.set(true, forKey: "onboarding_seen")
        
        // Start all services via the centralized ViewModel method
        // This handles mesh (BLE/WiFi) and notification authorization
        viewModel.startServices()
        
        // Start network activation (Tor, Nostr)
        NetworkActivationService.shared.start()
        
        isPresented = false
    }
}

// MARK: - Step 0: Language Selection
private struct LanguageStep: View {
    @ObservedObject var languageManager: LanguageManager
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                Spacer().frame(height: 60)
                
                // Globe icon
                Image(systemName: "globe")
                    .font(.system(size: 60))
                    .foregroundColor(Theme.legacyGreen(colorScheme))
                
                Text("onboarding.language_title")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                
                Text("onboarding.language_desc")
                    .font(.body)
                    .foregroundColor(Theme.secondaryText(colorScheme))
                    .multilineTextAlignment(.center)
                
                Spacer().frame(height: 20)
                
                // Language options
                VStack(spacing: 16) {
                    LanguageOption(
                        code: "en",
                        name: "English",
                        nativeName: "English",
                        isSelected: languageManager.currentLanguage == .english,
                        onSelect: { 
                            languageManager.setLanguage(.english)
                        }
                    )
                    
                    LanguageOption(
                        code: "fa",
                        name: "Farsi",
                        nativeName: "فارسی",
                        isSelected: languageManager.currentLanguage == .farsi,
                        onSelect: { 
                            languageManager.setLanguage(.farsi)
                        }
                    )
                }
                .padding(.horizontal, 24)
                
                Spacer()
            }
            .padding(.horizontal, 24)
        }
    }
}

private struct LanguageOption: View {
    let code: String
    let name: String
    let nativeName: String
    let isSelected: Bool
    let onSelect: () -> Void
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(nativeName)
                        .font(.headline)
                        .foregroundColor(Theme.primaryText(colorScheme))
                    if name != nativeName {
                        Text(name)
                            .font(.caption)
                            .foregroundColor(Theme.secondaryText(colorScheme))
                    }
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(Theme.legacyGreen(colorScheme))
                } else {
                    Circle()
                        .stroke(Color.gray.opacity(0.5), lineWidth: 2)
                        .frame(width: 24, height: 24)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                    .fill(Theme.surface(colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                            .stroke(isSelected ? Theme.legacyGreen(colorScheme) : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Step 1: Identity
private struct IdentityStep: View {
    @ObservedObject var viewModel: ChatViewModel
    @Environment(\.colorScheme) var colorScheme
    @Binding var isEditing: Bool
    @Binding var editedName: String
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer().frame(height: 40)
                
                // Welcome
                Text("onboarding.welcome")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                
                Text("onboarding.identity_desc")
                    .font(.body)
                    .foregroundColor(Theme.secondaryText(colorScheme))
                    .multilineTextAlignment(.center)
                
                Spacer().frame(height: 20)
                
                // Username card
                VStack(alignment: .leading, spacing: 12) {
                    Text("onboarding.username_label")
                        .font(.caption)
                        .foregroundColor(Theme.secondaryText(colorScheme))
                    
                    if isEditing {
                        HStack {
                            TextField("Username", text: $editedName)
                                .font(.system(.title2, design: .monospaced))
                                .textFieldStyle(.roundedBorder)
                                .focused($isFocused)
                                .submitLabel(.done)
                                .onSubmit {
                                    saveAndDismiss()
                                }
                                .onAppear {
                                    // Auto-focus when the field appears
                                    isFocused = true
                                }
                            
                            Button(action: saveAndDismiss) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(Theme.legacyGreen(colorScheme))
                            }
                        }
                    } else {
                        HStack {
                            Text(viewModel.nickname)
                                .font(.system(.title2, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle()) // Make entire area tappable
                                .onTapGesture {
                                    startEditing()
                                }
                            
                            Button(action: startEditing) {
                                Image(systemName: "pencil.circle")
                                    .font(.title2)
                                    .foregroundColor(Theme.secondaryText(colorScheme))
                            }
                        }
                    }
                }
                .padding()
                .background(Theme.surface(colorScheme))
                .cornerRadius(Theme.CornerRadius.medium)
                
                // Privacy warning
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("onboarding.privacy_note")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                .padding()
                .background(Color.orange.opacity(0.1))
                .cornerRadius(Theme.CornerRadius.medium)
                
                Spacer()
            }
            .padding(.horizontal, 24)
        }
        // Sync focus state with editing state
        .onChange(of: isEditing) { editing in
            if editing {
                isFocused = true
            }
        }
    }
    
    private func startEditing() {
        editedName = viewModel.nickname
        isEditing = true
    }
    
    private func saveAndDismiss() {
        // Validation check
        if !editedName.trimmingCharacters(in: .whitespaces).isEmpty {
            viewModel.nickname = editedName
        }
        
        // Critical: Dismiss keyboard BEFORE toggling isEditing
        // This prevents constraint errors when the TextField is removed
        isFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        
        // Add a small delay or just toggle state now? 
        // Toggling immediately is usually fine if keyboard dismissal has started
        isEditing = false
    }
}

// MARK: - Step 2: Mesh Explanation
private struct MeshStep: View {
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Spacer().frame(height: 40)
                
                Text("onboarding.mesh_title")
                    .font(.title)
                    .fontWeight(.bold)
                
                // Mesh icon
                HStack {
                    Spacer()
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 60))
                        .foregroundColor(Theme.meshChannel)
                    Spacer()
                }
                .padding(.vertical, 20)
                
                Text("onboarding.mesh_desc")
                    .font(.body)
                    .lineSpacing(4)
                
                // Key points
                VStack(alignment: .leading, spacing: 12) {
                    FeaturePoint(icon: "wifi.slash", textKey: "onboarding.mesh_offline")
                    FeaturePoint(icon: "lock.shield", textKey: "onboarding.mesh_encrypted")
                    FeaturePoint(icon: "server.rack", textKey: "onboarding.mesh_noserver")
                }
                .padding()
                .background(Theme.surface(colorScheme))
                .cornerRadius(Theme.CornerRadius.medium)
                                
                Spacer()
            }
            .padding(.horizontal, 24)
        }
    }
}

// MARK: - Step 3: Features & Status
private struct FeaturesStep: View {
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Spacer().frame(height: 40)
                
                Text("onboarding.features_title")
                    .font(.title)
                    .fontWeight(.bold)
                
                // Geohash feature
                FeatureCard(
                    icon: "location.circle.fill",
                    iconColor: Theme.locationChannel(colorScheme),
                    titleKey: "onboarding.feature_geo_title",
                    descKey: "onboarding.feature_geo_desc"
                )
                
                // Location Notes feature
                FeatureCard(
                    icon: "note.text",
                    iconColor: .yellow,
                    titleKey: "onboarding.feature_notes_title",
                    descKey: "onboarding.feature_notes_desc"
                )
                
                // Emergency wipe
                FeatureCard(
                    icon: "trash.circle.fill",
                    iconColor: .red,
                    titleKey: "onboarding.emergency_title",
                    descKey: "onboarding.emergency_desc"
                )
                
                Divider().padding(.vertical, 8)
                
                // Status icons
                Text("onboarding.status_title")
                    .font(.headline)
                
                VStack(alignment: .leading, spacing: 12) {
                    StatusRow(color: .green, nameKey: "onboarding.status_green", descKey: "onboarding.status_green_desc")
                    StatusRow(color: .orange, nameKey: "onboarding.status_orange", descKey: "onboarding.status_orange_desc")
                    StatusRow(color: .red, nameKey: "onboarding.status_red", descKey: "onboarding.status_red_desc")
                }
                
                Text("onboarding.status_dynamic")
                    .font(.caption)
                    .foregroundColor(Theme.secondaryText(colorScheme))
                    .padding(.top, 8)
                
                Spacer()
            }
            .padding(.horizontal, 24)
        }
    }
}

// MARK: - Helper Views

private struct FeaturePoint: View {
    let icon: String
    let textKey: LocalizedStringKey
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(Theme.legacyGreen(colorScheme))
            Text(textKey)
                .font(.subheadline)
        }
    }
}

private struct FeatureCard: View {
    let icon: String
    let iconColor: Color
    let titleKey: LocalizedStringKey
    let descKey: LocalizedStringKey
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(iconColor)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(titleKey)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(descKey)
                    .font(.caption)
                    .foregroundColor(Theme.secondaryText(colorScheme))
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface(colorScheme))
        .cornerRadius(Theme.CornerRadius.medium)
    }
}

private struct StatusRow: View {
    let color: Color
    let nameKey: LocalizedStringKey
    let descKey: LocalizedStringKey
    
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(nameKey)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(descKey)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Step 4: Permissions
private struct PermissionsStep: View {
    @Environment(\.colorScheme) var colorScheme
    @State private var bluetoothGranted = false
    @State private var locationGranted = false
    @State private var notificationsGranted = false
    
    // Managers must be persisted to keep prompts alive
    @State private var centralManager: CBCentralManager?
    @State private var locationManager: CLLocationManager?

    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Spacer().frame(height: 40)
                
                Text("onboarding.permissions_title")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("onboarding.permissions_desc")
                    .font(.body)
                    .foregroundColor(Theme.secondaryText(colorScheme))
                
                Spacer().frame(height: 20)
                
                // Permission cards
                VStack(spacing: 16) {
                    PermissionCard(
                        icon: "antenna.radiowaves.left.and.right",
                        iconColor: Theme.meshChannel,
                        titleKey: "onboarding.permission_bluetooth",
                        descKey: "onboarding.permission_bluetooth_desc",
                        isGranted: bluetoothGranted,
                        onRequest: requestBluetooth
                    )
                    
                    PermissionCard(
                        icon: "location.circle.fill",
                        iconColor: Theme.locationChannel(colorScheme),
                        titleKey: "onboarding.permission_location",
                        descKey: "onboarding.permission_location_desc",
                        isGranted: locationGranted,
                        onRequest: requestLocation
                    )
                    
                    PermissionCard(
                        icon: "bell.circle.fill",
                        iconColor: .orange,
                        titleKey: "onboarding.permission_notifications",
                        descKey: "onboarding.permission_notifications_desc",
                        isGranted: notificationsGranted,
                        onRequest: requestNotifications
                    )
                }
                
                Spacer()
            }
            .padding(.horizontal, 24)
        }
        .onAppear {
            checkPermissions()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            checkPermissions()
        }
    }
    
    private func checkPermissions() {
        // Check Bluetooth
        bluetoothGranted = CBManager.authorization == .allowedAlways
        
        // Check Location
        let locStatus = CLLocationManager().authorizationStatus
        locationGranted = locStatus == .authorizedWhenInUse || locStatus == .authorizedAlways
        
        // Check Notifications
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                notificationsGranted = settings.authorizationStatus == .authorized
            }
        }
    }
    
    private func requestBluetooth() {
        // Initializing the manager triggers the prompt if permission is not determined.
        // We must keep a reference to it.
        if centralManager == nil {
            centralManager = CBCentralManager(delegate: nil, queue: nil)
        }
        
        // Check again after a short delay to allow user interaction
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            bluetoothGranted = CBManager.authorization == .allowedAlways
        }
    }
    
    private func requestLocation() {
        if locationManager == nil {
            locationManager = CLLocationManager()
        }
        locationManager?.requestWhenInUseAuthorization()
        
        // Check again after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            let status = locationManager?.authorizationStatus ?? .notDetermined
            locationGranted = status == .authorizedWhenInUse || status == .authorizedAlways
        }
    }
    
    private func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            DispatchQueue.main.async {
                notificationsGranted = granted
            }
        }
    }
}

private struct PermissionCard: View {
    let icon: String
    let iconColor: Color
    let titleKey: LocalizedStringKey
    let descKey: LocalizedStringKey
    let isGranted: Bool
    let onRequest: () -> Void
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(iconColor)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(titleKey)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(descKey)
                    .font(.caption)
                    .foregroundColor(Theme.secondaryText(colorScheme))
            }
            
            Spacer()
            
            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.title2)
            } else {
                Button(action: onRequest) {
                    Text("onboarding.permission_allow")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Theme.legacyGreen(colorScheme))
                        .foregroundColor(.white)
                        .cornerRadius(Theme.CornerRadius.small)
                }
            }
        }
        .padding()
        .background(Theme.surface(colorScheme))
        .cornerRadius(Theme.CornerRadius.medium)
    }
}
