import SwiftUI

extension MainScreen {
    func updateVisibleBoxCountToFitDefinedButtons() {
        let requiredBoxCount = max(definedFunctionKeyCount, 1)
        visibleBoxCount = allowedVisibleBoxCounts.first(where: { $0 >= requiredBoxCount }) ?? allowedVisibleBoxCounts.last ?? requiredBoxCount
    }

    func decreaseVisibleBoxCount() {
        guard let currentIndex = allowedVisibleBoxCounts.firstIndex(of: visibleBoxCount),
              currentIndex > 0 else {
            return
        }

        let nextCount = allowedVisibleBoxCounts[currentIndex - 1]

        if resizeVisibleBoxCount(nextCount) {
            visibleBoxCount = nextCount
        }
    }

    func increaseVisibleBoxCount() {
        guard let currentIndex = allowedVisibleBoxCounts.firstIndex(of: visibleBoxCount),
              currentIndex < allowedVisibleBoxCounts.count - 1 else {
            return
        }

        let nextCount = allowedVisibleBoxCounts[currentIndex + 1]

        if resizeVisibleBoxCount(nextCount) {
            visibleBoxCount = nextCount
        }
    }

    func decreaseBoxFontSize() {
        updateDocumentFontSize(max(minimumBoxFontSize, boxFontSize - 2))
    }

    func increaseBoxFontSize() {
        updateDocumentFontSize(min(maximumBoxFontSize, boxFontSize + 2))
    }

    func commitDocumentRename() {
        let proposedName = documentNameDraft

        if let alertMessage = renameDocument(proposedName) {
            renameAlertMessage = alertMessage
            return
        }

        documentNameDraft = selectedDocumentDisplayName
        isEditingDocumentName = false
    }

    func cancelDocumentRename() {
        documentNameDraft = selectedDocumentDisplayName
        isEditingDocumentName = false
        isDocumentNameFieldFocused = false
    }

    func beginSlotEditing(at index: Int) {
        guard index >= 0, index < visibleBoxCount else {
            return
        }

        activeDragIndex = nil
        editingSlotIndex = index
        editingSlotText = editableText(for: functionKeys[index])
        isSlotEditorFocused = true
    }

    func commitSlotEditing() {
        guard let editingSlotIndex else {
            return
        }

        _ = updateFunctionKeySlot(editingSlotIndex, editingSlotText)
        cancelSlotEditing()
    }

    func cancelSlotEditing() {
        editingSlotIndex = nil
        editingSlotText = ""
        isSlotEditorFocused = false
    }

    func targetIndexForEditDrag(
        from sourceIndex: Int,
        translation: CGSize,
        gridDimensions: GridDimensions
    ) -> Int? {
        let horizontalDistance = translation.width
        let verticalDistance = translation.height

        guard max(abs(horizontalDistance), abs(verticalDistance)) >= 24 else {
            return nil
        }

        if abs(horizontalDistance) > abs(verticalDistance) {
            let step = horizontalDistance > 0 ? 1 : -1
            let targetIndex = sourceIndex + step
            let sourceRow = sourceIndex / gridDimensions.columns
            let targetRow = targetIndex / gridDimensions.columns

            guard targetIndex >= 0,
                  targetIndex < visibleBoxCount,
                  sourceRow == targetRow else {
                return nil
            }

            return targetIndex
        }

        let step = verticalDistance > 0 ? gridDimensions.columns : -gridDimensions.columns
        let targetIndex = sourceIndex + step

        guard targetIndex >= 0, targetIndex < visibleBoxCount else {
            return nil
        }

        return targetIndex
    }
}
