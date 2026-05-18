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

        commitSlotEditing()

        let maximumIndex = min(visibleBoxCount, functionKeys.count)
        guard maximumIndex > 0 else {
            return
        }

        var candidateIndex = editingSlotIndex
        for _ in 0..<maximumIndex {
            candidateIndex = (candidateIndex + step + maximumIndex) % maximumIndex
            let candidateEntry = functionKeys[candidateIndex]

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

        let sourceSpan = slotSpan(startingAt: index, gridDimensions: gridDimensions)
        guard let targetIndex = duplicateTargetIndex(from: index, span: sourceSpan, gridDimensions: gridDimensions) else {
            alertTitle = "Duplicate btn"
            renameAlertMessage = "no space to dup btn"
            return
        }

        guard duplicateWideSlot(from: index, to: targetIndex, span: sourceSpan) else {
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

        mainGridEditClipboardText = entry.rawLine
        clearWideSlot(startingAt: index, gridDimensions: visibleGridDimensions)
    }

    func resizeSlotIfPossible(entry: FunctionKeyEntry, index: Int, gridDimensions: GridDimensions) {
        guard isGridEditModeEnabled,
              !entry.isBlankPlaceholder,
              !isEmptyButtonEntry(entry),
              !isWideButtonContinuationEntry(entry) else {
            return
        }

        let currentSpan = slotSpan(startingAt: index, gridDimensions: gridDimensions)
        let targetSpan = currentSpan >= 3 ? 1 : currentSpan + 1

        guard canSetSlotSpan(startingAt: index, from: currentSpan, to: targetSpan, gridDimensions: gridDimensions) else {
            alertTitle = "Resize btn"
            renameAlertMessage = "no space to resize btn"
            return
        }

        setSlotSpan(startingAt: index, from: currentSpan, to: targetSpan)
    }

    func handleThreeTapEditAction(entry: FunctionKeyEntry, index: Int) {
        guard isGridEditModeEnabled else {
            return
        }

        if entry.isBlankPlaceholder || isEmptyButtonEntry(entry) {
            let clipboardEntryText = mainGridEditClipboardText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clipboardEntryText.isEmpty else {
                alertTitle = ""
                renameAlertMessage = "no btn data available\nto create new btn"
                return
            }

            _ = updateFunctionKeySlot(index, clipboardEntryText)
            alertTitle = ""
            renameAlertMessage = "btn pasted"
            return
        }

        mainGridEditClipboardText = entry.rawLine
        alertTitle = ""
        renameAlertMessage = "Copied btn data\nto clipboard"
    }

    func duplicateTargetIndex(from sourceIndex: Int, span: Int, gridDimensions: GridDimensions) -> Int? {
        let sourceRow = sourceIndex / gridDimensions.columns
        let rightIndex = sourceIndex + span
        let leftIndex = sourceIndex - span
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
            let isHorizontalNeighbor = abs(candidateIndex - sourceIndex) == span
            if isHorizontalNeighbor && candidateRow != sourceRow {
                continue
            }

            if hasAvailableBlankSpan(startingAt: candidateIndex, span: span, gridDimensions: gridDimensions) {
                return candidateIndex
            }
        }

        return nil
    }

    private func isWideButtonContinuationEntry(_ entry: FunctionKeyEntry) -> Bool {
        entry.rawLine.trimmingCharacters(in: .whitespacesAndNewlines) == wideButtonContinuationToken
    }

    private func slotSpan(startingAt index: Int, gridDimensions: GridDimensions) -> Int {
        guard functionKeys.indices.contains(index),
              !isWideButtonContinuationEntry(functionKeys[index]) else {
            return 1
        }

        let columns = max(gridDimensions.columns, 1)
        let row = index / columns
        var span = 1

        while span < 3 {
            let nextIndex = index + span
            guard functionKeys.indices.contains(nextIndex),
                  nextIndex < visibleBoxCount,
                  nextIndex / columns == row,
                  isWideButtonContinuationEntry(functionKeys[nextIndex]) else {
                break
            }

            span += 1
        }

        return span
    }

    private func canSetSlotSpan(startingAt index: Int, from currentSpan: Int, to targetSpan: Int, gridDimensions: GridDimensions) -> Bool {
        let columns = max(gridDimensions.columns, 1)
        let row = index / columns
        guard targetSpan >= 1,
              targetSpan <= 3,
              (index + targetSpan - 1) / columns == row,
              index + targetSpan <= visibleBoxCount else {
            return false
        }

        guard targetSpan > currentSpan else {
            return true
        }

        for slotIndex in (index + currentSpan)..<(index + targetSpan) {
            guard functionKeys.indices.contains(slotIndex) else {
                return false
            }

            let entry = functionKeys[slotIndex]
            guard entry.isBlankPlaceholder || isEmptyButtonEntry(entry) else {
                return false
            }
        }

        return true
    }

    private func setSlotSpan(startingAt index: Int, from currentSpan: Int, to targetSpan: Int) {
        guard functionKeys.indices.contains(index) else {
            return
        }

        let normalizedCurrentSpan = max(1, min(currentSpan, 3))
        let normalizedTargetSpan = max(1, min(targetSpan, 3))
        let maximumSpan = max(normalizedCurrentSpan, normalizedTargetSpan)

        for offset in 1..<maximumSpan {
            let slotIndex = index + offset
            guard slotIndex < visibleBoxCount else {
                continue
            }

            if offset < normalizedTargetSpan {
                _ = updateFunctionKeySlot(slotIndex, wideButtonContinuationToken)
            } else {
                _ = updateFunctionKeySlot(slotIndex, "_")
            }
        }
    }

    private func clearWideSlot(startingAt index: Int, gridDimensions: GridDimensions) {
        let span = slotSpan(startingAt: index, gridDimensions: gridDimensions)
        for offset in 0..<span {
            let slotIndex = index + offset
            guard slotIndex < visibleBoxCount else {
                continue
            }

            _ = updateFunctionKeySlot(slotIndex, "_")
        }
    }

    private func hasAvailableBlankSpan(startingAt index: Int, span: Int, gridDimensions: GridDimensions) -> Bool {
        let boundedSpan = max(1, min(span, 3))
        let columns = max(gridDimensions.columns, 1)
        let row = index / columns

        guard index >= 0,
              index + boundedSpan <= visibleBoxCount,
              (index + boundedSpan - 1) / columns == row else {
            return false
        }

        for offset in 0..<boundedSpan {
            let slotIndex = index + offset
            guard functionKeys.indices.contains(slotIndex) else {
                return false
            }

            let entry = functionKeys[slotIndex]
            guard entry.isBlankPlaceholder || isEmptyButtonEntry(entry) else {
                return false
            }
        }

        return true
    }

    private func duplicateWideSlot(from sourceIndex: Int, to targetIndex: Int, span: Int) -> Bool {
        guard functionKeys.indices.contains(sourceIndex),
              hasAvailableBlankSpan(startingAt: targetIndex, span: span, gridDimensions: visibleGridDimensions) else {
            return false
        }

        _ = updateFunctionKeySlot(targetIndex, functionKeys[sourceIndex].rawLine)

        if span > 1 {
            for offset in 1..<span {
                _ = updateFunctionKeySlot(targetIndex + offset, wideButtonContinuationToken)
            }
        }

        return true
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
