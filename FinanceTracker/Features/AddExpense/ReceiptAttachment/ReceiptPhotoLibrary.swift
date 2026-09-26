import Photos

/// The receipt grid's view of the photo library. It follows library changes,
/// including edits to a limited-access selection, and re-reads authorization
/// after the user changes it in Settings.
@Observable
@MainActor
final class ReceiptPhotoLibrary {
    private(set) var status: PHAuthorizationStatus = .notDetermined
    private var assets: PHFetchResult<PHAsset>?
    let imageManager = PHCachingImageManager()

    var count: Int { assets?.count ?? 0 }
    var hasAccess: Bool { status == .authorized || status == .limited }

    func asset(at index: Int) -> PHAsset? {
        guard let assets, index < assets.count else { return nil }
        return assets.object(at: index)
    }

    /// Prompts the first time. After that it returns the current status right away.
    func load() async {
        status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        if hasAccess, assets == nil { assets = Self.fetchImages() }
    }

    /// Picks up permission changes made in Settings while Syl was in the background.
    func refresh() {
        // Before load() finishes, the permission prompt itself toggles the scene phase.
        guard status != .notDetermined else { return }
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard current != status else { return }
        status = current
        assets = hasAccess ? Self.fetchImages() : nil
    }

    /// Applies library changes, such as a new limited selection or a new photo,
    /// until the calling task is cancelled.
    func observeChanges() async {
        guard hasAccess else { return }
        let (changes, continuation) = AsyncStream.makeStream(of: PHChange.self)
        let observer = ReceiptPhotoLibraryObserver(continuation: continuation)
        let library = PHPhotoLibrary.shared()
        library.register(observer)
        defer { library.unregisterChangeObserver(observer) }
        for await change in changes {
            guard let assets, let details = change.changeDetails(for: assets) else { continue }
            self.assets = details.fetchResultAfterChanges
        }
    }

    private static func fetchImages() -> PHFetchResult<PHAsset> {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        return PHAsset.fetchAssets(with: .image, options: options)
    }
}
