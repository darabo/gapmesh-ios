//
// BitchatApp.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import Tor
import SwiftUI
import UserNotifications

#if !DEBUG
// Globally suppress all print and debugPrint statements in Release builds
// to ensure privacy, security, and performance.
public func print(_ items: Any..., separator: String = " ", terminator: String = "\n") {}
public func debugPrint(_ items: Any..., separator: String = " ", terminator: String = "\n") {}
#endif

// ============================================================================
// BitchatApp — The Very First Code That Runs on iOS
// ============================================================================
//
// WHAT THIS FILE DOES:
// This is the "front door" of the Gap Mesh iOS app. When you tap the app icon,
// iOS runs this code FIRST. It creates the core objects (like ChatViewModel),
// decides which screen to show (chat, onboarding, or calculator decoy), and
// handles lifecycle events (app goes to background, comes back, etc.).
//
// KEY CONCEPTS FOR BEGINNERS:
//
// 1. @main — Tells Swift "start here." There is exactly ONE @main in every app.
//
// 2. @StateObject — Creates and owns an object. The object lives as long as
//    BitchatApp lives (= the entire app session). Used for ChatViewModel.
//
// 3. @AppStorage — A tiny database that persists simple values (strings, bools)
//    across app restarts. Think of it like UserDefaults at the SwiftUI level.
//
// 4. scenePhase — Tracks whether the app is .active (on screen), .background
//    (user switched away), or .inactive (transitioning). We use this to start/
//    stop Tor, Nostr, and BLE services at the right time.
//
// 5. Decoy Mode — A privacy feature where the app disguises itself as a
//    calculator. If `decoyManager.isDecoyActive` is true, we show a fake
//    calculator instead of the messaging interface.
//
// HOW THE APP DECIDES WHAT SCREEN TO SHOW:
//   - Decoy active?      → Show CalculatorDecoyView (fake calculator)
//   - First launch?      → Show OnboardingView (setup wizard)
//   - No PIN configured? → Show DecoyPINOnboardingView (security setup)
//   - Otherwise          → Show MainTabView (the real chat app!)
//
// ARCHITECTURE OVERVIEW:
//   BitchatApp (this file)
//     └── ChatViewModel — The "brain" of the app, manages all chat state
//           ├── BLEService — Bluetooth mesh for nearby phone-to-phone chat
//           ├── NostrTransport — Internet relay for long-range messaging
//           ├── NoiseEncryptionService — End-to-end encryption
//           └── TorManager — Anonymity network for internet traffic
//

/// The Main Entry Point of the iOS App.
///
/// This is where the app "wakes up". It has two main jobs:
/// 1. **Setup:** Create the objects that will run the app (like `ChatViewModel`).
/// 2. **Lifecycle:** Handle what happens when you close the app or open it again.
@main
struct BitchatApp: App {
    // Bundle ID: unique app identifier (e.g., "chat.gap")
    static let bundleID = Bundle.main.bundleIdentifier ?? "chat.gap"
    // App Group ID: allows the main app and the share extension to share data
    static let groupID = "group.\(bundleID)"
    
    // ── Core App State ─────────────────────────────────────────────────
    // ChatViewModel is the "brain" — it manages messages, peers, and all services.
    @StateObject private var chatViewModel: ChatViewModel
    // Manages the current language (English / Farsi) and triggers UI refresh on change.
    @StateObject private var languageManager = LanguageManager.shared
    // Tracks whether decoy mode (calculator disguise) is active.
    @ObservedObject private var decoyManager = DecoyModeManager.shared
    // Theme preference: 0=System, 1=Light, 2=Dark. Persisted across app restarts.
    @AppStorage("appAppearanceMode") private var appearanceMode: Int = 0
    // Whether the user has completed the first-time onboarding wizard.
    @AppStorage("onboarding_seen") private var onboardingSeen: Bool = false

    #if os(iOS)
    // scenePhase tracks active/background/inactive state for lifecycle management.
    @Environment(\.scenePhase) var scenePhase
    // AppDelegate handles UIKit-level events (background tasks, termination).
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    // Skip the very first .active-triggered Tor restart on cold launch
    // (because Tor was just started in onAppear — restarting immediately wastes time).
    @State private var didHandleInitialActive: Bool = false
    // Tracks whether the app has actually gone to background at least once.
    @State private var didEnterBackground: Bool = false
    #elseif os(macOS)
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) var appDelegate
    #endif
    
    // Computed property for preferred color scheme
    private var preferredColorScheme: ColorScheme? {
        switch appearanceMode {
        case 1: return .light
        case 2: return .dark
        default: return nil // System default
        }
    }
    
    // NostrIdentityBridge: Links the user's Nostr identity (public/private keys)
    // to the app's services. Nostr uses "npub" (public key) and "nsec" (secret key)
    // in a format called bech32 — like Bitcoin addresses but for social identities.
    private let idBridge = NostrIdentityBridge()
    
    /// App initialization — runs once when the app first loads.
    /// Sets up the ChatViewModel with all required dependencies.
    init() {
        // KeychainManager: Securely stores cryptographic keys in the iOS Keychain.
        // The Keychain is a hardware-backed secure storage that even other apps can't access.
        let keychain = KeychainManager()
        let idBridge = self.idBridge
        
        // Create the ChatViewModel with its three dependencies
        let cvm = ChatViewModel(
            keychain: keychain,
            idBridge: idBridge,
            identityManager: SecureIdentityStateManager(keychain)
        )
        // Assign to the StateObject
        _chatViewModel = StateObject(wrappedValue: cvm)
        
        // Register for push notifications so we can show alerts for new messages.
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        // Immediately bind the ChatViewModel to the notification delegate to prevent race conditions
        // where a user taps a notification on cold launch before SwiftUI's .onAppear fires.
        NotificationDelegate.shared.chatViewModel = cvm
        
        // Pre-load the geo-relay directory (maps regions to nearby relays)
        GeoRelayDirectory.shared.prefetchIfNeeded()
    }
    
    /// The main UI body — SwiftUI calls this to build the screen.
    /// Decides which view to show based on the app's current state.
    var body: some Scene {
        WindowGroup {
            Group {
                if decoyManager.isDecoyActive {
                    // DECOY MODE: Show a fake calculator app.
                    // This protects the user by hiding the messaging app.
                    CalculatorDecoyView()
                } else if !onboardingSeen {
                    // FIRST LAUNCH: Show setup wizard (permissions, tutorial).
                    OnboardingView(isPresented: .constant(true))
                } else if !decoyManager.hasPINConfigured {
                    // Existing user who updated before decoy mode existed.
                    // Must set up a PIN before proceeding, so they won't be
                    // trapped in the calculator after a triple-tap panic wipe.
                    DecoyPINOnboardingView()
                } else {
                    // NORMAL MODE: Show the real chat app.
                    MainTabView()
                }
            }
            .id(languageManager.refreshID)
            .environmentObject(chatViewModel)
            .environmentObject(languageManager)
            .applyLanguageEnvironment(languageManager)
            .preferredColorScheme(preferredColorScheme)
            .onAppear {
                NotificationDelegate.shared.chatViewModel = chatViewModel
                // Inject live Noise service into VerificationService to avoid creating new BLE instances
                VerificationService.shared.configure(with: chatViewModel.meshService.getNoiseService())
                // Prewarm Nostr identity and QR to make first VERIFY sheet fast
                let nickname = chatViewModel.nickname
                DispatchQueue.global(qos: .utility).async {
                    let npub = try? idBridge.getCurrentNostrIdentity()?.npub
                    _ = VerificationService.shared.buildMyQRString(nickname: nickname, npub: npub)
                }

                appDelegate.chatViewModel = chatViewModel
                
                // Resume interrupted panic wipe if any
                PanicWipeManager.shared.resumeWipeIfNeeded(chatViewModel: chatViewModel)

                // Initialize network activation policy; will start Tor/Nostr only when allowed
                // Services are started by OnboardingView.completeOnboarding() for new users
                if onboardingSeen && !decoyManager.isDecoyActive && decoyManager.hasPINConfigured {
                    NetworkActivationService.shared.start()
                    // Start presence service (will wait for Tor readiness)
                    GeohashPresenceService.shared.start()
                    // Reconcile Live Activity state if user previously enabled it
                    LiveActivityManager.shared.startIfEnabled()
                }
                // Check for shared content
                checkForSharedContent()
            }
                .onOpenURL { url in
                    handleURL(url)
                }
                #if os(iOS)
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .background:
                        // ── APP WENT TO BACKGROUND ──────────────────────────
                        // The user switched to another app or locked the phone.
                        // We need to:
                        //   1. Put Tor to sleep (save battery)
                        //   2. Stop geohash sampling (no need to track location)
                        //   3. Disconnect Nostr (avoids errors while Tor is down)
                        //   4. Schedule background tasks for cleanup
                        // NOTE: BLE mesh keeps running! iOS gives Bluetooth apps
                        // special background execution privileges.
                        TorManager.shared.setAppForeground(false)
                        TorManager.shared.goDormantOnBackground()
                        // Stop geohash sampling while backgrounded
                        Task { @MainActor in
                            chatViewModel.endGeohashSampling()
                        }
                        // Proactively disconnect Nostr to avoid spurious socket errors while Tor is down
                        NostrRelayManager.shared.disconnect()
                        P2PTransport.shared.stopServices()
                        didEnterBackground = true

                        // Schedule background tasks for relay refresh & media cleanup
                        RelayDirectoryBackgroundTask.scheduleNextRefresh()
                        MediaCleanupBackgroundTask.scheduleNextCleanup()
                        // Run an immediate foreground media cleanup while we still have execution time
                        MediaCleanupTask.cleanOutgoingMedia()
                    case .active:
                        // ── APP CAME BACK TO FOREGROUND ─────────────────────
                        // The user opened the app again. We need to:
                        //   1. Restart BLE mesh services
                        //   2. Wake up Tor for anonymous internet access
                        //   3. Reconnect to Nostr relays
                        //   4. Check for content shared via the share extension
                        
                        // Restart services when becoming active
                        if onboardingSeen && !decoyManager.isDecoyActive && decoyManager.hasPINConfigured {
                            chatViewModel.startServices()
                            // Reconcile Live Activity state on foreground transition.
                            LiveActivityManager.shared.startIfEnabled()
                        }
                        TorManager.shared.setAppForeground(true)
                        // On initial cold launch, Tor was just started in onAppear.
                        // Skip the deterministic restart the first time we become active.
                        if didHandleInitialActive && didEnterBackground {
                            if TorManager.shared.isAutoStartAllowed() && !TorManager.shared.isReady {
                                TorManager.shared.ensureRunningOnForeground()
                            }
                        } else {
                            didHandleInitialActive = true
                        }
                        didEnterBackground = false
                        if TorManager.shared.isAutoStartAllowed() {
                            Task.detached {
                                let _ = await TorManager.shared.awaitReady(timeout: 60)
                                await MainActor.run {
                                    // Rebuild proxied sessions to bind to the live Tor after readiness
                                    TorURLSession.shared.rebuild()
                                    // Reconnect Nostr via fresh sessions; will gate until Tor 100%
                                    NostrRelayManager.shared.resetAllConnections()
                                }
                            }
                        }
                        checkForSharedContent()
                    case .inactive:
                        break
                    @unknown default:
                        break
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    // Check for shared content when app becomes active
                    checkForSharedContent()
                }
                #elseif os(macOS)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    // App became active
                }
                #endif
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        #endif
    }
    
    /// Central deep-link router for all supported URI schemes:
    ///   - bitchat://share, gap://share     → shared content from extension
    ///   - bitchat://verify, gapmesh://verify → QR peer verification
    ///   - gapmesh://chat                    → open main chat tab
    ///   - gapmesh://stop                    → stop active networking + end Live Activity
    ///   - gapmesh://private_chat/{pubkey}   → open private chat with peer
    ///   - gapmesh://geohash_chat/{geohash}  → switch to geohash channel
    ///   - nostr:{entity}                    → NIP-19 bech32 handling (future)
    private func handleURL(_ url: URL) {
        let scheme = url.scheme?.lowercased()
        let host = url.host?.lowercased()

        switch (scheme, host) {
        // ---- Share extension content ----
        case ("bitchat", "share"), ("gap", "share"):
            checkForSharedContent()

        // ---- QR Verification ----
        case ("bitchat", "verify"), ("gapmesh", "verify"):
            if let qr = VerificationService.shared.verifyScannedQR(url.absoluteString) {
                _ = chatViewModel.beginQRVerification(with: qr)
            }

        // ---- gapmesh://chat → main chat ----
        case ("gapmesh", "chat"), ("bitchat", "chat"):
            // App opens to chat by default; no additional routing needed.
            break

        // ---- gapmesh://stop → stop active networking/services ----
        case ("gapmesh", "stop"), ("bitchat", "stop"):
            Task { @MainActor in
                self.chatViewModel.stopServicesFromLiveActivity()
            }

        // ---- gapmesh://stopLiveActivity → end the Live Activity only ----
        case ("gapmesh", "stopliveactivity"):
            LiveActivityManager.shared.setEnabled(false)

        // ---- gapmesh://private_chat/{pubkey} ----
        case ("gapmesh", "private_chat"), ("bitchat", "private_chat"):
            let pathComponents = url.pathComponents.filter { $0 != "/" }
            if let pubkey = pathComponents.first, !pubkey.isEmpty {
                chatViewModel.startPrivateChat(with: PeerID(str: pubkey))
                chatViewModel.objectWillChange.send()
            }

        // ---- gapmesh://geohash_chat/{geohash} ----
        case ("gapmesh", "geohash_chat"), ("bitchat", "geohash_chat"):
            let pathComponents = url.pathComponents.filter { $0 != "/" }
            if let geohash = pathComponents.first, !geohash.isEmpty {
                let level: GeohashChannelLevel = {
                    switch geohash.count {
                    case 7: return .block
                    case 6: return .neighborhood
                    case 5: return .city
                    case 4: return .province
                    case 2: return .region
                    default: return .city
                    }
                }()
                let channel = GeohashChannel(level: level, geohash: geohash)
                LocationChannelManager.shared.select(.location(channel))
            }

        // ---- nostr:{entity} → future NIP-19 bech32 routing ----
        case ("nostr", _):
            // TODO: Parse bech32 npub/nprofile/nevent and route accordingly
            break

        default:
            break
        }
    }
    
    private func checkForSharedContent() {
        // Check app group for shared content from extension
        guard let userDefaults = UserDefaults(suiteName: BitchatApp.groupID) else {
            return
        }
        
        guard let sharedContent = userDefaults.string(forKey: "sharedContent"),
              let sharedDate = userDefaults.object(forKey: "sharedContentDate") as? Date else {
            return
        }
        
        // Only process if shared within configured window
        if Date().timeIntervalSince(sharedDate) < TransportConfig.uiShareAcceptWindowSeconds {
            let contentType = userDefaults.string(forKey: "sharedContentType") ?? "text"
            
            // Clear the shared content
            userDefaults.removeObject(forKey: "sharedContent")
            userDefaults.removeObject(forKey: "sharedContentType")
            userDefaults.removeObject(forKey: "sharedContentDate")
            // No need to force synchronize here
            
            // Send the shared content immediately on the main queue
            DispatchQueue.main.async {
                if contentType == "url" {
                    // Try to parse as JSON first
                    if let data = sharedContent.data(using: .utf8),
                       let urlData = try? JSONSerialization.jsonObject(with: data) as? [String: String],
                       let url = urlData["url"] {
                        // Send plain URL
                        self.chatViewModel.sendMessage(url)
                    } else {
                        // Fallback to simple URL
                        self.chatViewModel.sendMessage(sharedContent)
                    }
                } else {
                    self.chatViewModel.sendMessage(sharedContent)
                }
            }
        }
    }
}

#if os(iOS)
final class AppDelegate: NSObject, UIApplicationDelegate {
    weak var chatViewModel: ChatViewModel?
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // Register background tasks — must happen before end of didFinishLaunching
        RelayDirectoryBackgroundTask.register()
        MediaCleanupBackgroundTask.register()
        return true
    }
    
    func applicationWillTerminate(_ application: UIApplication) {
        chatViewModel?.applicationWillTerminate()
    }
}
#endif

#if os(macOS)
import AppKit

final class MacAppDelegate: NSObject, NSApplicationDelegate {
    weak var chatViewModel: ChatViewModel?
    
    func applicationWillTerminate(_ notification: Notification) {
        chatViewModel?.applicationWillTerminate()
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
#endif

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()
    weak var chatViewModel: ChatViewModel?
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let identifier = response.notification.request.identifier
        let userInfo = response.notification.request.content.userInfo
        
        // Check if this is a private message notification
        if identifier.hasPrefix("private-") {
            // Get peer ID from userInfo
            if let peerID = userInfo["peerID"] as? String {
                DispatchQueue.main.async {
                    self.chatViewModel?.startPrivateChat(with: PeerID(str: peerID))
                    // Force SwiftUI to re-evaluate selectedPrivateChatPeer (computed property
                    // backed by PrivateChatManager) so .onChange triggers and opens the PM sheet
                    self.chatViewModel?.objectWillChange.send()
                }
            }
        }
        // Handle deeplink (e.g., geohash activity)
        if let deep = userInfo["deeplink"] as? String, let url = URL(string: deep) {
            #if os(iOS)
            DispatchQueue.main.async { UIApplication.shared.open(url) }
            #else
            DispatchQueue.main.async { NSWorkspace.shared.open(url) }
            #endif
        }
        
        // Handle georelay sharing back action
        if let action = userInfo["action"] as? String, action == "share_georelays_back" {
            DispatchQueue.main.async {
                self.chatViewModel?.shareGeorelaysLocally()
            }
        }
        
        completionHandler()
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let identifier = notification.request.identifier
        let userInfo = notification.request.content.userInfo
        
        // Check if this is a private message notification
        if identifier.hasPrefix("private-") {
            // Get peer ID from userInfo
            if let peerID = userInfo["peerID"] as? String {
                // Don't show notification if the private chat is already open
                // Access main-actor-isolated property via Task
                Task { @MainActor in
                    if self.chatViewModel?.selectedPrivateChatPeer == PeerID(str: peerID) {
                        completionHandler([])
                    } else {
                        completionHandler([.banner, .sound])
                    }
                }
                return
            }
        }
        // Suppress geohash activity notification if we're already in that geohash channel
        if identifier.hasPrefix("geo-activity-"),
           let deep = userInfo["deeplink"] as? String,
           let gh = deep.components(separatedBy: "/").last {
            if case .location(let ch) = LocationChannelManager.shared.selectedChannel, ch.geohash == gh {
                completionHandler([])
                return
            }
        }
        
        // Always show the share georelays prompt
        if identifier.hasPrefix("share-relays-") {
            completionHandler([.banner, .sound])
            return
        }
        
        // Show notification in all other cases
        completionHandler([.banner, .sound])
    }
}

extension String {
    var nilIfEmpty: String? {
        self.isEmpty ? nil : self
    }
}
