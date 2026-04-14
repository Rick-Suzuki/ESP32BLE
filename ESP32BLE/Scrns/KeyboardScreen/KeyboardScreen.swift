import SwiftUI
import UIKit

struct KeyboardScreen: View {
    // Easy-to-find key label sizing for the custom keyboard grid.
    private let gridKeyFontSize: CGFloat = 24
    let keypadKeyFontSize: CGFloat = 31
    private let typingAreaFontSize: CGFloat = 31
    // Easy-to-find key shape tuning for the custom keyboard grid.
    private let gridKeyCornerRadius: CGFloat = 12
    private let gridKeySpacing: CGFloat = 6
    private let gridRowHeightScale: CGFloat = 0.99
    // Easy-to-find sizing for the top keyboard control row.
    private let topControlSingleButtonWidth: CGFloat = 95
    private let topControlDoubleButtonWidth: CGFloat = 193
    private let topMainButtonWidth: CGFloat = 64

    @ObservedObject var ble: BLEKeyboardManager
    let isPresented: Bool
    @AppStorage("keyboardModeNumber") var keyboardModeNumber = 1
    @AppStorage("keyboardSendImmediatelyEnabled") var isSendImmediatelyEnabled = true
    @AppStorage("keyboardAutoCapEnabled") var isAutoCapEnabled = false
    @AppStorage("keyboardEachWordCapEnabled") var isEachWordCapEnabled = false
    @AppStorage("keyboardAutoCorrectEnabled") var isAutoCorrectEnabled = false
    let returnToMain: () -> Void

    @State var typingText = ""
    @State var shouldFocusInput = false
    @State var activeModifiers: Set<KeyboardModifier> = []
    @State var cursorCommand: CursorMovement = .right
    @State var cursorCommandID = 0
    @State var bufferedSoftKeyTokens: [String] = []
    @State var popupMessage: String?
    @State private var popupDismissTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            topSection
       //     Divider()
				//.overlay(Color.gray.opacity(0.45))
            keyGrid
        }
        .background(Color.black.ignoresSafeArea())
        .overlay {
            popupOverlay
        }
        .preferredColorScheme(.dark)
        .onChange(of: isPresented) {
            if !isPresented {
                shouldFocusInput = false
            }
        }
        .onChange(of: popupMessage) {
            schedulePopupDismissIfNeeded()
        }
    }

    private var topSection: some View {
        KeyboardTopSectionView(
            currentModeNumber: currentKeyboardMode.rawValue,
            typingText: $typingText,
            shouldFocusInput: $shouldFocusInput,
            isPresented: isPresented,
            typingAreaFontSize: typingAreaFontSize,
            autocapitalizationType: effectiveKeyboardAutocapitalizationType,
            autocorrectionEnabled: effectiveAutocorrectionEnabled,
            cursorCommand: cursorCommand,
            cursorCommandID: cursorCommandID,
            isSendImmediatelyEnabled: $isSendImmediatelyEnabled,
            isAutoCapEnabled: $isAutoCapEnabled,
            isEachWordCapEnabled: $isEachWordCapEnabled,
            isAutoCorrectEnabled: $isAutoCorrectEnabled,
            isSendOnReturnMode: isSendOnReturnMode,
            isSendButtonEnabled: isSendButtonEnabled,
            topControlSingleButtonWidth: topControlSingleButtonWidth,
            topControlDoubleButtonWidth: topControlDoubleButtonWidth,
            topMainButtonWidth: topMainButtonWidth,
            onAdvanceMode: advanceKeyboardMode,
            onInsertedText: handleInsertedText(_:),
            onBackspace: handleBackspace,
            onReturn: handleReturn,
            onClear: clearTypingArea,
            onReturnToMain: {
                shouldFocusInput = false
                returnToMain()
            },
            onMoveLeft: { moveCursor(.left) },
            onMoveRight: { moveCursor(.right) },
            onSend: sendBufferedKeyboardContent
        )
    }

    private var keyGrid: some View {
        KeyboardGridView(
            rows: currentLayoutRows,
            columnCount: currentColumnCount,
            gridKeySpacing: gridKeySpacing,
            gridRowHeightScale: gridRowHeightScale,
            gridKeyFontSize: gridKeyFontSize,
            gridKeyCornerRadius: gridKeyCornerRadius
        )
    }

    @ViewBuilder
    private var popupOverlay: some View {
        if let popupMessage {
            VStack {
                Spacer()

                Text(popupMessage)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(Color.black.opacity(0.88))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.25), lineWidth: 1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 24)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)
            .allowsHitTesting(false)
        }
    }

    private func schedulePopupDismissIfNeeded() {
        popupDismissTask?.cancel()

        guard popupMessage != nil else {
            popupDismissTask = nil
            return
        }

        popupDismissTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                popupMessage = nil
            }
        }
    }

}
