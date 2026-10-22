import SwiftUI
import UIKit

@MainActor
@Observable
final class SmartEditorPasteTarget {
    enum Editor {
        case command
        case button
    }

    private(set) var editor: Editor = .command
    private(set) weak var textView: UITextView?

    func activate(_ editor: Editor, textView: UITextView) {
        self.editor = editor
        self.textView = textView
    }
}

struct SmartScriptTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    let fontSize: CGFloat
    var onBeginEditing: ((UITextView) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = ProbeTextView()
        textView.delegate = context.coordinator
        textView.textColor = .white
        textView.tintColor = .white
        textView.backgroundColor = .clear
        textView.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 5, bottom: 8, right: 5)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.isUpdatingView = true
        defer {
            context.coordinator.isUpdatingView = false
        }

        if uiView.text != text {
            uiView.text = text
        }

        context.coordinator.applySelectedRange(to: uiView)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width,
              let height = proposal.height,
              width.isFinite,
              height.isFinite else {
            return nil
        }

        return CGSize(width: width, height: height)
    }

    private final class ProbeTextView: UITextView {
        private var keyboardNotificationObservers: [NSObjectProtocol] = []

        override init(frame: CGRect, textContainer: NSTextContainer?) {
            super.init(frame: frame, textContainer: textContainer)
            registerKeyboardNotificationObservers()
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            registerKeyboardNotificationObservers()
        }

        deinit {
            for observer in keyboardNotificationObservers {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        override func becomeFirstResponder() -> Bool {
            let result = super.becomeFirstResponder()
            return result
        }

        override func resignFirstResponder() -> Bool {
            let result = super.resignFirstResponder()
            return result
        }

        private func registerKeyboardNotificationObservers() {
            let notificationCenter = NotificationCenter.default
            let notifications = [
                UIResponder.keyboardWillShowNotification,
                UIResponder.keyboardDidShowNotification,
                UIResponder.keyboardWillHideNotification,
                UIResponder.keyboardDidHideNotification
            ]

            keyboardNotificationObservers = notifications.map { notificationName in
                notificationCenter.addObserver(forName: notificationName, object: nil, queue: .main) { notification in
                }
            }
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: SmartScriptTextEditor
        var isUpdatingView = false
        private var isApplyingSelectedRange = false

        init(_ parent: SmartScriptTextEditor) {
            self.parent = parent
            super.init()
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.onBeginEditing?(textView)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isUpdatingView, !isApplyingSelectedRange else {
                return
            }

            let newText = textView.text ?? ""
            let newSelectedRange = textView.selectedRange
            DispatchQueue.main.async {
                self.parent.text = newText
                self.parent.selectedRange = newSelectedRange
            }
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isUpdatingView, !isApplyingSelectedRange else {
                return
            }

            let newSelectedRange = textView.selectedRange
            DispatchQueue.main.async {
                self.parent.selectedRange = newSelectedRange
            }
        }

        func applySelectedRange(to textView: UITextView) {
            let textLength = textView.text.utf16.count
            let location = min(max(parent.selectedRange.location, 0), textLength)
            let length = max(0, min(parent.selectedRange.length, textLength - location))
            let clampedRange = NSRange(location: location, length: length)

            guard textView.selectedRange != clampedRange else {
                return
            }

            isApplyingSelectedRange = true
            textView.selectedRange = clampedRange
            isApplyingSelectedRange = false
        }
    }
}

struct SmartPreviewTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    let fontSize: CGFloat
    let maximumVisibleLines: Int
    let disablesAutomaticPeriodShortcut: Bool
    var onBeginEditing: ((UITextView) -> Void)? = nil
    private static let maximumManualLogicalLineCount = 4
    private static let minimumVerticalInset: CGFloat = 1

    static func preferredHeight(fontSize: CGFloat, maximumVisibleLines: Int) -> CGFloat {
        ceil(fontSize * 1.35 * CGFloat(max(maximumVisibleLines, 1)))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = PreviewTextView()
        textView.delegate = context.coordinator
        textView.onLayout = { [weak coordinator = context.coordinator] textView in
            coordinator?.updateFittedFont(for: textView)
            coordinator?.updateVerticalTextInsets(for: textView)
        }
        textView.textColor = .white
        textView.tintColor = .white
        textView.backgroundColor = .clear
        textView.textAlignment = .center
        textView.font = .systemFont(ofSize: fontSize, weight: .semibold)
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.smartInsertDeleteType = .no
        textView.textContainerInset = UIEdgeInsets(
            top: Self.minimumVerticalInset,
            left: 0,
            bottom: Self.minimumVerticalInset,
            right: 0
        )
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.lineBreakMode = .byTruncatingTail
        textView.isScrollEnabled = true
        textView.showsVerticalScrollIndicator = false
        textView.showsHorizontalScrollIndicator = false
        textView.clipsToBounds = true
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.isUpdatingView = true
        defer {
            context.coordinator.isUpdatingView = false
        }

        if uiView.text != text {
            uiView.text = text
        }

        context.coordinator.updateDisplayTruncation(for: uiView)
        context.coordinator.updateFittedFont(for: uiView)
        context.coordinator.applySelectedRange(to: uiView)
        context.coordinator.updateVerticalTextInsets(for: uiView)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width,
              width.isFinite else {
            return nil
        }

        let height = proposal.height?.isFinite == true
            ? proposal.height ?? Self.preferredHeight(fontSize: fontSize, maximumVisibleLines: maximumVisibleLines)
            : Self.preferredHeight(fontSize: fontSize, maximumVisibleLines: maximumVisibleLines)
        return CGSize(width: width, height: height)
    }

    private final class PreviewTextView: UITextView {
        var onLayout: ((UITextView) -> Void)?
        var isHandlingPaste = false

        override func layoutSubviews() {
            super.layoutSubviews()
            onLayout?(self)
        }

        override func paste(_ sender: Any?) {
            isHandlingPaste = true
            super.paste(sender)
            isHandlingPaste = false
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: SmartPreviewTextView
        var isUpdatingView = false
        private var isApplyingSelectedRange = false

        init(_ parent: SmartPreviewTextView) {
            self.parent = parent
            super.init()
        }

        func textViewDidChange(_ textView: UITextView) {
            updateFittedFont(for: textView)
            updateVerticalTextInsets(for: textView)
            syncTextAndSelection(from: textView)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.onBeginEditing?(textView)
            updateDisplayTruncation(for: textView)
            updateFittedFont(for: textView)
            updateVerticalTextInsets(for: textView)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            updateDisplayTruncation(for: textView)
            updateFittedFont(for: textView)
            updateVerticalTextInsets(for: textView)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isUpdatingView, !isApplyingSelectedRange else {
                return
            }

            let newSelectedRange = textView.selectedRange
            DispatchQueue.main.async {
                self.parent.selectedRange = newSelectedRange
            }
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText text: String
        ) -> Bool {
            if shouldRejectManualNewline(in: textView, range: range, replacementText: text) {
                return false
            }

            guard parent.disablesAutomaticPeriodShortcut,
                  text == ". ",
                  range.length == 1,
                  let currentText = textView.text,
                  let replacementRange = Range(range, in: currentText),
                  String(currentText[replacementRange]) == " " else {
                return true
            }

            let updatedText = (currentText as NSString).replacingCharacters(in: range, with: "  ")
            textView.text = updatedText
            textView.selectedRange = NSRange(location: range.location + 2, length: 0)
            updateFittedFont(for: textView)
            updateVerticalTextInsets(for: textView)
            syncTextAndSelection(from: textView)
            return false
        }

        func updateFittedFont(for textView: UITextView) {
            updateDisplayTruncation(for: textView)

            guard textView.bounds.width > 0,
                  textView.bounds.height > 0 else {
                applyFont(parent.fontSize, to: textView)
                return
            }

            let preferredFontSize = parent.fontSize
            let minimumFontSize = max(12, preferredFontSize * 0.45)
            let availableWidth = max(
                1,
                textView.bounds.width
                    - textView.textContainerInset.left
                    - textView.textContainerInset.right
                    - (textView.textContainer.lineFragmentPadding * 2)
            )
            let availableHeight = max(
                1,
                textView.bounds.height - (SmartPreviewTextView.minimumVerticalInset * 2)
            )
            let fittingText = fittingText(from: textView.text ?? "")

            if measuredSize(
                for: fittingText,
                fontSize: preferredFontSize,
                width: availableWidth
            ).fits(width: availableWidth, height: availableHeight) {
                applyFont(preferredFontSize, to: textView)
                return
            }

            var low = minimumFontSize
            var high = preferredFontSize

            for _ in 0..<8 {
                let candidate = (low + high) / 2
                let measuredSize = measuredSize(
                    for: fittingText,
                    fontSize: candidate,
                    width: availableWidth
                )

                if measuredSize.fits(width: availableWidth, height: availableHeight) {
                    low = candidate
                } else {
                    high = candidate
                }
            }

            applyFont(low, to: textView)
        }

        func applySelectedRange(to textView: UITextView) {
            let textLength = textView.text.utf16.count
            let location = min(max(parent.selectedRange.location, 0), textLength)
            let length = max(0, min(parent.selectedRange.length, textLength - location))
            let clampedRange = NSRange(location: location, length: length)

            guard textView.selectedRange != clampedRange else {
                return
            }

            isApplyingSelectedRange = true
            textView.selectedRange = clampedRange
            isApplyingSelectedRange = false
        }

        func updateVerticalTextInsets(for textView: UITextView) {
            guard textView.bounds.height > 0,
                  textView.bounds.width > 0 else {
                return
            }

            textView.layoutManager.ensureLayout(for: textView.textContainer)
            let usedHeight = ceil(textView.layoutManager.usedRect(for: textView.textContainer).height)
            let fallbackLineHeight = ceil(textView.font?.lineHeight ?? parent.fontSize * 1.2)
            let renderedTextHeight = max(usedHeight, fallbackLineHeight)
            let centeredInset = max(
                SmartPreviewTextView.minimumVerticalInset,
                floor((textView.bounds.height - renderedTextHeight) / 2)
            )
            let targetInsets = UIEdgeInsets(
                top: centeredInset,
                left: 0,
                bottom: centeredInset,
                right: 0
            )

            guard abs(textView.textContainerInset.top - targetInsets.top) > 0.5 ||
                    abs(textView.textContainerInset.bottom - targetInsets.bottom) > 0.5 else {
                return
            }

            textView.textContainerInset = targetInsets

            if renderedTextHeight <= textView.bounds.height {
                textView.setContentOffset(.zero, animated: false)
            } else {
                textView.scrollRangeToVisible(textView.selectedRange)
            }
        }

        func updateDisplayTruncation(for textView: UITextView) {
            textView.isScrollEnabled = textView.isFirstResponder
            textView.textContainer.maximumNumberOfLines = textView.isFirstResponder ? 0 : max(parent.maximumVisibleLines, 1)
            textView.textContainer.lineBreakMode = textView.isFirstResponder ? .byWordWrapping : .byTruncatingTail
        }

        private func shouldRejectManualNewline(
            in textView: UITextView,
            range: NSRange,
            replacementText: String
        ) -> Bool {
            guard replacementText == "\n",
                  (textView as? PreviewTextView)?.isHandlingPaste != true,
                  let currentText = textView.text else {
                return false
            }

            let currentLineCount = logicalLineCount(in: currentText)
            let proposedText = (currentText as NSString).replacingCharacters(in: range, with: replacementText)
            let proposedLineCount = logicalLineCount(in: proposedText)

            if proposedLineCount <= SmartPreviewTextView.maximumManualLogicalLineCount {
                return false
            }

            return proposedLineCount > currentLineCount
        }

        private func logicalLineCount(in text: String) -> Int {
            text.components(separatedBy: .newlines).count
        }

        private func fittingText(from text: String) -> String {
            let visibleLineCount = max(parent.maximumVisibleLines, 1)
            let lines = text.components(separatedBy: .newlines)
            let fittingLines = lines.prefix(visibleLineCount)
            let fittingText = fittingLines.joined(separator: "\n")
            return fittingText.isEmpty ? " " : fittingText
        }

        private func measuredSize(for text: String, fontSize: CGFloat, width: CGFloat) -> CGSize {
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            paragraphStyle.lineBreakMode = .byWordWrapping
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: fontSize, weight: .semibold),
                .paragraphStyle: paragraphStyle
            ]
            let rect = (text as NSString).boundingRect(
                with: CGSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attributes,
                context: nil
            )
            return CGSize(width: ceil(rect.width), height: ceil(rect.height))
        }

        private func applyFont(_ fontSize: CGFloat, to textView: UITextView) {
            let currentFontSize = textView.font?.pointSize ?? 0
            guard abs(currentFontSize - fontSize) > 0.25 else {
                return
            }

            textView.font = .systemFont(ofSize: fontSize, weight: .semibold)
        }

        private func syncTextAndSelection(from textView: UITextView) {
            guard !isUpdatingView, !isApplyingSelectedRange else {
                return
            }

            let newText = textView.text ?? ""
            let newSelectedRange = textView.selectedRange
            DispatchQueue.main.async {
                self.parent.text = newText
                self.parent.selectedRange = newSelectedRange
            }
        }
    }
}

private extension CGSize {
    func fits(width: CGFloat, height: CGFloat) -> Bool {
        self.width <= width + 0.5 && self.height <= height + 0.5
    }
}

struct SmartActionTextField: UIViewRepresentable {
    let placeholder: String
    @Binding var text: String
    @Binding var selectedRange: NSRange
    let fontSize: CGFloat
    let disablesAutomaticPeriodShortcut: Bool

    init(
        placeholder: String,
        text: Binding<String>,
        selectedRange: Binding<NSRange>,
        fontSize: CGFloat,
        disablesAutomaticPeriodShortcut: Bool = false
    ) {
        self.placeholder = placeholder
        self._text = text
        self._selectedRange = selectedRange
        self.fontSize = fontSize
        self.disablesAutomaticPeriodShortcut = disablesAutomaticPeriodShortcut
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.delegate = context.coordinator
        textField.placeholder = placeholder
        textField.textColor = .white
        textField.tintColor = .white
        textField.textAlignment = .center
        textField.backgroundColor = .clear
        textField.borderStyle = .none
        textField.font = .systemFont(ofSize: fontSize, weight: .semibold)
        textField.adjustsFontSizeToFitWidth = true
        textField.minimumFontSize = fontSize * 0.35
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textField.autocorrectionType = .no
        textField.autocapitalizationType = .none
        textField.addTarget(context.coordinator, action: #selector(Coordinator.textDidChange(_:)), for: .editingChanged)
        return textField
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.parent = self
        context.coordinator.isUpdatingView = true
        defer {
            context.coordinator.isUpdatingView = false
        }

        if uiView.text != text {
            uiView.text = text
        }

        context.coordinator.applySelectedRange(to: uiView)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: SmartActionTextField
        var isUpdatingView = false
        private var isApplyingSelectedRange = false

        init(_ parent: SmartActionTextField) {
            self.parent = parent
        }

        @objc func textDidChange(_ textField: UITextField) {
            guard !isUpdatingView, !isApplyingSelectedRange else {
                return
            }

            let newText = textField.text ?? ""
            let newSelectedRange = selectedRange(from: textField)
            DispatchQueue.main.async {
                self.parent.text = newText
                if let newSelectedRange {
                    self.parent.selectedRange = newSelectedRange
                }
            }
        }

        func textField(
            _ textField: UITextField,
            shouldChangeCharactersIn range: NSRange,
            replacementString string: String
        ) -> Bool {
            guard parent.disablesAutomaticPeriodShortcut,
                  string == ". ",
                  range.length == 1,
                  let currentText = textField.text,
                  let replacementRange = Range(range, in: currentText),
                  String(currentText[replacementRange]) == " " else {
                return true
            }

            let updatedText = (currentText as NSString).replacingCharacters(in: range, with: "  ")
            textField.text = updatedText

            if let cursorPosition = textField.position(from: textField.beginningOfDocument, offset: range.location + 2) {
                textField.selectedTextRange = textField.textRange(from: cursorPosition, to: cursorPosition)
            }

            textField.sendActions(for: .editingChanged)
            return false
        }

        func textFieldDidChangeSelection(_ textField: UITextField) {
            guard !isUpdatingView, !isApplyingSelectedRange,
                  let newSelectedRange = selectedRange(from: textField) else {
                return
            }

            DispatchQueue.main.async {
                self.parent.selectedRange = newSelectedRange
            }
        }

        func selectedRange(from textField: UITextField) -> NSRange? {
            guard let selectedTextRange = textField.selectedTextRange else {
                return nil
            }

            let location = textField.offset(from: textField.beginningOfDocument, to: selectedTextRange.start)
            let length = textField.offset(from: selectedTextRange.start, to: selectedTextRange.end)
            return NSRange(location: location, length: length)
        }

        func applySelectedRange(to textField: UITextField) {
            guard let start = textField.position(from: textField.beginningOfDocument, offset: parent.selectedRange.location),
                  let end = textField.position(from: start, offset: parent.selectedRange.length),
                  textField.selectedTextRange?.start != start || textField.selectedTextRange?.end != end else {
                return
            }

            isApplyingSelectedRange = true
            textField.selectedTextRange = textField.textRange(from: start, to: end)
            isApplyingSelectedRange = false
        }
    }
}
