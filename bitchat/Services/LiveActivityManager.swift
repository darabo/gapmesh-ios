import Foundation
import os
import Combine
#if canImport(ActivityKit)
import ActivityKit
#endif

private struct ActivityLifecycleLogger {
    #if DEBUG
    private let logger: Logger
    #endif

    init(subsystem: String, category: String) {
        #if DEBUG
        logger = Logger(subsystem: subsystem, category: category)
        #endif
    }

    func debug(_ message: @autoclosure @escaping () -> String) {
        #if DEBUG
        logger.debug("\(message())")
        #endif
    }

    func info(_ message: @autoclosure @escaping () -> String) {
        #if DEBUG
        logger.info("\(message())")
        #endif
    }

    func warning(_ message: @autoclosure @escaping () -> String) {
        #if DEBUG
        logger.warning("\(message())")
        #endif
    }

    func error(_ message: @autoclosure @escaping () -> String) {
        #if DEBUG
        logger.error("\(message())")
        #endif
    }
}

@MainActor
final class LiveActivityManager: ObservableObject {
    /// Internal lifecycle state for debugging and settings UI.
    /// This is intentionally small so every transition is easy to reason about.
    enum ManagerState: Equatable {
        case disabled
        case blockedBySystem
        case idle
        case running(activityID: String)

        var debugLabel: String {
            switch self {
            case .disabled:
                return "disabled"
            case .blockedBySystem:
                return "blockedBySystem"
            case .idle:
                return "idle"
            case .running(let activityID):
                return "running(\(String(activityID.suffix(6)).uppercased()))"
            }
        }
    }

    /// Single "snapshot" payload that the app sends to the Live Activity.
    /// All call sites should convert their runtime state into this one shape.
    struct SyncState: Equatable, Sendable {
        var peerCount: Int
        var channelName: String
        var statusText: String
        var isConnected: Bool
        
        let rawChannelName: String
        let rawStatusText: String
        
        // App-resolved strings
        private var userLabel: String
        private var usersLabel: String
        private var stopLabel: String
        private var defaultMeshNetworkLabel: String

        init(peerCount: Int, channelName: String, statusText: String, isConnected: Bool) {
            self.rawChannelName = channelName
            self.rawStatusText = statusText
            
            let normalizedChannelName = channelName.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedStatusText = statusText.trimmingCharacters(in: .whitespacesAndNewlines)
            self.peerCount = max(0, peerCount)
            self.channelName = normalizedChannelName.isEmpty || normalizedChannelName == "Mesh Network"
                ? String(localized: "Mesh Network", bundle: .main)
                : normalizedChannelName
                
            if normalizedStatusText.isEmpty {
                self.statusText = isConnected ? String(localized: "Connected", bundle: .main) : String(localized: "Scanning…", bundle: .main)
            } else if normalizedStatusText == "Relay Connected" {
                self.statusText = String(localized: "Relay Connected", bundle: .main)
            } else if normalizedStatusText == "Connecting…" || normalizedStatusText == "Connecting..." {
                self.statusText = String(localized: "Connecting…", bundle: .main)
            } else if normalizedStatusText == "Connected" {
                self.statusText = String(localized: "Connected", bundle: .main)
            } else if normalizedStatusText == "Scanning…" || normalizedStatusText == "Scanning..." {
                self.statusText = String(localized: "Scanning…", bundle: .main)
            } else {
                self.statusText = normalizedStatusText
            }
            
            self.isConnected = isConnected
            
            // Resolve labels on the main app side so the Widget doesn't have to guess
            self.userLabel = String(localized: "User", bundle: .main)
            self.usersLabel = String(localized: "Users", bundle: .main)
            self.stopLabel = String(localized: "Stop", bundle: .main)
            self.defaultMeshNetworkLabel = String(localized: "Mesh Network", bundle: .main)
        }
        
        func refreshed() -> SyncState {
            return SyncState(peerCount: peerCount, channelName: rawChannelName, statusText: rawStatusText, isConnected: isConnected)
        }

        static func mesh(peerCount: Int) -> SyncState {
            let clampedCount = max(0, peerCount)
            let connected = clampedCount > 0
            return SyncState(
                peerCount: clampedCount,
                channelName: String(localized: "Mesh Network", bundle: .main),
                statusText: connected ? String(localized: "Connected", bundle: .main) : String(localized: "Scanning…", bundle: .main),
                isConnected: connected
            )
        }

        fileprivate var contentState: Gap_MeshAttributes.ContentState {
            Gap_MeshAttributes.ContentState(
                peerCount: peerCount,
                channelName: channelName,
                statusText: statusText,
                isConnected: isConnected,
                userLabel: userLabel,
                usersLabel: usersLabel,
                stopLabel: stopLabel,
                defaultMeshNetworkLabel: defaultMeshNetworkLabel
            )
        }
    }

    static let shared = LiveActivityManager()

    private static let defaultsKey = "liveActivityEnabled"
    private static let pushTokenDefaultsKey = "liveActivityPushTokenHex"
    private nonisolated static let staleInterval: TimeInterval = 5 * 60
    private nonisolated static let startRetryInterval: TimeInterval = 8
    private nonisolated static let appName = "Gap Mesh"

    private let log = ActivityLifecycleLogger(
        subsystem: Bundle.main.bundleIdentifier ?? "gap-mesh",
        category: "LiveActivity"
    )

    @Published var isEnabled: Bool {
        didSet {
            guard oldValue != isEnabled else { return }
            UserDefaults.standard.set(isEnabled, forKey: Self.defaultsKey)
            log.info("preference changed: enabled=\(self.isEnabled ? "true" : "false")")
            scheduleReconcile(trigger: "toggle")
        }
    }
    @Published private(set) var managerState: ManagerState = .idle
    @Published private(set) var areActivitiesAuthorized: Bool = false
    @Published private(set) var activeActivityID: String?
    @Published private(set) var latestPushTokenHex: String?
    @Published private(set) var hasEmbeddedWidgetExtension: Bool = true

    var isRunning: Bool {
        if case .running = managerState {
            return true
        }
        return false
    }

    var debugStatusLine: String {
        "enabled=\(isEnabled ? "on" : "off") auth=\(areActivitiesAuthorized ? "on" : "off") widget=\(hasEmbeddedWidgetExtension ? "ok" : "missing") state=\(managerState.debugLabel) activity=\(shortActivityID) token=\(shortPushToken)"
    }

    var shortActivityID: String {
        guard let activeActivityID else { return "none" }
        return String(activeActivityID.suffix(6)).uppercased()
    }

    var shortPushToken: String {
        guard let latestPushTokenHex else { return "none" }
        return String(latestPushTokenHex.suffix(8)).uppercased()
    }

    /// Last state the app wants to show.
    private var desiredState: SyncState = .mesh(peerCount: 0)
    /// Last state we actually pushed to ActivityKit.
    private var lastAppliedState: SyncState?
    private var reconcileTask: Task<Void, Never>?
    private var nextStartAttemptAt: Date = .distantPast
    private var hasLoggedMissingWidgetWarning = false

    #if canImport(ActivityKit)
    private typealias MeshActivity = Activity<Gap_MeshAttributes>
    private var observedActivityID: String?
    private var pushTokenTask: Task<Void, Never>?
    private var activityStateTask: Task<Void, Never>?
    #endif
    
    private var languageCancellable: AnyCancellable?

    private init() {
        let defaults = UserDefaults.standard
        let savedEnabled = defaults.bool(forKey: Self.defaultsKey)
        _isEnabled = Published(initialValue: savedEnabled)
        _latestPushTokenHex = Published(initialValue: defaults.string(forKey: Self.pushTokenDefaultsKey))

        refreshAuthorizationSnapshot()
        refreshWidgetExtensionSnapshot()
        recomputeManagerState()
        
        languageCancellable = LanguageManager.shared.$refreshID.sink { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.sync(state: self.desiredState.refreshed())
            }
        }
    }

    // MARK: - Public API

    /// Reconcile current OS activity state with user preference.
    /// Safe to call on app launch and foreground transitions.
    func bootstrap() {
        refreshAuthorizationSnapshot()
        refreshWidgetExtensionSnapshot()
        scheduleReconcile(trigger: "bootstrap")
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
    }

    /// Canonical sync API for all runtime updates.
    func sync(state: SyncState) {
        let normalized = state
        let isDuplicateRunningUpdate = normalized == desiredState && isRunning
        desiredState = normalized
        if isDuplicateRunningUpdate {
            log.debug("sync dedupe skip: desired state unchanged while running")
            return
        }
        // While disabled, keep the latest desired snapshot but avoid noisy
        // reconcile churn/log spam from frequent mesh updates.
        if !isEnabled {
            return
        }
        scheduleReconcile(trigger: "sync")
    }

    /// Ends all activities immediately, without mutating the user's preference.
    func endAll() {
        scheduleReconcile(trigger: "endAll", forceEndAll: true)
    }

    // MARK: - Compatibility wrappers (legacy call sites)

    func startIfEnabled() {
        bootstrap()
    }

    func stop() {
        endAll()
    }

    func updatePeerCount(_ count: Int) {
        sync(state: .mesh(peerCount: count))
    }

    func updateGeoChannel(name: String, peerCount: Int, relayConnected: Bool) {
        sync(
            state: SyncState(
                peerCount: peerCount,
                channelName: name,
                statusText: relayConnected ? "Relay Connected" : "Connecting…",
                isConnected: relayConnected
            )
        )
    }

    // MARK: - Lifecycle reconciliation

    private func scheduleReconcile(trigger: String, forceEndAll: Bool = false) {
        // Debounce rapid callers (peer churn, foreground events, toggle changes)
        // into one deterministic reconciliation pass.
        reconcileTask?.cancel()
        reconcileTask = Task { @MainActor [weak self] in
            await self?.reconcileLifecycle(trigger: trigger, forceEndAll: forceEndAll)
        }
    }

    private func reconcileLifecycle(trigger: String, forceEndAll: Bool = false) async {
        refreshAuthorizationSnapshot()

        if forceEndAll {
            // Explicit kill-switch path used by settings/debug controls.
            await endAllActivities(reason: "manual-\(trigger)")
            lastAppliedState = nil
            activeActivityID = nil
            recomputeManagerState()
            return
        }

        guard isEnabled else {
            // User disabled Live Activities in app settings.
            log.debug("reconcile[\(trigger)]: disabled by user")
            await endAllActivities(reason: "disabled-\(trigger)")
            lastAppliedState = nil
            activeActivityID = nil
            recomputeManagerState()
            return
        }

        guard areActivitiesAuthorized else {
            // System-level authorization can be off even if our in-app toggle is on.
            log.warning("reconcile[\(trigger)]: blocked by system authorization")
            await endAllActivities(reason: "blocked-\(trigger)")
            lastAppliedState = nil
            activeActivityID = nil
            recomputeManagerState()
            return
        }

        guard hasEmbeddedWidgetExtension else {
            if !hasLoggedMissingWidgetWarning {
                log.error("reconcile[\(trigger)]: widget extension missing from app bundle; Live Activity UI cannot render")
                hasLoggedMissingWidgetWarning = true
            }
            return
        }

        #if canImport(ActivityKit)
        var activities = MeshActivity.activities
        if activities.count > 1 {
            let keep = preferredActivity(from: activities)
            let extras = activities.filter { $0.id != keep.id }
            log.warning("reconcile[\(trigger)]: ending \(extras.count) duplicate activities")
            for activity in extras {
                await end(activity: activity, reason: "dedupe-\(trigger)")
            }
            activities = [keep]
        }

        if let existing = activities.first {
            // App relaunch/foreground: adopt the existing Live Activity instead of
            // creating duplicates, then update it if state has changed.
            activeActivityID = existing.id
            lastAppliedState = SyncState(contentState: existing.content.state)
            recomputeManagerState()
            startObservers(for: existing)
            log.debug("reconcile[\(trigger)]: adopted existing activity id=\(existing.id)")
            await updateIfNeeded(activity: existing, state: desiredState, reason: "adopt-\(trigger)")
            return
        }

        let now = Date()
        if now < nextStartAttemptAt {
            // Back off repeated failures so we do not hammer ActivityKit.
            log.debug("start throttled until \(self.nextStartAttemptAt)")
            return
        }

        let attributes = Gap_MeshAttributes(appName: Self.appName)
        let initialContent = ActivityContent(
            state: desiredState.contentState,
            staleDate: staleDate()
        )

        do {
            let newActivity = try MeshActivity.request(
                attributes: attributes,
                content: initialContent,
                pushType: .token
            )
            activeActivityID = newActivity.id
            lastAppliedState = desiredState
            recomputeManagerState()
            startObservers(for: newActivity)
            nextStartAttemptAt = .distantPast
            log.info("start: requested activity id=\(newActivity.id)")
        } catch {
            let pushError = error as NSError
            log.warning(
                "start: push-token request failed domain=\(pushError.domain) code=\(pushError.code) desc=\(pushError.localizedDescription); retrying local-only"
            )

            do {
                // If push-token mode fails (common on simulator or transiently on device),
                // keep Live Activity working locally.
                let fallbackActivity = try MeshActivity.request(
                    attributes: attributes,
                    content: initialContent,
                    pushType: nil
                )
                activeActivityID = fallbackActivity.id
                lastAppliedState = desiredState
                recomputeManagerState()
                startObservers(for: fallbackActivity)
                nextStartAttemptAt = .distantPast
                log.info("start: fallback local-only activity requested id=\(fallbackActivity.id)")
            } catch {
                let localError = error as NSError
                activeActivityID = nil
                lastAppliedState = nil
                recomputeManagerState()
                nextStartAttemptAt = Date().addingTimeInterval(Self.startRetryInterval)
                log.error(
                    "start: failed to request activity in both modes push=(\(pushError.domain):\(pushError.code)) local=(\(localError.domain):\(localError.code)) nextRetry=\(self.nextStartAttemptAt)"
                )
            }
        }
        #else
        activeActivityID = nil
        lastAppliedState = nil
        recomputeManagerState()
        log.debug("reconcile[\(trigger)]: ActivityKit not available on this platform")
        #endif
    }

    private func refreshAuthorizationSnapshot() {
        #if canImport(ActivityKit)
        areActivitiesAuthorized = ActivityAuthorizationInfo().areActivitiesEnabled
        #else
        areActivitiesAuthorized = false
        #endif
    }

    private func refreshWidgetExtensionSnapshot() {
        hasEmbeddedWidgetExtension = detectEmbeddedWidgetExtension()
        if hasEmbeddedWidgetExtension {
            hasLoggedMissingWidgetWarning = false
        }
    }

    private func detectEmbeddedWidgetExtension() -> Bool {
        guard let plugInsURL = Bundle.main.builtInPlugInsURL else {
            return false
        }
        guard let pluginURLs = try? FileManager.default.contentsOfDirectory(
            at: plugInsURL,
            includingPropertiesForKeys: nil
        ) else {
            return false
        }
        for url in pluginURLs where url.pathExtension == "appex" {
            guard let bundle = Bundle(url: url),
                  let extensionDict = bundle.infoDictionary?["NSExtension"] as? [String: Any],
                  let identifier = extensionDict["NSExtensionPointIdentifier"] as? String else {
                continue
            }
            if identifier == "com.apple.widgetkit-extension" {
                return true
            }
        }
        return false
    }

    private func recomputeManagerState() {
        if !isEnabled {
            managerState = .disabled
            return
        }
        if !areActivitiesAuthorized {
            managerState = .blockedBySystem
            return
        }
        if let activeActivityID {
            managerState = .running(activityID: activeActivityID)
        } else {
            managerState = .idle
        }
    }

    private func staleDate() -> Date {
        // ActivityKit can dim stale content. We refresh this timestamp on each update.
        Date().addingTimeInterval(Self.staleInterval)
    }

    #if canImport(ActivityKit)
    private func preferredActivity(from activities: [MeshActivity]) -> MeshActivity {
        if let activeActivityID,
           let matching = activities.first(where: { $0.id == activeActivityID }) {
            return matching
        }
        return activities.last ?? activities[0]
    }

    private func updateIfNeeded(activity: MeshActivity, state: SyncState, reason: String) async {
        if lastAppliedState == state {
            // Skip no-op updates to reduce widget churn and system work.
            log.debug("update dedupe skip [\(reason)] id=\(activity.id)")
            return
        }
        let content = ActivityContent(state: state.contentState, staleDate: staleDate())
        await activity.update(content)
        lastAppliedState = state
        log.debug("update applied [\(reason)] id=\(activity.id) peers=\(state.peerCount)")
    }

    private func end(activity: MeshActivity, reason: String) async {
        await activity.end(
            ActivityContent(state: activity.content.state, staleDate: nil),
            dismissalPolicy: .immediate
        )
        log.info("end [\(reason)] id=\(activity.id)")
    }

    private func endAllActivities(reason: String) async {
        let activities = MeshActivity.activities
        guard !activities.isEmpty else {
            stopObservers()
            return
        }
        log.info("endAll [\(reason)]: ending \(activities.count) activity(ies)")
        for activity in activities {
            await end(activity: activity, reason: reason)
        }
        stopObservers()
    }

    private func startObservers(for activity: MeshActivity) {
        guard observedActivityID != activity.id else { return }
        stopObservers()
        observedActivityID = activity.id

        // Watch token refreshes so backend wiring can be added later without
        // changing app-side lifecycle code.
        pushTokenTask = Task { [weak self, activityID = activity.id] in
            for await tokenData in activity.pushTokenUpdates {
                let tokenHex = tokenData.map { String(format: "%02x", $0) }.joined()
                self?.storePushToken(tokenHex, activityID: activityID)
            }
        }

        // Watch activity lifecycle so settings/debug state stays accurate
        // if the system ends or dismisses the activity.
        activityStateTask = Task { [weak self, activityID = activity.id] in
            for await state in activity.activityStateUpdates {
                self?.handleActivityStateUpdate(state, activityID: activityID)
            }
        }
    }

    private func stopObservers() {
        pushTokenTask?.cancel()
        pushTokenTask = nil
        activityStateTask?.cancel()
        activityStateTask = nil
        observedActivityID = nil
    }

    private func storePushToken(_ tokenHex: String, activityID: String) {
        latestPushTokenHex = tokenHex
        UserDefaults.standard.set(tokenHex, forKey: Self.pushTokenDefaultsKey)
        log.info("push token updated: id=\(activityID) suffix=\(self.shortPushToken)")
    }

    private func handleActivityStateUpdate(_ state: ActivityState, activityID: String) {
        switch state {
        case .pending:
            log.debug("activity state pending: id=\(activityID)")
        case .active:
            log.debug("activity state active: id=\(activityID)")
        case .stale:
            log.debug("activity state stale: id=\(activityID)")
        case .ended:
            log.info("activity state ended: id=\(activityID)")
            clearActiveActivityIfMatching(activityID: activityID)
        case .dismissed:
            log.info("activity state dismissed: id=\(activityID)")
            clearActiveActivityIfMatching(activityID: activityID)
        @unknown default:
            log.debug("activity state unknown: id=\(activityID)")
        }
    }

    private func clearActiveActivityIfMatching(activityID: String) {
        guard activeActivityID == activityID else { return }
        activeActivityID = nil
        lastAppliedState = nil
        stopObservers()
        recomputeManagerState()
    }
    #endif
}

private extension LiveActivityManager.SyncState {
    init(contentState: Gap_MeshAttributes.ContentState) {
        self.init(
            peerCount: contentState.peerCount,
            channelName: contentState.channelName,
            statusText: contentState.statusText,
            isConnected: contentState.isConnected
        )
        self.userLabel = contentState.userLabel
        self.usersLabel = contentState.usersLabel
        self.stopLabel = contentState.stopLabel
        self.defaultMeshNetworkLabel = contentState.defaultMeshNetworkLabel
    }
}
