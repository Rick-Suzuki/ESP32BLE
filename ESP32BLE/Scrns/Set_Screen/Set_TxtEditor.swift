import SwiftUI
import UIKit

enum SettingsDocumentEditorAnimationGeometry {
    static let coordinateSpaceName = "SettingsDocumentEditorAnimationCoordinateSpace"
}

struct SettingsEditorPreviewFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let nextFrame = nextValue()
        guard nextFrame.width > 0, nextFrame.height > 0 else { return }
        value = nextFrame
    }
}

struct DedicatedDocumentEditorKeyboardLayout: Equatable {
    let frameInWindow: CGRect
    let dockedHeight: CGFloat
    let isDocked: Bool
}

enum SettingsFocusField: Hashable {
    case sendText
}

struct PlainDocumentEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var fontSize: CGFloat
    @Binding var isFocused: Bool
    let isReadOnly: Bool
    let onReadOnlyTap: (() -> Void)?
    let focusRequestID: UUID?
    let initialScrollResetID: UUID?
    let onEditingBegan: (() -> Void)?
    let wrapsText: Bool
    let textInsets: UIEdgeInsets

    init(
        text: Binding<String>,
        fontSize: Binding<CGFloat>,
        isFocused: Binding<Bool>,
        isReadOnly: Bool,
        onReadOnlyTap: (() -> Void)?,
        focusRequestID: UUID?,
        initialScrollResetID: UUID?,
        onEditingBegan: (() -> Void)?,
        wrapsText: Bool = false,
        textInsets: UIEdgeInsets = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
    ) {
        _text = text
        _fontSize = fontSize
        _isFocused = isFocused
        self.isReadOnly = isReadOnly
        self.onReadOnlyTap = onReadOnlyTap
        self.focusRequestID = focusRequestID
        self.initialScrollResetID = initialScrollResetID
        self.onEditingBegan = onEditingBegan
        self.wrapsText = wrapsText
        self.textInsets = textInsets
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: $isFocused)
    }

    func makeUIView(context: Context) -> NoWrapDocumentTextView {
        let textView = NoWrapDocumentTextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.textColor = .white
        textView.tintColor = .white
        textView.keyboardAppearance = .dark
        textView.autocapitalizationType = .none
        textView.autocorrectionType = .no
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.smartInsertDeleteType = .no
        textView.isEditable = !isReadOnly
        textView.isSelectable = !isReadOnly
        textView.isScrollEnabled = true
        textView.wrapsText = wrapsText
        textView.alwaysBounceHorizontal = !wrapsText
        textView.alwaysBounceVertical = true
        textView.showsHorizontalScrollIndicator = !wrapsText
        textView.showsVerticalScrollIndicator = true
        textView.textContainerInset = textInsets
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.lineBreakMode = wrapsText ? .byWordWrapping : .byClipping
        textView.textContainer.widthTracksTextView = wrapsText
        textView.textContainer.size = CGSize(
            width: wrapsText ? 0 : CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.font = .systemFont(ofSize: fontSize)
        textView.text = text
        let pinchGestureRecognizer = UIPinchGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePinch(_:))
        )
        pinchGestureRecognizer.delegate = context.coordinator
        pinchGestureRecognizer.cancelsTouchesInView = false
        textView.addGestureRecognizer(pinchGestureRecognizer)
        let tapGestureRecognizer = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleReadOnlyTap(_:))
        )
        tapGestureRecognizer.delegate = context.coordinator
        tapGestureRecognizer.cancelsTouchesInView = false
        textView.addGestureRecognizer(tapGestureRecognizer)
        return textView
    }

    func updateUIView(_ textView: NoWrapDocumentTextView, context: Context) {
        context.coordinator.parent = self
        if isReadOnly, textView.isFirstResponder {
            textView.resignFirstResponder()
        }
        textView.isEditable = !isReadOnly
        textView.isSelectable = !isReadOnly
        let didChangeWrapping = textView.wrapsText != wrapsText
        textView.wrapsText = wrapsText
        textView.alwaysBounceHorizontal = !wrapsText
        textView.showsHorizontalScrollIndicator = !wrapsText
        textView.textContainerInset = textInsets
        textView.textContainer.lineBreakMode = wrapsText ? .byWordWrapping : .byClipping
        textView.textContainer.widthTracksTextView = wrapsText
        context.coordinator.requestFocusIfNeeded(
            focusRequestID,
            on: textView
        )
        let previousOffset = textView.contentOffset
        var shouldRestoreOffset = didChangeWrapping
        var didChangeContent = false

        if textView.text != text {
            textView.text = text
            shouldRestoreOffset = true
            didChangeContent = true
            let currentSize = textView.font?.pointSize ?? fontSize
            if abs(currentSize - fontSize) > 0.25 {
                textView.font = .systemFont(ofSize: fontSize)
                shouldRestoreOffset = true
            }

            textView.layoutIfNeeded()
            textView.refreshNoWrapContentSize()
            let targetOffset: CGPoint
            if didChangeContent, !textView.hasUserAdjustedHorizontalOffset {
                targetOffset = .zero
            } else {
                targetOffset = textView.clampedContentOffset(for: previousOffset)
            }
            textView.setContentOffset(targetOffset, animated: false)
        } else {
            let currentSize = textView.font?.pointSize ?? fontSize
            if abs(currentSize - fontSize) > 0.25 {
                textView.font = .systemFont(ofSize: fontSize)
                shouldRestoreOffset = true
            }

            if shouldRestoreOffset {
                textView.layoutIfNeeded()
                textView.refreshNoWrapContentSize()
                textView.setContentOffset(
                    textView.clampedContentOffset(for: previousOffset),
                    animated: false
                )
            }
        }

        context.coordinator.resetInitialScrollPositionIfNeeded(
            initialScrollResetID,
            on: textView
        )
    }

    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        var parent: PlainDocumentEditor
        private var pinchStartingFontSize: CGFloat?
        private var handledFocusRequestID: UUID?
        private var handledInitialScrollResetID: UUID?

        init(text: Binding<String>, isFocused: Binding<Bool>) {
            self.parent = PlainDocumentEditor(
                text: text,
                fontSize: .constant(18),
                isFocused: isFocused,
                isReadOnly: false,
                onReadOnlyTap: nil,
                focusRequestID: nil,
                initialScrollResetID: nil,
                onEditingBegan: nil
            )
        }

        func textViewDidChange(_ textView: UITextView) {
            let updatedText = textView.text ?? ""
            guard parent.text != updatedText else { return }
            parent.text = updatedText
            (textView as? NoWrapDocumentTextView)?.ensureCaretVisible()
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            (textView as? NoWrapDocumentTextView)?.ensureCaretVisible()
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText text: String
        ) -> Bool {
            ButtonClickFeedback.playIfEnabled()
            return true
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            if !parent.isFocused {
                parent.isFocused = true
            }
            parent.onEditingBegan?()
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            guard parent.isFocused else { return }
            parent.isFocused = false
        }

        @objc func handlePinch(_ gestureRecognizer: UIPinchGestureRecognizer) {
            guard parent.isReadOnly else { return }

            switch gestureRecognizer.state {
            case .began:
                pinchStartingFontSize = parent.fontSize
            case .changed:
                guard let pinchStartingFontSize else { return }
                let updatedFontSize = min(
                    max((pinchStartingFontSize * gestureRecognizer.scale).rounded(), 10),
                    72
                )
                guard parent.fontSize != updatedFontSize else { return }
                parent.fontSize = updatedFontSize
            case .ended, .cancelled, .failed:
                pinchStartingFontSize = nil
            default:
                break
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            guard parent.isReadOnly else { return false }
            return gestureRecognizer is UIPinchGestureRecognizer || otherGestureRecognizer is UIPinchGestureRecognizer
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            if gestureRecognizer is UIPinchGestureRecognizer {
                return parent.isReadOnly
            }

            if gestureRecognizer is UITapGestureRecognizer {
                return parent.isReadOnly && parent.onReadOnlyTap != nil
            }

            return true
        }

        @objc func handleReadOnlyTap(_ gestureRecognizer: UITapGestureRecognizer) {
            guard gestureRecognizer.state == .ended,
                  parent.isReadOnly else {
                return
            }

            parent.onReadOnlyTap?()
        }

        func requestFocusIfNeeded(
            _ focusRequestID: UUID?,
            on textView: NoWrapDocumentTextView
        ) {
            guard let focusRequestID,
                  handledFocusRequestID != focusRequestID,
                  !parent.isReadOnly else {
                return
            }

            handledFocusRequestID = focusRequestID
            textView.focusWhenAvailable()
        }

        func resetInitialScrollPositionIfNeeded(
            _ initialScrollResetID: UUID?,
            on textView: NoWrapDocumentTextView
        ) {
            guard let initialScrollResetID,
                  handledInitialScrollResetID != initialScrollResetID else {
                return
            }

            handledInitialScrollResetID = initialScrollResetID
            textView.layoutIfNeeded()
            textView.refreshNoWrapContentSize()
            textView.selectedRange = NSRange(location: 0, length: 0)
            textView.setContentOffset(.zero, animated: false)
        }
    }
}

struct DedicatedDocumentEditorView: View {
    @Binding var text: String
    @Binding var fontSize: CGFloat
    @Binding var isFocused: Bool
    let focusRequestID: UUID?
    let hidesTextDuringOpening: Bool
    let showsCloseButton: Bool
    let initialScrollResetID: UUID?
    let onEditingBegan: () -> Void
    let onKeyboardFrameReceived: (DedicatedDocumentEditorKeyboardLayout) -> Void
    let onKeyboardLayoutReady: (DedicatedDocumentEditorKeyboardLayout) -> Void
    let onSaveAndClose: () -> Void
    @State private var dockedKeyboardHeight: CGFloat = 0
    @State private var latestKeyboardLayout: DedicatedDocumentEditorKeyboardLayout?
    @State private var editorViewportSize: CGSize = .zero
    @State private var editorPresentationSize: CGSize = .zero
    @State private var lastReportedKeyboardLayout: DedicatedDocumentEditorKeyboardLayout?

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            GeometryReader { proxy in
                ZStack(alignment: .bottomTrailing) {
                    PlainDocumentEditor(
                        text: $text,
                        fontSize: $fontSize,
                        isFocused: $isFocused,
                        isReadOnly: false,
                        onReadOnlyTap: nil,
                        focusRequestID: focusRequestID,
                        initialScrollResetID: initialScrollResetID,
                        onEditingBegan: onEditingBegan
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(hidesTextDuringOpening ? 0 : 1)

                    if isPad && showsCloseButton {
                        dedicatedDocumentEditorCloseButton
                            .padding(
                                .trailing,
                                max(6, proxy.safeAreaInsets.trailing + 2)
                            )
                            .padding(
                                .bottom,
                                max(8, proxy.safeAreaInsets.bottom + 2)
                            )
                    }
                }
                .frame(
                    width: proxy.size.width,
                    height: max(0, proxy.size.height - dockedKeyboardHeight),
                    alignment: .topLeading
                )
                .background {
                    GeometryReader { viewportProxy in
                        Color.clear
                            .onAppear {
                                updateEditorViewport(
                                    viewportProxy.size,
                                    presentationSize: proxy.size
                                )
                            }
                            .onChange(of: viewportProxy.size) { _, newSize in
                                updateEditorViewport(
                                    newSize,
                                    presentationSize: proxy.size
                                )
                            }
                    }
                }
                .overlay {
                    if !isPad && showsCloseButton {
                        DedicatedDocumentEditorIPhoneCloseButtonLayer(
                            onSaveAndClose: onSaveAndClose
                        )
                        .frame(width: 0, height: 0)
                        .allowsHitTesting(false)
                    }
                }
            }

            DedicatedDocumentEditorKeyboardObserver(
                dockedKeyboardHeight: $dockedKeyboardHeight,
                onKeyboardFrameReceived: { layout in
                    latestKeyboardLayout = layout
                    onKeyboardFrameReceived(layout)
                    reportKeyboardLayoutIfViewportIsReady()
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
        }
    }

    private func updateEditorViewport(_ size: CGSize, presentationSize: CGSize) {
        guard size.width > 0, size.height >= 0 else { return }
        editorViewportSize = size
        editorPresentationSize = presentationSize
        reportKeyboardLayoutIfViewportIsReady()
    }

    private func reportKeyboardLayoutIfViewportIsReady() {
        guard let latestKeyboardLayout,
              latestKeyboardLayout != lastReportedKeyboardLayout,
              editorPresentationSize.width > 0,
              editorPresentationSize.height >= 0 else {
            return
        }

        let expectedHeight = max(0, editorPresentationSize.height - latestKeyboardLayout.dockedHeight)
        guard abs(editorViewportSize.height - expectedHeight) <= 1 else { return }

        lastReportedKeyboardLayout = latestKeyboardLayout
        onKeyboardLayoutReady(latestKeyboardLayout)
    }

    private var dedicatedDocumentEditorCloseButton: some View {
        Button(action: onSaveAndClose) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: isPad ? 32 : 28, weight: .semibold))
                .foregroundStyle(.cyan)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Save and Close")
    }
}

private struct DedicatedDocumentEditorIPhoneCloseButtonLayer: UIViewRepresentable {
    let onSaveAndClose: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSaveAndClose: onSaveAndClose)
    }

    func makeUIView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.isUserInteractionEnabled = false
        view.windowDidChange = { [weak coordinator = context.coordinator] window in
            coordinator?.install(in: window)
        }
        return view
    }

    func updateUIView(_ view: AnchorView, context: Context) {
        context.coordinator.onSaveAndClose = onSaveAndClose
        context.coordinator.install(in: view.window)
    }

    static func dismantleUIView(_ view: AnchorView, coordinator: Coordinator) {
        coordinator.removeOverlay()
    }

    final class Coordinator {
        var onSaveAndClose: () -> Void
        private weak var window: UIWindow?
        private var overlay: PassthroughCloseButtonOverlayView?
        private var overlayConstraints: [NSLayoutConstraint] = []

        init(onSaveAndClose: @escaping () -> Void) {
            self.onSaveAndClose = onSaveAndClose
        }

        func install(in newWindow: UIWindow?) {
            guard let newWindow else { return }

            guard window !== newWindow || overlay == nil else {
                overlay?.onSaveAndClose = onSaveAndClose
                return
            }

            removeOverlay()

            let overlay = PassthroughCloseButtonOverlayView(onSaveAndClose: onSaveAndClose)
            overlay.translatesAutoresizingMaskIntoConstraints = false
            newWindow.addSubview(overlay)

            overlayConstraints = [
                overlay.leadingAnchor.constraint(equalTo: newWindow.leadingAnchor),
                overlay.trailingAnchor.constraint(equalTo: newWindow.trailingAnchor),
                overlay.topAnchor.constraint(equalTo: newWindow.topAnchor),
                overlay.bottomAnchor.constraint(equalTo: newWindow.bottomAnchor)
            ]
            NSLayoutConstraint.activate(overlayConstraints)

            self.window = newWindow
            self.overlay = overlay
        }

        func removeOverlay() {
            NSLayoutConstraint.deactivate(overlayConstraints)
            overlayConstraints.removeAll()
            overlay?.removeFromSuperview()
            overlay = nil
            window = nil
        }
    }

    final class AnchorView: UIView {
        var windowDidChange: ((UIWindow?) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            windowDidChange?(window)
        }
    }
}

private final class PassthroughCloseButtonOverlayView: UIView {
    var onSaveAndClose: () -> Void {
        didSet {
            closeButtonAction = onSaveAndClose
        }
    }

    private var closeButtonAction: () -> Void
    private let closeButton = UIButton(type: .system)

    init(onSaveAndClose: @escaping () -> Void) {
        self.onSaveAndClose = onSaveAndClose
        self.closeButtonAction = onSaveAndClose
        super.init(frame: .zero)

        backgroundColor = .clear
        isOpaque = false
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.tintColor = .cyan
        closeButton.accessibilityLabel = "Save and Close"
        closeButton.setImage(
            UIImage(
                systemName: "xmark.circle.fill",
                withConfiguration: UIImage.SymbolConfiguration(
                    pointSize: 28,
                    weight: .semibold
                )
            ),
            for: .normal
        )
        closeButton.addAction(
            UIAction { [weak self] _ in
                self?.closeButtonAction()
            },
            for: .touchUpInside
        )
        addSubview(closeButton)

        NSLayoutConstraint.activate([
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44),
            closeButton.trailingAnchor.constraint(
                equalTo: safeAreaLayoutGuide.trailingAnchor,
                constant: -10
            ),
            closeButton.bottomAnchor.constraint(
                equalTo: keyboardLayoutGuide.topAnchor,
                constant: -10
            )
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        closeButton.frame.contains(point)
    }
}

private struct DedicatedDocumentEditorKeyboardObserver: UIViewRepresentable {
    @Binding var dockedKeyboardHeight: CGFloat
    let onKeyboardFrameReceived: (DedicatedDocumentEditorKeyboardLayout) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            dockedKeyboardHeight: $dockedKeyboardHeight,
            onKeyboardFrameReceived: onKeyboardFrameReceived
        )
    }

    func makeUIView(context: Context) -> KeyboardGeometryView {
        let view = KeyboardGeometryView()
        view.isUserInteractionEnabled = false
        view.layoutDidChange = { [weak coordinator = context.coordinator] view in
            coordinator?.updateKeyboardHeight(for: view)
        }
        context.coordinator.observeKeyboard()
        return view
    }

    func updateUIView(_ view: KeyboardGeometryView, context: Context) {
        context.coordinator.dockedKeyboardHeight = $dockedKeyboardHeight
        context.coordinator.onKeyboardFrameReceived = onKeyboardFrameReceived
        context.coordinator.updateKeyboardHeight(for: view)
    }

    final class Coordinator {
        var dockedKeyboardHeight: Binding<CGFloat>
        var onKeyboardFrameReceived: (DedicatedDocumentEditorKeyboardLayout) -> Void
        private weak var observerView: KeyboardGeometryView?
        private var keyboardFrameInScreen: CGRect?
        private var notificationObservers: [NSObjectProtocol] = []

        init(
            dockedKeyboardHeight: Binding<CGFloat>,
            onKeyboardFrameReceived: @escaping (DedicatedDocumentEditorKeyboardLayout) -> Void
        ) {
            self.dockedKeyboardHeight = dockedKeyboardHeight
            self.onKeyboardFrameReceived = onKeyboardFrameReceived
        }

        deinit {
            notificationObservers.forEach(NotificationCenter.default.removeObserver)
        }

        func observeKeyboard() {
            guard notificationObservers.isEmpty else { return }

            let center = NotificationCenter.default
            notificationObservers = [
                center.addObserver(
                    forName: UIResponder.keyboardWillChangeFrameNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] notification in
                    self?.handleKeyboard(notification, reportsSettledFrame: false)
                },
                center.addObserver(
                    forName: UIResponder.keyboardDidChangeFrameNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] notification in
                    self?.handleKeyboard(notification, reportsSettledFrame: true)
                },
                center.addObserver(
                    forName: UIResponder.keyboardWillHideNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    self?.keyboardFrameInScreen = nil
                    self?.updateKeyboardHeight()
                },
                center.addObserver(
                    forName: UIResponder.keyboardDidHideNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    self?.keyboardFrameInScreen = nil
                    self?.updateKeyboardHeight()
                    self?.reportHiddenKeyboardLayout()
                }
            ]
        }

        @discardableResult
        func updateKeyboardHeight(
            for view: KeyboardGeometryView? = nil
        ) -> DedicatedDocumentEditorKeyboardLayout? {
            if let view {
                observerView = view
            }

            guard let observerView,
                  let window = observerView.window,
                  let keyboardFrameInScreen else {
                setDockedKeyboardHeight(0)
                return nil
            }

            let keyboardFrame = observerView.convert(keyboardFrameInScreen, from: nil)
            let visibleBounds = observerView.bounds
            let overlapsFullWidth = keyboardFrame.width >= visibleBounds.width - 1
            let keyboardFrameInWindow = window.convert(keyboardFrameInScreen, from: nil)
            let isDockedAtBottom = abs(keyboardFrameInWindow.maxY - window.bounds.maxY) <= 1
            let keyboardHeight = max(0, visibleBounds.maxY - keyboardFrame.minY)

            let isDocked = overlapsFullWidth && isDockedAtBottom
            let dockedHeight = isDocked ? keyboardHeight : 0
            setDockedKeyboardHeight(dockedHeight)
            return DedicatedDocumentEditorKeyboardLayout(
                frameInWindow: keyboardFrameInWindow,
                dockedHeight: dockedHeight,
                isDocked: isDocked
            )
        }

        private func handleKeyboard(
            _ notification: Notification,
            reportsSettledFrame: Bool
        ) {
            guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
                return
            }

            keyboardFrameInScreen = keyboardFrame
            guard reportsSettledFrame,
                  let layout = updateKeyboardHeight() else {
                updateKeyboardHeight()
                return
            }

            onKeyboardFrameReceived(layout)
        }

        private func reportHiddenKeyboardLayout() {
            onKeyboardFrameReceived(
                DedicatedDocumentEditorKeyboardLayout(
                    frameInWindow: .zero,
                    dockedHeight: 0,
                    isDocked: false
                )
            )
        }

        private func setDockedKeyboardHeight(_ height: CGFloat) {
            guard abs(dockedKeyboardHeight.wrappedValue - height) > 0.5 else { return }
            dockedKeyboardHeight.wrappedValue = height
        }
    }

    final class KeyboardGeometryView: UIView {
        var layoutDidChange: ((KeyboardGeometryView) -> Void)?

        override func layoutSubviews() {
            super.layoutSubviews()
            layoutDidChange?(self)
        }
    }
}

final class NoWrapDocumentTextView: UITextView {
    var hasUserAdjustedHorizontalOffset = false
    var wrapsText = false
    private var shouldFocusWhenAttached = false
    private var lastViewportSize: CGSize?

    override func didMoveToWindow() {
        super.didMoveToWindow()

        guard shouldFocusWhenAttached, window != nil else { return }
        shouldFocusWhenAttached = false
        becomeFirstResponder()
    }

    func focusWhenAvailable() {
        guard window != nil else {
            shouldFocusWhenAttached = true
            return
        }

        becomeFirstResponder()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let viewportSize = bounds.size
        let didViewportSizeChange = lastViewportSize != viewportSize
        lastViewportSize = viewportSize

        textContainer.widthTracksTextView = wrapsText
        textContainer.size = CGSize(
            width: wrapsText ? 0 : CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        refreshDocumentContentSize()

        if isFirstResponder,
           didViewportSizeChange,
           viewportSize.width > 0,
           viewportSize.height > 0 {
            ensureCaretVisible()
        }
    }

    override var contentOffset: CGPoint {
        didSet {
            if abs(contentOffset.x) > 0.5 {
                hasUserAdjustedHorizontalOffset = true
            }
        }
    }

    override func scrollRectToVisible(_ rect: CGRect, animated: Bool) {
        // Keep the user's horizontal position instead of auto-jumping back to the caret.
    }

    override func scrollRangeToVisible(_ range: NSRange) {
        // Keep the user's horizontal position instead of auto-jumping back to the caret.
    }

    func refreshNoWrapContentSize() {
        refreshDocumentContentSize()
    }

    func refreshDocumentContentSize() {
        if wrapsText {
            let measuredSize = sizeThatFits(
                CGSize(width: max(0, bounds.width), height: CGFloat.greatestFiniteMagnitude)
            )
            contentSize = CGSize(
                width: max(bounds.width, ceil(measuredSize.width)),
                height: max(bounds.height + 1, ceil(measuredSize.height))
            )
            return
        }

        let measuredSize = sizeThatFits(
            CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        )
        contentSize = CGSize(
            width: max(bounds.width + 1, ceil(measuredSize.width)),
            height: max(bounds.height + 1, ceil(measuredSize.height))
        )
    }

    func ensureCaretVisible() {
        guard let selectedTextRange else { return }

        let caretRect = self.caretRect(for: selectedTextRange.end).insetBy(dx: -16, dy: -12)
        var targetOffset = contentOffset

        let visibleMinX = contentOffset.x
        let visibleMaxX = contentOffset.x + bounds.width
        if caretRect.maxX > visibleMaxX {
            targetOffset.x = caretRect.maxX - bounds.width
        } else if caretRect.minX < visibleMinX {
            targetOffset.x = caretRect.minX
        }

        let visibleMinY = contentOffset.y
        let visibleMaxY = contentOffset.y + bounds.height
        if caretRect.maxY > visibleMaxY {
            targetOffset.y = caretRect.maxY - bounds.height
        } else if caretRect.minY < visibleMinY {
            targetOffset.y = caretRect.minY
        }

        setContentOffset(clampedContentOffset(for: targetOffset), animated: false)
    }

    func clampedContentOffset(for proposedOffset: CGPoint) -> CGPoint {
        let maximumX = max(0, contentSize.width - bounds.width)
        let maximumY = max(0, contentSize.height - bounds.height)

        return CGPoint(
            x: min(max(0, proposedOffset.x), maximumX),
            y: min(max(0, proposedOffset.y), maximumY)
        )
    }
}

struct SettingsToolbarButton: View {
    let title: String
    let backgroundColor: Color
    let minWidth: CGFloat
    let isEnabled: Bool
    let action: () -> Void

    private var titleFont: Font {
        isPad ? .body : .system(size: 15)
    }

    private var uiKitTitleFont: UIFont? {
        isPad ? nil : .systemFont(ofSize: 15)
    }

    private var horizontalPadding: CGFloat {
        isPad ? 5 : 2
    }

    @ViewBuilder
    var body: some View {
        if #available(iOS 18, *) {
            Button(title) {
                ButtonClickFeedback.playIfEnabled()
                action()
            }
            .disabled(!isEnabled)
            .font(titleFont)
            .foregroundStyle(isEnabled ? .white : Color(white: 0.8))
            .padding(.horizontal, horizontalPadding)
            .frame(minWidth: minWidth, minHeight: 36)
            .background(isEnabled ? backgroundColor : Color.gray.opacity(0.45))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray.opacity(0.5), lineWidth: 1.5)
            }
            .clipShape(.rect(cornerRadius: 12))
            .contentShape(.rect)
            .opacity(isEnabled ? 1 : 0.75)
        } else {
            SettingsUIKitVisualButton(
                title: title,
                backgroundColor: backgroundColor,
                width: minWidth,
                height: 36,
                isEnabled: isEnabled,
                fontStyle: .body,
                font: uiKitTitleFont,
                titleColor: isEnabled ? .white : UIColor(white: 0.8, alpha: 1),
                adjustsFontSizeToFitWidth: false,
                contentInsets: UIEdgeInsets(top: 0, left: horizontalPadding, bottom: 0, right: horizontalPadding)
            ) {
                ButtonClickFeedback.playIfEnabled()
                action()
            }
        }
    }
}

struct SettingsUIKitVisualButton: View {
    let title: String
    let backgroundColor: Color
    let width: CGFloat
    let height: CGFloat
    let isEnabled: Bool
    let fontStyle: UIFont.TextStyle
    var font: UIFont? = nil
    let titleColor: UIColor
    let adjustsFontSizeToFitWidth: Bool
    let contentInsets: UIEdgeInsets
    let action: () -> Void

    var body: some View {
        SettingsUIKitVisualButtonRepresentable(
            title: title,
            backgroundColor: backgroundColor,
            isEnabled: isEnabled,
            fontStyle: fontStyle,
            font: font,
            titleColor: titleColor,
            adjustsFontSizeToFitWidth: adjustsFontSizeToFitWidth,
            contentInsets: contentInsets,
            action: action
        )
        .frame(width: width, height: height)
    }
}

private struct SettingsUIKitVisualButtonRepresentable: UIViewRepresentable {
    let title: String
    let backgroundColor: Color
    let isEnabled: Bool
    let fontStyle: UIFont.TextStyle
    let font: UIFont?
    let titleColor: UIColor
    let adjustsFontSizeToFitWidth: Bool
    let contentInsets: UIEdgeInsets
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.titleLabel?.textAlignment = .center
        button.titleLabel?.lineBreakMode = .byTruncatingTail
        button.titleLabel?.adjustsFontSizeToFitWidth = adjustsFontSizeToFitWidth
        button.titleLabel?.minimumScaleFactor = adjustsFontSizeToFitWidth ? 0.7 : 1
        button.contentEdgeInsets = contentInsets
        button.layer.cornerRadius = 12
        button.layer.borderWidth = 1.5
        button.layer.borderColor = UIColor.gray.withAlphaComponent(0.5).cgColor
        button.clipsToBounds = true
        button.addTarget(context.coordinator, action: #selector(Coordinator.buttonTapped), for: .touchUpInside)
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.action = action
        button.setTitle(title, for: .normal)
        button.setTitleColor(titleColor, for: .normal)
        button.titleLabel?.font = font ?? .preferredFont(forTextStyle: fontStyle)
        button.titleLabel?.adjustsFontSizeToFitWidth = adjustsFontSizeToFitWidth
        button.titleLabel?.minimumScaleFactor = adjustsFontSizeToFitWidth ? 0.7 : 1
        button.contentEdgeInsets = contentInsets
        button.backgroundColor = isEnabled ? UIColor(backgroundColor) : UIColor.gray.withAlphaComponent(0.45)
        button.isEnabled = isEnabled
        button.alpha = isEnabled ? 1 : 0.75
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIButton, context: Context) -> CGSize? {
        let width = proposal.width ?? uiView.intrinsicContentSize.width
        let height = proposal.height ?? uiView.intrinsicContentSize.height
        return CGSize(width: width, height: height)
    }

    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func buttonTapped() {
            action()
        }
    }
}

struct SettingsEditorSectionView: View {
    @Binding var text: String
    @Binding var fontSize: CGFloat
    @Binding var isFocused: Bool
    let isReadOnly: Bool
    let onReadOnlyTap: (() -> Void)?
    let savedText: String
    let onUndo: () -> Void
    @State private var clipboardStatusMessage: String?
    @State private var clipboardStatusMessageID = UUID()

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            PlainDocumentEditor(
                text: $text,
                fontSize: $fontSize,
                isFocused: $isFocused,
                isReadOnly: isReadOnly,
                onReadOnlyTap: onReadOnlyTap,
                focusRequestID: nil,
                initialScrollResetID: nil,
                onEditingBegan: nil
            )

            clipboardStatusOverlay

            if !isReadOnly {
                HStack(spacing: isPad ? 10 : 6) {
                    undoButton
                    cpyToCbButton
                    pasteButton
                }
                .padding(.trailing, 8)
                .padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            if isReadOnly {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: SettingsEditorPreviewFramePreferenceKey.self,
                        value: proxy.frame(
                            in: .named(
                                SettingsDocumentEditorAnimationGeometry.coordinateSpaceName
                            )
                        )
                    )
                }
            }
        }
        .overlay {
            Rectangle()
                .stroke(Color.white, lineWidth: 1)
        }
    }

    private var undoButton: some View {
        editorActionButton(
            systemName: "arrow.counterclockwise.circle",
            color: .cyan,
            accessibilityLabel: "Undo",
            isEnabled: text != savedText
        ) {
            ButtonClickFeedback.playIfEnabled()
            onUndo()
        }
    }

    private var cpyToCbButton: some View {
        editorActionButton(
            systemName: "doc.on.doc",
            color: .yellow,
            accessibilityLabel: "Copy All"
        ) {
            ButtonClickFeedback.playIfEnabled()
            UIPasteboard.general.string = text
            showClipboardStatus("text copied\nto clipboard")
        }
    }

    private var pasteButton: some View {
        editorActionButton(
            systemName: "doc.on.clipboard",
            color: .red,
            accessibilityLabel: "Paste All"
        ) {
            ButtonClickFeedback.playIfEnabled()
            if let clipboardText = UIPasteboard.general.string {
                text = clipboardText
                showClipboardStatus("text pasted\nfrom clipboard")
            }
        }
    }

    private func editorActionButton(
        systemName: String,
        color: Color,
        accessibilityLabel: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            guard isEnabled else { return }
            action()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: editorActionButtonCornerRadius)
                    .fill(Color.black)

                Image(systemName: systemName)
                    .font(.system(size: isPad ? 22 : 18, weight: .semibold))
                    .foregroundStyle(color)
                    .opacity(isEnabled ? 1 : 0.35)
            }
            .frame(width: editorActionButtonSize, height: editorActionButtonSize)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(isEnabled)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(isEnabled ? "" : "Unavailable")
    }

    private var editorActionButtonSize: CGFloat {
        isPad ? 44 : 34
    }

    private var editorActionButtonCornerRadius: CGFloat {
        isPad ? 10 : 8
    }


    @ViewBuilder
    private var clipboardStatusOverlay: some View {
        if let clipboardStatusMessage {
            Text(clipboardStatusMessage)
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.black.opacity(0.8))
                .clipShape(.rect(cornerRadius: 12))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 74)
                .transition(.opacity)
        }
    }

    private func showClipboardStatus(_ message: String) {
        let messageID = UUID()
        clipboardStatusMessageID = messageID

        withAnimation(.easeInOut(duration: 0.15)) {
            clipboardStatusMessage = message
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            guard clipboardStatusMessageID == messageID else { return }
            withAnimation(.easeInOut(duration: 0.15)) {
                clipboardStatusMessage = nil
            }
        }
    }
}

struct SettingsBluetoothMonitorView: View {
    let monitorText: String
    // Bluetooth monitor panel font. Edit this value to tune monitor text size.
    private let monitorFontSize: CGFloat = 16.2

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(displayText)
                    .font(.system(size: monitorFontSize, design: .monospaced))
                    .foregroundStyle(monitorText.isEmpty ? Color.gray : .green)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(8)
                    .id("monitor-bottom")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.black)
            .overlay {
                Rectangle()
                    .stroke(Color.white, lineWidth: 1)
            }
            .onChange(of: monitorText) {
                proxy.scrollTo("monitor-bottom", anchor: .bottom)
            }
        }
    }

    private var displayText: String {
        monitorText.isEmpty ? "Bluetooth monitor waiting for ESP32 input..." : monitorText
    }
}
