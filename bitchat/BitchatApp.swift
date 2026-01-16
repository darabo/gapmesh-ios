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

// This is the main entry point for the application.
// In SwiftUI, the @main attribute identifies the struct that serves as the app's entry point.
@main
struct BitchatApp: App {
    // Defines the App Group ID for sharing data between the main app and extensions (like the Share Extension).
    static let bundleID = Bundle.main.bundleIdentifier ?? "chat.gap"
    static let groupID = "group.\(bundleID)"
    
    // The main view model for the chat, managed as a StateObject.
    // This object holds the state of the chat and is responsible for business logic.
    @StateObject private var chatViewModel: ChatViewModel

    #if os(iOS)
    // Environment variable to track the scene phase (active, inactive, background).
    @Environment(\.scenePhase) var scenePhase
    // Adapts the legacy AppDelegate for use in SwiftUI.
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    // Flags to manage Tor restart logic on app launch/resume.
    // Skip the very first .active-triggered Tor restart on cold launch
    @State private var didHandleInitialActive: Bool = false
    @State private var didEnterBackground: Bool = false
    #elseif os(macOS)
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) var appDelegate
    #endif
    
    // Bridge to manage Nostr identity operations.
    private let idBridge = NostrIdentityBridge()
    
    // Initializer for the App struct.
    // Sets up the dependency injection for the ChatViewModel.
    init() {
        let keychain = KeychainManager()
        let idBridge = self.idBridge
        // Initialize ChatViewModel with dependencies.
        _chatViewModel = StateObject(
            wrappedValue: ChatViewModel(
                keychain: keychain,
                idBridge: idBridge,
                identityManager: SecureIdentityStateManager(keychain)
            )
        )
        
        // Set the delegate for handling push/local notifications.
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        // Warm up georelay directory and refresh if stale (once/day)
        GeoRelayDirectory.shared.prefetchIfNeeded()
    }
    
    // The body property defines the content of the app.
    var body: some Scene {
        WindowGroup {
            ContentView()
                // Inject the chatViewModel into the environment so child views can access it.
                .environmentObject(chatViewModel)
                .onAppear {
                    // Perform setup tasks when the view appears.
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

                    // Initialize network activation policy; will start Tor/Nostr only when allowed
                    NetworkActivationService.shared.start()
                    // Check for shared content (e.g. from other apps)
                    checkForSharedContent()
                }
                .onOpenURL { url in
                    // Handle deep links or file URLs.
                    handleURL(url)
                }
                #if os(iOS)
                .onChange(of: scenePhase) { newPhase in
                    // Handle changes in the app's lifecycle state (active, background, etc.)
                    switch newPhase {
                    case .background:
                        // App moved to background.
                        // Keep BLE mesh running in background; BLEService adapts scanning automatically
                        // Always send Tor to dormant on background for a clean restart later.
                        TorManager.shared.setAppForeground(false)
                        TorManager.shared.goDormantOnBackground()
                        // Stop geohash sampling while backgrounded to save battery.
                        Task { @MainActor in
                            chatViewModel.endGeohashSampling()
                        }
                        // Proactively disconnect Nostr to avoid spurious socket errors while Tor is down
                        NostrRelayManager.shared.disconnect()
                        didEnterBackground = true
                    case .active:
                        // App became active (foreground).
                        // Restart services when becoming active
                        chatViewModel.meshService.startServices()
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
                        // Check if any content was shared while the app was in the background.
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
    
    // Handles incoming URLs (deep links).
    private func handleURL(_ url: URL) {
        if (url.scheme == "bitchat" || url.scheme == "gap") && url.host == "share" {
            // Handle shared content
            checkForSharedContent()
        }
    }
    
    // Checks for content shared via the Share Extension.
    private func checkForSharedContent() {
        // Check app group for shared content from extension
        guard let userDefaults = UserDefaults(suiteName: BitchatApp.groupID) else {
            return
        }
        
        guard let sharedContent = userDefaults.string(forKey: "sharedContent"),
              let sharedDate = userDefaults.object(forKey: "sharedContentDate") as? Date else {
            return
        }
        
        // Only process if shared within configured window (to avoid processing old shares)
        if Date().timeIntervalSince(sharedDate) < TransportConfig.uiShareAcceptWindowSeconds {
            let contentType = userDefaults.string(forKey: "sharedContentType") ?? "text"
            
            // Clear the shared content from UserDefaults
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
// AppDelegate for iOS specific lifecycle events.
final class AppDelegate: NSObject, UIApplicationDelegate {
    weak var chatViewModel: ChatViewModel?
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        return true
    }
    
    func applicationWillTerminate(_ application: UIApplication) {
        chatViewModel?.applicationWillTerminate()
    }
}
#endif

#if os(macOS)
import AppKit

// AppDelegate for macOS specific lifecycle events.
final class MacAppDelegate: NSObject, NSApplicationDelegate {
    weak var chatViewModel: ChatViewModel?
    
    func applicationWillTerminate(_ notification: Notification) {
        chatViewModel?.applicationWillTerminate()
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Close the app when the last window is closed.
        return true
    }
}
#endif

// Delegate to handle user notifications (both local and remote).
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()
    weak var chatViewModel: ChatViewModel?
    
    // Called when a user interacts with a notification (e.g., taps it).
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let identifier = response.notification.request.identifier
        let userInfo = response.notification.request.content.userInfo
        
        // Check if this is a private message notification
        if identifier.hasPrefix("private-") {
            // Get peer ID from userInfo
            if let peerID = userInfo["peerID"] as? String {
                DispatchQueue.main.async {
                    // Navigate to the private chat
                    self.chatViewModel?.startPrivateChat(with: PeerID(str: peerID))
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
    
    // Called when a notification is delivered while the app is in the foreground.
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
    // Helper to return nil if the string is empty.
    var nilIfEmpty: String? {
        self.isEmpty ? nil : self
    }
}
