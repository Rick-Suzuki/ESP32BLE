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
    let onDeleteSlot: (FunctionKeyEntry, Int) -> Void
    @State private var pendingTapIndex: Int?
    @State private var pendingTapCount = 0
    @State private var pendingTapTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { geometry in
            let gridDimensions = visibleGridDimensions
            let totalGridSpacing = mainGridButtonSpacing * CGFloat(max(gridDimensions.rows - 1, 0))
            let availableGridHeight = geometry.size.height.isFinite ? max(0, geometry.size.height - totalGridSpacing - reservedBottomInset) : 0
            let buttonHeight = availableGridHeight / CGFloat(max(gridDimensions.rows, 1))
            let totalColumnSpacing = mainGridButtonSpacing * CGFloat(max(gridDimensions.columns - 1, 0))
            let safeAvailableWidth = availableWidth.isFinite ? max(0, availableWidth) : 0
            let availableGridWidth = max(0, safeAvailableWidth - totalColumnSpacing)
            let buttonWidth = availableGridWidth / CGFloat(max(gridDimensions.columns, 1))
            let columns = Array(
                repeating: GridItem(.fixed(buttonWidth), spacing: mainGridButtonSpacing),
                count: gridDimensions.columns
            )
            let visibleEntries = Array(functionKeys.prefix(visibleBoxCount).enumerated())

            LazyVGrid(columns: columns, spacing: mainGridButtonSpacing) {
                ForEach(visibleEntries, id: \.offset) { index, entry in
                    if isWideButtonContinuationEntry(entry) {
                        Color.clear
                            .frame(width: buttonWidth, height: buttonHeight)
                    } else if !isGridEditModeEnabled && isInteractiveWidgetEntry(entry) {
                        let buttonSpan = wideButtonSpan(startingAt: index, gridDimensions: gridDimensions)
                        let resolvedButtonWidth = resolvedWidth(
                            buttonWidth: buttonWidth,
                            spacing: mainGridButtonSpacing,
                            span: buttonSpan
                        )

                        buttonLabel(entry, index, buttonHeight)
                            .frame(width: resolvedButtonWidth, height: buttonHeight)
                            .offset(x: wideButtonOffset(buttonWidth: buttonWidth, spacing: mainGridButtonSpacing, span: buttonSpan))
                            .contentShape(Rectangle())
                            .simultaneousGesture(dragGesture(entry, index, gridDimensions))
                            .zIndex(buttonSpan > 1 ? 1 : 0)
                    } else {
                        let buttonSpan = wideButtonSpan(startingAt: index, gridDimensions: gridDimensions)
                        let resolvedButtonWidth = resolvedWidth(
                            buttonWidth: buttonWidth,
                            spacing: mainGridButtonSpacing,
                            span: buttonSpan
                        )

                        Button {
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
                        .frame(width: resolvedButtonWidth, height: buttonHeight)
                        .offset(x: wideButtonOffset(buttonWidth: buttonWidth, spacing: mainGridButtonSpacing, span: buttonSpan))
                        .contentShape(Rectangle())
                        .simultaneousGesture(dragGesture(entry, index, gridDimensions))
                        .simultaneousGesture(
                            TapGesture()
                                .onEnded {
                                    guard isGridEditModeEnabled else {
                                        return
                                    }

                                    registerEditTap(
                                        entry: entry,
                                        index: index,
                                        gridDimensions: gridDimensions
                                    )
                                }
                        )
                        .simultaneousGesture(
                            LongPressGesture(minimumDuration: 0.4)
                                .onEnded { _ in
                                    guard isGridEditModeEnabled else {
                                        return
                                    }

                                    onBeginSlotEditing(index)
                                }
                        )
                        .zIndex(buttonSpan > 1 ? 1 : 0)
                    }
                }
            }
            .frame(width: safeAvailableWidth, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDisappear {
            pendingTapTask?.cancel()
        }
    }

    private func registerEditTap(
        entry: FunctionKeyEntry,
        index: Int,
        gridDimensions: GridDimensions
    ) {
        if pendingTapIndex == index {
            pendingTapCount += 1
        } else {
            pendingTapTask?.cancel()
            pendingTapIndex = index
            pendingTapCount = 1
        }

        guard pendingTapCount < 4 else {
            pendingTapTask?.cancel()
            resetPendingTapState()
            onDeleteSlot(entry, index)
            return
        }

        schedulePendingTapResolution(entry: entry, index: index, gridDimensions: gridDimensions)
    }

    private func schedulePendingTapResolution(
        entry: FunctionKeyEntry,
        index: Int,
        gridDimensions: GridDimensions
    ) {
        pendingTapTask?.cancel()
        let tapCount = pendingTapCount

        pendingTapTask = Task {
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                guard pendingTapIndex == index, pendingTapCount == tapCount else {
                    return
                }

				if tapCount == 1 {
					onCopyPasteSlot(entry, index)
				}
				
                if tapCount == 2 {
                    onDuplicateSlot(entry, index, gridDimensions)
                }

                if tapCount == 3 {
                    onResizeSlot(entry, index, gridDimensions)
                }

				
				
                resetPendingTapState()
            }
        }
    }

    private func resetPendingTapState() {
        pendingTapTask = nil
        pendingTapIndex = nil
        pendingTapCount = 0
    }

    private func isWideButtonContinuationEntry(_ entry: FunctionKeyEntry) -> Bool {
        entry.rawLine.trimmingCharacters(in: .whitespacesAndNewlines) == wideButtonContinuationToken
    }

    private func wideButtonSpan(startingAt index: Int, gridDimensions: GridDimensions) -> Int {
        guard functionKeys.indices.contains(index),
              !isWideButtonContinuationEntry(functionKeys[index]) else {
            return 1
        }

        let row = index / max(gridDimensions.columns, 1)
        var span = 1

        while span < 3 {
            let nextIndex = index + span
            guard functionKeys.indices.contains(nextIndex),
                  nextIndex < visibleBoxCount,
                  nextIndex / max(gridDimensions.columns, 1) == row,
                  isWideButtonContinuationEntry(functionKeys[nextIndex]) else {
                break
            }

            span += 1
        }

        return span
    }

    private func resolvedWidth(buttonWidth: CGFloat, spacing: CGFloat, span: Int) -> CGFloat {
        let boundedSpan = max(1, min(span, 3))
        return (buttonWidth * CGFloat(boundedSpan)) + (spacing * CGFloat(boundedSpan - 1))
    }

    private func wideButtonOffset(buttonWidth: CGFloat, spacing: CGFloat, span: Int) -> CGFloat {
        let boundedSpan = max(1, min(span, 3))
        guard boundedSpan > 1 else {
            return 0
        }

        return ((buttonWidth + spacing) * CGFloat(boundedSpan - 1)) / 2
    }
}
