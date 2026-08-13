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

struct MainScreenGridSection: View {
    let availableWidth: CGFloat
    let reservedBottomInset: CGFloat
    let functionKeys: [FunctionKeyEntry]
    let visibleBoxCount: Int
    let visibleGridDimensions: GridDimensions
    let mainGridButtonSpacing: CGFloat
    let isGridEditModeEnabled: Bool
    let bleSendEnabled: Bool
    let onButtonClick: () -> Void
    let isHiddenEntry: (FunctionKeyEntry) -> Bool
    let isInteractiveWidgetEntry: (FunctionKeyEntry) -> Bool
    let sendLine: (FunctionKeyEntry) -> Void
    let onBeginSlotEditing: (Int) -> Void
    let buttonLabel: (FunctionKeyEntry, Int, CGFloat) -> AnyView
    let dragGesture: (FunctionKeyEntry, Int, GridDimensions) -> AnyGesture<DragGesture.Value>
    let onDuplicateSlot: (FunctionKeyEntry, Int, GridDimensions) -> Void
    let onCopyPasteSlot: (FunctionKeyEntry, Int) -> Void
    let onResizeSlot: (FunctionKeyEntry, Int, GridDimensions) -> Void
    let onResetSlotSize: (FunctionKeyEntry, Int, GridDimensions) -> Void
    let onDeleteSlot: (FunctionKeyEntry, Int) -> Void
    @State private var pendingTapIndex: Int?
    @State private var pendingTapCount = 0
    @State private var pendingTapTask: Task<Void, Never>?
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
                            gridDimensions: gridDimensions
                        )
                        .frame(width: resolvedButtonWidth, height: resolvedButtonHeight)
                        .position(
                            x: origin.x + (resolvedButtonWidth / 2),
                            y: origin.y + (resolvedButtonHeight / 2)
                        )
                    }
                }
            }
            .frame(width: safeAvailableWidth, height: geometry.size.height, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDisappear {
            pendingTapTask?.cancel()
            longPressedEditIndex = nil
        }
    }

    private func registerEditTap(
        entry: FunctionKeyEntry,
        index: Int,
        gridDimensions: GridDimensions
    ) {
        let callbackStartTime = CFAbsoluteTimeGetCurrent()
        db("ENTER MainScreenGridSection.registerEditTap index=\(index) pendingTapIndex=\(String(describing: pendingTapIndex)) pendingTapCount=\(pendingTapCount)")
        if pendingTapIndex == index {
            pendingTapCount += 1
        } else {
            pendingTapTask?.cancel()
            pendingTapIndex = index
            pendingTapCount = 1
        }

        guard pendingTapCount < 5 else {
            pendingTapTask?.cancel()
            resetPendingTapState()
            db("ENTER MainScreenGridSection.registerEditTap onDeleteSlot")
            onDeleteSlot(entry, index)
            db("EXIT MainScreenGridSection.registerEditTap onDeleteSlot (\(scriptEditorProbeDurationMilliseconds(since: callbackStartTime)) ms)")
            return
        }

        schedulePendingTapResolution(entry: entry, index: index, gridDimensions: gridDimensions)
        db("EXIT MainScreenGridSection.registerEditTap pendingTapCount=\(pendingTapCount) (\(scriptEditorProbeDurationMilliseconds(since: callbackStartTime)) ms)")
    }

	// MARK: - BM:🟨 taps 1,2,3,4,5: main scrn
    private func schedulePendingTapResolution(
        entry: FunctionKeyEntry,
        index: Int,
        gridDimensions: GridDimensions
    ) {
        let callbackStartTime = CFAbsoluteTimeGetCurrent()
        db("ENTER MainScreenGridSection.schedulePendingTapResolution index=\(index)")
        pendingTapTask?.cancel()
        let tapCount = pendingTapCount

        db("SCHEDULED MainScreenGridSection.schedulePendingTapResolution Task tapCount=\(tapCount)")
        pendingTapTask = Task {
            db("EXECUTED MainScreenGridSection.schedulePendingTapResolution Task tapCount=\(tapCount)")
            try? await Task.sleep(for: .milliseconds(450))
            db("EXECUTED MainScreenGridSection.schedulePendingTapResolution Task sleep returned tapCount=\(tapCount)")
            guard !Task.isCancelled else {
                db("EXIT MainScreenGridSection.schedulePendingTapResolution Task cancelled")
                return
            }

            db("SCHEDULED MainScreenGridSection.schedulePendingTapResolution MainActor.run tapCount=\(tapCount)")
            await MainActor.run {
                let mainActorStartTime = CFAbsoluteTimeGetCurrent()
                db("EXECUTED MainScreenGridSection.schedulePendingTapResolution MainActor.run tapCount=\(tapCount)")
                guard pendingTapIndex == index, pendingTapCount == tapCount else {
                    db("EXIT MainScreenGridSection.schedulePendingTapResolution MainActor.run guard (\(scriptEditorProbeDurationMilliseconds(since: mainActorStartTime)) ms)")
                    return
                }

						if tapCount == 1 {
							db("ENTER MainScreenGridSection.schedulePendingTapResolution onCopyPasteSlot")
							onCopyPasteSlot(entry, index)
							db("EXIT MainScreenGridSection.schedulePendingTapResolution onCopyPasteSlot")
						}
						
                if tapCount == 2 {
                    db("ENTER MainScreenGridSection.schedulePendingTapResolution onDuplicateSlot")
                    onDuplicateSlot(entry, index, gridDimensions)
                    db("EXIT MainScreenGridSection.schedulePendingTapResolution onDuplicateSlot")
                }

                if tapCount == 3 {
                    db("ENTER MainScreenGridSection.schedulePendingTapResolution onResizeSlot")
                    onResizeSlot(entry, index, gridDimensions)
                    db("EXIT MainScreenGridSection.schedulePendingTapResolution onResizeSlot")
                }

                if tapCount == 4 {
                    db("ENTER MainScreenGridSection.schedulePendingTapResolution onResetSlotSize")
                    onResetSlotSize(entry, index, gridDimensions)
                    db("EXIT MainScreenGridSection.schedulePendingTapResolution onResetSlotSize")
                }

				db("\(tapCount)")
					
                resetPendingTapState()
                db("EXIT MainScreenGridSection.schedulePendingTapResolution MainActor.run (\(scriptEditorProbeDurationMilliseconds(since: mainActorStartTime)) ms)")
            }
            db("EXIT MainScreenGridSection.schedulePendingTapResolution Task")
        }
        db("EXIT MainScreenGridSection.schedulePendingTapResolution (\(scriptEditorProbeDurationMilliseconds(since: callbackStartTime)) ms)")
    }

    private func resetPendingTapState() {
        pendingTapTask = nil
        pendingTapIndex = nil
        pendingTapCount = 0
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

        let columns = max(gridDimensions.columns, 1)
        let hasRight = functionKeys.indices.contains(index + 1) &&
            index + 1 < visibleBoxCount &&
            isWideButtonContinuationEntry(functionKeys[index + 1])
        let hasBelow = functionKeys.indices.contains(index + columns) &&
            index + columns < visibleBoxCount &&
            isBlockButtonContinuationEntry(functionKeys[index + columns])
        let hasBelowRight = functionKeys.indices.contains(index + columns + 1) &&
            index + columns + 1 < visibleBoxCount &&
            isBlockButtonContinuationEntry(functionKeys[index + columns + 1])
        let hasSecondRight = functionKeys.indices.contains(index + 2) &&
            index + 2 < visibleBoxCount &&
            isWideButtonContinuationEntry(functionKeys[index + 2])
        let hasThreeByThreeBlock = (1...2).allSatisfy { rowOffset in
            (0...2).allSatisfy { columnOffset in
                let blockIndex = index + (rowOffset * columns) + columnOffset
                return functionKeys.indices.contains(blockIndex) &&
                    blockIndex < visibleBoxCount &&
                    isBlockButtonContinuationEntry(functionKeys[blockIndex])
            }
        }

        if hasRight && hasSecondRight && hasThreeByThreeBlock {
            return ButtonGridShape(width: 3, height: 3)
        }

        if hasRight && hasBelow && hasBelowRight {
            return ButtonGridShape(width: 2, height: 2)
        }

        if hasRight {
            return ButtonGridShape(width: hasSecondRight ? 3 : 2, height: 1)
        }

        return ButtonGridShape(width: 1, height: 1)
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

    @ViewBuilder
    private func gridButtonView(
        entry: FunctionKeyEntry,
        index: Int,
        buttonHeight: CGFloat,
        gridDimensions: GridDimensions
    ) -> some View {
        if !isGridEditModeEnabled && isInteractiveWidgetEntry(entry) {
            buttonLabel(entry, index, buttonHeight)
                .contentShape(Rectangle())
                .simultaneousGesture(dragGesture(entry, index, gridDimensions))
                .simultaneousGesture(slotEditorLongPressGesture(index: index))
        } else {
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
                buttonLabel(entry, index, buttonHeight)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .simultaneousGesture(dragGesture(entry, index, gridDimensions))
            .simultaneousGesture(
                TapGesture()
                    .onEnded {
                        let callbackStartTime = CFAbsoluteTimeGetCurrent()
                        db("ENTER MainScreenGridSection.TapGesture.onEnded index=\(index) isGridEditModeEnabled=\(isGridEditModeEnabled)")
                        guard isGridEditModeEnabled else {
                            db("EXIT MainScreenGridSection.TapGesture.onEnded non-edit (\(scriptEditorProbeDurationMilliseconds(since: callbackStartTime)) ms)")
                            return
                        }

                        registerEditTap(
                            entry: entry,
                            index: index,
                            gridDimensions: gridDimensions
                        )
                        db("EXIT MainScreenGridSection.TapGesture.onEnded (\(scriptEditorProbeDurationMilliseconds(since: callbackStartTime)) ms)")
                    }
            )
            .simultaneousGesture(
                slotEditorLongPressGesture(index: index)
            )
        }
    }

    private func slotEditorLongPressGesture(index: Int) -> some Gesture {
        LongPressGesture(minimumDuration: 0.4)
            .onEnded { _ in
                let callbackStartTime = CFAbsoluteTimeGetCurrent()
                scriptEditorProbeBeginSlotEditingStartTime = callbackStartTime
                db("\(scriptEditorProbeTimingPrefix()) ENTER MainScreenGridSection.LongPressGesture.onEnded index=\(index)")
                longPressedEditIndex = index
                db("\(scriptEditorProbeTimingPrefix()) ENTER MainScreenGridSection.LongPressGesture.onEnded onBeginSlotEditing")
                onBeginSlotEditing(index)
                db("\(scriptEditorProbeTimingPrefix()) EXIT MainScreenGridSection.LongPressGesture.onEnded onBeginSlotEditing (\(scriptEditorProbeDurationMilliseconds(since: callbackStartTime)) ms)")
                db("\(scriptEditorProbeTimingPrefix()) MainScreenGridSection.LongPressGesture.onEnded gesture completely finished")
                db("\(scriptEditorProbeTimingPrefix()) SCHEDULED MainScreenGridSection.LongPressGesture.onEnded DispatchQueue.main.async first runloop")
                DispatchQueue.main.async {
                    db("\(scriptEditorProbeTimingPrefix()) EXECUTED MainScreenGridSection.LongPressGesture.onEnded first runloop after long press")
                }
                let checkpointDelays: [Double] = [0.1, 0.25, 0.5, 1, 2, 3, 4]
                for checkpointDelay in checkpointDelays {
                    db("\(scriptEditorProbeTimingPrefix()) SCHEDULED MainScreenGridSection.LongPressGesture.onEnded asyncAfter \(checkpointDelay)s")
                    DispatchQueue.main.asyncAfter(deadline: .now() + checkpointDelay) {
                        db("\(scriptEditorProbeTimingPrefix()) EXECUTED MainScreenGridSection.LongPressGesture.onEnded \(checkpointDelay)s after long press")
                    }
                }
            }
    }
}
