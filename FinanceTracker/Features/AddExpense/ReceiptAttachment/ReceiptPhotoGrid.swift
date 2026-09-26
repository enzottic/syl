import SwiftUI
import Photos

/// PhotoKit grid filling the attachment panel. The system inline PhotosPicker
/// can't be used here: it forces partial-height sheets to full screen.
/// "All Photos" still opens the out-of-process picker, which works with any
/// permission (including none), so every state below leaves a way forward.
struct ReceiptPhotoGrid: View {
    let onBack: () -> Void
    let onSelect: (PHAsset) -> Void
    let onAllPhotos: () -> Void

    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var library = ReceiptPhotoLibrary()
    @State private var isSelectingPhotos = false
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    var body: some View {
        ZStack {
            Color.black
            content
                // The panel is always black, so its text uses dark-mode colors.
                .environment(\.colorScheme, .dark)
        }
        .overlay(alignment: .bottom) {
            HStack {
                ReceiptPanelBackButton(action: onBack)
                Spacer()
                Button(action: onAllPhotos) {
                    Text("All Photos")
                        .font(.headline)
                        .padding(.horizontal, 12)
                        .frame(height: ReceiptPanelBackButton.labelHeight)
                }
                .receiptPanelGlassButtonStyle()
                .accessibilityIdentifier("receipt-panel-all-photos")
            }
            .padding(20)
        }
        .background { LimitedLibraryPicker(isPresented: $isSelectingPhotos) }
        .task { await library.load() }
        .task(id: library.hasAccess) { await library.observeChanges() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { library.refresh() }
        }
    }

    @ViewBuilder private var content: some View {
        switch library.status {
        case .authorized, .limited:
            if library.count > 0 {
                grid
            } else if library.status == .limited {
                ReceiptPhotoAccessMessage(
                    title: "No Photos Selected",
                    systemImage: "photo.badge.plus",
                    description: "Choose which photos Syl can see, or use All Photos to pick any receipt."
                ) {
                    Button("Select Photos", action: selectPhotos)
                        .accessibilityIdentifier("receipt-photos-select")
                }
            } else {
                ReceiptPhotoAccessMessage(
                    title: "No Photos",
                    systemImage: "photo.on.rectangle",
                    description: "Photos you take or save will appear here."
                )
            }
        case .denied:
            ReceiptPhotoAccessMessage(
                title: "Photo Access Off",
                systemImage: "hand.raised",
                description: "Allow Photos access for Syl in Settings, or use All Photos to pick a receipt without giving access."
            ) {
                Button("Open Settings", action: openSettings)
                    .accessibilityIdentifier("receipt-photos-open-settings")
            }
        case .restricted:
            ReceiptPhotoAccessMessage(
                title: "Photo Access Restricted",
                systemImage: "lock",
                description: "Photos access is restricted on this device. Use All Photos to pick a receipt."
            )
        default:
            EmptyView()
        }
    }

    private var grid: some View {
        ScrollView {
            if library.status == .limited {
                ReceiptLimitedAccessBanner(onSelectPhotos: selectPhotos, onOpenSettings: openSettings)
            }
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(0..<library.count, id: \.self) { index in
                    if let asset = library.asset(at: index) {
                        Button { onSelect(asset) } label: {
                            ReceiptPhotoThumbnail(asset: asset, manager: library.imageManager)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(accessibilityLabel(for: asset))
                        // Library changes shift indices; a new asset needs a fresh thumbnail.
                        .id(asset.localIdentifier)
                    }
                }
            }
        }
        .contentMargins(.bottom, 92, for: .scrollContent)
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("receipt-photo-grid")
    }

    private func selectPhotos() {
        isSelectingPhotos = true
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }

    private func accessibilityLabel(for asset: PHAsset) -> String {
        guard let date = asset.creationDate else { return "Photo" }
        return "Photo, \(date.formatted(date: .abbreviated, time: .shortened))"
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
