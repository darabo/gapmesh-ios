#if os(iOS)
import SwiftUI
import UIKit

/// A transparent UIKit-level triple-tap recognizer overlay.
///
/// SwiftUI's `TapGesture(count: 3)` cannot fire inside a `ScrollView`
/// because the scroll view's gesture recognizers consume the taps before
/// SwiftUI can accumulate them.
///
/// This attaches a `UITapGestureRecognizer(numberOfTapsRequired: 3)` to
/// the hosting **window** so it receives every tap regardless of which
/// responder the scroll view routes touches to.  The recognizer is set
/// to *not* cancel touches so scrolling and all other interactions are
/// unaffected.
struct TripleTapOverlay: UIViewRepresentable {
    let action: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = WindowTapInstallerView()
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let action: () -> Void
        var tapGesture: UITapGestureRecognizer?

        init(action: @escaping () -> Void) { self.action = action }

        @objc func handleTripleTap() {
            action()
        }

        // Allow the triple-tap to recognise simultaneously with every
        // other gesture (scroll, single-tap, etc.)
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}

/// Invisible helper view that installs the tap recognizer on its window
/// once it is moved into the view hierarchy.
private final class WindowTapInstallerView: UIView {
    weak var coordinator: TripleTapOverlay.Coordinator?
    private var installed = false

    override func didMoveToWindow() {
        super.didMoveToWindow()

        guard let window, let coordinator, !installed else { return }
        installed = true

        let tap = UITapGestureRecognizer(
            target: coordinator,
            action: #selector(TripleTapOverlay.Coordinator.handleTripleTap)
        )
        tap.numberOfTapsRequired = 3
        tap.cancelsTouchesInView = false
        tap.delaysTouchesBegan = false
        tap.delaysTouchesEnded = false
        tap.delegate = coordinator          // allow simultaneous recognition
        coordinator.tapGesture = tap
        window.addGestureRecognizer(tap)
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        // Remove from old window
        if let old = window, let tap = coordinator?.tapGesture {
            old.removeGestureRecognizer(tap)
            installed = false
        }
    }

    // Fully transparent to hit testing — all touches pass through
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        nil
    }
}
#endif
