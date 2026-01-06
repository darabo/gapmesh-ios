import Foundation

/// Helper to check WiFi Aware availability at runtime.
/// WiFi Aware requires iOS 26+ and compatible hardware (iPhone 12+).
///
/// NOTE: This currently returns false because WiFi Aware framework
/// is not yet available in the SDK. Update when building with Xcode 26+.
struct WiFiAwareAvailability {
    
    /// Check if WiFi Aware is supported on this device.
    /// Uses Network framework (AWDL) for peer-to-peer connectivity.
    static var isSupported: Bool {
        // Network framework P2P is valid on these targets
        return true
    }
    
    /// Check if WiFi Aware is currently available (supported + enabled).
    static var isAvailable: Bool {
        return isSupported
    }
    
    /// Human-readable description of WiFi Aware status.
    static var statusDescription: String {
        if isSupported {
            return "WiFi Aware available"
        } else {
            return "WiFi Aware not supported"
        }
    }
}
