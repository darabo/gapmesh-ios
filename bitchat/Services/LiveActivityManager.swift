import Foundation
#if os(iOS)
import ActivityKit
#endif

/// Manages iOS Live Activities that keep the app visible on the lock screen
/// and Dynamic Island, displaying mesh network status including channel name,
/// connection status, and user count.
///
/// **Requires:** Widget Extension target with `chat.gap.kevahazadi.Gap-Mesh` bundle ID.
///
final class LiveActivityManager: ObservableObject {
    /// Posted (on MainActor) after a new Live Activity is created.
    /// Observers should call `syncLiveActivityState()` so the current
    /// channel (mesh or geohash) is reflected immediately.
    static let liveActivityDidStart = Notification.Name("LiveActivityDidStart")
    static let shared = LiveActivityManager()

    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "liveActivityEnabled")
            if isEnabled {
                startLiveActivity()
            } else {
                stopLiveActivity()
            }
        }
    }

    @Published private(set) var isActive: Bool = false

    /// Whether the system allows Live Activities for this app.
    var areActivitiesAuthorized: Bool {
        #if os(iOS)
        if #available(iOS 16.2, *) {
            return ActivityAuthorizationInfo().areActivitiesEnabled
        }
        #endif
        return false
    }

    #if os(iOS)
    private var currentActivityID: String?
    /// Guard against re-entrant starts (e.g. multiple onAppear calls)
    private var isStarting = false
    #endif

    /// One-line summary for the debug label in Settings.
    var debugStatusLine: String {
        let auth = areActivitiesAuthorized ? "auth" : "no-auth"
        let state = isActive ? "active" : "inactive"
        let enabled = isEnabled ? "enabled" : "disabled"
        return "\(enabled) · \(state) · \(auth)"
    }

    private init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: "liveActivityEnabled")
    }

    /// Start the Live Activity if the feature is enabled.
    func startIfEnabled() {
        guard isEnabled else { return }
        startLiveActivity()
    }

    /// Full update: channel name, connection status, user count.
    /// All localized strings are resolved from LanguageManager here.
    func update(channelName: String, statusText: String, peerCount: Int, isConnected: Bool) {
        #if os(iOS)
        guard #available(iOS 16.2, *) else { return }
        guard currentActivityID != nil else { return }

        Task {
            let state = buildContentState(
                peerCount: peerCount,
                channelName: channelName,
                statusText: statusText,
                isConnected: isConnected
            )
            for activity in Activity<Gap_MeshAttributes>.activities {
                await activity.update(
                    ActivityContent(state: state, staleDate: Date().addingTimeInterval(5 * 60))
                )
            }
        }
        #endif
    }

    /// Convenience: update peer count only (keeps existing channel name as localized "Mesh Network").
    func updatePeerCount(_ count: Int) {
        let status = count == 0
            ? LanguageManager.shared.localizedString("live_activity.scanning")
            : LanguageManager.shared.localizedString("live_activity.connected")
        update(
            channelName: LanguageManager.shared.localizedString("live_activity.mesh_network"),
            statusText: status,
            peerCount: count,
            isConnected: count > 0
        )
    }

    /// Update with relay/geochannel connection status.
    func updateGeoChannel(name: String, peerCount: Int, relayConnected: Bool) {
        let status = relayConnected
            ? LanguageManager.shared.localizedString("live_activity.relay_connected")
            : LanguageManager.shared.localizedString("live_activity.connecting")
        update(
            channelName: name,
            statusText: status,
            peerCount: peerCount,
            isConnected: relayConnected
        )
    }

    /// Toggle enabled state explicitly (used by Settings toggle and stop action).
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
    }

    /// End all running Live Activities (called on app termination or deactivation).
    func endAll() {
        stopLiveActivity()
    }

    /// Restart the Live Activity with fresh localized strings.
    func restartForLanguageChange() {
        guard isEnabled, isActive else { return }
        stopLiveActivity()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.startLiveActivity()
        }
    }

    /// Stop all activities (called on app termination or deactivation).
    func stop() {
        stopLiveActivity()
    }

    // MARK: - Private

    /// Build a ContentState with all localized strings resolved from LanguageManager.
    private func buildContentState(
        peerCount: Int,
        channelName: String,
        statusText: String,
        isConnected: Bool
    ) -> Gap_MeshAttributes.ContentState {
        Gap_MeshAttributes.ContentState(
            peerCount: peerCount,
            channelName: channelName,
            statusText: statusText,
            isConnected: isConnected,
            userLabel: LanguageManager.shared.localizedString("live_activity.user_singular"),
            usersLabel: LanguageManager.shared.localizedString("live_activity.user_plural"),
            stopLabel: LanguageManager.shared.localizedString("live_activity.stop"),
            defaultMeshNetworkLabel: LanguageManager.shared.localizedString("live_activity.mesh_network")
        )
    }

    private func startLiveActivity() {
        #if os(iOS)
        guard #available(iOS 16.2, *) else {
            print("[LiveActivityManager] Live Activities require iOS 16.2+")
            return
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("[LiveActivityManager] Live Activities not authorized")
            return
        }

        // Guard against re-entrant calls (e.g. multiple onAppear triggers)
        guard !isStarting else {
            print("[LiveActivityManager] Start already in progress, skipping")
            return
        }
        isStarting = true

        // If we already have a running activity, just keep it — don't spawn a new one
        if let existingID = currentActivityID,
           Activity<Gap_MeshAttributes>.activities.contains(where: { $0.id == existingID }) {
            print("[LiveActivityManager] Activity \(existingID) already running, skipping")
            isStarting = false
            return
        }

        // Synchronously end ALL existing activities before requesting a new one.
        // This prevents the race where async stop + immediate request = duplicates.
        Task {
            for activity in Activity<Gap_MeshAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }

            // Now request a fresh activity
            let attributes = Gap_MeshAttributes(appName: "Gap Mesh")
            let initialState = buildContentState(
                peerCount: 0,
                channelName: LanguageManager.shared.localizedString("live_activity.mesh_network"),
                statusText: LanguageManager.shared.localizedString("live_activity.starting"),
                isConnected: false
            )

            do {
                let activity = try Activity.request(
                    attributes: attributes,
                    content: .init(state: initialState, staleDate: nil),
                    pushType: nil
                )
                await MainActor.run {
                    self.currentActivityID = activity.id
                    self.isActive = true
                    self.isStarting = false
                    // Let ChatViewModel re-sync channel state now that the activity exists
                    NotificationCenter.default.post(name: Self.liveActivityDidStart, object: nil)
                }
                print("[LiveActivityManager] Started Live Activity: \(activity.id)")
            } catch {
                print("[LiveActivityManager] Failed to start: \(error.localizedDescription)")
                await MainActor.run {
                    self.isActive = false
                    self.isStarting = false
                }
            }
        }
        #endif
    }

    private func stopLiveActivity() {
        #if os(iOS)
        guard #available(iOS 16.2, *) else { return }

        Task {
            for activity in Activity<Gap_MeshAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            await MainActor.run {
                currentActivityID = nil
                isActive = false
            }
        }
        #endif
    }
}
