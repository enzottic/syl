import AVFoundation

/// Keeps the receipt camera level with the horizon. The iPad UI rotates to every
/// orientation and an iPhone can be held sideways, so neither the preview nor a
/// captured photo can assume portrait.
final class ReceiptCameraRotation {
    private var coordinator: AVCaptureDevice.RotationCoordinator?
    private var observation: NSKeyValueObservation?
    private weak var previewLayer: AVCaptureVideoPreviewLayer?

    /// Angle that makes the next photo upright relative to gravity, or nil
    /// before a preview is attached.
    var captureAngle: CGFloat? { coordinator?.videoRotationAngleForHorizonLevelCapture }

    /// Tracks `layer`'s interface orientation and rotates its preview to match.
    /// Call once the layer is in a window.
    func attach(to layer: AVCaptureVideoPreviewLayer) {
        guard layer !== previewLayer,
              let device = layer.connection?.inputPorts.lazy
                  .compactMap({ ($0.input as? AVCaptureDeviceInput)?.device }).first
        else { return }
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: layer)
        self.coordinator = coordinator
        previewLayer = layer
        applyPreviewAngle(coordinator.videoRotationAngleForHorizonLevelPreview)
        // KVO isn't guaranteed to arrive on the main thread.
        observation = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview,
                                          options: .new) { @Sendable [weak self] _, change in
            guard let angle = change.newValue else { return }
            DispatchQueue.main.async { self?.applyPreviewAngle(angle) }
        }
    }

    private func applyPreviewAngle(_ angle: CGFloat) {
        guard let connection = previewLayer?.connection,
              connection.isVideoRotationAngleSupported(angle) else { return }
        connection.videoRotationAngle = angle
    }
}
