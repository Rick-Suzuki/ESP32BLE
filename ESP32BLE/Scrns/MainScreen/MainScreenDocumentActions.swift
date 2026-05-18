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
              !isButtonContinuationEntry(entry) else {
            return
        }

        let currentSpan = slotSpan(startingAt: index, gridDimensions: gridDimensions)
        let candidateSpans = resizeCandidateSpans(after: currentSpan)

        guard let targetSpan = candidateSpans.first(where: { candidateSpan in
            canSetSlotSpan(
                startingAt: index,
                from: currentSpan,
                to: candidateSpan,
                gridDimensions: gridDimensions
            )
        }) else {
            setSlotSpan(startingAt: index, from: currentSpan, to: 1)
            return
        }

        setSlotSpan(startingAt: index, from: currentSpan, to: targetSpan)
    }

    private func resizeCandidateSpans(after currentSpan: Int) -> [Int] {
        let orderedSpans = [1, 2, 3, 4, 5]
        let currentIndex = orderedSpans.firstIndex(of: currentSpan) ?? 0
        let nextSpans = Array(orderedSpans.dropFirst(currentIndex + 1))

        return nextSpans.isEmpty ? [1] : nextSpans
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
        let sourceShape = shape(for: span)
        let rightIndex = sourceIndex + sourceShape.width
        let leftIndex = sourceIndex - sourceShape.width
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
            let isHorizontalNeighbor = abs(candidateIndex - sourceIndex) == sourceShape.width
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

    private func isBlockButtonContinuationEntry(_ entry: FunctionKeyEntry) -> Bool {
        entry.rawLine.trimmingCharacters(in: .whitespacesAndNewlines) == blockButtonContinuationToken
    }

    private func isButtonContinuationEntry(_ entry: FunctionKeyEntry) -> Bool {
        isWideButtonContinuationEntry(entry) || isBlockButtonContinuationEntry(entry)
    }

    func slotSpan(startingAt index: Int, gridDimensions: GridDimensions) -> Int {
        guard functionKeys.indices.contains(index),
              !isButtonContinuationEntry(functionKeys[index]) else {
            return 1
        }

        return shapeSpan(buttonShape(startingAt: index, gridDimensions: gridDimensions))
    }

    private struct ButtonGridShape {
        let width: Int
        let height: Int
    }

    private func shapeSpan(_ shape: ButtonGridShape) -> Int {
        if shape.width == 3 && shape.height == 3 {
            return 5
        }

        if shape.width == 2 && shape.height == 2 {
            return 4
        }

        return shape.width
    }

    private func shape(for span: Int) -> ButtonGridShape {
        if span == 5 {
            return ButtonGridShape(width: 3, height: 3)
        }

        if span == 4 {
            return ButtonGridShape(width: 2, height: 2)
        }

        return ButtonGridShape(width: max(1, min(span, 3)), height: 1)
    }

    private func buttonShape(startingAt index: Int, gridDimensions: GridDimensions) -> ButtonGridShape {
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

    private func indexes(startingAt index: Int, shape: ButtonGridShape, gridDimensions: GridDimensions) -> [Int] {
        let columns = max(gridDimensions.columns, 1)
        var indexes: [Int] = []

        for rowOffset in 0..<shape.height {
            for columnOffset in 0..<shape.width {
                indexes.append(index + (rowOffset * columns) + columnOffset)
            }
        }

        return indexes
    }

    private func continuationAssignments(startingAt index: Int, shape: ButtonGridShape, gridDimensions: GridDimensions) -> [(index: Int, token: String)] {
        let columns = max(gridDimensions.columns, 1)
        var assignments: [(index: Int, token: String)] = []

        for rowOffset in 0..<shape.height {
            for columnOffset in 0..<shape.width {
                guard rowOffset != 0 || columnOffset != 0 else {
                    continue
                }

                let token = rowOffset == 0 ? wideButtonContinuationToken : blockButtonContinuationToken
                assignments.append((index + (rowOffset * columns) + columnOffset, token))
            }
        }

        return assignments
    }

    private func canSetSlotSpan(startingAt index: Int, from currentSpan: Int, to targetSpan: Int, gridDimensions: GridDimensions) -> Bool {
        let currentShape = shape(for: currentSpan)
        let targetShape = shape(for: targetSpan)
        let currentIndexes = Set(indexes(startingAt: index, shape: currentShape, gridDimensions: gridDimensions))
        let targetIndexes = indexes(startingAt: index, shape: targetShape, gridDimensions: gridDimensions)
        let columns = max(gridDimensions.columns, 1)
        let startColumn = index % columns

        guard targetSpan >= 1,
              targetSpan <= 5,
              startColumn + targetShape.width <= columns,
              (index / columns) + targetShape.height <= gridDimensions.rows,
              let maximumTargetIndex = targetIndexes.max(),
              maximumTargetIndex < visibleBoxCount else {
            return false
        }

        guard targetSpan > currentSpan else {
            return true
        }

        for slotIndex in targetIndexes where !currentIndexes.contains(slotIndex) {
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

        let currentShape = shape(for: currentSpan)
        let targetShape = shape(for: targetSpan)
        let currentIndexes = Set(indexes(startingAt: index, shape: currentShape, gridDimensions: visibleGridDimensions))
        let targetIndexes = Set(indexes(startingAt: index, shape: targetShape, gridDimensions: visibleGridDimensions))

        for slotIndex in currentIndexes where slotIndex != index && !targetIndexes.contains(slotIndex) {
            guard slotIndex < visibleBoxCount else {
                continue
            }

            _ = updateFunctionKeySlot(slotIndex, "_")
        }

        for assignment in continuationAssignments(startingAt: index, shape: targetShape, gridDimensions: visibleGridDimensions) {
            guard assignment.index < visibleBoxCount else {
                continue
            }

            _ = updateFunctionKeySlot(assignment.index, assignment.token)
        }
    }

    private func clearWideSlot(startingAt index: Int, gridDimensions: GridDimensions) {
        let shape = buttonShape(startingAt: index, gridDimensions: gridDimensions)
        for slotIndex in indexes(startingAt: index, shape: shape, gridDimensions: gridDimensions) {
            guard slotIndex < visibleBoxCount else {
                continue
            }

            _ = updateFunctionKeySlot(slotIndex, "_")
        }
    }

    private func hasAvailableBlankSpan(startingAt index: Int, span: Int, gridDimensions: GridDimensions) -> Bool {
        let shape = shape(for: span)
        let columns = max(gridDimensions.columns, 1)
        let startColumn = index % columns
        let targetIndexes = indexes(startingAt: index, shape: shape, gridDimensions: gridDimensions)

        guard index >= 0,
              startColumn + shape.width <= columns,
              (index / columns) + shape.height <= gridDimensions.rows,
              let maximumTargetIndex = targetIndexes.max(),
              maximumTargetIndex < visibleBoxCount else {
            return false
        }

        for slotIndex in targetIndexes {
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

        for assignment in continuationAssignments(startingAt: targetIndex, shape: shape(for: span), gridDimensions: visibleGridDimensions) {
            _ = updateFunctionKeySlot(assignment.index, assignment.token)
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
            let sourceSpan = slotSpan(startingAt: sourceIndex, gridDimensions: gridDimensions)
            let sourceShape = shape(for: sourceSpan)
            let step = horizontalDistance > 0 ? 1 : -1
            let targetIndex = sourceIndex + step
            let sourceRow = sourceIndex / gridDimensions.columns
            let targetColumn = targetIndex % max(gridDimensions.columns, 1)

            guard targetIndex >= 0,
                  targetIndex < visibleBoxCount,
                  targetIndex / gridDimensions.columns == sourceRow,
                  targetColumn + sourceShape.width <= gridDimensions.columns,
                  canMoveSlotSpan(
                    startingAt: targetIndex,
                    span: sourceSpan,
                    from: sourceIndex,
                    gridDimensions: gridDimensions
                  ) else {
                return nil
            }

            return targetIndex
        }

        let sourceSpan = slotSpan(startingAt: sourceIndex, gridDimensions: gridDimensions)
        let step = verticalDistance > 0 ? gridDimensions.columns : -gridDimensions.columns
        let targetIndex = sourceIndex + step

        guard targetIndex >= 0,
              targetIndex < visibleBoxCount,
              canMoveSlotSpan(
                startingAt: targetIndex,
                span: sourceSpan,
                from: sourceIndex,
                gridDimensions: gridDimensions
              ) else {
            return nil
        }

        return targetIndex
    }

    private func canMoveSlotSpan(
        startingAt targetIndex: Int,
        span: Int,
        from sourceIndex: Int,
        gridDimensions: GridDimensions
    ) -> Bool {
        let moveShape = shape(for: span)
        let columns = max(gridDimensions.columns, 1)
        let targetIndexes = indexes(startingAt: targetIndex, shape: moveShape, gridDimensions: gridDimensions)
        let sourceIndexes = Set(indexes(startingAt: sourceIndex, shape: moveShape, gridDimensions: gridDimensions))
        let targetColumn = targetIndex % columns

        guard targetIndex >= 0,
              targetColumn + moveShape.width <= columns,
              (targetIndex / columns) + moveShape.height <= gridDimensions.rows,
              let maximumTargetIndex = targetIndexes.max(),
              maximumTargetIndex < visibleBoxCount else {
            return false
        }

        for slotIndex in targetIndexes {
            guard functionKeys.indices.contains(slotIndex) else {
                return false
            }

            if sourceIndexes.contains(slotIndex) {
                continue
            }

            let entry = functionKeys[slotIndex]
            if entry.isBlankPlaceholder || isEmptyButtonEntry(entry) {
                continue
            }

            if moveShape.width == 1 && moveShape.height == 1,
               !isWideButtonContinuationEntry(entry),
               !isBlockButtonContinuationEntry(entry),
               slotSpan(startingAt: slotIndex, gridDimensions: gridDimensions) == 1 {
                continue
            }

            return false
        }

        return true
    }
}
