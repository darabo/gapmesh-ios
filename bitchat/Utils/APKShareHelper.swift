import SwiftUI
#if os(iOS)
import UIKit

/// Helper to share the Gap Mesh Android APK file from iOS to Android devices.
///
/// The pre-built light APK (~4.5 MB) must be bundled as a resource named
/// `GapMesh.apk` in the app target.  Add the file to the Xcode project
/// (drag into the project navigator → check "Copy items if needed" and
/// the correct target membership).
///
/// Sharing flow:
///   1.  Locate the APK in the app bundle.
///   2.  Copy it to a temporary directory so the share sheet can read it.
///   3.  Present `UIActivityViewController` with the file URL.
enum APKShareHelper {

    static let apkFileName = "gapmesh-light.apk"

    /// Whether the bundled APK is available (i.e. was added to the Xcode project).
    static var isAPKBundled: Bool {
        Bundle.main.url(forResource: "gapmesh-light", withExtension: "apk") != nil
    }

    /// Present the system share sheet to send the APK file.
    ///
    /// - Parameter sourceView: The UIView used as the popover anchor on iPad.
    static func shareAPK(from sourceView: UIView? = nil) {
        guard let bundledURL = Bundle.main.url(forResource: "gapmesh-light", withExtension: "apk") else {
            #if DEBUG
            print("[APKShareHelper] gapmesh-light.apk not found in bundle")
            #endif
            return
        }

        // Copy to a temp directory so the share sheet has unrestricted read access.
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("apk_share", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let destURL = tempDir.appendingPathComponent(apkFileName)

        // Overwrite any previous copy
        try? FileManager.default.removeItem(at: destURL)
        do {
            try FileManager.default.copyItem(at: bundledURL, to: destURL)
        } catch {
            #if DEBUG
            print("[APKShareHelper] Failed to copy APK: \(error)")
            #endif
            return
        }

        let activityVC = UIActivityViewController(
            activityItems: [
                destURL,
                "Install Gap Mesh — decentralized mesh messaging with end-to-end encryption."
            ],
            applicationActivities: nil
        )

        // iPad popover anchor
        if let popover = activityVC.popoverPresentationController {
            if let anchor = sourceView {
                popover.sourceView = anchor
                popover.sourceRect = anchor.bounds
            }
        }

        // Present from the top-most view controller
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first,
              let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            return
        }

        var presenter = rootVC
        while let presented = presenter.presentedViewController {
            presenter = presented
        }
        presenter.present(activityVC, animated: true)
    }
}
#endif
