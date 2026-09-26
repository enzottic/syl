import SwiftUI
import AVFoundation
import AVKit

/// Live camera preview filling the attachment panel, on a custom AVCaptureSession.
struct ReceiptCameraView: View {
    let camera: ReceiptCameraSession
    let onBack: () -> Void
    let onCapture: (UIImage) -> Void

    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var status: Status
    @State private var isCapturing = false
    @State private var rotation = ReceiptCameraRotation()

    enum Status { case loading, running, denied, unavailable }

    init(camera: ReceiptCameraSession, onBack: @escaping () -> Void, onCapture: @escaping (UIImage) -> Void) {
        self.camera = camera
        self.onBack = onBack
        self.onCapture = onCapture
        // A prewarmed session shows its preview on the very first frame.
        _status = State(initialValue: camera.isRunning ? .running : .loading)
    }

    private var interruption: ReceiptCameraInterruption? {
        status == .running ? camera.interruption.current : nil
    }

    private var canCapture: Bool { status == .running && interruption == nil }

    var body: some View {
        ZStack {
            Color.black
            Group {
                switch status {
                case .running:
                    ReceiptCameraPreview(session: camera.session, rotation: rotation)
                case .loading:
                    EmptyView()
                case .denied:
                    VStack {
                        message("Camera access is off. Allow access for Syl in Settings.")
                        Button("Open Settings") {
                            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                            openURL(url)
                        }
                        .accessibilityIdentifier("receipt-camera-open-settings")
                    }
                case .unavailable:
                    message("This device doesn't have a camera.")
                }
                if let interruption {
                    // Covers the frozen or black preview while the session is paused.
                    Color.black
                        .overlay { message(interruption.message) }
                        .transition(.opacity)
                }
            }
            // The panel is always black, so its text uses dark-mode colors.
            .environment(\.colorScheme, .dark)
        }
        .animation(.smooth(duration: 0.2), value: interruption)
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
                .disabled(!canCapture || isCapturing)
                .opacity(canCapture ? 1 : 0.4)
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
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, status == .denied {
                Task { await start() }
            }
        }
        // Volume buttons, Camera Control and AirPods stem clicks act as the
        // shutter. Enabled only while a photo can be taken: while enabled the
        // system hands the buttons over entirely (volume stops changing).
        .onCameraCaptureEvent(isEnabled: canCapture && !isCapturing) { event in
            // Fire on release, like the Camera app.
            if event.phase == .ended { capture() }
        }
        .onChange(of: interruption) { _, interruption in
            if let interruption {
                AccessibilityNotification.Announcement(String(localized: interruption.message)).post()
            }
        }
    }

    private func message(_ text: LocalizedStringResource) -> some View {
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
        guard !isCapturing, canCapture else { return }
        isCapturing = true
        // Read on the main actor, where the coordinator tracks the interface.
        let angle = rotation.captureAngle
        Task {
            let image = await camera.capture(rotationAngle: angle)
            isCapturing = false
            if let image { onCapture(image) }
        }
    }
}

private struct ReceiptCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let rotation: ReceiptCameraRotation

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.rotation = rotation
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        var rotation: ReceiptCameraRotation?

        override var frame: CGRect {
            get { super.frame }
            set { withoutImplicitAnimations { super.frame = newValue } }
        }

        override var bounds: CGRect {
            get { super.bounds }
            set { withoutImplicitAnimations { super.bounds = newValue } }
        }

        private func withoutImplicitAnimations(_ change: () -> Void) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            change()
            layer.layoutIfNeeded()
            CATransaction.commit()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            // The coordinator reads the interface orientation from the layer's window.
            if window != nil { rotation?.attach(to: previewLayer) }
        }
    }
}
