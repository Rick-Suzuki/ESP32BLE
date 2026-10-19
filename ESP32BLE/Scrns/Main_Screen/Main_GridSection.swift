/*
 This is the UI layer for the grid.
 It attaches the drag/swipe gestures to each button and
 calls the move handler when a drag direction is detected.
 */

/*
 MainScreenGridSection.swift for gesture detection,
 then follow the move call into MainScreenButtonBehavior.swift
 then into ContentView.swift where the data is actually changed.
 */
import SwiftUI
import UIKit

typealias GridDimensions = (columns: Int, rows: Int)

// MARK: - BM:🔆 grid dimensions

func functionKeyGridDimensions(for itemCount: Int) -> GridDimensions {
    let preferredDimensions: [Int: GridDimensions] = [
		
		1: (1, 1),
		2: (2, 1),
		3: (3, 1),
		4: (2, 2),
		6: (3, 2),
		8: (4, 2),
		9: (3, 3),

		10: (5, 2),
		12: (4, 3),
        15: (5, 3),
        18: (6, 3),

		20: (5, 4),
		21: (7, 3),
			24: (6, 4),
			25: (5, 5),
			27: (9, 3),
			28: (7, 4),

			30: (6, 5),
			32: (8, 4),
        35: (7, 5),
		36: (6, 6),

			40: (8, 5),
			42: (7, 6),
			44: (11, 4),
			45: (9, 5),
        48: (8, 6),
			49: (7, 7),

			50: (10, 5),
        54: (9, 6),
			56: (8, 7),
		
			60: (10, 6),
        63: (9, 7),
			64: (8, 8),
			66: (11, 6),
			
			70: (10, 7),
			72: (9, 8),
			75: (15, 5),
			78: (13, 6),
			
			80: (10, 8),
        84: (12, 7),
        88: (11, 8),
		
				90: (10, 9),
				96: (12, 8),
				98: (14, 7),
        99: (11, 9),
        100: (10, 10),
    ]

    if let preferred = preferredDimensions[itemCount] {
        return preferred
    }

    guard itemCount > 0 else {
        return (1, 1)
    }

    let baseColumns = Int(ceil(sqrt(Double(itemCount))))
    var columns = max(baseColumns, Int(ceil(Double(itemCount) / Double(baseColumns))))
    var rows = Int(ceil(Double(itemCount) / Double(columns)))

    if rows > columns {
        swap(&rows, &columns)
    }

    return (columns, rows)
}

struct MainScreenGridSection<ButtonLabel: View>: View {
    @Environment(\.scenePhase) private var scenePhase
    let availableWidth: CGFloat
    let reservedBottomInset: CGFloat
    let functionKeys: [FunctionKeyEntry]
    let visibleBoxCount: Int
    let visibleGridDimensions: GridDimensions
    let mainGridButtonSpacing: CGFloat
    let mainGridButtonCornerRadius: CGFloat
    let boxFontSize: Double
    let clipsButtonContentToBounds: Bool
    let isGridEditModeEnabled: Bool
    let selectedActionMenuIndex: Int?
    let renderedButtonFrameRefreshToken: Int
    let bleSendEnabled: Bool
    let onButtonClick: () -> Void
    let isHiddenEntry: (FunctionKeyEntry) -> Bool
    let isEmptyEntry: (FunctionKeyEntry) -> Bool
    let isInteractiveWidgetEntry: (FunctionKeyEntry) -> Bool
    let isSimpleOrdinarySoundEntry: (FunctionKeyEntry) -> Bool
    let midiNoteNumber: (FunctionKeyEntry) -> Int?
    let onMIDITouchDown: (Int) -> Void
    let onMIDITouchUp: (Int) -> Void
    let sendLine: (FunctionKeyEntry) -> Void
    let onSimpleOrdinarySoundSingleTap: (FunctionKeyEntry, Int) -> Void
    let onSimpleOrdinarySoundDoubleTap: (FunctionKeyEntry, Int) -> Void
    let onBeginSlotEditing: (Int) -> Void
    let buttonLabel: (FunctionKeyEntry, Int, CGFloat, CGSize) -> ButtonLabel
    let dragGesture: (FunctionKeyEntry, Int, GridDimensions) -> AnyGesture<DragGesture.Value>
    let onRenderedButtonFrame: (Int, CGRect, GridDimensions) -> Void
    let onRenderedGridFrame: (CGRect) -> Void
    let onSingleEditTap: (FunctionKeyEntry, Int, CGRect, GridDimensions) -> Void
    let onResizeSlot: (FunctionKeyEntry, Int, GridDimensions) -> Void
    let onResetSlotSize: (FunctionKeyEntry, Int, GridDimensions) -> Void
    let onDeleteSlot: (FunctionKeyEntry, Int) -> Void
    @State private var longPressedEditIndex: Int?

    var body: some View {
        GeometryReader { geometry in
            let gridDimensions = visibleGridDimensions
            let totalGridSpacing = mainGridButtonSpacing * CGFloat(max(gridDimensions.rows - 1, 0))
            let availableGridHeight = geometry.size.height.isFinite ? max(0, geometry.size.height - totalGridSpacing - (reservedBottomInset-30)) : 0
            let buttonHeight = availableGridHeight / CGFloat(max(gridDimensions.rows, 1))
            let totalColumnSpacing = mainGridButtonSpacing * CGFloat(max(gridDimensions.columns - 1, 0))
            let safeAvailableWidth = availableWidth.isFinite ? max(0, availableWidth) : 0
            let availableGridWidth = max(0, safeAvailableWidth - totalColumnSpacing)
            let buttonWidth = availableGridWidth / CGFloat(max(gridDimensions.columns, 1))
            let visibleEntries = Array(functionKeys.prefix(visibleBoxCount).enumerated())
            let visualGridHeight = renderedButtonGridVisualHeight(
                visibleEntries: visibleEntries,
                buttonWidth: buttonWidth,
                buttonHeight: buttonHeight,
                spacing: mainGridButtonSpacing,
                gridDimensions: gridDimensions,
                containerHeight: geometry.size.height
            )

            ZStack(alignment: .topLeading) {
                ForEach(visibleEntries, id: \.offset) { index, entry in
                    if isButtonContinuationEntry(entry) {
                        EmptyView()
                    } else {
                        let shape = buttonShape(startingAt: index, gridDimensions: gridDimensions)
                        let resolvedButtonWidth = resolvedWidth(
                            buttonWidth: buttonWidth,
                            spacing: mainGridButtonSpacing,
                            span: shape.width
                        )
                        let resolvedButtonHeight = resolvedHeight(
                            buttonHeight: buttonHeight,
                            spacing: mainGridButtonSpacing,
                            span: shape.height
                        )
                        let origin = buttonOrigin(
                            index: index,
                            buttonWidth: buttonWidth,
                            buttonHeight: buttonHeight,
                            spacing: mainGridButtonSpacing,
                            gridDimensions: gridDimensions
                        )

                        gridButtonView(
                            entry: entry,
                            index: index,
                            buttonHeight: resolvedButtonHeight,
                            buttonSize: CGSize(width: resolvedButtonWidth, height: resolvedButtonHeight),
                            buttonFrame: CGRect(
                                x: origin.x,
                                y: origin.y,
                                width: resolvedButtonWidth,
                                height: resolvedButtonHeight
                            ),
                            gridDimensions: gridDimensions
                        )
                        .frame(width: resolvedButtonWidth, height: resolvedButtonHeight)
                        .modifier(MainGridButtonBoundsClip(cornerRadius: mainGridButtonCornerRadius, isEnabled: clipsButtonContentToBounds))
                        .overlay {
                            if selectedActionMenuIndex == index {
                                RoundedRectangle(cornerRadius: mainGridButtonCornerRadius)
                                    .strokeBorder(Color.white, lineWidth: 2)
                                    .allowsHitTesting(false)
                            }
                        }
                        .position(
                            x: origin.x + (resolvedButtonWidth / 2),
                            y: origin.y + (resolvedButtonHeight / 2)
                        )
                        .task(id: renderedButtonFrameTaskID(
                            index: index,
                            buttonFrame: CGRect(
                                x: origin.x,
                                y: origin.y,
                                width: resolvedButtonWidth,
                                height: resolvedButtonHeight
                            ),
                            gridDimensions: gridDimensions,
                            refreshToken: renderedButtonFrameRefreshToken
                        )) {
                            onRenderedButtonFrame(
                                index,
                                CGRect(
                                    x: origin.x,
                                    y: origin.y,
                                    width: resolvedButtonWidth,
                                    height: resolvedButtonHeight
                                ),
                                gridDimensions
                            )
                        }
                    }
                }
            }
            .frame(width: safeAvailableWidth, height: geometry.size.height, alignment: .topLeading)
            .task(id: renderedGridFrameTaskID(
                width: safeAvailableWidth,
                height: visualGridHeight
            )) {
                onRenderedGridFrame(CGRect(
                    x: 0,
                    y: 0,
                    width: safeAvailableWidth,
                    height: visualGridHeight
                ))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDisappear {
            longPressedEditIndex = nil
        }
    }

    private func isWideButtonContinuationEntry(_ entry: FunctionKeyEntry) -> Bool {
        entry.rawLine.trimmingCharacters(in: .whitespacesAndNewlines) == wideButtonContinuationToken
    }

    private func isBlockButtonContinuationEntry(_ entry: FunctionKeyEntry) -> Bool {
        entry.rawLine.trimmingCharacters(in: .whitespacesAndNewlines) == blockButtonContinuationToken
    }

    private func isButtonContinuationEntry(_ entry: FunctionKeyEntry) -> Bool {
        isWideButtonContinuationEntry(entry) || isBlockButtonContinuationEntry(entry)
    }

    private struct ButtonGridShape {
        let width: Int
        let height: Int
    }

    private func buttonShape(startingAt index: Int, gridDimensions: GridDimensions) -> ButtonGridShape {
        guard functionKeys.indices.contains(index),
              !isButtonContinuationEntry(functionKeys[index]) else {
            return ButtonGridShape(width: 1, height: 1)
        }

        let candidateShapes = [
            ButtonGridShape(width: 3, height: 3),
            ButtonGridShape(width: 3, height: 2),
            ButtonGridShape(width: 2, height: 2),
            ButtonGridShape(width: 1, height: 3),
            ButtonGridShape(width: 3, height: 1),
            ButtonGridShape(width: 1, height: 2),
            ButtonGridShape(width: 2, height: 1)
        ]

        for shape in candidateShapes where shapeFits(shape, startingAt: index, gridDimensions: gridDimensions) &&
            continuationTokensMatch(startingAt: index, shape: shape, gridDimensions: gridDimensions) {
            return shape
        }

        return ButtonGridShape(width: 1, height: 1)
    }

    private func shapeFits(_ shape: ButtonGridShape, startingAt index: Int, gridDimensions: GridDimensions) -> Bool {
        let columns = max(gridDimensions.columns, 1)
        let startColumn = index % columns
        let startRow = index / columns

        return index >= 0 &&
            startColumn + shape.width <= columns &&
            startRow + shape.height <= gridDimensions.rows
    }

    private func continuationTokensMatch(startingAt index: Int, shape: ButtonGridShape, gridDimensions: GridDimensions) -> Bool {
        let columns = max(gridDimensions.columns, 1)

        for rowOffset in 0..<shape.height {
            for columnOffset in 0..<shape.width {
                guard rowOffset != 0 || columnOffset != 0 else {
                    continue
                }

                let slotIndex = index + (rowOffset * columns) + columnOffset
                let token = rowOffset == 0 ? wideButtonContinuationToken : blockButtonContinuationToken
                guard functionKeys.indices.contains(slotIndex),
                      slotIndex < visibleBoxCount,
                      functionKeys[slotIndex].rawLine.trimmingCharacters(in: .whitespacesAndNewlines) == token else {
                    return false
                }
            }
        }

        return true
    }

    private func resolvedWidth(buttonWidth: CGFloat, spacing: CGFloat, span: Int) -> CGFloat {
        let boundedSpan = max(1, min(span, 3))
        return (buttonWidth * CGFloat(boundedSpan)) + (spacing * CGFloat(boundedSpan - 1))
    }

    private func resolvedHeight(buttonHeight: CGFloat, spacing: CGFloat, span: Int) -> CGFloat {
        let boundedSpan = max(1, min(span, 3))
        return (buttonHeight * CGFloat(boundedSpan)) + (spacing * CGFloat(boundedSpan - 1))
    }

    private func buttonOrigin(
        index: Int,
        buttonWidth: CGFloat,
        buttonHeight: CGFloat,
        spacing: CGFloat,
        gridDimensions: GridDimensions
    ) -> CGPoint {
        let columns = max(gridDimensions.columns, 1)
        let row = index / columns
        let column = index % columns

        return CGPoint(
            x: CGFloat(column) * (buttonWidth + spacing),
            y: CGFloat(row) * (buttonHeight + spacing)
        )
    }

    private func renderedButtonGridVisualHeight(
        visibleEntries: [(offset: Int, element: FunctionKeyEntry)],
        buttonWidth: CGFloat,
        buttonHeight: CGFloat,
        spacing: CGFloat,
        gridDimensions: GridDimensions,
        containerHeight: CGFloat
    ) -> CGFloat {
        let visualMaxY = visibleEntries.reduce(CGFloat.zero) { currentMaxY, visibleEntry in
            guard !isButtonContinuationEntry(visibleEntry.element) else {
                return currentMaxY
            }

            let shape = buttonShape(startingAt: visibleEntry.offset, gridDimensions: gridDimensions)
            let origin = buttonOrigin(
                index: visibleEntry.offset,
                buttonWidth: buttonWidth,
                buttonHeight: buttonHeight,
                spacing: spacing,
                gridDimensions: gridDimensions
            )
            let resolvedButtonHeight = resolvedHeight(
                buttonHeight: buttonHeight,
                spacing: spacing,
                span: shape.height
            )

            return max(currentMaxY, origin.y + resolvedButtonHeight)
        }

        return visualMaxY > 0 ? visualMaxY : containerHeight
    }

    private func renderedButtonFrameTaskID(
        index: Int,
        buttonFrame: CGRect,
        gridDimensions: GridDimensions,
        refreshToken: Int
    ) -> String {
        "\(index)-\(buttonFrame.minX)-\(buttonFrame.minY)-\(buttonFrame.width)-\(buttonFrame.height)-\(gridDimensions.columns)-\(gridDimensions.rows)-\(refreshToken)"
    }

    private func renderedGridFrameTaskID(width: CGFloat, height: CGFloat) -> String {
        "\(width)-\(height)"
    }

    @ViewBuilder
    private func gridButtonView(
        entry: FunctionKeyEntry,
        index: Int,
        buttonHeight: CGFloat,
        buttonSize: CGSize,
        buttonFrame: CGRect,
        gridDimensions: GridDimensions
    ) -> some View {
        if !isGridEditModeEnabled && isSimpleOrdinarySoundEntry(entry) {
            buttonLabel(entry, index, buttonHeight, buttonSize)
                .contentShape(Rectangle())
                .gesture(
                    TapGesture(count: 2)
                        .exclusively(before: TapGesture(count: 1))
                        .onEnded { gesture in
                            guard longPressedEditIndex != index else {
                                longPressedEditIndex = nil
                                return
                            }

                            onButtonClick()

                            guard bleSendEnabled else {
                                return
                            }

                            switch gesture {
                            case .first:
                                onSimpleOrdinarySoundDoubleTap(entry, index)
                            case .second:
                                onSimpleOrdinarySoundSingleTap(entry, index)
                            }
                        }
                )
        } else if !isGridEditModeEnabled && isInteractiveWidgetEntry(entry) {
            buttonLabel(entry, index, buttonHeight, buttonSize)
                .contentShape(Rectangle())
        } else if !isGridEditModeEnabled, let midiNote = midiNoteNumber(entry) {
            ZStack {
                buttonLabel(entry, index, buttonHeight, buttonSize)
                    .allowsHitTesting(false)

                MIDITouchView(
                    note: midiNote,
                    isEnabled: scenePhase == .active,
                    onDown: onMIDITouchDown,
                    onUp: onMIDITouchUp
                )
            }
        } else {
            editingGestures(
                Button {
                    guard longPressedEditIndex != index else {
                        longPressedEditIndex = nil
                        return
                    }

                    guard !isGridEditModeEnabled else {
                        return
                    }

                    onButtonClick()

                    guard bleSendEnabled else {
                        return
                    }

                    sendLine(entry)
                } label: {
                    buttonLabel(entry, index, buttonHeight, buttonSize)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle()),
                entry: entry,
                index: index,
                buttonFrame: buttonFrame,
                gridDimensions: gridDimensions
            )
        }
    }

    @ViewBuilder
    private func editingGestures<Content: View>(
        _ content: Content,
        entry: FunctionKeyEntry,
        index: Int,
        buttonFrame: CGRect,
        gridDimensions: GridDimensions
    ) -> some View {
        if isGridEditModeEnabled {
            content
                .simultaneousGesture(dragGesture(entry, index, gridDimensions))
                .simultaneousGesture(
                    TapGesture()
                        .onEnded {
                            onSingleEditTap(entry, index, buttonFrame, gridDimensions)
                        }
                )
                .simultaneousGesture(
                    slotEditorLongPressGesture(index: index)
                )
        } else {
            content
        }
    }

    private func slotEditorLongPressGesture(index: Int) -> some Gesture {
        LongPressGesture(minimumDuration: 0.25)
            .onEnded { _ in
                guard isGridEditModeEnabled else {
                    return
                }

                longPressedEditIndex = index
                onBeginSlotEditing(index)
            }
    }
}

private struct MIDITouchView: UIViewRepresentable {
    let note: Int
    let isEnabled: Bool
    let onDown: (Int) -> Void
    let onUp: (Int) -> Void

    func makeUIView(context: Context) -> MIDITouchCaptureView {
        MIDITouchCaptureView()
    }

    func updateUIView(_ uiView: MIDITouchCaptureView, context: Context) {
        uiView.configure(note: note, isEnabled: isEnabled, onDown: onDown, onUp: onUp)
    }

    static func dismantleUIView(_ uiView: MIDITouchCaptureView, coordinator: ()) {
        uiView.cancelActiveTouch()
    }
}

private final class MIDITouchCaptureView: UIView {
    private var note: Int?
    private var onDown: ((Int) -> Void)?
    private var onUp: ((Int) -> Void)?
    private var activeTouch: UITouch?
    private var activeNote: Int?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isMultipleTouchEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        note: Int,
        isEnabled: Bool,
        onDown: @escaping (Int) -> Void,
        onUp: @escaping (Int) -> Void
    ) {
        if activeNote != nil && (self.note != note || !isEnabled) {
            cancelActiveTouch()
        }

        self.note = note
        self.onDown = onDown
        self.onUp = onUp
        isUserInteractionEnabled = isEnabled
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard activeTouch == nil,
              let touch = touches.first,
              let note else {
            return
        }

        activeTouch = touch
        activeNote = note
        print("🐞 [MIDI-TOUCH] DOWN note=\(note)")
        onDown?(note)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let activeTouch,
              touches.contains(where: { $0 === activeTouch }),
              !bounds.contains(activeTouch.location(in: self)) else {
            return
        }

        cancelActiveTouch()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let activeTouch,
              touches.contains(where: { $0 === activeTouch }),
              let activeNote else {
            return
        }

        let endedInside = bounds.contains(activeTouch.location(in: self))
        if endedInside {
            print("🐞 [MIDI-TOUCH] UP note=\(activeNote)")
        } else {
            print("🐞 [MIDI-TOUCH] CANCEL note=\(activeNote)")
        }
        onUp?(activeNote)
        self.activeTouch = nil
        self.activeNote = nil
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let activeTouch,
              touches.contains(where: { $0 === activeTouch }) else {
            return
        }

        cancelActiveTouch()
    }

    func cancelActiveTouch() {
        guard let activeNote else {
            return
        }

        print("🐞 [MIDI-TOUCH] CANCEL note=\(activeNote)")
        onUp?(activeNote)
        activeTouch = nil
        self.activeNote = nil
    }
}

private struct MainGridButtonBoundsClip: ViewModifier {
    let cornerRadius: CGFloat
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content.clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            content
        }
    }
}
