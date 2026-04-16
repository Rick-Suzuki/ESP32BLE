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

        for candidateCount in allowedVisibleBoxCounts[..<currentIndex].reversed() {
            if resizeVisibleBoxCount(candidateCount) {
                visibleBoxCount = candidateCount
                return
            }
        }
    }

    func increaseVisibleBoxCount() {
        guard let currentIndex = allowedVisibleBoxCounts.firstIndex(of: visibleBoxCount),
              currentIndex < allowedVisibleBoxCounts.count - 1 else {
            return
        }

        for candidateCount in allowedVisibleBoxCounts[(currentIndex + 1)...] {
            if resizeVisibleBoxCount(candidateCount) {
                visibleBoxCount = candidateCount
                return
            }
        }
    }

    func decreaseBoxFontSize() {
        updateDocumentFontSize(max(minimumBoxFontSize, boxFontSize - 1))
    }

    func increaseBoxFontSize() {
        updateDocumentFontSize(min(maximumBoxFontSize, boxFontSize + 1))
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
