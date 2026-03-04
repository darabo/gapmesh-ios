//
//  Gap_MeshLiveActivity.swift
//  Gap Mesh Widget Extension
//
//  Live Activity UI for Lock Screen, Dynamic Island, and paired devices.
//  Shows mesh/geohash network status with peer count, channel, and connection state.
//
//  ⚠️ The `Gap_MeshAttributes` struct here MUST match Shared/Gap_MeshAttributes.swift.
//

import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - ActivityAttributes Definition
// ⚠️ This MUST be an exact copy of the definition in Shared/Gap_MeshAttributes.swift.
public struct Gap_MeshAttributes: ActivityAttributes {

    public struct ContentState: Codable, Hashable {
        public var peerCount: Int
        public var channelName: String
        public var statusText: String
        public var isConnected: Bool
        public var userLabel: String
        public var usersLabel: String
        public var stopLabel: String
        public var defaultMeshNetworkLabel: String

        public init(
            peerCount: Int,
            channelName: String,
            statusText: String,
            isConnected: Bool,
            userLabel: String = "User",
            usersLabel: String = "Users",
            stopLabel: String = "Stop",
            defaultMeshNetworkLabel: String = "Mesh Network"
        ) {
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

    public var appName: String

    public init(appName: String = "Gap Mesh") {
        self.appName = appName
    }
}

// MARK: - Helper: connection-aware antenna color

/// Returns green when connected, orange when scanning/starting, red for error states.
private func antennaColor(for state: Gap_MeshAttributes.ContentState) -> Color {
    if state.isConnected {
        return .green
    }
    // If the status text contains error-like keywords, use red
    let lower = state.statusText.lowercased()
    if lower.contains("error") || lower.contains("fail") || lower.contains("denied") {
        return .red
    }
    return .orange
}

// MARK: - Live Activity Widget

struct Gap_MeshLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: Gap_MeshAttributes.self) { context in
            // ── Lock Screen / Banner ──
            lockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                expandedView(context: context)
            } compactLeading: {
                compactLeadingView(context: context)
            } compactTrailing: {
                compactTrailingView(context: context)
            } minimal: {
                minimalView(context: context)
            }
        }
    }

    // MARK: - Lock Screen View
    // Symmetric 4-corner layout
    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<Gap_MeshAttributes>) -> some View {
        VStack(spacing: 10) {
            // ── Top row: channel + antenna (left) | peer count (right) ──
            HStack(alignment: .center) {
                // Top-left: antenna + channel name
                HStack(spacing: 6) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.subheadline)
                        .foregroundColor(antennaColor(for: context.state))
                    Text(context.state.channelName)
                        .font(.headline)
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }

                Spacer()

                // Top-right: peer count + person icon
                HStack(spacing: 6) {
                    Image(systemName: "person.2.fill")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                    Text("\(context.state.peerCount)")
                        .font(.title2.bold())
                        .foregroundColor(.white)
                        .monospacedDigit()
                }
            }

            // ── Bottom row: stop button (left) | connection status (right) ──
            HStack(alignment: .center) {
                // Bottom-left: stop button
                if let url = URL(string: "gapmesh://stopLiveActivity") {
                    Link(destination: url) {
                        HStack(spacing: 5) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 10))
                            Text(context.state.stopLabel)
                                .font(.subheadline.bold())
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(Color.red.opacity(0.8))
                        )
                    }
                }

                Spacer()

                // Bottom-right: connection status
                HStack(spacing: 5) {
                    Text(context.state.statusText)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Circle()
                        .fill(antennaColor(for: context.state))
                        .frame(width: 8, height: 8)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .activityBackgroundTint(Color.black.opacity(0.75))
        .activitySystemActionForegroundColor(.white)
    }

    // MARK: - Compact Leading
    // Antenna icon colored by connection status, with more inset so it's not on the edge
    @ViewBuilder
    private func compactLeadingView(context: ActivityViewContext<Gap_MeshAttributes>) -> some View {
        HStack(spacing: 0) {
            Spacer() // Takes all available space on the very left, pushing icon inwards
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 13))
                .foregroundColor(antennaColor(for: context.state))
            Spacer().frame(width: 6) // Gives the icon a little breathing room from the camera
        }
    }

    // MARK: - Compact Trailing
    // Peer count + person icon with more spacing from edge
    private func compactTrailingView(context: ActivityViewContext<Gap_MeshAttributes>) -> some View {
        HStack(spacing: 0) {
            Spacer().frame(width: 6) // Gives the icon a little breathing room from the camera
            HStack(spacing: 4) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 10))
                Text("\(context.state.peerCount)")
                    .font(.system(size: 15, weight: .bold))
                    .monospacedDigit()
            }
            .foregroundColor(.white)
            Spacer() // Takes all available space on the very right, pushing icon inwards
        }
    }

    // MARK: - Minimal
    // Small badge with antenna icon, properly centered
    @ViewBuilder
    private func minimalView(context: ActivityViewContext<Gap_MeshAttributes>) -> some View {
        Image(systemName: "antenna.radiowaves.left.and.right")
            .font(.system(size: 11))
            .foregroundColor(antennaColor(for: context.state))
    }

    // MARK: - Expanded View
    //   Leading top:  antenna + channel name
    //   Trailing top: peer count
    //   Bottom: stop button (left) and connection status (right)
    @DynamicIslandExpandedContentBuilder
    private func expandedView(context: ActivityViewContext<Gap_MeshAttributes>) -> DynamicIslandExpandedContent<some View> {
        // Leading region: channel name
        DynamicIslandExpandedRegion(.leading) {
            HStack(spacing: 5) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 14))
                    .foregroundColor(antennaColor(for: context.state))
                Text(context.state.channelName)
                    .font(.headline.bold())
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(.top, 4)
            .padding(.leading, 8)
        }

        // Trailing region: peer count
        DynamicIslandExpandedRegion(.trailing) {
            HStack(spacing: 5) {
                Image(systemName: "person.2.fill")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                Text("\(context.state.peerCount)")
                    .font(.title2.bold())
                    .foregroundColor(.white)
                    .monospacedDigit()
            }
            .padding(.top, 4)
            .padding(.trailing, 8)
        }
        
        // Bottom region: Stop button (left) & connection status (right)
        DynamicIslandExpandedRegion(.bottom) {
            HStack(alignment: .center) {
                // Stop button — bigger, capsule shape with "Liquid Glass" inner shine
                if let url = URL(string: "gapmesh://stopLiveActivity") {
                    Link(destination: url) {
                        HStack(spacing: 6) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 12, weight: .semibold))
                            Text(context.state.stopLabel)
                                .font(.system(size: 15, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(Color.red.opacity(0.85))
                                .overlay(
                                    Capsule()
                                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                )
                        )
                    }
                }
                
                Spacer(minLength: 16)
                
                // Connection status
                HStack(spacing: 6) {
                    Text(context.state.statusText)
                        .font(.headline.weight(.bold))
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Circle()
                        .fill(antennaColor(for: context.state))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.top, 8)
            .padding(.horizontal, 4)
        }
    }
}

// MARK: - Xcode Previews

extension Gap_MeshAttributes {
    fileprivate static var preview: Gap_MeshAttributes {
        Gap_MeshAttributes(appName: "Gap Mesh")
    }
}

extension Gap_MeshAttributes.ContentState {
    fileprivate static var connected: Gap_MeshAttributes.ContentState {
        Gap_MeshAttributes.ContentState(
            peerCount: 3,
            channelName: "Mesh Network",
            statusText: "Connected",
            isConnected: true
        )
    }

    fileprivate static var scanning: Gap_MeshAttributes.ContentState {
        Gap_MeshAttributes.ContentState(
            peerCount: 0,
            channelName: "Mesh Network",
            statusText: "Scanning…",
            isConnected: false
        )
    }

    fileprivate static var geohash: Gap_MeshAttributes.ContentState {
        Gap_MeshAttributes.ContentState(
            peerCount: 5,
            channelName: "Geohash #u3qy5",
            statusText: "Relay Connected",
            isConnected: true
        )
    }
}

#Preview("Notification", as: .content, using: Gap_MeshAttributes.preview) {
    Gap_MeshLiveActivity()
} contentStates: {
    Gap_MeshAttributes.ContentState.connected
    Gap_MeshAttributes.ContentState.scanning
    Gap_MeshAttributes.ContentState.geohash
}
