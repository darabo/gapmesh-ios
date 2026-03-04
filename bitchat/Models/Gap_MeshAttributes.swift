import ActivityKit
import Foundation

/// Shared ActivityAttributes for Gap Mesh Live Activities.
///
/// This file is compiled into BOTH the main app target and the widget extension
/// target via Xcode's File System Synchronized Groups on the "Shared/" folder.
///
/// - The main app uses `Activity<Gap_MeshAttributes>` to request/update/end.
/// - The widget extension uses `ActivityConfiguration(for: Gap_MeshAttributes.self)`
///   to render the Lock Screen, Dynamic Island, and expanded presentations.
public struct Gap_MeshAttributes: ActivityAttributes {

    // MARK: - Dynamic data (changes over the lifetime of the Live Activity)

    public struct ContentState: Codable, Hashable {
        /// Number of connected peers (BLE mesh + geochannel participants).
        public var peerCount: Int
        /// Display name for the current channel (e.g. "Mesh Network", "Tehran #u3qy5").
        public var channelName: String
        /// Human-readable connection status (e.g. "Connected", "Scanning…").
        public var statusText: String
        /// `true` when at least one peer is reachable.
        public var isConnected: Bool
        
        // Localized strings resolved by the main app and passed down
        public var userLabel: String
        public var usersLabel: String
        public var stopLabel: String
        public var defaultMeshNetworkLabel: String

        public init(peerCount: Int, channelName: String, statusText: String, isConnected: Bool, userLabel: String = "User", usersLabel: String = "Users", stopLabel: String = "Stop", defaultMeshNetworkLabel: String = "Mesh Network") {
            self.peerCount = peerCount
            self.channelName = channelName
            self.statusText = statusText
            self.isConnected = isConnected
            self.userLabel = userLabel
            self.usersLabel = usersLabel
            self.stopLabel = stopLabel
            self.defaultMeshNetworkLabel = defaultMeshNetworkLabel
        }
    }

    // MARK: - Static data (fixed for the lifetime of the Live Activity)

    /// Display name shown in the expanded Live Activity (e.g. "Gap Mesh").
    public var appName: String

    public init(appName: String = "Gap Mesh") {
        self.appName = appName
    }
}
