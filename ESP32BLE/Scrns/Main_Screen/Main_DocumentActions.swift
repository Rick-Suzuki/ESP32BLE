//
//-----------------------------------------------------------------------------------------------
//
import SwiftUI
//
//-----------------------------------------------------------------------------------------------
//
extension MainScreen {
    func updateVisibleBoxCountToFitDefinedButtons() {
        let requiredBoxCount = max(definedFunctionKeyCount, 1)
        guard requiredBoxCount > visibleBoxCount else {
            return
        }

        restoreVisibleGridState(requiredBoxCount: requiredBoxCount)
    }
	//
	//----------------------------------------
	//
    func restoreVisibleGridState(requiredBoxCount: Int? = nil) {
        let resolvedRequiredBoxCount = max(requiredBoxCount ?? definedFunctionKeyCount, 1)
        let restoredGridDimensions = loadGridDimensions(selectedDocumentName, resolvedRequiredBoxCount)
        visibleGridDimensions = restoredGridDimensions
        visibleBoxCount = max(resolvedRequiredBoxCount, restoredGridDimensions.columns * restoredGridDimensions.rows)
    }
	//
	//----------------------------------------
	//

    func decreaseGridRows() {
        guard visibleGridDimensions.rows > 1 else {
            return
        }

        _ = applyGridDimensions(columns: visibleGridDimensions.columns, rows: visibleGridDimensions.rows - 1)
    }
	//
	//----------------------------------------
	//
    func increaseGridRows() {
        let nextRows = visibleGridDimensions.rows + 1
        guard nextRows <= maxGridDimension else {
            return
        }

        _ = applyGridDimensions(columns: visibleGridDimensions.columns, rows: nextRows)
    }
	//
	//----------------------------------------
	//
    func decreaseGridColumns() {
        guard visibleGridDimensions.columns > 1 else {
            return
        }

        _ = applyGridDimensions(columns: visibleGridDimensions.columns - 1, rows: visibleGridDimensions.rows)
    }
	//
	//----------------------------------------
	//
    func increaseGridColumns() {
        let nextColumns = visibleGridDimensions.columns + 1
        guard nextColumns <= maxGridDimension else {
            return
        }

        _ = applyGridDimensions(columns: nextColumns, rows: visibleGridDimensions.rows)
    }
	//
	//----------------------------------------
	//
    func decreaseBoxFontSize() {
        boxFontSize = max(minimumBoxFontSize, boxFontSize - 1)
    }
	//
	//----------------------------------------
	//
    func increaseBoxFontSize() {
        boxFontSize = min(maximumBoxFontSize, boxFontSize + 1)
    }
	//
	//----------------------------------------
	//
    func resetBoxFontSize() {
        boxFontSize = min(maximumBoxFontSize, max(minimumBoxFontSize, 24))
    }
	//
	//----------------------------------------
	//
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
	//
	//----------------------------------------
	//
    func commitDocumentRename() {
        let proposedName = documentNameDraft

        if let alertMessage = renameDocument(proposedName) {
            renameAlertMessage = alertMessage
            return
        }

        documentNameDraft = selectedDocumentDisplayName
        isEditingDocumentName = false
    }
	//
	//----------------------------------------
	//
    func cancelDocumentRename() {
        documentNameDraft = selectedDocumentDisplayName
        isEditingDocumentName = false
        isDocumentNameFieldFocused = false
    }
	//
	//----------------------------------------
	//
    func beginSlotEditing(at index: Int) {
        guard index >= 0, index < visibleBoxCount else {
            return
        }

        let editableIndex = editableAnchorIndex(containing: index) ?? index
        activeDragIndex = nil
        editingSlotIndex = index
        editingSlotText = editableText(for: functionKeys[editableIndex])
        isSlotEditorFocused = true
    }
	//
	//----------------------------------------
	//
    func selectPreviousEditableSlot() {
        selectAdjacentEditableSlot(step: -1)
    }
	//
	//----------------------------------------
	//
    func selectNextEditableSlot() {
        selectAdjacentEditableSlot(step: 1)
    }
	//
	//----------------------------------------
	//
    func commitSlotEditing() {
        guard let editingSlotIndex else {
            return
        }

        let editableIndex = editableAnchorIndex(containing: editingSlotIndex) ?? editingSlotIndex
        let currentSpan = slotSpan(startingAt: editableIndex, gridDimensions: visibleGridDimensions)
        _ = updateFunctionKeySlot(editableIndex, normalizedSlotEditorTextForCommit(editingSlotText))

        if currentSpan > 1 {
            setSlotSpan(startingAt: editableIndex, from: currentSpan, to: currentSpan)
        }
    }
	//
	//----------------------------------------
	//
    func saveSlotEditing() {
        commitSlotEditing()
        alertTitle = ""
        renameAlertMessage = "btn has been\nsaved to file"
    }
	//
	//----------------------------------------
	//
    func cancelSlotEditing() {
        editingSlotIndex = nil
        editingSlotText = ""
        isSlotEditorFocused = false
    }
	//
	//----------------------------------------
	//

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
            let editableIndex = editableAnchorIndex(containing: candidateIndex) ?? candidateIndex
            let candidateEntry = functionKeys[editableIndex]

            activeDragIndex = nil
            self.editingSlotIndex = candidateIndex
            editingSlotText = editableText(for: candidateEntry)
            isSlotEditorFocused = true
            return
        }
    }

    private func editableAnchorIndex(containing index: Int) -> Int? {
        guard functionKeys.indices.contains(index) else {
            return nil
        }

        guard isButtonContinuationEntry(functionKeys[index]) else {
            return index
        }

        let maximumIndex = min(visibleBoxCount, functionKeys.count)
        for anchorIndex in 0..<maximumIndex {
            guard functionKeys.indices.contains(anchorIndex),
                  !isButtonContinuationEntry(functionKeys[anchorIndex]) else {
                continue
            }

            let shape = buttonShape(startingAt: anchorIndex, gridDimensions: visibleGridDimensions)
            if indexes(startingAt: anchorIndex, shape: shape, gridDimensions: visibleGridDimensions).contains(index) {
                return anchorIndex
            }
        }

        return nil
    }

    private func normalizedSlotEditorTextForCommit(_ text: String) -> String {
        let components = text
            .components(separatedBy: "::")
            .filter { $0 != hiddenButtonMetadataToken }
        let hasUserVisibleText = components.contains { component in
            !component.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        return hasUserVisibleText ? text : ""
    }
		//
		//----------------------------------------
		//
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
	//
	//----------------------------------------
	//
    func deleteSlotIfPossible(entry: FunctionKeyEntry, index: Int) {
        guard isGridEditModeEnabled,
              !entry.isBlankPlaceholder,
              !isEmptyButtonEntry(entry) else {
            return
        }

        mainGridEditClipboardText = entry.rawLine
        clearWideSlot(startingAt: index, gridDimensions: visibleGridDimensions)
    }
	//
	//----------------------------------------
	//
    func resetSlotSizeIfNeeded(entry: FunctionKeyEntry, index: Int, gridDimensions: GridDimensions) {
        guard isGridEditModeEnabled,
              !entry.isBlankPlaceholder,
              !isEmptyButtonEntry(entry),
              !isButtonContinuationEntry(entry) else {
            return
        }

        let currentSpan = slotSpan(startingAt: index, gridDimensions: gridDimensions)
        guard currentSpan != 1 else {
            return
        }

        setSlotSpan(startingAt: index, from: currentSpan, to: 1)
    }
	//
	//----------------------------------------
	//
    func resizeSlotIfPossible(entry: FunctionKeyEntry, index: Int, gridDimensions: GridDimensions) {
        guard isGridEditModeEnabled,
              !entry.isBlankPlaceholder,
              !isEmptyButtonEntry(entry),
              !isButtonContinuationEntry(entry) else {
            return
        }

        let currentSpan = slotSpan(startingAt: index, gridDimensions: gridDimensions)
        let candidateSpans = resizeCandidateSpans(after: currentSpan)

        guard let resizePlacement = resizePlacement(
            startingAt: index,
            from: currentSpan,
            candidateSpans: candidateSpans,
            gridDimensions: gridDimensions
        ) else {
            setSlotSpan(startingAt: index, from: currentSpan, to: 1)
            return
        }

        if resizePlacement.index == index {
            setSlotSpan(startingAt: index, from: currentSpan, to: resizePlacement.span)
        } else {
            setShiftedSlotSpan(
                from: index,
                currentSpan: currentSpan,
                to: resizePlacement.index,
                targetSpan: resizePlacement.span,
                gridDimensions: gridDimensions
            )
        }
    }
	//
	//----------------------------------------
	//
    private func resizeCandidateSpans(after currentSpan: Int) -> [Int] {
        let orderedSpans = [1, 2, 3, 4, 5]
        let currentIndex = orderedSpans.firstIndex(of: currentSpan) ?? 0
        let nextSpans = Array(orderedSpans.dropFirst(currentIndex + 1))

        return nextSpans.isEmpty ? [1] : nextSpans
    }
	//
	//----------------------------------------
	//
    private func resizePlacement(
        startingAt index: Int,
        from currentSpan: Int,
        candidateSpans: [Int],
        gridDimensions: GridDimensions
    ) -> (index: Int, span: Int)? {
        for candidateSpan in candidateSpans {
            let candidateIndexes = resizeAnchorCandidates(
                currentIndex: index,
                targetSpan: candidateSpan,
                gridDimensions: gridDimensions
            )

            for candidateIndex in candidateIndexes {
                if canSetSlotSpan(
                    startingAt: candidateIndex,
                    currentIndex: index,
                    from: currentSpan,
                    to: candidateSpan,
                    gridDimensions: gridDimensions
                ) {
                    return (candidateIndex, candidateSpan)
                }
            }
        }

        return nil
    }
	//
	//----------------------------------------
	//
    private func resizeAnchorCandidates(
        currentIndex: Int,
        targetSpan: Int,
        gridDimensions: GridDimensions
    ) -> [Int] {
        let targetShape = shape(for: targetSpan)
        let columns = max(gridDimensions.columns, 1)
        let currentRow = currentIndex / columns
        let currentColumn = currentIndex % columns
        var candidates: [Int] = []

        for rowOffset in 0..<targetShape.height {
            for columnOffset in 0..<targetShape.width {
                let anchorRow = currentRow - rowOffset
                let anchorColumn = currentColumn - columnOffset
                guard anchorRow >= 0, anchorColumn >= 0 else {
                    continue
                }

                let anchorIndex = (anchorRow * columns) + anchorColumn
                if !candidates.contains(anchorIndex) {
                    candidates.append(anchorIndex)
                }
            }
        }

        return candidates
    }
	//
	//----------------------------------------
	//
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
	//
	//----------------------------------------
	//
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
	//
	//----------------------------------------
	//
    private func isWideButtonContinuationEntry(_ entry: FunctionKeyEntry) -> Bool {
        entry.rawLine.trimmingCharacters(in: .whitespacesAndNewlines) == wideButtonContinuationToken
    }
	//
	//----------------------------------------
	//
    private func isBlockButtonContinuationEntry(_ entry: FunctionKeyEntry) -> Bool {
        entry.rawLine.trimmingCharacters(in: .whitespacesAndNewlines) == blockButtonContinuationToken
    }
	//
	//----------------------------------------
	//
    private func isButtonContinuationEntry(_ entry: FunctionKeyEntry) -> Bool {
        isWideButtonContinuationEntry(entry) || isBlockButtonContinuationEntry(entry)
    }
	//
	//----------------------------------------
	//
    func slotSpan(startingAt index: Int, gridDimensions: GridDimensions) -> Int {
        guard functionKeys.indices.contains(index),
              !isButtonContinuationEntry(functionKeys[index]) else {
            return 1
        }

        return shapeSpan(buttonShape(startingAt: index, gridDimensions: gridDimensions))
    }
	//
	//----------------------------------------
	//
    private struct ButtonGridShape {
        let width: Int
        let height: Int
    }
	//
	//----------------------------------------
	//
    private func shapeSpan(_ shape: ButtonGridShape) -> Int {
        if shape.width == 3 && shape.height == 3 {
            return 5
        }

        if shape.width == 2 && shape.height == 2 {
            return 4
        }

        return shape.width
    }
	//
	//----------------------------------------
	//
    private func shape(for span: Int) -> ButtonGridShape {
        if span == 5 {
            return ButtonGridShape(width: 3, height: 3)
        }

        if span == 4 {
            return ButtonGridShape(width: 2, height: 2)
        }

        return ButtonGridShape(width: max(1, min(span, 3)), height: 1)
    }
	//
	//----------------------------------------
	//
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
	//
	//----------------------------------------
	//
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
	//
	//----------------------------------------
	//
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
	//
	//----------------------------------------
	//
    private func canSetSlotSpan(startingAt index: Int, from currentSpan: Int, to targetSpan: Int, gridDimensions: GridDimensions) -> Bool {
        canSetSlotSpan(
            startingAt: index,
            currentIndex: index,
            from: currentSpan,
            to: targetSpan,
            gridDimensions: gridDimensions
        )
    }
	//
	//----------------------------------------
	//
    private func canSetSlotSpan(
        startingAt index: Int,
        currentIndex: Int,
        from currentSpan: Int,
        to targetSpan: Int,
        gridDimensions: GridDimensions
    ) -> Bool {
        let currentShape = shape(for: currentSpan)
        let targetShape = shape(for: targetSpan)
        let currentIndexes = Set(indexes(startingAt: currentIndex, shape: currentShape, gridDimensions: gridDimensions))
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
            return index == currentIndex
        }

        for slotIndex in targetIndexes where !currentIndexes.contains(slotIndex) {
            guard functionKeys.indices.contains(slotIndex) else {
                return false
            }

            let entry = functionKeys[slotIndex]
            guard isEmptyButtonEntry(entry) else {
                return false
            }
        }

        return true
    }
	//
	//----------------------------------------
	//
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
	//
	//----------------------------------------
	//
    private func setShiftedSlotSpan(
        from sourceIndex: Int,
        currentSpan: Int,
        to targetIndex: Int,
        targetSpan: Int,
        gridDimensions: GridDimensions
    ) {
        guard functionKeys.indices.contains(sourceIndex),
              functionKeys.indices.contains(targetIndex) else {
            return
        }

        let sourceLine = functionKeys[sourceIndex].rawLine
        let sourceShape = shape(for: currentSpan)
        let targetShape = shape(for: targetSpan)
        let sourceIndexes = indexes(startingAt: sourceIndex, shape: sourceShape, gridDimensions: gridDimensions)

        for slotIndex in sourceIndexes where slotIndex < visibleBoxCount {
            _ = updateFunctionKeySlot(slotIndex, "_")
        }

        _ = updateFunctionKeySlot(targetIndex, sourceLine)

        for assignment in continuationAssignments(startingAt: targetIndex, shape: targetShape, gridDimensions: gridDimensions) {
            guard assignment.index < visibleBoxCount else {
                continue
            }

            _ = updateFunctionKeySlot(assignment.index, assignment.token)
        }
    }
	//
	//----------------------------------------
	//
    private func clearWideSlot(startingAt index: Int, gridDimensions: GridDimensions) {
        let shape = buttonShape(startingAt: index, gridDimensions: gridDimensions)
        for slotIndex in indexes(startingAt: index, shape: shape, gridDimensions: gridDimensions) {
            guard slotIndex < visibleBoxCount else {
                continue
            }

            _ = updateFunctionKeySlot(slotIndex, "_")
        }
    }
	//
	//----------------------------------------
	//
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
	//
	//----------------------------------------
	//
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
	//
	//-----------------------------------------------------------------------------------------------
	// MARK: - BM:😎 FUNCS Dragging Code
	//
		// Supports:
		//
		// • Horizontal and vertical dragging only
		// • One grid-step movement requests
		// • No diagonal movement
		// • Prevents target anchors outside grid boundaries
		//
		// The stored document move planner decides whether the requested
		// one-step move becomes a plain move, same-size swap, or legal push.
	//
    func targetIndexForEditDrag(
        from sourceIndex: Int,
        translation: CGSize,
        gridDimensions: GridDimensions
    ) -> Int? {
        let horizontalDistance = translation.width
        let verticalDistance = translation.height

			// Ignore very short drags to avoid accidental movement.
			guard max(abs(horizontalDistance), abs(verticalDistance)) >= 24 else {
            return nil
        }

        let sourceSpan = slotSpan(startingAt: sourceIndex, gridDimensions: gridDimensions)
        let sourceShape = shape(for: sourceSpan)

			// MARK: - Horizontal movement
        if abs(horizontalDistance) > abs(verticalDistance) {
            let step = horizontalDistance > 0 ? 1 : -1
            let targetIndex = sourceIndex + step
            let sourceRow = sourceIndex / gridDimensions.columns
            let targetColumn = targetIndex % max(gridDimensions.columns, 1)

            guard targetIndex >= 0,
                  targetIndex < visibleBoxCount,
                  targetIndex / gridDimensions.columns == sourceRow,
                  targetColumn + sourceShape.width <= gridDimensions.columns else {
                return nil
            }

            return targetIndex
        }

			// MARK: - Vertical movement
        let step = verticalDistance > 0 ? gridDimensions.columns : -gridDimensions.columns
			let targetIndex = sourceIndex + step

        let targetRow = targetIndex / max(gridDimensions.columns, 1)
        guard targetIndex >= 0,
              targetIndex < visibleBoxCount,
              targetRow + sourceShape.height <= gridDimensions.rows else {
            return nil
        }

        return targetIndex
    }
	//
	//----------------------------------------
	// private funcs for dragging
	//
	// Single-cell jump movement
	//
	// Searches along a row or column looking for the first
	// valid destination.
	//
	// Can jump over:
	//
	//     • Continuation cells
	//     • Large button regions ("islands")
	//
	// Stops when:
	//
	//     • A valid target is found
	//     • A blocking cell is encountered
	//     • Grid edge is reached
	//
    private func singleCellTargetIndexForEditDrag(
        from sourceIndex: Int,
        step: Int,
        isHorizontalMove: Bool,
        gridDimensions: GridDimensions
    ) -> Int? {
        let columns = max(gridDimensions.columns, 1)
        let sourceRow = sourceIndex / columns
        var candidateIndex = sourceIndex + step

        while candidateIndex >= 0 && candidateIndex < visibleBoxCount {
          
			// Prevent horizontal wrap-around.
			if isHorizontalMove && candidateIndex / columns != sourceRow {
                return nil
            }

            if isSingleCellMoveTarget(candidateIndex, gridDimensions: gridDimensions) {
                return candidateIndex
            }

            guard isIslandCell(candidateIndex, gridDimensions: gridDimensions) else {
                return nil
            }

            candidateIndex += step
        }

        return nil
    }
	//
	//----------------------------------------
	// Diagonal jump movement
	//
	// Same idea as singleCellTargetIndexForEditDrag()
	// but walks diagonally through the grid.
	//
    private func singleCellDiagonalTargetIndexForEditDrag(
        from sourceIndex: Int,
        columnStep: Int,
        rowStep: Int,
        gridDimensions: GridDimensions
    ) -> Int? {
        let columns = max(gridDimensions.columns, 1)
        var candidateRow = (sourceIndex / columns) + rowStep
        var candidateColumn = (sourceIndex % columns) + columnStep

        while candidateRow >= 0,
              candidateRow < gridDimensions.rows,
              candidateColumn >= 0,
              candidateColumn < columns {
            let candidateIndex = (candidateRow * columns) + candidateColumn
            guard candidateIndex < visibleBoxCount else {
                return nil
            }

            if isSingleCellMoveTarget(candidateIndex, gridDimensions: gridDimensions) {
                return candidateIndex
            }

            guard isIslandCell(candidateIndex, gridDimensions: gridDimensions) else {
                return nil
            }

            candidateRow += rowStep
            candidateColumn += columnStep
        }

        return nil
    }
	//
	//----------------------------------------
	// Valid destination test
	//
	// Returns true when the cell can receive a moved
	// single-cell button.
	//
	// Valid targets:
	//
	//     • Blank placeholder
	//     • Empty button
	//     • Another single-cell button
	//
	private func isSingleCellMoveTarget(_ index: Int, gridDimensions: GridDimensions) -> Bool {
        guard functionKeys.indices.contains(index) else {
            return false
        }

        let entry = functionKeys[index]
        guard !isButtonContinuationEntry(entry) else {
            return false
        }

        if entry.isBlankPlaceholder || isEmptyButtonEntry(entry) {
            return true
        }

        return slotSpan(startingAt: index, gridDimensions: gridDimensions) == 1
    }
	//
	//----------------------------------------
	// Island detection
	//
	// Island cells are areas occupied by larger buttons.
	// Single-cell buttons may jump over islands.
	//
	private func isIslandCell(_ index: Int, gridDimensions: GridDimensions) -> Bool {
        guard functionKeys.indices.contains(index) else {
            return false
        }

        let entry = functionKeys[index]
        if isButtonContinuationEntry(entry) {
            return true
        }

        guard !entry.isBlankPlaceholder, !isEmptyButtonEntry(entry) else {
            return false
        }

        return slotSpan(startingAt: index, gridDimensions: gridDimensions) > 1
    }
	//
	//----------------------------------------
	// Multi-cell collision check
	//
	// Determines whether a button occupying multiple cells
	// can legally move into a target location.
	//
	// Allows:
	//
	//     • Overlap with its own current cells
	//     • Blank placeholders
	//     • Empty slots
	//     • Single-cell buttons (for swapping)
	//
	// Rejects:
	//     • Other large buttons
	//     • Out-of-bounds placement
	//
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
	//
	//-----------------------------------------------------------------------------------------------
	//
}
//
//-----------------------------------------------------------------------------------------------
//
