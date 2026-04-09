import SwiftUI

struct MainScreenGridSection: View {
    let functionKeys: [FunctionKeyEntry]
    let visibleBoxCount: Int
    let mainGridButtonSpacing: CGFloat
    let isGridEditModeEnabled: Bool
    let bleSendEnabled: Bool
    let onButtonClick: () -> Void
    let sendLine: (FunctionKeyEntry) -> Void
    let onBeginSlotEditing: (Int) -> Void
    let buttonLabel: (FunctionKeyEntry, Int, CGFloat) -> AnyView
    let dragGesture: (FunctionKeyEntry, Int, GridDimensions) -> AnyGesture<Void>

    var body: some View {
        GeometryReader { geometry in
            let gridDimensions = gridDimensions(for: visibleBoxCount)
            let columns = Array(
                repeating: GridItem(.flexible(), spacing: mainGridButtonSpacing),
                count: gridDimensions.columns
            )
            let totalGridSpacing = mainGridButtonSpacing * CGFloat(max(gridDimensions.rows - 1, 0))
            let availableGridHeight = geometry.size.height.isFinite ? max(0, geometry.size.height - totalGridSpacing) : 0
            let buttonHeight = availableGridHeight / CGFloat(max(gridDimensions.rows, 1))
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
            .background(Color.black)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func gridDimensions(for count: Int) -> GridDimensions {
        switch count {
        case ...1:
            return GridDimensions(columns: 1, rows: 1)
        case 2:
            return GridDimensions(columns: 2, rows: 1)
        case 3...4:
            return GridDimensions(columns: 2, rows: 2)
        case 5...6:
            return GridDimensions(columns: 3, rows: 2)
        case 7...9:
            return GridDimensions(columns: 3, rows: 3)
        case 10...12:
            return GridDimensions(columns: 4, rows: 3)
        case 13...16:
            return GridDimensions(columns: 4, rows: 4)
        case 17...20:
            return GridDimensions(columns: 5, rows: 4)
        case 21...24:
            return GridDimensions(columns: 6, rows: 4)
        case 25...28:
            return GridDimensions(columns: 7, rows: 4)
        case 29...32:
            return GridDimensions(columns: 8, rows: 4)
        case 33...36:
            return GridDimensions(columns: 9, rows: 4)
        case 37...40:
            return GridDimensions(columns: 10, rows: 4)
        case 41...45:
            return GridDimensions(columns: 9, rows: 5)
        case 46...50:
            return GridDimensions(columns: 10, rows: 5)
        case 51...56:
            return GridDimensions(columns: 8, rows: 7)
        case 57...64:
            return GridDimensions(columns: 8, rows: 8)
        case 65...72:
            return GridDimensions(columns: 9, rows: 8)
        case 73...81:
            return GridDimensions(columns: 9, rows: 9)
        case 82...90:
            return GridDimensions(columns: 10, rows: 9)
        default:
            return GridDimensions(columns: 10, rows: 10)
        }
    }
}
