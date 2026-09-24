import SwiftUI
import UIKit
import QuartzCore

/// Live SwiftUI geometry reports each section's ideal size at the sheet width.
/// Only the scroll viewport shrinks; native controls never do.
@MainActor
final class ExpenseEntrySheetViewController: UIViewController {
    enum HostedSection { case header, content, footer }

    private var idealSizes: [HostedSection: CGSize] = [:]
    private var animatesHeightChanges = true

    private struct HostedUpdate {
        var header: AnyView
        var content: AnyView
        var footer: AnyView
        var step: Int
        var animatesHeightChanges: Bool
        var transaction: Transaction
    }

    private var pendingUpdate: HostedUpdate?
    private var updateScheduled = false

    private let headerHost = UIHostingController(rootView: AnyView(EmptyView()))
    private let contentState = ExpenseEntryContentState()
    private lazy var contentHost = UIHostingController(rootView: AnyView(ExpenseEntryHostedContent(state: contentState)))
    private let footerHost = UIHostingController(rootView: AnyView(EmptyView()))
    private let scrollView = UIScrollView()
    private var headerHeight: NSLayoutConstraint!
    private var contentHeight: NSLayoutConstraint!
    private var footerHeight: NSLayoutConstraint!
    private var footerContentLimit: NSLayoutConstraint!
    private var measurementScheduled = false
    private var isMeasuring = false
    private var measuredWidth: CGFloat = 0
    private var measuredTopInset: CGFloat = 0
    private var targetHeight: CGFloat = 0
    private var step: Int?
    private var needsScrollReset = false
    private var hasAppeared = false
    private var previousViewportSize: CGSize = .zero
    private weak var previousResponder: UIView?
    private var previousResponderFrame: CGRect?
    private weak var managedSheet: UISheetPresentationController?
    private let detentIdentifier = UISheetPresentationController.Detent.Identifier("expense-entry-content")
    private var pageGeneration = 0
    private var layoutGeneration = 0
    private var stagedPage: Int?
    private var revealingPage: Int?
    private var outgoingSnapshot: UIView?
    private var resizeGeneration = 0
    private var activeResizes = Set<Int>()
    private var revealScheduled = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.keyboardDismissMode = .interactive
        scrollView.alwaysBounceVertical = false
        scrollView.backgroundColor = .clear
        view.addSubview(scrollView)

        install(headerHost, in: view)
        install(contentHost, in: scrollView)
        install(footerHost, in: view)

        headerHeight = headerHost.view.heightAnchor.constraint(equalToConstant: 0)
        contentHeight = contentHost.view.heightAnchor.constraint(equalToConstant: 0)
        footerHeight = footerHost.view.heightAnchor.constraint(equalToConstant: 0)

        let safeArea = view.safeAreaLayoutGuide
        let keyboard = view.keyboardLayoutGuide
        // A floating iPad keyboard must not drag the full-width footer around.
        // When docked/absent the guide already accounts for the bottom safe area.
        keyboard.followsUndockedKeyboard = false
        keyboard.usesBottomSafeArea = true

        let viewportBottom = scrollView.bottomAnchor.constraint(equalTo: footerHost.view.topAnchor)
        // Allows a zero-height viewport in a temporarily tiny presentation,
        // without breaking the footer's keyboard constraint or compressing it.
        viewportBottom.priority = UILayoutPriority(999)
        // Follow the keyboard, but never travel below the page's natural bottom
        // while the presentation is still settling after keyboard dismissal.
        let footerKeyboardAnchor = footerHost.view.bottomAnchor.constraint(equalTo: keyboard.topAnchor)
        footerKeyboardAnchor.priority = .defaultHigh
        footerContentLimit = footerHost.view.topAnchor.constraint(
            lessThanOrEqualTo: scrollView.topAnchor, constant: 0)
        NSLayoutConstraint.activate([
            headerHost.view.topAnchor.constraint(equalTo: safeArea.topAnchor),
            headerHost.view.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor),
            headerHost.view.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor),
            headerHeight,
            footerHost.view.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor),
            footerHost.view.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor),
            footerHost.view.bottomAnchor.constraint(lessThanOrEqualTo: keyboard.topAnchor),
            footerKeyboardAnchor,
            footerContentLimit,
            footerHeight,
            scrollView.topAnchor.constraint(equalTo: headerHost.view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 0),
            viewportBottom,
            contentHost.view.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentHost.view.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentHost.view.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentHost.view.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentHost.view.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            contentHeight
        ])
    }

    private func install(_ host: UIHostingController<AnyView>, in container: UIView) {
        // UIKit has already applied all safe areas. In particular, never let a
        // hosting controller independently add keyboard avoidance to its root.
        host.safeAreaRegions = []
        addChild(host)
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(host.view)
        host.didMove(toParent: self)
    }

    func update(header: AnyView, content: AnyView, footer: AnyView, step: Int,
                animatesHeightChanges: Bool, transaction: Transaction) {
        pendingUpdate = HostedUpdate(header: header, content: content, footer: footer, step: step,
                                     animatesHeightChanges: animatesHeightChanges, transaction: transaction)
        // Lock synchronously, before the deferred fade can leave an old Next
        // action targeting the wizard's already-advanced step. Hide it from AX too.
        updateFooterInteraction()
        // Invalidate any reveal already waiting for a layout/commit barrier.
        layoutGeneration += 1
        schedulePendingUpdate()
    }

    private func schedulePendingUpdate() {
        guard pendingUpdate != nil, outgoingSnapshot == nil, !updateScheduled else { return }
        updateScheduled = true
        // A snapshot or rootView assignment can synchronously lay out a hosted
        // SwiftUI tree and run its state/focus callbacks. Exit the representable's
        // graph update before doing either; only apply the latest complete input.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.updateScheduled = false
            guard self.outgoingSnapshot == nil, let candidate = self.pendingUpdate else { return }
            self.animatesHeightChanges = candidate.animatesHeightChanges
            if self.step != candidate.step, self.step != nil, self.stagedPage == nil,
               self.hasAppeared, self.view.window != nil {
                var transaction = candidate.transaction
                transaction.animation = nil
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    self.stageStepChange()
                }
            }
            // Keep the old roots and detent until the outgoing fade completes.
            // Re-read the payload: snapshot layout may have enqueued newer inputs.
            guard self.outgoingSnapshot == nil, let update = self.pendingUpdate else { return }
            // Clear before applying so reentrant updates schedule a new turn.
            self.pendingUpdate = nil
            self.apply(update)
        }
    }

    func cancelPendingUpdate() {
        pendingUpdate = nil
    }

    private func updateFooterInteraction() {
        let enabled = stagedPage == nil && revealingPage == nil
            && (pendingUpdate == nil || pendingUpdate?.step == step)
        footerHost.view.isUserInteractionEnabled = enabled
        footerHost.view.accessibilityElementsHidden = !enabled
    }

    private func apply(_ update: HostedUpdate) {
        animatesHeightChanges = update.animatesHeightChanges
        // Page transitions run inside the content host concurrently with the
        // native detent animation; header/footer layout stays nonanimated.
        let animatesContent = step != nil && animatesPageChanges
        var quietTransaction = update.transaction
        quietTransaction.animation = nil
        quietTransaction.disablesAnimations = true
        var contentTransaction = animatesContent ? update.transaction : quietTransaction
        if animatesContent {
            contentTransaction.disablesAnimations = false
            if step != update.step {
                contentTransaction.animation = .smooth(duration: 0.3)
            }
        }
        if step != update.step {
            step = update.step
            idealSizes[.content] = nil
            needsScrollReset = true
        }
        withTransaction(quietTransaction) {
            UIView.performWithoutAnimation {
                headerHost.rootView = update.header
                footerHost.rootView = update.footer
            }
        }
        withTransaction(contentTransaction) {
            contentState.animates = animatesContent
            contentState.content = update.content
            contentState.step = update.step
            contentState.revision += 1
        }
        updateFooterInteraction()
        requestMeasurement()
    }

    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        // The presentation width is now authoritative, including form sheets
        // and multitasking on iPad. Size before the initial presentation finishes.
        view.layoutIfNeeded()
        measureAndResize()
    }

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        if parent != nil { requestMeasurement() }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        hasAppeared = true
        requestMeasurement()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        hasAppeared = false
        cancelStagedPage()
        // A covering presentation may interrupt the fade. Apply retained inputs
        // off this lifecycle callback even if its animation completion is stale.
        schedulePendingUpdate()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Height changes (including every keyboard frame) do NOT invalidate the
        // detent. Rotation / iPad window resizing do invalidate the width.
        if !isMeasuring && (!ownsInstalledDetent
            || abs(scrollView.bounds.width - measuredWidth) > pixelTolerance
            || abs(view.safeAreaInsets.top - measuredTopInset) > pixelTolerance) {
            requestMeasurement()
        }
        keepFocusedControlVisible()
    }

    func receiveIdealSize(_ size: CGSize, for section: HostedSection, step: Int) {
        // Removed pages can still lay out during blurReplace. Only the incoming
        // page determines the native detent; never wait for the blur to finish.
        guard section != .content || step == self.step,
              size.width.isFinite, size.height.isFinite, size.height > 0,
              idealSizes[section] != size else { return }
        idealSizes[section] = size
        requestMeasurement()
    }

    func requestMeasurement() {
        layoutGeneration += 1
        guard !measurementScheduled else { return }
        measurementScheduled = true
        // Coalesce the three hosts' layout callbacks and representable updates.
        // Do not mutate the presentation during a SwiftUI layout callback.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.measurementScheduled = false
            self.measureAndResize()
        }
    }

    private var pixelTolerance: CGFloat { 1 / max(traitCollection.displayScale, 1) }

    private func measureAndResize() {
        guard pendingUpdate == nil, outgoingSnapshot == nil,
              !isMeasuring, isViewLoaded, view.window != nil else { return }
        let width = scrollView.bounds.width
        guard width > 0 else { return }
        isMeasuring = true
        defer { isMeasuring = false }

        // Let SwiftUI commit its animated update normally. sizeThatFits on the
        // live host can consume that pending update in a measurement transaction.
        let sections: [HostedSection] = [.header, .content, .footer]
        let sizes = sections.compactMap { idealSizes[$0] }
        guard sizes.count == sections.count,
              sizes.allSatisfy({ abs($0.width - width) <= pixelTolerance }) else { return }
        let heights = sizes.map(\.height)
        measuredWidth = width
        measuredTopInset = view.safeAreaInsets.top
        let scale = max(traitCollection.displayScale, 1)
        let rounded = heights.map { ceil($0 * scale) / scale }
        headerHeight.constant = rounded[0]
        contentHeight.constant = rounded[1]
        footerContentLimit.constant = rounded[1]
        footerHeight.constant = rounded[2]

        if needsScrollReset {
            scrollView.setContentOffset(.zero, animated: false)
            previousResponder = nil
            needsScrollReset = false
        }

        // Custom detents exclude the bottom safe area; UIKit adds it. Never add
        // keyboard height here: the sheet and keyboard guide handle it natively.
        let height = rounded.reduce(0, +) + measuredTopInset
        applyDetent(height: height)
        // UIKit lays out the new constraints in its normal animation pass; do
        // not synchronously flush the hosted SwiftUI transition here.
        view.setNeedsLayout()
        keepFocusedControlVisible()
        scheduleStagedReveal()
    }

    private var ownsInstalledDetent: Bool {
        guard let sheet = managedSheet else { return false }
        return sheet.detents.count == 1
            && sheet.detents.first?.identifier == detentIdentifier
            && sheet.prefersGrabberVisible
    }

    private func enclosingSheet() -> UISheetPresentationController? {
        // SwiftUI can use an adapting presentation controller whose public
        // presentationController is NOT the sheet. Ask the sheet accessor first.
        // Also follow the presentation links: the owner can be outside the
        // representable's containment chain during presentation/adaptation.
        var candidates: [UIViewController] = []
        if let parent { candidates.append(parent) }
        if let presentingViewController { candidates.append(presentingViewController) }
        // Some SwiftUI presentation wrappers participate in the view/responder
        // hierarchy before the containment links have finished updating.
        var responder: UIResponder? = view.superview
        while let current = responder {
            if let controller = current as? UIViewController { candidates.append(controller) }
            responder = current.next
        }
        var visited = Set<ObjectIdentifier>()
        var index = 0
        while index < candidates.count {
            let controller = candidates[index]
            index += 1
            guard visited.insert(ObjectIdentifier(controller)).inserted else { continue }

            let sheets = [
                controller.sheetPresentationController,
                controller.presentationController as? UISheetPresentationController,
                controller.popoverPresentationController?.adaptiveSheetPresentationController
            ]
            for case let sheet? in sheets where containsContainer(sheet.presentedViewController) {
                return sheet
            }

            if let parent = controller.parent { candidates.append(parent) }
            if let presenter = controller.presentingViewController { candidates.append(presenter) }
            if let presented = controller.presentedViewController { candidates.append(presented) }
        }
        return nil
    }

    private func containsContainer(_ controller: UIViewController) -> Bool {
        // Don't accidentally resize the presenting sheet or a photo picker /
        // alert above us. Only the nearest presentation containing this view
        // can own this detent. View ancestry also covers SwiftUI wrapper hosts.
        if let presentedView = controller.viewIfLoaded,
           view.isDescendant(of: presentedView) { return true }
        var ancestor: UIViewController? = self
        while let current = ancestor {
            if current === controller { return true }
            ancestor = current.parent
        }
        return false
    }

    private func applyDetent(height: CGFloat) {
        guard let sheet = enclosingSheet() else { return }
        let requiresInstallation = managedSheet !== sheet || !ownsInstalledDetent

        if requiresInstallation {
            managedSheet = sheet
            let install = { [self] in
                self.targetHeight = height
                sheet.prefersGrabberVisible = true
                sheet.prefersScrollingExpandsWhenScrolledToEdge = false
                sheet.detents = [.custom(identifier: self.detentIdentifier) { [weak self] context in
                    min(self?.targetHeight ?? context.maximumDetentValue, context.maximumDetentValue)
                }]
                sheet.selectedDetentIdentifier = self.detentIdentifier
            }
            // Discovery may complete after the initial presentation. Installing
            // then must animate too, rather than abruptly replacing the large sheet.
            performSheetChanges(on: sheet, changes: install)
            return
        }

        guard abs(height - targetHeight) > pixelTolerance else { return }
        let changes = {
            self.targetHeight = height
            sheet.invalidateDetents()
        }
        performSheetChanges(on: sheet, changes: changes)
    }

    private func performSheetChanges(on sheet: UISheetPresentationController, changes: () -> Void) {
        if hasAppeared && animatesHeightChanges && !UIAccessibility.isReduceMotionEnabled {
            // One native animation per new ideal-height target. There is no
            // animated SwiftUI number, detent replacement, or display-link loop.
            resizeGeneration += 1
            let generation = resizeGeneration
            activeResizes.insert(generation)
            CATransaction.begin()
            CATransaction.setCompletionBlock { [weak self] in
                // CA completion has no actor contract. Hop to main and allow
                // pending SwiftUI geometry callbacks to settle before revealing.
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.activeResizes.remove(generation)
                    self.scheduleStagedReveal()
                }
            }
            sheet.animateChanges(changes)
            CATransaction.commit()
        } else {
            UIView.performWithoutAnimation(changes)
        }
    }

    private var animatesPageChanges: Bool {
        animatesHeightChanges && !UIAccessibility.isReduceMotionEnabled
    }

    private func stageStepChange() {
        pageGeneration += 1
        stagedPage = pageGeneration
        revealingPage = nil
        updateFooterInteraction()
        outgoingSnapshot?.removeFromSuperview()
        outgoingSnapshot = nil
        // Install the next page immediately and keep it visible throughout the
        // native sheet resize. Only interaction waits for the layout to settle.
        contentHost.view.alpha = 1
        contentHost.view.isUserInteractionEnabled = false
        contentHost.view.accessibilityElementsHidden = true
    }

    private func scheduleStagedReveal() {
        guard let page = stagedPage, hasAppeared, activeResizes.isEmpty,
              ownsInstalledDetent, pendingUpdate == nil, outgoingSnapshot == nil,
              !measurementScheduled, !revealScheduled else { return }
        revealScheduled = true
        let layout = layoutGeneration
        // Re-enable interaction after the native layout commit, without forcing
        // a nonanimated layout through the still-transitioning SwiftUI host.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard self.canReveal(page: page, layout: layout) else {
                self.revealScheduled = false
                self.scheduleStagedReveal()
                return
            }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            CATransaction.setCompletionBlock { [weak self] in
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.revealScheduled = false
                    guard self.canReveal(page: page, layout: layout) else {
                        self.scheduleStagedReveal()
                        return
                    }
                    self.revealStagedPage(page)
                }
            }
            CATransaction.commit()
        }
    }

    private func canReveal(page: Int, layout: Int) -> Bool {
        stagedPage == page && pageGeneration == page && layoutGeneration == layout
            && hasAppeared && view.window != nil && ownsInstalledDetent
            && activeResizes.isEmpty && pendingUpdate == nil && outgoingSnapshot == nil
            && !measurementScheduled
    }

    private func revealStagedPage(_ page: Int) {
        guard pageGeneration == page else { return }
        stagedPage = nil
        revealingPage = nil
        contentHost.view.isUserInteractionEnabled = true
        contentHost.view.accessibilityElementsHidden = false
        updateFooterInteraction()
    }

    private func cancelStagedPage() {
        pageGeneration += 1
        stagedPage = nil
        revealingPage = nil
        outgoingSnapshot?.removeFromSuperview()
        outgoingSnapshot = nil
        contentHost.view.layer.removeAllAnimations()
        contentHost.view.alpha = 1
        contentHost.view.isUserInteractionEnabled = true
        contentHost.view.accessibilityElementsHidden = false
        updateFooterInteraction()
    }

    private func keepFocusedControlVisible() {
        let size = scrollView.bounds.size
        let responder = firstResponder(in: contentHost.view)
        // Content coordinates exclude scroll offset: inserting suggestions moves
        // the field, but intentionally scrolling the viewport does not.
        let frame = responder.map { $0.convert($0.bounds, to: contentHost.view) }
        let changed = size != previousViewportSize || responder !== previousResponder
            || frame != previousResponderFrame
        // Store before scrolling, which can synchronously trigger another layout.
        previousViewportSize = size
        previousResponder = responder
        previousResponderFrame = frame
        guard size.height > 0, let responder,
              changed else { return }
        let rect = responder.convert(responder.bounds, to: scrollView).insetBy(dx: 0, dy: -12)
        // Runs in the keyboard guide's layout transaction, not a second keyboard
        // notification animation. User scrolling is otherwise left untouched.
        scrollView.scrollRectToVisible(rect, animated: false)
    }

    private func firstResponder(in view: UIView) -> UIView? {
        if view.isFirstResponder { return view }
        for child in view.subviews {
            if let responder = firstResponder(in: child) { return responder }
        }
        return nil
    }
}
