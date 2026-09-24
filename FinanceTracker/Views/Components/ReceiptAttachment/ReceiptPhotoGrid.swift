import SwiftUI
import Photos

/// PhotoKit grid filling the attachment panel. The system inline PhotosPicker
/// can't be used here: it forces partial-height sheets to full screen.
struct ReceiptPhotoGrid: View {
    let onBack: () -> Void
    let onSelect: (PHAsset) -> Void
    let onAllPhotos: () -> Void

    @State private var library = ReceiptPhotoLibrary()
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    var body: some View {
        ZStack {
            Color.black
            switch library.status {
            case .authorized, .limited:
                grid
            case .denied, .restricted:
                Text("Photo access is off. Allow access for Syl in Settings, or use All Photos.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(32)
            default:
                EmptyView()
            }
        }
        .overlay(alignment: .bottom) {
            HStack {
                ReceiptPanelBackButton(action: onBack)
                Spacer()
                Button(action: onAllPhotos) {
                    Text("All Photos")
                        .font(.headline)
                        .padding(.horizontal, 12)
                        .frame(height: 40)
                }
                .buttonStyle(.glass)
                .accessibilityIdentifier("receipt-panel-all-photos")
            }
            .padding(20)
        }
        .task { await library.load() }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(0..<library.count, id: \.self) { index in
                    if let asset = library.asset(at: index) {
                        Button { onSelect(asset) } label: {
                            ReceiptPhotoThumbnail(asset: asset, manager: library.imageManager)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(accessibilityLabel(for: asset))
                    }
                }
            }
        }
        .contentMargins(.bottom, 92, for: .scrollContent)
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("receipt-photo-grid")
    }

    private func accessibilityLabel(for asset: PHAsset) -> String {
        guard let date = asset.creationDate else { return "Photo" }
        return "Photo, \(date.formatted(date: .abbreviated, time: .shortened))"
    }
}

@Observable
@MainActor
final class ReceiptPhotoLibrary {
    private(set) var status: PHAuthorizationStatus = .notDetermined
    private var assets: PHFetchResult<PHAsset>?
    let imageManager = PHCachingImageManager()

    var count: Int { assets?.count ?? 0 }

    func asset(at index: Int) -> PHAsset? {
        guard let assets, index < assets.count else { return nil }
        return assets.object(at: index)
    }

    func load() async {
        status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited, assets == nil else { return }
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        assets = PHAsset.fetchAssets(with: .image, options: options)
    }
}

enum ReceiptPhotoLoader {
    /// Full-quality image for receipt parsing, downloading from iCloud if needed.
    static func image(for asset: PHAsset) async -> UIImage? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.version = .current
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                continuation.resume(returning: data.flatMap(UIImage.init(data:)))
            }
        }
    }
}

private struct ReceiptPhotoThumbnail: View {
    let asset: PHAsset
    let manager: PHCachingImageManager

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    @State private var requestID: PHImageRequestID?

    var body: some View {
        Color.white.opacity(0.06)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipped()
            .contentShape(.rect)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                requestImage(side: width)
            }
            .onDisappear {
                if let requestID { manager.cancelImageRequest(requestID) }
                requestID = nil
            }
    }

    private func requestImage(side: CGFloat) {
        guard side > 0, image == nil, requestID == nil else { return }
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        let pixels = side * displayScale
        requestID = manager.requestImage(
            for: asset,
            targetSize: CGSize(width: pixels, height: pixels),
            contentMode: .aspectFill,
            options: options
        ) { result, _ in
            if let result { image = result }
        }
    }
}
