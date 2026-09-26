import AVFoundation
import UIKit

/// Owns the capture session; all session work happens on a private serial queue.
nonisolated final class ReceiptCameraSession: NSObject, @unchecked Sendable, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    /// Why the running session can't take photos right now. Main actor only.
    let interruption = ReceiptCameraInterruptionState()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "syl.receipt.camera")
    private var isConfigured = false
    /// Whether the session should be running, so a media services reset can restart it.
    private var wantsRunning = false
    private var observers: [any NSObjectProtocol] = []
    private var pendingCapture: CheckedContinuation<UIImage?, Never>?

    /// Safe to read from any thread.
    var isRunning: Bool { session.isRunning }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    /// Returns false when no back camera exists (e.g. the Simulator).
    /// Idempotent: returns immediately when already running.
    func start() async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                guard configureIfNeeded() else {
                    continuation.resume(returning: false)
                    return
                }
                wantsRunning = true
                if !session.isRunning { session.startRunning() }
                if session.isRunning { clearFailure() }
                continuation.resume(returning: true)
            }
        }
    }

    func stop() {
        queue.async { [self] in
            wantsRunning = false
            if session.isRunning { session.stopRunning() }
            // A stopped session reports nothing further; the next start re-reports.
            let state = interruption
            DispatchQueue.main.async { state.current = nil }
        }
    }

    /// `rotationAngle` levels the photo with the horizon; nil keeps the last angle.
    func capture(rotationAngle: CGFloat?) async -> UIImage? {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                guard pendingCapture == nil, session.isRunning, !session.isInterrupted else {
                    continuation.resume(returning: nil)
                    return
                }
                if let rotationAngle, let connection = output.connection(with: .video),
                   connection.isVideoRotationAngleSupported(rotationAngle) {
                    connection.videoRotationAngle = rotationAngle
                }
                pendingCapture = continuation
                output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
            }
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: (any Error)?) {
        let image = error == nil ? photo.fileDataRepresentation().flatMap(UIImage.init(data:)) : nil
        queue.async { [self] in
            pendingCapture?.resume(returning: image)
            pendingCapture = nil
        }
    }

    private func configureIfNeeded() -> Bool {
        if isConfigured { return true }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else { return false }
        session.beginConfiguration()
        session.sessionPreset = .photo
        if session.canAddInput(input) { session.addInput(input) }
        if session.canAddOutput(output) { session.addOutput(output) }
        // Portrait until the panel's rotation coordinator supplies a live angle.
        if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        // iPads that support it keep the camera live beside other apps
        // (Split View, Slide Over, Stage Manager) instead of interrupting it.
        if session.isMultitaskingCameraAccessSupported {
            session.isMultitaskingCameraAccessEnabled = true
        }
        session.commitConfiguration()
        observeSession()
        isConfigured = true
        return true
    }

    private func observeSession() {
        let center = NotificationCenter.default
        let state = interruption
        observers = [
            center.addObserver(forName: AVCaptureSession.wasInterruptedNotification,
                               object: session, queue: nil) { notification in
                let reason = (notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int)
                    .flatMap(AVCaptureSession.InterruptionReason.init(rawValue:))
                let interruption = ReceiptCameraInterruption(reason: reason)
                DispatchQueue.main.async { state.current = interruption }
            },
            center.addObserver(forName: AVCaptureSession.interruptionEndedNotification,
                               object: session, queue: nil) { _ in
                DispatchQueue.main.async { state.current = nil }
            },
            center.addObserver(forName: AVCaptureSession.runtimeErrorNotification,
                               object: session, queue: nil) { [weak self] notification in
                let code = (notification.userInfo?[AVCaptureSessionErrorKey] as? AVError)?.code
                self?.recover(from: code)
            }
        ]
    }

    /// A media services reset is recoverable by restarting; anything else
    /// leaves the panel explaining why the shutter is off.
    private func recover(from code: AVError.Code?) {
        queue.async { [self] in
            guard wantsRunning else { return }
            if code == .mediaServicesWereReset, !session.isRunning {
                session.startRunning()
            }
            guard !session.isRunning else { return }
            let state = interruption
            DispatchQueue.main.async { state.current = .failed }
        }
    }

    /// Runs on `queue` after a successful start.
    private func clearFailure() {
        let state = interruption
        DispatchQueue.main.async {
            if state.current == .failed { state.current = nil }
        }
    }
}
