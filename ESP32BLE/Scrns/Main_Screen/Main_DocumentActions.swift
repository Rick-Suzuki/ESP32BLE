//
//-----------------------------------------------------------------------------------------------
//
import SwiftUI
//
//-----------------------------------------------------------------------------------------------
//
struct MainGridEditClipboardPayload: Codable {
    static let encodedPrefixV1 = "ESP32BLE_GRID_CLIPBOARD_V1:"
    static let encodedPrefixV2 = "ESP32BLE_GRID_CLIPBOARD_V2:"
    static let encodedPrefix = encodedPrefixV2

    let version: Int
    let rawLine: String
    let span: Int
    let width: Int?
    let height: Int?

    init(rawLine: String, span: Int) {
        self.version = 1
        self.rawLine = rawLine
        self.span = span
        self.width = nil
        self.height = nil
    }

    init(rawLine: String, span: Int, width: Int, height: Int) {
        self.version = 2
        self.rawLine = rawLine
        self.span = span
        self.width = width
        self.height = height
    }
}

enum MainGridPopupPasteOutcome {
    case success(MainGridPopupPasteResult)
    case nothingToPaste
    case notEnoughSpace
    case spaceOccupied
}

struct MainGridPopupPasteResult {
    let targetIndex: Int
    let destinationWidth: Int
    let destinationHeight: Int
    let pastedWidth: Int
    let pastedHeight: Int
    let slotLines: [String]
}

enum MainGridPopupDuplicateOutcome {
    case success(MainGridPopupDuplicateResult)
    case invalidSource
    case noSpace
}

struct MainGridPopupButtonShape: Equatable, Identifiable {
    let width: Int
    let height: Int

    var id: String {
        "\(width)x\(height)"
    }

    var label: String {
        "\(width)×\(height)"
    }

    static let resizeOptions = [
        MainGridPopupButtonShape(width: 1, height: 1),
        MainGridPopupButtonShape(width: 2, height: 1),
        MainGridPopupButtonShape(width: 3, height: 1),
        MainGridPopupButtonShape(width: 1, height: 2),
        MainGridPopupButtonShape(width: 2, height: 2),
        MainGridPopupButtonShape(width: 3, height: 2),
        MainGridPopupButtonShape(width: 1, height: 3),
        MainGridPopupButtonShape(width: 3, height: 3)
    ]
}

struct MainGridPopupDuplicateResult {
    let sourceIndex: Int
    let targetIndex: Int
    let sourceWidth: Int
    let sourceHeight: Int
    let slotLines: [String]
}

enum MainGridPopupResizeOutcome {
    case success(MainGridPopupResizeResult)
    case invalidSource
    case sameSize
    case notEnoughSpace
    case spaceOccupied
}

struct MainGridPopupResizeResult {
    let sourceIndex: Int
    let targetIndex: Int
    let sourceWidth: Int
    let sourceHeight: Int
    let targetWidth: Int
    let targetHeight: Int
    let slotLines: [String]
}

struct MainGridPopupResizePlacementResult {
    let sourceIndex: Int
    let sourceFootprint: [Int]
    let targetShape: MainGridPopupButtonShape
    let targetIndex: Int
    let targetFootprint: [Int]
}

private enum MainGridPasteDestinationResult {
    case available
    case outOfBounds
    case occupied
}

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
        let currentBoxFontSize = boxFontSize
        let newBoxFontSize = max(minimumBoxFontSize, currentBoxFontSize - 1)
        boxFontSize = newBoxFontSize
    }
	//
	//----------------------------------------
	//
    func increaseBoxFontSize() {
        let currentBoxFontSize = boxFontSize
        let newBoxFontSize = min(maximumBoxFontSize, currentBoxFontSize + 1)
        boxFontSize = newBoxFontSize
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
        editingSlotText = editableText(for: functionKeys[editableIndex])
        didModifyCurrentSlotEditorSession = false
        resetSmartScriptEditingModel()
        editingSlotIndex = index
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
        if didModifyCurrentSlotEditorSession {
            alertTitle = ""
            renameAlertMessage = "btn has been\nsaved to file"
        }
    }
	//
	//----------------------------------------
	//
    func cancelSlotEditing() {
        editingSlotIndex = nil
        editingSlotText = ""
        didModifyCurrentSlotEditorSession = false
        resetSmartScriptEditingModel()
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

        let currentAnchorIndex = editableAnchorIndex(containing: editingSlotIndex) ?? editingSlotIndex
        commitSlotEditing()

        let maximumIndex = min(visibleBoxCount, functionKeys.count)
        guard maximumIndex > 0 else {
            return
        }

        let candidateStartIndex: Int
        if step > 0 {
            let currentShape = buttonShape(startingAt: currentAnchorIndex, gridDimensions: visibleGridDimensions)
            candidateStartIndex = currentAnchorIndex + max(currentShape.width, 1)
        } else {
            candidateStartIndex = currentAnchorIndex - 1
        }

        var candidateIndex = wrappedEditableIndex(candidateStartIndex, maximumIndex: maximumIndex)
        for _ in 0..<maximumIndex {
            let editableIndex = editableAnchorIndex(containing: candidateIndex) ?? candidateIndex
            guard functionKeys.indices.contains(editableIndex) else {
                candidateIndex = wrappedEditableIndex(candidateIndex + step, maximumIndex: maximumIndex)
                continue
            }

            let candidateEntry = functionKeys[editableIndex]

            activeDragIndex = nil
            editingSlotText = editableText(for: candidateEntry)
            resetSmartScriptEditingModel()
            self.editingSlotIndex = editableIndex
            isSlotEditorFocused = true
            return
        }
    }

    private func wrappedEditableIndex(_ index: Int, maximumIndex: Int) -> Int {
        guard maximumIndex > 0 else {
            return 0
        }

        return (index % maximumIndex + maximumIndex) % maximumIndex
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

    func editableMainGridAnchorIndex(containing index: Int) -> Int? {
        editableAnchorIndex(containing: index)
    }

    private func normalizedSlotEditorTextForCommit(_ text: String) -> String {
        let components = text
            .components(separatedBy: "::")
            .filter { $0 != hiddenButtonMetadataToken }
        let hasUserVisibleText = components.contains { component in
            !component.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        return hasUserVisibleText ? canonicalSmartEditorStoredText(text) : ""
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
        _ = deleteSlotIfPossible(entry: entry, index: index, gridDimensions: visibleGridDimensions, copiesToClipboard: true)
    }

    @discardableResult
    func deleteSlotForPopupIfPossible(entry: FunctionKeyEntry, index: Int, gridDimensions: GridDimensions) -> Bool {
        deleteSlotIfPossible(entry: entry, index: index, gridDimensions: gridDimensions, copiesToClipboard: false)
    }

    func copySlotForPopupIfPossible(entry: FunctionKeyEntry, index: Int, gridDimensions: GridDimensions) -> Bool {
        guard let clipboardText = encodedGridEditClipboardText(entry: entry, index: index, gridDimensions: gridDimensions) else {
            return false
        }

        mainGridEditClipboardText = clipboardText
        return true
    }

    func updatedSlotLinesForPopupCut(
        entry: FunctionKeyEntry,
        index: Int,
        gridDimensions: GridDimensions,
        slotLines: [String]
    ) -> (clipboardText: String, slotLines: [String])? {
        guard let anchorIndex = editableAnchorIndex(containing: index),
              functionKeys.indices.contains(anchorIndex),
              let clipboardText = encodedGridEditClipboardText(entry: entry, index: anchorIndex, gridDimensions: gridDimensions) else {
            return nil
        }

        let shape = buttonShape(startingAt: anchorIndex, gridDimensions: gridDimensions)
        let footprintIndexes = indexes(startingAt: anchorIndex, shape: shape, gridDimensions: gridDimensions)
        guard let maximumIndex = footprintIndexes.max(),
              maximumIndex < visibleBoxCount else {
            return nil
        }

        var updatedLines = slotLinesExpanded(slotLines, through: maximumIndex)
        for slotIndex in footprintIndexes {
            updatedLines[slotIndex] = "_"
        }

        guard updatedLines != slotLines else {
            return nil
        }

        return (clipboardText, updatedLines)
    }

    func updatedSlotLinesForPopupPaste(
        at index: Int,
        gridDimensions: GridDimensions,
        slotLines: [String]
    ) -> MainGridPopupPasteOutcome {
        guard let payload = decodedGridEditClipboardPayload(),
              !payload.rawLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .nothingToPaste
        }

        let targetIndex = editableAnchorIndex(containing: index) ?? index
        guard targetIndex >= 0,
              targetIndex < visibleBoxCount,
              functionKeys.indices.contains(targetIndex) else {
            return .notEnoughSpace
        }

        let pastedShape = shape(for: payload)
        guard shapeFits(pastedShape, startingAt: targetIndex, gridDimensions: gridDimensions) else {
            return .notEnoughSpace
        }

        let destinationEntry = functionKeys[targetIndex]
        let destinationShape: ButtonGridShape
        let destinationFootprint: [Int]

        if destinationEntry.isBlankPlaceholder || isEmptyButtonEntry(destinationEntry) {
            destinationShape = ButtonGridShape(width: 1, height: 1)
            destinationFootprint = [targetIndex]
        } else {
            guard !isButtonContinuationEntry(destinationEntry) else {
                return .notEnoughSpace
            }

            destinationShape = buttonShape(startingAt: targetIndex, gridDimensions: gridDimensions)
            destinationFootprint = indexes(startingAt: targetIndex, shape: destinationShape, gridDimensions: gridDimensions)
        }

        let pastedFootprint = indexes(startingAt: targetIndex, shape: pastedShape, gridDimensions: gridDimensions)
        let maximumIndex = max(destinationFootprint.max() ?? targetIndex, pastedFootprint.max() ?? targetIndex)
        guard maximumIndex < visibleBoxCount else {
            return .notEnoughSpace
        }

        let availableReplacementIndexes = Set(destinationFootprint)
        for slotIndex in pastedFootprint {
            guard slotIndex >= 0,
                  slotIndex < visibleBoxCount,
                  functionKeys.indices.contains(slotIndex) else {
                return .notEnoughSpace
            }

            if availableReplacementIndexes.contains(slotIndex) {
                continue
            }

            let entry = functionKeys[slotIndex]
            guard entry.isBlankPlaceholder || isEmptyButtonEntry(entry) else {
                return .notEnoughSpace
            }
        }

        var updatedLines = slotLinesExpanded(slotLines, through: maximumIndex)
        for slotIndex in destinationFootprint where updatedLines.indices.contains(slotIndex) && slotIndex < visibleBoxCount {
            updatedLines[slotIndex] = "_"
        }

        updatedLines[targetIndex] = payload.rawLine
        for assignment in continuationAssignments(startingAt: targetIndex, shape: pastedShape, gridDimensions: gridDimensions) {
            updatedLines[assignment.index] = assignment.token
        }

        let result = MainGridPopupPasteResult(
            targetIndex: targetIndex,
            destinationWidth: destinationShape.width,
            destinationHeight: destinationShape.height,
            pastedWidth: pastedShape.width,
            pastedHeight: pastedShape.height,
            slotLines: updatedLines
        )

        return .success(result)
    }

    func updatedSlotLinesForPopupDuplicate(
        entry: FunctionKeyEntry,
        index: Int,
        gridDimensions: GridDimensions,
        slotLines: [String]
    ) -> MainGridPopupDuplicateOutcome {
        guard isGridEditModeEnabled,
              let sourceIndex = editableAnchorIndex(containing: index),
              functionKeys.indices.contains(sourceIndex) else {
            return .invalidSource
        }

        let sourceEntry = functionKeys[sourceIndex]
        guard !sourceEntry.isBlankPlaceholder,
              !isEmptyButtonEntry(sourceEntry),
              !isButtonContinuationEntry(sourceEntry) else {
            return .invalidSource
        }

        let sourceSpan = slotSpan(startingAt: sourceIndex, gridDimensions: gridDimensions)
        let sourceShape = shape(for: sourceSpan)
        guard let targetIndex = popupDuplicateTargetIndex(
            from: sourceIndex,
            shape: sourceShape,
            span: sourceSpan,
            gridDimensions: gridDimensions
        ) else {
            return .noSpace
        }

        let footprintIndexes = indexes(startingAt: targetIndex, shape: sourceShape, gridDimensions: gridDimensions)
        guard let maximumIndex = footprintIndexes.max(),
              maximumIndex < visibleBoxCount else {
            return .noSpace
        }

        var updatedLines = slotLinesExpanded(slotLines, through: maximumIndex)
        updatedLines[targetIndex] = sourceEntry.rawLine
        for assignment in continuationAssignments(startingAt: targetIndex, shape: sourceShape, gridDimensions: gridDimensions) {
            updatedLines[assignment.index] = assignment.token
        }

        guard updatedLines != slotLines else {
            return .noSpace
        }

        return .success(MainGridPopupDuplicateResult(
            sourceIndex: sourceIndex,
            targetIndex: targetIndex,
            sourceWidth: sourceShape.width,
            sourceHeight: sourceShape.height,
            slotLines: updatedLines
        ))
    }

    func popupButtonShapeForActionMenu(
        at index: Int,
        gridDimensions: GridDimensions
    ) -> MainGridPopupButtonShape? {
        guard let anchorIndex = editableAnchorIndex(containing: index),
              functionKeys.indices.contains(anchorIndex) else {
            return nil
        }

        let anchorEntry = functionKeys[anchorIndex]
        guard !anchorEntry.isBlankPlaceholder,
              !isEmptyButtonEntry(anchorEntry),
              !isButtonContinuationEntry(anchorEntry) else {
            return nil
        }

        let shape = buttonShape(startingAt: anchorIndex, gridDimensions: gridDimensions)
        return MainGridPopupButtonShape(width: shape.width, height: shape.height)
    }

    func updatedSlotLinesForPopupResize(
        entry: FunctionKeyEntry,
        index: Int,
        gridDimensions: GridDimensions,
        slotLines: [String],
        targetShape: MainGridPopupButtonShape
    ) -> MainGridPopupResizeOutcome {
        guard isGridEditModeEnabled,
              isSupportedShape(width: targetShape.width, height: targetShape.height),
              let sourceIndex = editableAnchorIndex(containing: index),
              functionKeys.indices.contains(sourceIndex) else {
            return .invalidSource
        }

        let sourceEntry = functionKeys[sourceIndex]
        guard !sourceEntry.isBlankPlaceholder,
              !isEmptyButtonEntry(sourceEntry),
              !isButtonContinuationEntry(sourceEntry) else {
            return .invalidSource
        }

        let sourceShape = buttonShape(startingAt: sourceIndex, gridDimensions: gridDimensions)
        guard sourceShape.width != targetShape.width || sourceShape.height != targetShape.height else {
            return .sameSize
        }

        guard let placement = resolvedPopupResizePlacement(
            entry: entry,
            index: index,
            gridDimensions: gridDimensions,
            targetShape: targetShape
        ) else {
            return .notEnoughSpace
        }

        let maximumIndex = max(
            placement.sourceFootprint.max() ?? placement.sourceIndex,
            placement.targetFootprint.max() ?? placement.targetIndex
        )
        guard maximumIndex < visibleBoxCount else {
            return .notEnoughSpace
        }

        var updatedLines = slotLinesExpanded(slotLines, through: maximumIndex)
        for slotIndex in placement.sourceFootprint where slotIndex < updatedLines.count {
            updatedLines[slotIndex] = "_"
        }

        let targetGridShape = ButtonGridShape(width: targetShape.width, height: targetShape.height)
        updatedLines[placement.targetIndex] = sourceEntry.rawLine
        for assignment in continuationAssignments(startingAt: placement.targetIndex, shape: targetGridShape, gridDimensions: gridDimensions) {
            updatedLines[assignment.index] = assignment.token
        }

        guard updatedLines != slotLines else {
            return .sameSize
        }

        return .success(MainGridPopupResizeResult(
            sourceIndex: sourceIndex,
            targetIndex: placement.targetIndex,
            sourceWidth: sourceShape.width,
            sourceHeight: sourceShape.height,
            targetWidth: targetShape.width,
            targetHeight: targetShape.height,
            slotLines: updatedLines
        ))
    }

    func resolvedPopupResizePlacement(
        entry: FunctionKeyEntry,
        index: Int,
        gridDimensions: GridDimensions,
        targetShape: MainGridPopupButtonShape
    ) -> MainGridPopupResizePlacementResult? {
        guard isGridEditModeEnabled,
              isSupportedShape(width: targetShape.width, height: targetShape.height),
              let sourceIndex = editableAnchorIndex(containing: index),
              functionKeys.indices.contains(sourceIndex) else {
            return nil
        }

        let sourceEntry = functionKeys[sourceIndex]
        guard !sourceEntry.isBlankPlaceholder,
              !isEmptyButtonEntry(sourceEntry),
              !isButtonContinuationEntry(sourceEntry) else {
            return nil
        }

        let sourceShape = buttonShape(startingAt: sourceIndex, gridDimensions: gridDimensions)
        let sourceFootprint = indexes(startingAt: sourceIndex, shape: sourceShape, gridDimensions: gridDimensions)
        let sourceFootprintSet = Set(sourceFootprint)
        let targetGridShape = ButtonGridShape(width: targetShape.width, height: targetShape.height)

        if sourceShape.width == targetShape.width,
           sourceShape.height == targetShape.height {
            return MainGridPopupResizePlacementResult(
                sourceIndex: sourceIndex,
                sourceFootprint: sourceFootprint,
                targetShape: targetShape,
                targetIndex: sourceIndex,
                targetFootprint: sourceFootprint
            )
        }

        if let existingAnchorPlacement = popupResizePlacementCandidate(
            sourceIndex: sourceIndex,
            sourceFootprint: sourceFootprint,
            sourceFootprintSet: sourceFootprintSet,
            targetShape: targetShape,
            targetGridShape: targetGridShape,
            targetIndex: sourceIndex,
            gridDimensions: gridDimensions
        ) {
            return existingAnchorPlacement
        }

        let columns = max(gridDimensions.columns, 1)
        let sourceRows = sourceFootprint.map { $0 / columns }
        let sourceColumns = sourceFootprint.map { $0 % columns }
        guard let sourceMinRow = sourceRows.min(),
              let sourceMaxRow = sourceRows.max(),
              let sourceMinColumn = sourceColumns.min(),
              let sourceMaxColumn = sourceColumns.max() else {
            return nil
        }

        let minimumColumn = max(0, sourceMinColumn - targetShape.width + 1)
        let maximumColumn = min(columns - targetShape.width, sourceMaxColumn)
        let minimumRow = max(0, sourceMinRow - targetShape.height + 1)
        let maximumRow = min(gridDimensions.rows - targetShape.height, sourceMaxRow)
        guard minimumColumn <= maximumColumn,
              minimumRow <= maximumRow else {
            return nil
        }

        var candidates: [(placement: MainGridPopupResizePlacementResult, distance: Int, rowDelta: Int, columnDelta: Int, row: Int, column: Int)] = []
        let sourceRow = sourceIndex / columns
        let sourceColumn = sourceIndex % columns

        for row in minimumRow...maximumRow {
            for column in minimumColumn...maximumColumn {
                let targetIndex = (row * columns) + column
                guard targetIndex != sourceIndex,
                      let placement = popupResizePlacementCandidate(
                        sourceIndex: sourceIndex,
                        sourceFootprint: sourceFootprint,
                        sourceFootprintSet: sourceFootprintSet,
                        targetShape: targetShape,
                        targetGridShape: targetGridShape,
                        targetIndex: targetIndex,
                        gridDimensions: gridDimensions
                      ) else {
                    continue
                }

                let rowDelta = abs(row - sourceRow)
                let columnDelta = abs(column - sourceColumn)
                candidates.append((placement, rowDelta + columnDelta, rowDelta, columnDelta, row, column))
            }
        }

        return candidates
            .sorted {
                if $0.distance != $1.distance { return $0.distance < $1.distance }
                if $0.rowDelta != $1.rowDelta { return $0.rowDelta < $1.rowDelta }
                if $0.columnDelta != $1.columnDelta { return $0.columnDelta < $1.columnDelta }
                if $0.row != $1.row { return $0.row < $1.row }
                return $0.column < $1.column
            }
            .first?
            .placement
    }

    private func popupResizePlacementCandidate(
        sourceIndex: Int,
        sourceFootprint: [Int],
        sourceFootprintSet: Set<Int>,
        targetShape: MainGridPopupButtonShape,
        targetGridShape: ButtonGridShape,
        targetIndex: Int,
        gridDimensions: GridDimensions
    ) -> MainGridPopupResizePlacementResult? {
        guard shapeFits(targetGridShape, startingAt: targetIndex, gridDimensions: gridDimensions) else {
            return nil
        }

        guard popupResizePlacementFollowsFingerStretchRules(
            sourceFootprint: sourceFootprint,
            targetIndex: targetIndex,
            targetShape: targetShape,
            gridDimensions: gridDimensions
        ) else {
            return nil
        }

        let targetFootprint = indexes(startingAt: targetIndex, shape: targetGridShape, gridDimensions: gridDimensions)
        guard let maximumIndex = targetFootprint.max(),
              maximumIndex < visibleBoxCount,
              targetFootprint.contains(where: { sourceFootprintSet.contains($0) }) else {
            return nil
        }

        for slotIndex in targetFootprint where !sourceFootprintSet.contains(slotIndex) {
            guard functionKeys.indices.contains(slotIndex) else {
                return nil
            }

            let entry = functionKeys[slotIndex]
            guard !isButtonContinuationEntry(entry),
                  entry.isBlankPlaceholder || isEmptyButtonEntry(entry) else {
                return nil
            }
        }

        return MainGridPopupResizePlacementResult(
            sourceIndex: sourceIndex,
            sourceFootprint: sourceFootprint,
            targetShape: targetShape,
            targetIndex: targetIndex,
            targetFootprint: targetFootprint
        )
    }

    private func popupResizePlacementFollowsFingerStretchRules(
        sourceFootprint: [Int],
        targetIndex: Int,
        targetShape: MainGridPopupButtonShape,
        gridDimensions: GridDimensions
    ) -> Bool {
        let columns = max(gridDimensions.columns, 1)
        let sourceRows = sourceFootprint.map { $0 / columns }
        let sourceColumns = sourceFootprint.map { $0 % columns }
        guard let sourceMinRow = sourceRows.min(),
              let sourceMaxRow = sourceRows.max(),
              let sourceMinColumn = sourceColumns.min(),
              let sourceMaxColumn = sourceColumns.max() else {
            return false
        }

        let targetMinRow = targetIndex / columns
        let targetMaxRow = targetMinRow + targetShape.height - 1
        let targetMinColumn = targetIndex % columns
        let targetMaxColumn = targetMinColumn + targetShape.width - 1

        return popupResizeAxisFollowsFingerStretchRules(
            sourceMin: sourceMinColumn,
            sourceMax: sourceMaxColumn,
            targetMin: targetMinColumn,
            targetMax: targetMaxColumn
        ) && popupResizeAxisFollowsFingerStretchRules(
            sourceMin: sourceMinRow,
            sourceMax: sourceMaxRow,
            targetMin: targetMinRow,
            targetMax: targetMaxRow
        )
    }

    private func popupResizeAxisFollowsFingerStretchRules(
        sourceMin: Int,
        sourceMax: Int,
        targetMin: Int,
        targetMax: Int
    ) -> Bool {
        let sourceSize = sourceMax - sourceMin + 1
        let targetSize = targetMax - targetMin + 1

        if targetSize == sourceSize {
            return targetMin == sourceMin && targetMax == sourceMax
        }

        if targetSize < sourceSize {
            return targetMin >= sourceMin && targetMax <= sourceMax
        }

        return targetMin <= sourceMin && targetMax >= sourceMax
    }

    @discardableResult
    private func deleteSlotIfPossible(
        entry: FunctionKeyEntry,
        index: Int,
        gridDimensions: GridDimensions,
        copiesToClipboard: Bool
    ) -> Bool {
        guard isGridEditModeEnabled,
              !entry.isBlankPlaceholder,
              !isEmptyButtonEntry(entry) else {
            return false
        }

        if copiesToClipboard {
            mainGridEditClipboardText = entry.rawLine
        }

        return clearWideSlot(startingAt: index, gridDimensions: gridDimensions)
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
            guard let clipboardPayload = decodedGridEditClipboardPayload(),
                  !clipboardPayload.rawLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                alertTitle = ""
                renameAlertMessage = "no btn data available\nto create new btn"
                return
            }

            _ = updateFunctionKeySlot(index, clipboardPayload.rawLine)
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

    private func popupDuplicateTargetIndex(
        from sourceIndex: Int,
        shape: ButtonGridShape,
        span: Int,
        gridDimensions: GridDimensions
    ) -> Int? {
        let columns = max(gridDimensions.columns, 1)
        let sourceColumn = sourceIndex % columns
        let sourceRow = sourceIndex / columns
        let candidateCoordinates = [
            (row: sourceRow, column: sourceColumn + shape.width),
            (row: sourceRow + shape.height, column: sourceColumn),
            (row: sourceRow, column: sourceColumn - shape.width),
            (row: sourceRow - shape.height, column: sourceColumn)
        ]

        for coordinate in candidateCoordinates {
            guard coordinate.row >= 0,
                  coordinate.column >= 0,
                  coordinate.row < gridDimensions.rows,
                  coordinate.column < columns else {
                continue
            }

            let candidateIndex = (coordinate.row * columns) + coordinate.column
            guard candidateIndex >= 0,
                  candidateIndex < visibleBoxCount,
                  functionKeys.indices.contains(candidateIndex) else {
                continue
            }

            if pasteDestinationResult(startingAt: candidateIndex, span: span, gridDimensions: gridDimensions) == .available {
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

    private func encodedGridEditClipboardText(entry: FunctionKeyEntry, index: Int, gridDimensions: GridDimensions) -> String? {
        guard isGridEditModeEnabled,
              let anchorIndex = editableAnchorIndex(containing: index),
              functionKeys.indices.contains(anchorIndex) else {
            return nil
        }

        let anchorEntry = functionKeys[anchorIndex]
        guard !anchorEntry.isBlankPlaceholder,
              !isEmptyButtonEntry(anchorEntry),
              !isButtonContinuationEntry(anchorEntry) else {
            return nil
        }

        let shape = buttonShape(startingAt: anchorIndex, gridDimensions: gridDimensions)
        let payload = MainGridEditClipboardPayload(
            rawLine: anchorEntry.rawLine,
            span: shapeSpan(shape),
            width: shape.width,
            height: shape.height
        )

        guard let payloadData = try? JSONEncoder().encode(payload) else {
            return nil
        }

        return MainGridEditClipboardPayload.encodedPrefix + payloadData.base64EncodedString()
    }

    private func decodedGridEditClipboardPayload() -> MainGridEditClipboardPayload? {
        let clipboardText = mainGridEditClipboardText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clipboardText.isEmpty else {
            return nil
        }

        let payloadPrefix: String
        if clipboardText.hasPrefix(MainGridEditClipboardPayload.encodedPrefixV2) {
            payloadPrefix = MainGridEditClipboardPayload.encodedPrefixV2
        } else if clipboardText.hasPrefix(MainGridEditClipboardPayload.encodedPrefixV1) {
            payloadPrefix = MainGridEditClipboardPayload.encodedPrefixV1
        } else {
            return MainGridEditClipboardPayload(rawLine: clipboardText, span: 1)
        }

        let encodedPayload = String(clipboardText.dropFirst(payloadPrefix.count))
        guard let payloadData = Data(base64Encoded: encodedPayload),
              let payload = try? JSONDecoder().decode(MainGridEditClipboardPayload.self, from: payloadData),
              isValidClipboardPayload(payload),
              !payload.rawLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return payload
    }

    func hasValidMainGridActionMenuPastePayload() -> Bool {
        decodedGridEditClipboardPayload() != nil
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

        if shape.width == 3 && shape.height == 2 {
            return 8
        }

        if shape.width == 1 && shape.height == 3 {
            return 7
        }

        if shape.width == 1 && shape.height == 2 {
            return 6
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

        if span == 8 {
            return ButtonGridShape(width: 3, height: 2)
        }

        if span == 7 {
            return ButtonGridShape(width: 1, height: 3)
        }

        if span == 6 {
            return ButtonGridShape(width: 1, height: 2)
        }

        if span == 4 {
            return ButtonGridShape(width: 2, height: 2)
        }

        return ButtonGridShape(width: max(1, min(span, 3)), height: 1)
    }

    private func shape(for payload: MainGridEditClipboardPayload) -> ButtonGridShape {
        if payload.version == 2,
           let width = payload.width,
           let height = payload.height,
           isSupportedShape(width: width, height: height) {
            return ButtonGridShape(width: width, height: height)
        }

        return shape(for: payload.span)
    }

    private func isValidClipboardPayload(_ payload: MainGridEditClipboardPayload) -> Bool {
        if payload.version == 1 {
            return (1...5).contains(payload.span)
        }

        if payload.version == 2,
           let width = payload.width,
           let height = payload.height,
           isSupportedShape(width: width, height: height) {
            return payload.span == shapeSpan(ButtonGridShape(width: width, height: height))
        }

        return false
    }

    private func isSupportedShape(width: Int, height: Int) -> Bool {
        switch (width, height) {
        case (1, 1), (2, 1), (3, 1), (1, 2), (2, 2), (3, 2), (1, 3), (3, 3):
            return true
        default:
            return false
        }
    }
	//
	//----------------------------------------
	//
    private func buttonShape(startingAt index: Int, gridDimensions: GridDimensions) -> ButtonGridShape {
        let candidateShapes = [
            ButtonGridShape(width: 3, height: 3),
            ButtonGridShape(width: 3, height: 2),
            ButtonGridShape(width: 2, height: 2),
            ButtonGridShape(width: 1, height: 3),
            ButtonGridShape(width: 3, height: 1),
            ButtonGridShape(width: 1, height: 2),
            ButtonGridShape(width: 2, height: 1)
        ]

        for shape in candidateShapes where shapeFits(shape, startingAt: index, gridDimensions: gridDimensions) &&
            continuationTokensMatch(startingAt: index, shape: shape, gridDimensions: gridDimensions) {
            return shape
        }

        return ButtonGridShape(width: 1, height: 1)
    }

    private func shapeFits(_ shape: ButtonGridShape, startingAt index: Int, gridDimensions: GridDimensions) -> Bool {
        let columns = max(gridDimensions.columns, 1)
        let startColumn = index % columns
        let startRow = index / columns

        return index >= 0 &&
            startColumn + shape.width <= columns &&
            startRow + shape.height <= gridDimensions.rows
    }

    private func continuationTokensMatch(startingAt index: Int, shape: ButtonGridShape, gridDimensions: GridDimensions) -> Bool {
        continuationAssignments(startingAt: index, shape: shape, gridDimensions: gridDimensions)
            .allSatisfy { assignment in
                functionKeys.indices.contains(assignment.index) &&
                    assignment.index < visibleBoxCount &&
                    functionKeys[assignment.index].rawLine.trimmingCharacters(in: .whitespacesAndNewlines) == assignment.token
            }
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
    @discardableResult
    private func clearWideSlot(startingAt index: Int, gridDimensions: GridDimensions) -> Bool {
        let shape = buttonShape(startingAt: index, gridDimensions: gridDimensions)
        var didAttemptClear = false
        var didFailClear = false

        for slotIndex in indexes(startingAt: index, shape: shape, gridDimensions: gridDimensions) {
            guard slotIndex < visibleBoxCount else {
                continue
            }

            didAttemptClear = true
            didFailClear = !updateFunctionKeySlot(slotIndex, "_") || didFailClear
        }

        return didAttemptClear && !didFailClear
    }
	//
	//----------------------------------------
	//
    private func hasAvailableBlankSpan(startingAt index: Int, span: Int, gridDimensions: GridDimensions) -> Bool {
        pasteDestinationResult(startingAt: index, shape: shape(for: span), gridDimensions: gridDimensions) == .available
    }

    private func pasteDestinationResult(startingAt index: Int, span: Int, gridDimensions: GridDimensions) -> MainGridPasteDestinationResult {
        let shape = shape(for: span)
        return pasteDestinationResult(startingAt: index, shape: shape, gridDimensions: gridDimensions)
    }

    private func pasteDestinationResult(startingAt index: Int, shape: ButtonGridShape, gridDimensions: GridDimensions) -> MainGridPasteDestinationResult {
        let columns = max(gridDimensions.columns, 1)
        let startColumn = index % columns
        let targetIndexes = indexes(startingAt: index, shape: shape, gridDimensions: gridDimensions)

        guard index >= 0,
              startColumn + shape.width <= columns,
              (index / columns) + shape.height <= gridDimensions.rows,
              let maximumTargetIndex = targetIndexes.max(),
              maximumTargetIndex < visibleBoxCount else {
            return .outOfBounds
        }

        for slotIndex in targetIndexes {
            guard functionKeys.indices.contains(slotIndex) else {
                return .outOfBounds
            }

            let entry = functionKeys[slotIndex]
            guard entry.isBlankPlaceholder || isEmptyButtonEntry(entry) else {
                return .occupied
            }
        }

        return .available
    }

    private func slotLinesExpanded(_ slotLines: [String], through maximumIndex: Int) -> [String] {
        guard maximumIndex >= slotLines.count else {
            return slotLines
        }

        return slotLines + Array(repeating: "_", count: maximumIndex - slotLines.count + 1)
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
