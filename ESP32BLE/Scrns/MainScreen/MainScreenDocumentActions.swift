import SwiftUI

extension MainScreen {
    func updateVisibleBoxCountToFitDefinedButtons() {
        let requiredBoxCount = max(definedFunctionKeyCount, 1)
        guard requiredBoxCount > visibleBoxCount else {
            return
        }

        restoreVisibleGridState(requiredBoxCount: requiredBoxCount)
    }

    func restoreVisibleGridState(requiredBoxCount: Int? = nil) {
        let resolvedRequiredBoxCount = max(requiredBoxCount ?? definedFunctionKeyCount, 1)
        let restoredGridDimensions = loadGridDimensions(selectedDocumentName, resolvedRequiredBoxCount)
        visibleGridDimensions = restoredGridDimensions
        visibleBoxCount = max(resolvedRequiredBoxCount, restoredGridDimensions.columns * restoredGridDimensions.rows)
    }

    func decreaseGridRows() {
        guard visibleGridDimensions.rows > 1 else {
            return
        }

        _ = applyGridDimensions(columns: visibleGridDimensions.columns, rows: visibleGridDimensions.rows - 1)
    }

    func increaseGridRows() {
        let nextRows = visibleGridDimensions.rows + 1
        guard nextRows <= maxGridDimension else {
            return
        }

        _ = applyGridDimensions(columns: visibleGridDimensions.columns, rows: nextRows)
    }

    func decreaseGridColumns() {
        guard visibleGridDimensions.columns > 1 else {
            return
        }

        _ = applyGridDimensions(columns: visibleGridDimensions.columns - 1, rows: visibleGridDimensions.rows)
    }

    func increaseGridColumns() {
        let nextColumns = visibleGridDimensions.columns + 1
        guard nextColumns <= maxGridDimension else {
            return
        }

        _ = applyGridDimensions(columns: nextColumns, rows: visibleGridDimensions.rows)
    }

    func decreaseBoxFontSize() {
        boxFontSize = max(minimumBoxFontSize, boxFontSize - 1)
    }

    func increaseBoxFontSize() {
        boxFontSize = min(maximumBoxFontSize, boxFontSize + 1)
    }

    func resetBoxFontSize() {
        boxFontSize = min(maximumBoxFontSize, max(minimumBoxFontSize, 24))
    }

    @discardableResult
    func applyGridDimensions(columns: Int, rows: Int) -> Bool {
        let sanitizedColumns = max(columns, 1)
        let sanitizedRows = max(rows, 1)
        let currentGridDimensions = visibleGridDimensions
        let candidateBoxCount = sanitizedColumns * sanitizedRows

        guard candidateBoxCount <= maxFunctionKeyCount else {
            return false
        }

        let updatedGridDimensions = (columns: sanitizedColumns, rows: sanitizedRows)

        guard resizeVisibleBoxCount(currentGridDimensions, updatedGridDimensions) else {
            return false
        }

        visibleGridDimensions = updatedGridDimensions
        visibleBoxCount = candidateBoxCount
        saveGridDimensions(selectedDocumentName, updatedGridDimensions)
        return true
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

    func selectPreviousEditableSlot() {
        selectAdjacentEditableSlot(step: -1)
    }

    func selectNextEditableSlot() {
        selectAdjacentEditableSlot(step: 1)
    }

    func commitSlotEditing() {
        guard let editingSlotIndex else {
            return
        }

        _ = updateFunctionKeySlot(editingSlotIndex, editingSlotText)
    }

    func saveSlotEditing() {
        commitSlotEditing()
        alertTitle = ""
        renameAlertMessage = "btn has been\nsaved to file"
    }

    func cancelSlotEditing() {
        editingSlotIndex = nil
        editingSlotText = ""
        isSlotEditorFocused = false
    }

    private func selectAdjacentEditableSlot(step: Int) {
        guard let editingSlotIndex,
              !functionKeys.isEmpty,
              step != 0 else {
            return
        }

        let maximumIndex = min(visibleBoxCount, functionKeys.count)
        guard maximumIndex > 0 else {
            return
        }

        var candidateIndex = editingSlotIndex
        for _ in 0..<maximumIndex {
            candidateIndex = (candidateIndex + step + maximumIndex) % maximumIndex
            let candidateEntry = functionKeys[candidateIndex]
            guard !candidateEntry.isBlankPlaceholder,
                  !isEmptyButtonEntry(candidateEntry) else {
                continue
            }

            activeDragIndex = nil
            self.editingSlotIndex = candidateIndex
            editingSlotText = editableText(for: candidateEntry)
            isSlotEditorFocused = true
            return
        }
    }

    func duplicateSlotIfPossible(entry: FunctionKeyEntry, index: Int, gridDimensions: GridDimensions) {
        guard isGridEditModeEnabled else {
            return
        }

        guard !entry.isBlankPlaceholder,
              !isEmptyButtonEntry(entry) else {
            return
        }

        guard let targetIndex = duplicateTargetIndex(from: index, gridDimensions: gridDimensions) else {
            alertTitle = "Duplicate btn"
            renameAlertMessage = "no space to dup btn"
            return
        }

        guard duplicateFunctionKeySlot(index, targetIndex) else {
            alertTitle = "Duplicate btn"
            renameAlertMessage = "no space to dup btn"
            return
        }
    }

    func deleteSlotIfPossible(entry: FunctionKeyEntry, index: Int) {
        guard isGridEditModeEnabled,
              !entry.isBlankPlaceholder,
              !isEmptyButtonEntry(entry) else {
            return
        }

        _ = updateFunctionKeySlot(index, "_")
    }

    func duplicateTargetIndex(from sourceIndex: Int, gridDimensions: GridDimensions) -> Int? {
        let sourceRow = sourceIndex / gridDimensions.columns
        let rightIndex = sourceIndex + 1
        let leftIndex = sourceIndex - 1
        let downIndex = sourceIndex + gridDimensions.columns
        let upIndex = sourceIndex - gridDimensions.columns

        let candidateIndexes = [
            rightIndex,
            leftIndex,
            downIndex,
            upIndex
        ]

        for candidateIndex in candidateIndexes {
            guard candidateIndex >= 0,
                  candidateIndex < visibleBoxCount,
                  functionKeys.indices.contains(candidateIndex) else {
                continue
            }

            let candidateRow = candidateIndex / gridDimensions.columns
            let isHorizontalNeighbor = abs(candidateIndex - sourceIndex) == 1
            if isHorizontalNeighbor && candidateRow != sourceRow {
                continue
            }

            let candidateEntry = functionKeys[candidateIndex]
            if candidateEntry.isBlankPlaceholder || isEmptyButtonEntry(candidateEntry) {
                return candidateIndex
            }
        }

        return nil
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
