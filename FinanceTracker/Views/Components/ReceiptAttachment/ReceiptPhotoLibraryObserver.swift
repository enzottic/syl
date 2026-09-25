import Photos

/// PhotoKit calls change observers on a background queue. This forwards each
/// change into a stream that ``ReceiptPhotoLibrary`` reads on the main actor.
nonisolated final class ReceiptPhotoLibraryObserver: NSObject, PHPhotoLibraryChangeObserver, Sendable {
    private let continuation: AsyncStream<PHChange>.Continuation

    init(continuation: AsyncStream<PHChange>.Continuation) {
        self.continuation = continuation
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        continuation.yield(changeInstance)
    }
}
