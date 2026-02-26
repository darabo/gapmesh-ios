import Foundation
import BackgroundTasks
import BitLogger

/// Registers and schedules a `BGAppRefreshTask` so the geo-relay CSV can be
/// refreshed even when the app is suspended.
///
/// The existing `GeoRelayDirectory` foreground Timer is kept as the primary
/// mechanism; this background task is a bonus that improves freshness for
/// users who leave the app backgrounded for long periods.
enum RelayDirectoryBackgroundTask {

    static let taskIdentifier = "chat.gap.relay-directory-refresh"

    // MARK: - Registration (call once at launch)

    /// Register the task handler with `BGTaskScheduler`.
    /// Must be called **before** the end of `application(_:didFinishLaunchingWithOptions:)` or
    /// during `App.init` for SwiftUI lifecycle apps.
    static func register() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            handleTask(refreshTask)
        }
        SecureLogger.info("RelayDirectoryBackgroundTask: registered \(taskIdentifier)", category: .session)
    }

    // MARK: - Scheduling

    /// Submit a request so the OS runs the task ~24 h from now (best-effort).
    static func scheduleNextRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 24 * 3600) // 24 hours
        do {
            try BGTaskScheduler.shared.submit(request)
            SecureLogger.info("RelayDirectoryBackgroundTask: scheduled next refresh", category: .session)
        } catch {
            SecureLogger.warning("RelayDirectoryBackgroundTask: failed to schedule – \(error.localizedDescription)", category: .session)
        }
    }

    // MARK: - Execution

    private static func handleTask(_ task: BGAppRefreshTask) {
        // Always re-schedule so the chain continues.
        scheduleNextRefresh()

        let workTask = Task {
            await GeoRelayDirectory.shared.backgroundRefresh()
        }

        // If the OS revokes time, cancel the network call.
        task.expirationHandler = {
            workTask.cancel()
        }

        Task {
            _ = await workTask.result
            task.setTaskCompleted(success: true)
        }
    }
}
