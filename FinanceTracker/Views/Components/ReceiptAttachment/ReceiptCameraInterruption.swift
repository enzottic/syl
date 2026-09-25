import AVFoundation

/// Why a running receipt camera can't take a photo right now.
enum ReceiptCameraInterruption: Equatable {
    /// Split View, Slide Over or Stage Manager on an iPad that can't share the camera.
    case multitasking
    case inUseByAnotherApp
    case systemPressure
    case other
    /// A runtime error the session couldn't recover from.
    case failed

    nonisolated init(reason: AVCaptureSession.InterruptionReason?) {
        switch reason {
        case .videoDeviceNotAvailableWithMultipleForegroundApps: self = .multitasking
        case .videoDeviceInUseByAnotherClient: self = .inUseByAnotherApp
        case .videoDeviceNotAvailableDueToSystemPressure: self = .systemPressure
        default: self = .other
        }
    }

    var message: LocalizedStringResource {
        switch self {
        case .multitasking: "Camera unavailable while multitasking. Make Syl full screen to take a photo."
        case .inUseByAnotherApp: "Another app is using the camera."
        case .systemPressure: "The camera is paused while your device cools down."
        case .other: "The camera is unavailable right now."
        case .failed: "The camera stopped unexpectedly. Go back and try again."
        }
    }
}

/// Main-actor mirror of the capture session's interruptions, for SwiftUI.
@Observable
final class ReceiptCameraInterruptionState {
    var current: ReceiptCameraInterruption?

    nonisolated init() {}
}
