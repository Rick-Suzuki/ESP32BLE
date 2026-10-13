import SwiftUI

struct MainGridEditActionMenu: View {
    enum Metrics {
        static let menuSize = CGSize(width: 146, height: 146)
        static let buttonSize: CGFloat = 44
        static let spacing: CGFloat = 2
        static let cornerRadius: CGFloat = 14
        static let borderWidth: CGFloat = 2
    }

    enum SymbolColor {
        static let close = Color(white: 0.45)
        static let edit = Color.cyan
        static let undo = Color(red: 1.0, green: 0.68, blue: 0.18)
        static let copy = Color.white
        static let cut = Color.orange
        static let paste = Color.green
        static let duplicate = Color.yellow
        static let resize = Color.purple
        static let delete = Color.red
    }

    let cornerRadius: CGFloat
    let isUndoAvailable: Bool
    let isRedoAvailable: Bool
    let isButtonOperationAvailable: Bool
    let isPasteAvailable: Bool
    let onEdit: () -> Void
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onCopy: () -> Void
    let onCut: () -> Void
    let onPaste: () -> Void
    let onDuplicate: () -> Void
    let onResize: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: Metrics.spacing) {
            HStack(spacing: Metrics.spacing) {
                menuButton(systemName: "pencil", accessibilityLabel: "Edit button", foregroundColor: SymbolColor.edit, action: onEdit)
                menuButton(systemName: "arrow.uturn.backward", accessibilityLabel: "Undo", foregroundColor: SymbolColor.undo, isEnabled: isUndoAvailable, action: onUndo)
                menuButton(systemName: "arrow.uturn.forward", accessibilityLabel: "Redo", foregroundColor: SymbolColor.undo, isEnabled: isRedoAvailable, action: onRedo)
            }

            HStack(spacing: Metrics.spacing) {
                menuButton(systemName: "doc.on.doc", accessibilityLabel: "Copy button", foregroundColor: SymbolColor.copy, isEnabled: isButtonOperationAvailable, action: onCopy)
                menuButton(systemName: "scissors", accessibilityLabel: "Cut button", foregroundColor: SymbolColor.cut, isEnabled: isButtonOperationAvailable, action: onCut)
                menuButton(systemName: "doc.on.clipboard", accessibilityLabel: "Paste button", foregroundColor: SymbolColor.paste, isEnabled: isPasteAvailable, action: onPaste)
            }

            HStack(spacing: Metrics.spacing) {
                menuButton(systemName: "plus.square.on.square", accessibilityLabel: "Duplicate button", foregroundColor: SymbolColor.duplicate, isEnabled: isButtonOperationAvailable, action: onDuplicate)
                menuButton(systemName: "arrow.up.left.and.arrow.down.right", accessibilityLabel: "Resize button", foregroundColor: SymbolColor.resize, isEnabled: isButtonOperationAvailable, action: onResize)
                menuButton(systemName: "trash", accessibilityLabel: "Delete button", foregroundColor: SymbolColor.delete, isEnabled: isButtonOperationAvailable, action: onDelete)
            }
        }
        .padding(5)
        .background(Color.black)
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(Color.white, lineWidth: Metrics.borderWidth)
        }
        .clipShape(.rect(cornerRadius: cornerRadius))
        .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 3)
    }

    private func menuButton(
        systemName: String,
        accessibilityLabel: String,
        foregroundColor: Color,
        isEnabled: Bool = true,
        action: @escaping () -> Void = {}
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(isEnabled ? foregroundColor : SymbolColor.close)
                .frame(width: Metrics.buttonSize, height: Metrics.buttonSize)
                .background(Color.white.opacity(0.13))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct MainGridResizeActionMenu: View {
    private let rows: [[MainGridPopupButtonShape?]] = [
        [nil, MainGridPopupButtonShape(width: 1, height: 1), MainGridPopupButtonShape(width: 2, height: 1)],
        [MainGridPopupButtonShape(width: 3, height: 1), MainGridPopupButtonShape(width: 1, height: 2), MainGridPopupButtonShape(width: 2, height: 2)],
        [MainGridPopupButtonShape(width: 3, height: 2), MainGridPopupButtonShape(width: 1, height: 3), MainGridPopupButtonShape(width: 3, height: 3)]
    ]

    let cornerRadius: CGFloat
    let selectedShape: MainGridPopupButtonShape?
    let isShapeEnabled: (MainGridPopupButtonShape) -> Bool
    let onCancel: () -> Void
    let onSelectShape: (MainGridPopupButtonShape) -> Void

    var body: some View {
        VStack(spacing: MainGridEditActionMenu.Metrics.spacing) {
            ForEach(rows.indices, id: \.self) { rowIndex in
                HStack(spacing: MainGridEditActionMenu.Metrics.spacing) {
                    ForEach(rows[rowIndex].indices, id: \.self) { columnIndex in
                        if let shape = rows[rowIndex][columnIndex] {
                            shapeButton(shape)
                        } else {
                            cancelButton
                        }
                    }
                }
            }
        }
        .padding(5)
        .background(Color.black)
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(Color.white, lineWidth: MainGridEditActionMenu.Metrics.borderWidth)
        }
        .clipShape(.rect(cornerRadius: cornerRadius))
        .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 3)
    }

    private var cancelButton: some View {
        Button(action: onCancel) {
            Image(systemName: "xmark")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(MainGridEditActionMenu.SymbolColor.close)
                .frame(width: MainGridEditActionMenu.Metrics.buttonSize, height: MainGridEditActionMenu.Metrics.buttonSize)
                .background(Color.white.opacity(0.13))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back to action menu")
    }

    private func shapeButton(_ shape: MainGridPopupButtonShape) -> some View {
        let isSelected = selectedShape == shape
        let isEnabled = isShapeEnabled(shape)
        let foregroundColor = isEnabled ? Color.white : MainGridEditActionMenu.SymbolColor.close
        let diagramColor = isEnabled ? MainGridEditActionMenu.SymbolColor.resize : MainGridEditActionMenu.SymbolColor.close

        return Button {
            onSelectShape(shape)
        } label: {
            VStack(spacing: 2) {
                shapeDiagram(shape, color: diagramColor)
                Text(shape.label)
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(foregroundColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(width: MainGridEditActionMenu.Metrics.buttonSize, height: MainGridEditActionMenu.Metrics.buttonSize)
            .background(isSelected ? MainGridEditActionMenu.SymbolColor.resize.opacity(0.34) : Color.white.opacity(0.13))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(MainGridEditActionMenu.SymbolColor.resize, lineWidth: 1.5)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel("Resize to \(shape.label)")
    }

    private func shapeDiagram(_ shape: MainGridPopupButtonShape, color: Color) -> some View {
        let gap: CGFloat = 1.5
        let maxWidth: CGFloat = 22
        let maxHeight: CGFloat = 18
        let cellSize = min(
            (maxWidth - (CGFloat(shape.width - 1) * gap)) / CGFloat(shape.width),
            (maxHeight - (CGFloat(shape.height - 1) * gap)) / CGFloat(shape.height)
        )
        let resolvedCellSize = shape.width == 1 && shape.height == 1 ? min(cellSize, 5) : cellSize

        return VStack(spacing: gap) {
            ForEach(0..<shape.height, id: \.self) { _ in
                HStack(spacing: gap) {
                    ForEach(0..<shape.width, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 1.2)
                            .fill(color)
                            .frame(width: resolvedCellSize, height: resolvedCellSize)
                    }
                }
            }
        }
        .frame(width: maxWidth, height: maxHeight)
    }
}
