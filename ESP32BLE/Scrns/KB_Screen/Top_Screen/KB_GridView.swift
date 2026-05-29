import SwiftUI

struct KeyboardGridView: View {
    let rows: [[KeyboardCell]]
    let columnCount: Int
    let gridKeySpacing: CGFloat
    let gridRowHeightScale: CGFloat
    let gridKeyFontSize: CGFloat
    let gridKeyCornerRadius: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let rowCount = rows.count
            let totalSpacing = gridKeySpacing * CGFloat(rowCount - 1)
            let totalHorizontalSpacing = gridKeySpacing * CGFloat(max(columnCount - 1, 0))
            let safeGridHeight = geometry.size.height.isFinite ? max(0, geometry.size.height - totalSpacing) : 0
            let availableRowHeight = floor(safeGridHeight / CGFloat(rowCount))
            let rowHeight = max(32, floor(availableRowHeight * gridRowHeightScale))
            let availableGridWidth = geometry.size.width.isFinite
                ? max(0, geometry.size.width - totalHorizontalSpacing)
                : 0
            let unitWidth = columnCount > 0 ? floor(availableGridWidth / CGFloat(columnCount)) : 0

            VStack(spacing: gridKeySpacing) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: gridKeySpacing) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            let cellWidth = max(0, (unitWidth * CGFloat(cell.widthUnits)) + (gridKeySpacing * CGFloat(cell.widthUnits - 1)))

                            KeyboardGridCellView(
                                cell: cell,
                                gridKeyFontSize: gridKeyFontSize,
                                gridKeyCornerRadius: gridKeyCornerRadius,
                                cellWidth: cellWidth
                            ) {
                                cell.action()
                            }
                        }
                    }
                    .frame(height: rowHeight)
                }
            }
            .padding(.vertical, gridKeySpacing)
            .background(Color.black)
        }
    }
}
