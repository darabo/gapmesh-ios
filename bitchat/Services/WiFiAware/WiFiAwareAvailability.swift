import Foundation

/// Helper to check WiFi Aware availability at runtime.
/// WiFi Aware requires iOS 26+ and compatible hardware (iPhone 12+).
///
/// NOTE: This currently returns false because WiFi Aware framework
/// is not yet available in the SDK. Update when building with Xcode 26+.
struct WiFiAwareAvailability {
    
    /// Check if WiFi Aware is supported on this device.
    /// Returns false until iOS 26 SDK is available.
    static var isSupported: Bool {
        // TODO: When building with Xcode 26+ SDK, uncomment:
        // #if canImport(WiFiAware)
        // if #available(iOS 26.0, *) {
        //     return WACapabilities.shared.isSupported
        // }
        // #endif
        return false
    }
    
    /// Check if WiFi Aware is currently available (supported + enabled).
    static var isAvailable: Bool {
        // TODO: When building with Xcode 26+ SDK, uncomment:
        // #if canImport(WiFiAware)
        // if #available(iOS 26.0, *) {
        //     return WACapabilities.shared.isAvailable
        // }
        // #endif
        return false
    }
    
    /// Human-readable description of WiFi Aware status.
    static var statusDescription: String {
        if isSupported {
            return isAvailable ? "WiFi Aware available" : "WiFi Aware supported but not available"
        } else {
            return "WiFi Aware not supported (requires iOS 26+)"
        }
    }
}
