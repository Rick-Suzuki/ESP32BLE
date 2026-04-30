import SwiftUI
import UIKit

enum SettingsFocusField: Hashable {
    case sendText
}

struct PlainDocumentEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var fontSize: CGFloat
    @Binding var isFocused: Bool

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
        textView.isEditable = true
        textView.isSelectable = true
        textView.isScrollEnabled = true
        textView.alwaysBounceHorizontal = true
        textView.alwaysBounceVertical = true
        textView.showsHorizontalScrollIndicator = true
        textView.showsVerticalScrollIndicator = true
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.lineBreakMode = .byClipping
        textView.textContainer.widthTracksTextView = false
        textView.textContainer.size = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.font = .systemFont(ofSize: fontSize)
        textView.text = text
        return textView
    }

    func updateUIView(_ textView: NoWrapDocumentTextView, context: Context) {
        context.coordinator.parent = self
        let previousOffset = textView.contentOffset
        var shouldRestoreOffset = false
        var didChangeContent = false

        if textView.text != text {
            textView.text = text
            shouldRestoreOffset = true
            didChangeContent = true
        }

        let currentSize = textView.font?.pointSize ?? fontSize
        if abs(currentSize - fontSize) > 0.25 {
            textView.font = .systemFont(ofSize: fontSize)
            shouldRestoreOffset = true
        }

        if shouldRestoreOffset {
            textView.layoutIfNeeded()
            textView.refreshNoWrapContentSize()
            let targetOffset: CGPoint
            if didChangeContent, !textView.hasUserAdjustedHorizontalOffset {
                targetOffset = .zero
            } else {
                targetOffset = textView.clampedContentOffset(for: previousOffset)
            }
            textView.setContentOffset(targetOffset, animated: false)
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: PlainDocumentEditor

        init(text: Binding<String>, isFocused: Binding<Bool>) {
            self.parent = PlainDocumentEditor(text: text, fontSize: .constant(18), isFocused: isFocused)
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
            guard !parent.isFocused else { return }
            parent.isFocused = true
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            guard parent.isFocused else { return }
            parent.isFocused = false
        }
    }
}

final class NoWrapDocumentTextView: UITextView {
    var hasUserAdjustedHorizontalOffset = false

    override func layoutSubviews() {
        super.layoutSubviews()
        textContainer.size = CGSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        refreshNoWrapContentSize()
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

struct BackButton: View {
    @Environment(\.dismiss) private var dismiss
    let action: () -> Void

    var body: some View {
        Button("main") {
            ButtonClickFeedback.playIfEnabled()
            action()
            dismiss()
        }
        .font(.headline)
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .frame(minWidth: 92, minHeight: 44)
        .background(Color.gray.opacity(0.45))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.5), lineWidth: 1.5)
        }
        .clipShape(.rect(cornerRadius: 12))
        .contentShape(.rect)
    }
}

struct SettingsToolbarButton: View {
    let title: String
    let backgroundColor: Color
    let minWidth: CGFloat
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(title) {
            ButtonClickFeedback.playIfEnabled()
            action()
        }
        .disabled(!isEnabled)
        .font(.headline)
        .foregroundStyle(isEnabled ? .white : Color(white: 0.8))
        .padding(.horizontal, 5)
        .frame(minWidth: minWidth, minHeight: 44)
        .background(isEnabled ? backgroundColor : Color.gray.opacity(0.45))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.5), lineWidth: 1.5)
        }
        .clipShape(.rect(cornerRadius: 12))
        .contentShape(.rect)
        .opacity(isEnabled ? 1 : 0.75)
    }
}

struct SettingsEditorSectionView: View {
    @Binding var text: String
    @Binding var fontSize: CGFloat
    @Binding var isFocused: Bool
    let savedText: String
    let onUndo: () -> Void

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            PlainDocumentEditor(
                text: $text,
                fontSize: $fontSize,
                isFocused: $isFocused
            )

            HStack(spacing: 10) {
                fontSizeControls
                undoButton
            }
            .padding(.trailing, 8)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay {
            Rectangle()
                .stroke(Color.white, lineWidth: 1)
        }
    }

    private var fontSizeControls: some View {
        HStack(spacing: 14) {
            fontTriangleButton(rotationDegrees: -90) {
                fontSize = max(10, fontSize - 2)
            }

            Text("font:\(Int(fontSize))")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)

            fontTriangleButton(rotationDegrees: 90) {
                fontSize = min(72, fontSize + 2)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.5))
        .clipShape(.rect(cornerRadius: 12))
    }

    private var undoButton: some View {
        Button("undo") {
            ButtonClickFeedback.playIfEnabled()
            onUndo()
        }
        .buttonStyle(.plain)
        .font(.headline)
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(Color.gray.opacity(0.25))
        .clipShape(.rect(cornerRadius: 12))
        .disabled(text == savedText)
        .opacity(text == savedText ? 0.5 : 1)
    }

    private func fontTriangleButton(rotationDegrees: Double, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "triangle.fill")
                .font(.system(size: 18, weight: .bold))
                .rotationEffect(.degrees(rotationDegrees))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
