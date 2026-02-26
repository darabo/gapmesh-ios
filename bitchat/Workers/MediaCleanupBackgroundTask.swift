import Foundation
import BackgroundTasks
import BitLogger

/// Registers and schedules a `BGProcessingTask` for periodic media cleanup.
/// This is the heavy-lifting counterpart to the inline `MediaCleanupTask.cleanOutgoingMedia()`
/// that runs on each background transition.
///
/// `BGProcessingTask` is better suited for stale-data cleanup because it can run for
/// minutes (vs. seconds for `BGAppRefreshTask`).
enum MediaCleanupBackgroundTask {

    static let taskIdentifier = "chat.gap.media-cleanup"

    // MARK: - Registration

    /// Register the task handler with `BGTaskScheduler`.
    /// Call from `application(_:didFinishLaunchingWithOptions:)`.
    static func register() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskIdentifier,
            using: nil
        ) { task in
            guard let processingTask = task as? BGProcessingTask else { return }
            handleTask(processingTask)
        }
        SecureLogger.info("MediaCleanupBackgroundTask: registered \(taskIdentifier)", category: .session)
    }

    // MARK: - Scheduling

    /// Schedule the next cleanup ~6 h from now (best-effort).
    static func scheduleNextCleanup() {
        let request = BGProcessingTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 3600)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        do {
            try BGTaskScheduler.shared.submit(request)
            SecureLogger.info("MediaCleanupBackgroundTask: scheduled next cleanup", category: .session)
        } catch {
            SecureLogger.warning("MediaCleanupBackgroundTask: failed to schedule – \(error.localizedDescription)", category: .session)
        }
    }

    // MARK: - Execution

    private static func handleTask(_ task: BGProcessingTask) {
        scheduleNextCleanup() // re-schedule to keep the chain going

        let workTask = Task.detached(priority: .utility) {
            MediaCleanupTask.cleanOutgoingMedia()
            MediaCleanupTask.cleanStaleData()
        }

        task.expirationHandler = {
            workTask.cancel()
        }

        Task {
            _ = await workTask.result
            task.setTaskCompleted(success: true)
        }
    }
}
