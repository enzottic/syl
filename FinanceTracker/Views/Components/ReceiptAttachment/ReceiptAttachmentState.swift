import SwiftUI
import AVFoundation

/// Drives the receipt button → menu → picker panel morph.
///
/// The page's receipt button and the sheet-level overlay live in different
/// hosting controllers, so they share this object instead of SwiftUI state.
@Observable
@MainActor
final class ReceiptAttachmentState {
    enum Mode: Equatable {
        case closed, menu, photos, camera

        var isExpanded: Bool { self == .photos || self == .camera }
    }

    private(set) var mode: Mode = .closed
    /// The overlay stays mounted until the shape has collapsed back into the button.
    private(set) var isPresented = false
    /// The page button's frame in global coordinates; the overlay morphs from it.
    var buttonFrame: CGRect = .zero
    private(set) var cameraAvailability: CameraAvailability = .available
    /// Owned here (not by the camera panel) so it can warm up while the menu is
    /// open, making the preview live as soon as Camera is chosen.
    let cameraSession = ReceiptCameraSession()
    var reduceMotion = false
    /// A receipt is loading or being read; the button shows a spinner.
    var isBusy = false

    private var generation = 0

    var menuAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : .bouncy(duration: 0.28, extraBounce: 0.1)
    }

    var expandAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : .smooth(duration: 0.3)
    }

    func openMenu() {
        guard !isPresented else { return }
        generation += 1
        cameraAvailability = .current
        prewarmCamera()
        mode = .closed
        isPresented = true
        // Mount at the button's frame first, then morph into the menu.
        DispatchQueue.main.async { [self] in
            guard isPresented, mode == .closed else { return }
            withAnimation(menuAnimation) { mode = .menu }
        }
    }

    func show(_ destination: Mode) {
        guard isPresented, destination.isExpanded else { return }
        withAnimation(expandAnimation) { mode = destination }
    }

    func back() {
        guard mode.isExpanded else { return }
        withAnimation(expandAnimation) { mode = .menu }
    }

    /// Collapses into the button from any state.
    func close() {
        guard isPresented, mode != .closed else { return }
        let generation = generation
        // Collapse without overshoot: a bouncy spring would dip below the
        // button's size. Hand back only once the animation has fully settled.
        withAnimation(expandAnimation, completionCriteria: .removed) {
            mode = .closed
        } completion: { [self] in
            guard self.generation == generation, mode == .closed else { return }
            isPresented = false
            cameraSession.stop()
        }
    }

    /// Stops the camera immediately, e.g. when the sheet goes away.
    func tearDown() {
        cameraSession.stop()
    }

    /// Only starts without prompting: an undetermined permission is requested
    /// when the user actually picks Camera.
    private func prewarmCamera() {
        guard cameraAvailability == .available,
              AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { return }
        let session = cameraSession
        Task { _ = await session.start() }
    }
}

enum CameraAvailability: Equatable {
    case available
    case unavailable(reason: String?)

    static var current: CameraAvailability {
        guard AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil else {
            return .unavailable(reason: "This device doesn't have a camera.")
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .denied:
            return .unavailable(reason: "Allow camera access for Syl in Settings.")
        case .restricted:
            return .unavailable(reason: "Camera access is restricted on this device.")
        default:
            return .available
        }
    }
}
