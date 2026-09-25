import SwiftUI
import PhotosUI

/// Presents the system picker where someone who shared only some photos with
/// Syl can change that selection. PhotoKit reports the new selection as a
/// library change, so nothing is returned here.
struct LimitedLibraryPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {
        guard isPresented, !context.coordinator.isPresenting else { return }
        let coordinator = context.coordinator
        coordinator.isPresenting = true
        Task {
            // Outside limited mode, PhotoKit does nothing and may never call back.
            if PHPhotoLibrary.authorizationStatus(for: .readWrite) == .limited {
                _ = await PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: controller)
            }
            coordinator.isPresenting = false
            isPresented = false
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var isPresenting = false
    }
}
