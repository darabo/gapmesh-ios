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

/// The Main Entry Point of the iOS App.
///
/// This is where the app "wakes up". It has two main jobs:
/// 1. **Setup:** Create the objects that will run the app (like `ChatViewModel`).
/// 2. **Lifecycle:** Handle what happens when you close the app or open it again.
@main
struct BitchatApp: App {
    static let bundleID = Bundle.main.bundleIdentifier ?? "chat.gap"
    static let groupID = "group.\(bundleID)"
    
    @StateObject private var chatViewModel: ChatViewModel
    @StateObject private var languageManager = LanguageManager.shared
    @ObservedObject private var decoyManager = DecoyModeManager.shared
    @AppStorage("appAppearanceMode") private var appearanceMode: Int = 0 // 0=System, 1=Light, 2=Dark
    @AppStorage("onboarding_seen") private var onboardingSeen: Bool = false

    #if os(iOS)
    @Environment(\.scenePhase) var scenePhase
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    // Skip the very first .active-triggered Tor restart on cold launch
    @State private var didHandleInitialActive: Bool = false
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
    
    private let idBridge = NostrIdentityBridge()
    
    init() {
        let keychain = KeychainManager()
        let idBridge = self.idBridge
        _chatViewModel = StateObject(
            wrappedValue: ChatViewModel(
                keychain: keychain,
                idBridge: idBridge,
                identityManager: SecureIdentityStateManager(keychain)
            )
        )
        
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        // Warm up georelay directory and refresh if stale (once/day)
        GeoRelayDirectory.shared.prefetchIfNeeded()
    }
    
    var body: some Scene {
        WindowGroup {
            Group {
                if decoyManager.isDecoyActive {
                    CalculatorDecoyView()
                } else if !onboardingSeen {
                    OnboardingView(isPresented: .constant(true))
                } else if !decoyManager.hasPINConfigured {
                    // Existing user who updated before decoy mode existed.
                    // Must set up a PIN before proceeding, so they won't be
                    // trapped in the calculator after a triple-tap panic wipe.
                    DecoyPINOnboardingView()
                } else {
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
                }
                // Check for shared content
                checkForSharedContent()
            }
                .onOpenURL { url in
                    handleURL(url)
                }
                #if os(iOS)
                .onChange(of: scenePhase) { newPhase in
                    switch newPhase {
                    case .background:
                        // Keep BLE mesh running in background; BLEService adapts scanning automatically
                        // Always send Tor to dormant on background for a clean restart later.
                        TorManager.shared.setAppForeground(false)
                        TorManager.shared.goDormantOnBackground()
                        // Stop geohash sampling while backgrounded
                        Task { @MainActor in
                            chatViewModel.endGeohashSampling()
                        }
                        // Proactively disconnect Nostr to avoid spurious socket errors while Tor is down
                        NostrRelayManager.shared.disconnect()
                        didEnterBackground = true

                        // Schedule background tasks for relay refresh & media cleanup
                        RelayDirectoryBackgroundTask.scheduleNextRefresh()
                        MediaCleanupBackgroundTask.scheduleNextCleanup()
                        // Run an immediate foreground media cleanup while we still have execution time
                        MediaCleanupTask.cleanOutgoingMedia()
                    case .active:
                        // "Active" means the app is open on the screen and the user is using it.
                        // We need to wake everything up!
                        
                        // Restart services when becoming active
                        if onboardingSeen && !decoyManager.isDecoyActive && decoyManager.hasPINConfigured {
                            chatViewModel.startServices()
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
            VerificationService.shared.showSheet()
            if let qr = VerificationService.shared.verifyScannedQR(url.absoluteString) {
                chatViewModel.beginQRVerification(qr)
            }

        // ---- gapmesh://chat → main chat ----
        case ("gapmesh", "chat"), ("bitchat", "chat"):
            // App opens to chat by default; no additional routing needed.
            break

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
        
        // Show notification in all other cases
        completionHandler([.banner, .sound])
    }
}

extension String {
    var nilIfEmpty: String? {
        self.isEmpty ? nil : self
    }
}
