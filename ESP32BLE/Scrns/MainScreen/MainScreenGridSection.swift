import SwiftUI

typealias GridDimensions = (columns: Int, rows: Int)

func functionKeyGridDimensions(for itemCount: Int) -> GridDimensions {
    let preferredDimensions: [Int: GridDimensions] = [
        15: (5, 3),
        18: (6, 3),
        24: (6, 4),
        28: (7, 4),
        32: (8, 4),
        40: (8, 5),
        45: (9, 5),
        48: (8, 6),
        50: (10, 5),
        54: (9, 6),
        60: (10, 6),
        63: (9, 7),
        70: (10, 7),
        80: (10, 8),
        84: (12, 7),
        88: (11, 8),
        96: (12, 8),
        99: (11, 9)
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
    let functionKeys: [FunctionKeyEntry]
    let visibleBoxCount: Int
    let mainGridButtonSpacing: CGFloat
    let isGridEditModeEnabled: Bool
    let bleSendEnabled: Bool
    let onButtonClick: () -> Void
    let sendLine: (FunctionKeyEntry) -> Void
    let onBeginSlotEditing: (Int) -> Void
    let buttonLabel: (FunctionKeyEntry, Int, CGFloat) -> AnyView
    let dragGesture: (FunctionKeyEntry, Int, GridDimensions) -> AnyGesture<DragGesture.Value>

    var body: some View {
        GeometryReader { geometry in
            let gridDimensions = functionKeyGridDimensions(for: visibleBoxCount)
            let totalGridSpacing = mainGridButtonSpacing * CGFloat(max(gridDimensions.rows - 1, 0))
            let availableGridHeight = geometry.size.height.isFinite ? max(0, geometry.size.height - totalGridSpacing) : 0
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
                    .frame(width: buttonWidth, height: buttonHeight)
                    .contentShape(Rectangle())
                    .simultaneousGesture(dragGesture(entry, index, gridDimensions))
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.4)
                            .onEnded { _ in
                                guard isGridEditModeEnabled else {
                                    return
                                }

                                onBeginSlotEditing(index)
                            }
                    )
                }
            }
            .frame(width: safeAvailableWidth, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
