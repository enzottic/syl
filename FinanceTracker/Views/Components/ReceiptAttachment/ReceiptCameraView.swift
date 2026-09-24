import SwiftUI
import AVFoundation

/// Live camera preview filling the attachment panel, on a custom AVCaptureSession.
struct ReceiptCameraView: View {
    let camera: ReceiptCameraSession
    let onBack: () -> Void
    let onCapture: (UIImage) -> Void

    @State private var status: Status
    @State private var isCapturing = false

    enum Status { case loading, running, denied, unavailable }

    init(camera: ReceiptCameraSession, onBack: @escaping () -> Void, onCapture: @escaping (UIImage) -> Void) {
        self.camera = camera
        self.onBack = onBack
        self.onCapture = onCapture
        // A prewarmed session shows its preview on the very first frame.
        _status = State(initialValue: camera.isRunning ? .running : .loading)
    }

    var body: some View {
        ZStack {
            Color.black
            switch status {
            case .running:
                ReceiptCameraPreview(session: camera.session)
            case .loading:
                EmptyView()
            case .denied:
                message("Camera access is off. Allow access for Syl in Settings.")
            case .unavailable:
                message("This device doesn't have a camera.")
            }
        }
        .overlay(alignment: .bottom) {
            ZStack {
                Button(action: capture) {
                    Circle()
                        .fill(.white)
                        .frame(width: 62, height: 62)
                        .padding(5)
                        .overlay(Circle().stroke(.white, lineWidth: 3))
                }
                .buttonStyle(.plain)
                .disabled(status != .running || isCapturing)
                .opacity(status == .running ? 1 : 0.4)
                .accessibilityLabel("Take Receipt Photo")
                .accessibilityIdentifier("receipt-camera-shutter")

                HStack {
                    ReceiptPanelBackButton(action: onBack)
                    Spacer()
                }
            }
            .padding(20)
        }
        .task { await start() }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(32)
    }

    private func start() async {
        guard await AVCaptureDevice.requestAccess(for: .video) else {
            status = .denied
            return
        }
        status = await camera.start() ? .running : .unavailable
    }

    private func capture() {
        guard !isCapturing else { return }
        isCapturing = true
        Task {
            let image = await camera.capture()
            isCapturing = false
            if let image { onCapture(image) }
        }
    }
}

/// Owns the capture session; all session work happens on a private serial queue.
nonisolated final class ReceiptCameraSession: NSObject, @unchecked Sendable, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "syl.receipt.camera")
    private var isConfigured = false
    private var pendingCapture: CheckedContinuation<UIImage?, Never>?

    /// Safe to read from any thread.
    var isRunning: Bool { session.isRunning }

    /// Returns false when no back camera exists (e.g. the Simulator).
    /// Idempotent: returns immediately when already running.
    func start() async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                guard configureIfNeeded() else {
                    continuation.resume(returning: false)
                    return
                }
                if !session.isRunning { session.startRunning() }
                continuation.resume(returning: true)
            }
        }
    }

    func stop() {
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    func capture() async -> UIImage? {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                guard pendingCapture == nil, session.isRunning else {
                    continuation.resume(returning: nil)
                    return
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
        // Syl's iPhone UI is portrait-only; captured photos should be upright.
        if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        session.commitConfiguration()
        isConfigured = true
        return true
    }
}

private struct ReceiptCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
