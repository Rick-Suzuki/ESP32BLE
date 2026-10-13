import Foundation

struct SmartScriptEditingModel {
    private struct EditingState {
        var scriptText: String
        var selectionRange: NSRange
    }

    private enum EditTransactionKind {
        case keyboardTyping
        case deleteBackward
        case deleteForward
    }

    var scriptText = ""
    var selectionRange = NSRange(location: 0, length: 0)
    private var preferredVerticalColumn: Int?
    private var undoStack: [EditingState] = []
    private var redoStack: [EditingState] = []
    private var activeEditTransactionKind: EditTransactionKind?
    private var pendingSelectionRangeAfterEdit: NSRange?

    mutating func setText(_ text: String) {
        scriptText = text
        preferredVerticalColumn = nil
        undoStack.removeAll()
        redoStack.removeAll()
        activeEditTransactionKind = nil
        pendingSelectionRangeAfterEdit = nil
        clampSelectionRange()
    }

    mutating func setEditedText(_ text: String) {
        guard text != scriptText else {
            clampSelectionRange()
            return
        }

        pushUndoState()
        scriptText = text
        preferredVerticalColumn = nil
        clampSelectionRange()
    }

    mutating func setKeyboardEditedText(_ text: String) {
        guard text != scriptText else {
            clampSelectionRange()
            return
        }

        let keyboardEdit = keyboardEditInfo(for: text)
        pushUndoState(kind: keyboardEdit.kind)
        scriptText = text
        preferredVerticalColumn = nil
        clampSelectionRange()
        pendingSelectionRangeAfterEdit = keyboardEdit.selectionRange
        if keyboardEdit.shouldEndUndoGroup {
            activeEditTransactionKind = nil
        }
    }

    mutating func setSelectionRange(_ range: NSRange) {
        let newRange = clampedRange(range)
        if newRange != selectionRange {
            preferredVerticalColumn = nil
        }

        if let pendingSelectionRangeAfterEdit, pendingSelectionRangeAfterEdit == newRange {
            self.pendingSelectionRangeAfterEdit = nil
        } else if newRange != selectionRange {
            activeEditTransactionKind = nil
            pendingSelectionRangeAfterEdit = nil
        }

        selectionRange = newRange
    }

    mutating func replaceSelection(with insertedText: String) {
        let replacementNSRange = clampedRange(selectionRange)
        let replacementRange = Range(replacementNSRange, in: scriptText) ?? scriptText.endIndex..<scriptText.endIndex
        let insertionLocation = replacementNSRange.location + insertedText.utf16.count
        if String(scriptText[replacementRange]) == insertedText {
            selectionRange = clampedRange(NSRange(location: insertionLocation, length: 0))
            return
        }

        pushUndoState()
        scriptText.replaceSubrange(replacementRange, with: insertedText)
        preferredVerticalColumn = nil
        selectionRange = clampedRange(NSRange(location: insertionLocation, length: 0))
    }

    var canUndo: Bool {
        !undoStack.isEmpty
    }

    var canRedo: Bool {
        !redoStack.isEmpty
    }

    var canMoveCaretLeft: Bool {
        let range = clampedRange(selectionRange)
        return range.length > 0 || range.location > 0
    }

    var canMoveCaretRight: Bool {
        let range = clampedRange(selectionRange)
        return range.length > 0 || range.location < scriptText.utf16.count
    }

    var canDeleteBackward: Bool {
        let range = clampedRange(selectionRange)
        return range.length > 0 || range.location > 0
    }

    var canDeleteForward: Bool {
        let range = clampedRange(selectionRange)
        return range.length > 0 || range.location < scriptText.utf16.count
    }

    var canMoveCaretUp: Bool {
        lineBounds(containing: clampedRange(selectionRange).location).start > 0
    }

    var canMoveCaretDown: Bool {
        let range = clampedRange(selectionRange)
        let location = range.location + range.length
        return nextLineBounds(after: lineBounds(containing: location)) != nil
    }

    mutating func moveCaretLeft() {
        let range = clampedRange(selectionRange)
        preferredVerticalColumn = nil
        activeEditTransactionKind = nil
        pendingSelectionRangeAfterEdit = nil

        if range.length > 0 {
            selectionRange = NSRange(location: range.location, length: 0)
            return
        }

        guard range.location > 0 else {
            return
        }

        let text = scriptText as NSString
        let previousRange = text.rangeOfComposedCharacterSequence(at: range.location - 1)
        selectionRange = clampedRange(NSRange(location: previousRange.location, length: 0))
    }

    mutating func moveCaretRight() {
        let range = clampedRange(selectionRange)
        preferredVerticalColumn = nil
        activeEditTransactionKind = nil
        pendingSelectionRangeAfterEdit = nil

        if range.length > 0 {
            selectionRange = NSRange(location: range.location + range.length, length: 0)
            return
        }

        guard range.location < scriptText.utf16.count else {
            return
        }

        let text = scriptText as NSString
        let nextRange = text.rangeOfComposedCharacterSequence(at: range.location)
        selectionRange = clampedRange(NSRange(location: nextRange.location + nextRange.length, length: 0))
    }

    mutating func moveCaretUp() {
        let range = clampedRange(selectionRange)
        activeEditTransactionKind = nil
        pendingSelectionRangeAfterEdit = nil
        let line = lineBounds(containing: range.location)
        guard let previousLine = previousLineBounds(before: line) else {
            selectionRange = NSRange(location: range.location, length: 0)
            return
        }

        let column = preferredVerticalColumn ?? (range.location - line.start)
        preferredVerticalColumn = column
        selectionRange = clampedRange(NSRange(location: min(previousLine.start + column, previousLine.end), length: 0))
    }

    mutating func moveCaretDown() {
        let range = clampedRange(selectionRange)
        activeEditTransactionKind = nil
        pendingSelectionRangeAfterEdit = nil
        let location = range.location + range.length
        let line = lineBounds(containing: location)
        guard let nextLine = nextLineBounds(after: line) else {
            selectionRange = NSRange(location: location, length: 0)
            return
        }

        let column = preferredVerticalColumn ?? (location - line.start)
        preferredVerticalColumn = column
        selectionRange = clampedRange(NSRange(location: min(nextLine.start + column, nextLine.end), length: 0))
    }

    mutating func deleteBackward() {
        let range = clampedRange(selectionRange)
        preferredVerticalColumn = nil

        if range.length > 0 {
            replaceSelection(with: "")
            return
        }

        guard range.location > 0 else {
            return
        }

        let text = scriptText as NSString
        let deletedRange = text.rangeOfComposedCharacterSequence(at: range.location - 1)
        if let stringRange = Range(deletedRange, in: scriptText) {
            pushUndoState(kind: .deleteBackward)
            scriptText.removeSubrange(stringRange)
            selectionRange = clampedRange(NSRange(location: deletedRange.location, length: 0))
        }
    }

    mutating func deleteForward() {
        let range = clampedRange(selectionRange)
        preferredVerticalColumn = nil

        if range.length > 0 {
            replaceSelection(with: "")
            return
        }

        guard range.location < scriptText.utf16.count else {
            return
        }

        let text = scriptText as NSString
        let deletedRange = text.rangeOfComposedCharacterSequence(at: range.location)
        if let stringRange = Range(deletedRange, in: scriptText) {
            pushUndoState(kind: .deleteForward)
            scriptText.removeSubrange(stringRange)
            selectionRange = clampedRange(NSRange(location: range.location, length: 0))
        }
    }

    mutating func undo() {
        guard let previousState = undoStack.popLast() else {
            return
        }

        redoStack.append(currentState)
        restore(previousState)
    }

    mutating func redo() {
        guard let nextState = redoStack.popLast() else {
            return
        }

        undoStack.append(currentState)
        restore(nextState)
    }

    private mutating func clampSelectionRange() {
        selectionRange = clampedRange(selectionRange)
    }

    private var currentState: EditingState {
        EditingState(scriptText: scriptText, selectionRange: clampedRange(selectionRange))
    }

    private mutating func pushUndoState() {
        undoStack.append(currentState)
        redoStack.removeAll()
        activeEditTransactionKind = nil
        pendingSelectionRangeAfterEdit = nil
    }

    private mutating func pushUndoState(kind: EditTransactionKind?) {
        if let kind, activeEditTransactionKind == kind {
            return
        }

        undoStack.append(currentState)
        redoStack.removeAll()
        activeEditTransactionKind = kind
        pendingSelectionRangeAfterEdit = nil
    }

    private mutating func restore(_ state: EditingState) {
        scriptText = state.scriptText
        preferredVerticalColumn = nil
        activeEditTransactionKind = nil
        pendingSelectionRangeAfterEdit = nil
        selectionRange = clampedRange(state.selectionRange)
    }

    private func keyboardEditInfo(for newText: String) -> (kind: EditTransactionKind?, selectionRange: NSRange?, shouldEndUndoGroup: Bool) {
        let range = clampedRange(selectionRange)
        let oldText = scriptText as NSString
        let newNSString = newText as NSString
        let insertedLength = newNSString.length - (oldText.length - range.length)

        if insertedLength > 0,
           range.location <= newNSString.length,
           range.location + insertedLength <= newNSString.length,
           range.location + range.length <= oldText.length {
            let insertedText = newNSString.substring(with: NSRange(location: range.location, length: insertedLength))
            let expectedText = oldText.replacingCharacters(in: range, with: insertedText)
            if expectedText == newText {
                let expectedRange = NSRange(location: range.location + insertedLength, length: 0)
                if insertedText.count == 1 {
                    return (.keyboardTyping, expectedRange, isUndoGroupingSeparator(insertedText))
                }

                return (nil, expectedRange, true)
            }
        }

        if range.length == 0,
           range.location > 0 {
            let deletedRange = oldText.rangeOfComposedCharacterSequence(at: range.location - 1)
            let expectedText = oldText.replacingCharacters(in: deletedRange, with: "")
            if expectedText == newText {
                return (.deleteBackward, NSRange(location: deletedRange.location, length: 0), false)
            }
        }

        if range.length == 0,
           range.location < oldText.length {
            let deletedRange = oldText.rangeOfComposedCharacterSequence(at: range.location)
            let expectedText = oldText.replacingCharacters(in: deletedRange, with: "")
            if expectedText == newText {
                return (.deleteForward, NSRange(location: range.location, length: 0), false)
            }
        }

        if range.length > 0 {
            let expectedText = oldText.replacingCharacters(in: range, with: "")
            if expectedText == newText {
                return (nil, NSRange(location: range.location, length: 0), true)
            }
        }

        return (nil, nil, true)
    }

    private func isUndoGroupingSeparator(_ text: String) -> Bool {
        text == " " || text == "\n" || text == "\t"
    }

    private func clampedRange(_ range: NSRange) -> NSRange {
        let textLength = scriptText.utf16.count

        guard range.location != NSNotFound else {
            return NSRange(location: textLength, length: 0)
        }

        let location = min(max(range.location, 0), textLength)
        let length = max(range.length, 0)
        let upperBound = min(location + length, textLength)
        return NSRange(location: location, length: max(upperBound - location, 0))
    }

    private func lineBounds(containing location: Int) -> (start: Int, end: Int) {
        let text = scriptText as NSString
        let textLength = text.length
        let safeLocation = min(max(location, 0), textLength)
        let previousNewlineRange = text.range(of: "\n", options: .backwards, range: NSRange(location: 0, length: safeLocation))
        let nextNewlineRange = text.range(of: "\n", range: NSRange(location: safeLocation, length: textLength - safeLocation))
        let lineStart = previousNewlineRange.location == NSNotFound ? 0 : previousNewlineRange.location + previousNewlineRange.length
        let lineEnd = nextNewlineRange.location == NSNotFound ? textLength : nextNewlineRange.location
        return (lineStart, lineEnd)
    }

    private func previousLineBounds(before line: (start: Int, end: Int)) -> (start: Int, end: Int)? {
        guard line.start > 0 else {
            return nil
        }

        let previousLineEnd = line.start - 1
        let text = scriptText as NSString
        let previousNewlineRange = text.range(of: "\n", options: .backwards, range: NSRange(location: 0, length: previousLineEnd))
        let previousLineStart = previousNewlineRange.location == NSNotFound ? 0 : previousNewlineRange.location + previousNewlineRange.length
        return (previousLineStart, previousLineEnd)
    }

    private func nextLineBounds(after line: (start: Int, end: Int)) -> (start: Int, end: Int)? {
        let text = scriptText as NSString
        let textLength = text.length
        guard line.end < textLength else {
            return nil
        }

        let nextLineStart = line.end + 1
        let nextNewlineRange = text.range(of: "\n", range: NSRange(location: nextLineStart, length: textLength - nextLineStart))
        let nextLineEnd = nextNewlineRange.location == NSNotFound ? textLength : nextNewlineRange.location
        return (nextLineStart, nextLineEnd)
    }
}
