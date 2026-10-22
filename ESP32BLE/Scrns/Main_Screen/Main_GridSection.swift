/*
 This is the UI layer for the grid.
 It attaches the drag/swipe gestures to each button and
 calls the move handler when a drag direction is detected.
 */

/*
 MainScreenGridSection.swift for gesture detection,
 then follow the move call into MainScreenButtonBehavior.swift
 then into ContentView.swift where the data is actually changed.
 */
import SwiftUI
import UIKit

typealias GridDimensions = (columns: Int, rows: Int)

// MARK: - BM:🔆 grid dimensions

func functionKeyGridDimensions(for itemCount: Int) -> GridDimensions {
    let preferredDimensions: [Int: GridDimensions] = [
		
		1: (1, 1),
		2: (2, 1),
		3: (3, 1),
		4: (2, 2),
		6: (3, 2),
		8: (4, 2),
		9: (3, 3),

		10: (5, 2),
		12: (4, 3),
        15: (5, 3),
        18: (6, 3),

		20: (5, 4),
		21: (7, 3),
			24: (6, 4),
			25: (5, 5),
			27: (9, 3),
			28: (7, 4),

			30: (6, 5),
			32: (8, 4),
        35: (7, 5),
		36: (6, 6),

			40: (8, 5),
			42: (7, 6),
			44: (11, 4),
			45: (9, 5),
        48: (8, 6),
			49: (7, 7),

			50: (10, 5),
        54: (9, 6),
			56: (8, 7),
		
			60: (10, 6),
        63: (9, 7),
			64: (8, 8),
			66: (11, 6),
			
			70: (10, 7),
			72: (9, 8),
			75: (15, 5),
			78: (13, 6),
			
			80: (10, 8),
        84: (12, 7),
        88: (11, 8),
		
				90: (10, 9),
				96: (12, 8),
				98: (14, 7),
        99: (11, 9),
        100: (10, 10),
    ]

    if let preferred = preferredDimensions[itemCount] {
        return preferred
    }

    guard itemCount > 0 else {
        return (1, 1)
    }

    let baseColumns = Int(ceil(sqrt(Double(itemCount))))
    var columns = max(baseColumns, Int(ceil(Double(itemCount) / Double(baseColumns))))
    var rows = Int(ceil(Double(itemCount) / Double(columns)))

    if rows > columns {
        swap(&rows, &columns)
    }

    return (columns, rows)
}

struct MainScreenGridSection<ButtonLabel: View>: View {
    @Environment(\.scenePhase) private var scenePhase
    let availableWidth: CGFloat
    let reservedBottomInset: CGFloat
    let functionKeys: [FunctionKeyEntry]
    let visibleBoxCount: Int
    let visibleGridDimensions: GridDimensions
    let mainGridButtonSpacing: CGFloat
    let mainGridButtonCornerRadius: CGFloat
    let boxFontSize: Double
    let clipsButtonContentToBounds: Bool
    let isGridEditModeEnabled: Bool
    let selectedActionMenuIndex: Int?
    let renderedButtonFrameRefreshToken: Int
    let bleSendEnabled: Bool
    let onButtonClick: () -> Void
    let isHiddenEntry: (FunctionKeyEntry) -> Bool
    let isEmptyEntry: (FunctionKeyEntry) -> Bool
    let isInteractiveWidgetEntry: (FunctionKeyEntry) -> Bool
    let isSimpleOrdinarySoundEntry: (FunctionKeyEntry) -> Bool
    let midiContext: (FunctionKeyEntry, Int) -> MainMIDITouchContext?
    let midiActivations: MainMIDIActivationRegistry
    let midiInputEnabled: Bool
    let onMIDITouchDown: (MainMIDITouchContext) -> UUID?
    let onMIDITouchUp: (UUID) -> Void
    let onMIDITogglePress: (MainMIDITouchContext, UUID?) -> Void
    let sendLine: (FunctionKeyEntry) -> Void
    let onSimpleOrdinarySoundSingleTap: (FunctionKeyEntry, Int) -> Void
    let onSimpleOrdinarySoundDoubleTap: (FunctionKeyEntry, Int) -> Void
    let onBeginSlotEditing: (Int) -> Void
    let buttonLabel: (FunctionKeyEntry, Int, CGFloat, CGSize) -> ButtonLabel
    let dragGesture: (FunctionKeyEntry, Int, GridDimensions) -> AnyGesture<DragGesture.Value>
    let onRenderedButtonFrame: (Int, CGRect, GridDimensions) -> Void
    let onRenderedGridFrame: (CGRect) -> Void
    let onSingleEditTap: (FunctionKeyEntry, Int, CGRect, GridDimensions) -> Void
    let onResizeSlot: (FunctionKeyEntry, Int, GridDimensions) -> Void
    let onResetSlotSize: (FunctionKeyEntry, Int, GridDimensions) -> Void
    let onDeleteSlot: (FunctionKeyEntry, Int) -> Void
    @State private var longPressedEditIndex: Int?
    @State private var slideCoordinator = MIDISlideCoordinator()

    var body: some View {
        GeometryReader { geometry in
            let gridDimensions = visibleGridDimensions
            let totalGridSpacing = mainGridButtonSpacing * CGFloat(max(gridDimensions.rows - 1, 0))
            let availableGridHeight = geometry.size.height.isFinite ? max(0, geometry.size.height - totalGridSpacing - (reservedBottomInset-30)) : 0
            let buttonHeight = availableGridHeight / CGFloat(max(gridDimensions.rows, 1))
            let totalColumnSpacing = mainGridButtonSpacing * CGFloat(max(gridDimensions.columns - 1, 0))
            let safeAvailableWidth = availableWidth.isFinite ? max(0, availableWidth) : 0
            let availableGridWidth = max(0, safeAvailableWidth - totalColumnSpacing)
            let buttonWidth = availableGridWidth / CGFloat(max(gridDimensions.columns, 1))
            let visibleEntries = Array(functionKeys.prefix(visibleBoxCount).enumerated())
            let visualGridHeight = renderedButtonGridVisualHeight(
                visibleEntries: visibleEntries,
                buttonWidth: buttonWidth,
                buttonHeight: buttonHeight,
                spacing: mainGridButtonSpacing,
                gridDimensions: gridDimensions,
                containerHeight: geometry.size.height
            )

            ZStack(alignment: .topLeading) {
                ForEach(visibleEntries, id: \.offset) { index, entry in
                    if isButtonContinuationEntry(entry) {
                        EmptyView()
                    } else {
                        let shape = buttonShape(startingAt: index, gridDimensions: gridDimensions)
                        let resolvedButtonWidth = resolvedWidth(
                            buttonWidth: buttonWidth,
                            spacing: mainGridButtonSpacing,
                            span: shape.width
                        )
                        let resolvedButtonHeight = resolvedHeight(
                            buttonHeight: buttonHeight,
                            spacing: mainGridButtonSpacing,
                            span: shape.height
                        )
                        let origin = buttonOrigin(
                            index: index,
                            buttonWidth: buttonWidth,
                            buttonHeight: buttonHeight,
                            spacing: mainGridButtonSpacing,
                            gridDimensions: gridDimensions
                        )

                        gridButtonView(
                            entry: entry,
                            index: index,
                            buttonHeight: resolvedButtonHeight,
                            buttonSize: CGSize(width: resolvedButtonWidth, height: resolvedButtonHeight),
                            buttonFrame: CGRect(
                                x: origin.x,
                                y: origin.y,
                                width: resolvedButtonWidth,
                                height: resolvedButtonHeight
                            ),
                            gridDimensions: gridDimensions
                        )
                        .frame(width: resolvedButtonWidth, height: resolvedButtonHeight)
                        .modifier(MainGridButtonBoundsClip(cornerRadius: mainGridButtonCornerRadius, isEnabled: clipsButtonContentToBounds))
                        .overlay {
                            if selectedActionMenuIndex == index {
                                RoundedRectangle(cornerRadius: mainGridButtonCornerRadius)
                                    .strokeBorder(Color.white, lineWidth: 2)
                                    .allowsHitTesting(false)
                            }
                        }
                        .position(
                            x: origin.x + (resolvedButtonWidth / 2),
                            y: origin.y + (resolvedButtonHeight / 2)
                        )
                        .task(id: renderedButtonFrameTaskID(
                            index: index,
                            buttonFrame: CGRect(
                                x: origin.x,
                                y: origin.y,
                                width: resolvedButtonWidth,
                                height: resolvedButtonHeight
                            ),
                            gridDimensions: gridDimensions,
                            refreshToken: renderedButtonFrameRefreshToken
                        )) {
                            onRenderedButtonFrame(
                                index,
                                CGRect(
                                    x: origin.x,
                                    y: origin.y,
                                    width: resolvedButtonWidth,
                                    height: resolvedButtonHeight
                                ),
                                gridDimensions
                            )
                        }
                    }
                }
            }
            .frame(width: safeAvailableWidth, height: geometry.size.height, alignment: .topLeading)
            .onChange(of: geometry.frame(in: .global)) {
                slideCoordinator.cancel()
            }
            .task(id: renderedGridFrameTaskID(
                width: safeAvailableWidth,
                height: visualGridHeight
            )) {
                onRenderedGridFrame(CGRect(
                    x: 0,
                    y: 0,
                    width: safeAvailableWidth,
                    height: visualGridHeight
                ))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDisappear {
            longPressedEditIndex = nil
            slideCoordinator.cancel()
        }
        .onChange(of: midiActivations.generation) { slideCoordinator.cancel() }
        .onChange(of: midiInputEnabled) { slideCoordinator.cancel() }
        .onChange(of: scenePhase) { slideCoordinator.cancel() }
        .onChange(of: isGridEditModeEnabled) { slideCoordinator.cancel() }
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

    private struct ButtonGridShape {
        let width: Int
        let height: Int
    }

    private func buttonShape(startingAt index: Int, gridDimensions: GridDimensions) -> ButtonGridShape {
        guard functionKeys.indices.contains(index),
              !isButtonContinuationEntry(functionKeys[index]) else {
            return ButtonGridShape(width: 1, height: 1)
        }

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
        let columns = max(gridDimensions.columns, 1)

        for rowOffset in 0..<shape.height {
            for columnOffset in 0..<shape.width {
                guard rowOffset != 0 || columnOffset != 0 else {
                    continue
                }

                let slotIndex = index + (rowOffset * columns) + columnOffset
                let token = rowOffset == 0 ? wideButtonContinuationToken : blockButtonContinuationToken
                guard functionKeys.indices.contains(slotIndex),
                      slotIndex < visibleBoxCount,
                      functionKeys[slotIndex].rawLine.trimmingCharacters(in: .whitespacesAndNewlines) == token else {
                    return false
                }
            }
        }

        return true
    }

    private func resolvedWidth(buttonWidth: CGFloat, spacing: CGFloat, span: Int) -> CGFloat {
        let boundedSpan = max(1, min(span, 3))
        return (buttonWidth * CGFloat(boundedSpan)) + (spacing * CGFloat(boundedSpan - 1))
    }

    private func resolvedHeight(buttonHeight: CGFloat, spacing: CGFloat, span: Int) -> CGFloat {
        let boundedSpan = max(1, min(span, 3))
        return (buttonHeight * CGFloat(boundedSpan)) + (spacing * CGFloat(boundedSpan - 1))
    }

    private func buttonOrigin(
        index: Int,
        buttonWidth: CGFloat,
        buttonHeight: CGFloat,
        spacing: CGFloat,
        gridDimensions: GridDimensions
    ) -> CGPoint {
        let columns = max(gridDimensions.columns, 1)
        let row = index / columns
        let column = index % columns

        return CGPoint(
            x: CGFloat(column) * (buttonWidth + spacing),
            y: CGFloat(row) * (buttonHeight + spacing)
        )
    }

    private func renderedButtonGridVisualHeight(
        visibleEntries: [(offset: Int, element: FunctionKeyEntry)],
        buttonWidth: CGFloat,
        buttonHeight: CGFloat,
        spacing: CGFloat,
        gridDimensions: GridDimensions,
        containerHeight: CGFloat
    ) -> CGFloat {
        let visualMaxY = visibleEntries.reduce(CGFloat.zero) { currentMaxY, visibleEntry in
            guard !isButtonContinuationEntry(visibleEntry.element) else {
                return currentMaxY
            }

            let shape = buttonShape(startingAt: visibleEntry.offset, gridDimensions: gridDimensions)
            let origin = buttonOrigin(
                index: visibleEntry.offset,
                buttonWidth: buttonWidth,
                buttonHeight: buttonHeight,
                spacing: spacing,
                gridDimensions: gridDimensions
            )
            let resolvedButtonHeight = resolvedHeight(
                buttonHeight: buttonHeight,
                spacing: spacing,
                span: shape.height
            )

            return max(currentMaxY, origin.y + resolvedButtonHeight)
        }

        return visualMaxY > 0 ? visualMaxY : containerHeight
    }

    private func renderedButtonFrameTaskID(
        index: Int,
        buttonFrame: CGRect,
        gridDimensions: GridDimensions,
        refreshToken: Int
    ) -> String {
        "\(index)-\(buttonFrame.minX)-\(buttonFrame.minY)-\(buttonFrame.width)-\(buttonFrame.height)-\(gridDimensions.columns)-\(gridDimensions.rows)-\(refreshToken)"
    }

    private func renderedGridFrameTaskID(width: CGFloat, height: CGFloat) -> String {
        "\(width)-\(height)"
    }

    @ViewBuilder
    private func gridButtonView(
        entry: FunctionKeyEntry,
        index: Int,
        buttonHeight: CGFloat,
        buttonSize: CGSize,
        buttonFrame: CGRect,
        gridDimensions: GridDimensions
    ) -> some View {
        if !isGridEditModeEnabled && isSimpleOrdinarySoundEntry(entry) {
            buttonLabel(entry, index, buttonHeight, buttonSize)
                .contentShape(Rectangle())
                .gesture(
                    TapGesture(count: 2)
                        .exclusively(before: TapGesture(count: 1))
                        .onEnded { gesture in
                            guard longPressedEditIndex != index else {
                                longPressedEditIndex = nil
                                return
                            }

                            onButtonClick()

                            guard bleSendEnabled else {
                                return
                            }

                            switch gesture {
                            case .first:
                                onSimpleOrdinarySoundDoubleTap(entry, index)
                            case .second:
                                onSimpleOrdinarySoundSingleTap(entry, index)
                            }
                        }
                )
        } else if !isGridEditModeEnabled && isInteractiveWidgetEntry(entry) {
            buttonLabel(entry, index, buttonHeight, buttonSize)
                .contentShape(Rectangle())
        } else if !isGridEditModeEnabled, let context = midiContext(entry, index) {
            MIDINoteButton(
                context: context,
                slideCoordinator: slideCoordinator,
                buttonFrame: buttonFrame,
                activeToken: midiActivations.activeToken(for: context),
                isEnabled: midiInputEnabled && scenePhase == .active,
                cornerRadius: mainGridButtonCornerRadius,
                onDown: onMIDITouchDown,
                onUp: onMIDITouchUp,
                onTogglePress: onMIDITogglePress
            ) {
                buttonLabel(entry, index, buttonHeight, buttonSize)
            }
        } else {
            editingGestures(
                Button {
                    guard longPressedEditIndex != index else {
                        longPressedEditIndex = nil
                        return
                    }

                    guard !isGridEditModeEnabled else {
                        return
                    }

                    onButtonClick()

                    guard bleSendEnabled else {
                        return
                    }

                    sendLine(entry)
                } label: {
                    buttonLabel(entry, index, buttonHeight, buttonSize)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle()),
                entry: entry,
                index: index,
                buttonFrame: buttonFrame,
                gridDimensions: gridDimensions
            )
        }
    }

    @ViewBuilder
    private func editingGestures<Content: View>(
        _ content: Content,
        entry: FunctionKeyEntry,
        index: Int,
        buttonFrame: CGRect,
        gridDimensions: GridDimensions
    ) -> some View {
        if isGridEditModeEnabled {
            content
                .simultaneousGesture(dragGesture(entry, index, gridDimensions))
                .simultaneousGesture(
                    TapGesture()
                        .onEnded {
                            onSingleEditTap(entry, index, buttonFrame, gridDimensions)
                        }
                )
                .simultaneousGesture(
                    slotEditorLongPressGesture(index: index)
                )
        } else {
            content
        }
    }

    private func slotEditorLongPressGesture(index: Int) -> some Gesture {
        LongPressGesture(minimumDuration: 0.25)
            .onEnded { _ in
                guard isGridEditModeEnabled else {
                    return
                }

                longPressedEditIndex = index
                onBeginSlotEditing(index)
            }
    }
}
// MARK: - BM:🔠🔢 MIDI NOTE BTN
private struct MIDINoteButton<Label: View>: View {
    private let pressedAccentColor = Color(red: 0, green: 1, blue: 0)
    private let pressedAccentStrokeWidth: CGFloat = 3

    let context: MainMIDITouchContext
    let slideCoordinator: MIDISlideCoordinator
    let buttonFrame: CGRect
    let activeToken: UUID?
    let isEnabled: Bool
    let cornerRadius: CGFloat
    let onDown: (MainMIDITouchContext) -> UUID?
    let onUp: (UUID) -> Void
    let onTogglePress: (MainMIDITouchContext, UUID?) -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        ZStack {
            label()
                .allowsHitTesting(false)

            if activeToken != nil {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        pressedAccentColor,
                        lineWidth: pressedAccentStrokeWidth
                    )
                    .allowsHitTesting(false)
            }

            MIDITouchView(
                touchContext: context,
                slideCoordinator: slideCoordinator,
                buttonFrame: buttonFrame,
                activeToken: activeToken,
                isEnabled: isEnabled,
                onDown: onDown,
                onUp: onUp,
                onTogglePress: onTogglePress
            )
        }
    }
}

private struct MIDITouchView: UIViewRepresentable {
    let touchContext: MainMIDITouchContext
    let slideCoordinator: MIDISlideCoordinator
    let buttonFrame: CGRect
    let activeToken: UUID?
    let isEnabled: Bool
    let onDown: (MainMIDITouchContext) -> UUID?
    let onUp: (UUID) -> Void
    let onTogglePress: (MainMIDITouchContext, UUID?) -> Void

    func makeUIView(context: Context) -> MIDITouchCaptureView {
        MIDITouchCaptureView()
    }

    func updateUIView(_ uiView: MIDITouchCaptureView, context: Context) {
        uiView.configure(
            context: touchContext,
            slideCoordinator: slideCoordinator,
            buttonFrame: buttonFrame,
            activeToken: activeToken,
            isEnabled: isEnabled,
            onDown: onDown,
            onUp: onUp,
            onTogglePress: onTogglePress
        )
    }

    static func dismantleUIView(_ uiView: MIDITouchCaptureView, coordinator: ()) {
        uiView.cancelActiveTouch()
        uiView.unregisterSlideTarget()
    }
}

// MARK: - BM:🅱️ Every note touch owns an activation; the first finger leaving its button becomes the sole slider.
@MainActor
private final class MIDISlideCoordinator {
    private final class TouchOwner {
        let touch: UITouch
        weak var source: MIDITouchCaptureView?
        var targetContext: MainMIDITouchContext?
        var token: UUID?
        var release: ((UUID) -> Void)?

        init(touch: UITouch, source: MIDITouchCaptureView) {
            self.touch = touch
            self.source = source
        }
    }

    private let targets = NSHashTable<MIDITouchCaptureView>.weakObjects()
    private var owners: [ObjectIdentifier: TouchOwner] = [:]
    private var sliderID: ObjectIdentifier?

    func register(_ view: MIDITouchCaptureView) {
        targets.add(view)
    }

    func unregister(_ view: MIDITouchCaptureView) {
        let affected = owners.values.filter {
            $0.source === view || $0.targetContext == view.context
        }
        for owner in affected { end(owner.touch) }
        targets.remove(view)
    }

    func begin(_ touch: UITouch, from view: MIDITouchCaptureView) {
        let id = ObjectIdentifier(touch)
        guard owners[id] == nil, view.slideEligible else { return }
        let owner = TouchOwner(touch: touch, source: view)
        owners[id] = owner
        transition(owner, to: view)
    }

    func move(_ touch: UITouch) {
        let id = ObjectIdentifier(touch)
        guard let owner = owners[id] else { return }
        guard let source = owner.source, let window = source.window else {
            end(touch)
            return
        }
        if sliderID != id {
            guard !source.bounds.contains(touch.location(in: source)) else { return }
            guard sliderID == nil else {
                end(touch)
                return
            }
            sliderID = id
        }

        let target = targets.allObjects.first { view in
            view.window === window && view.isUserInteractionEnabled &&
                view.slideEligible && view.bounds.contains(touch.location(in: view))
        }
        transition(owner, to: target)
    }

    func end(_ touch: UITouch) {
        let id = ObjectIdentifier(touch)
        guard let owner = owners.removeValue(forKey: id) else { return }
        if sliderID == id { sliderID = nil }
        transition(owner, to: nil)
    }

    func cancelTouches(from view: MIDITouchCaptureView) {
        let affected = owners.values.filter { $0.source === view }
        for owner in affected { end(owner.touch) }
    }

    func cancel() {
        let cancelled = Array(owners.values)
        owners.removeAll()
        sliderID = nil
        for owner in cancelled { transition(owner, to: nil) }
    }

    private func transition(_ owner: TouchOwner, to view: MIDITouchCaptureView?) {
        let context = view?.context
        guard context != owner.targetContext else { return }
        let oldToken = owner.token
        let oldRelease = owner.release
        owner.token = nil
        owner.release = nil
        owner.targetContext = context
        if let oldToken { oldRelease?(oldToken) }
        if let view {
            owner.release = view.slideReleaseHandler
            owner.token = view.beginSlideNote()
        }
    }
}

private final class MIDITouchCaptureView: UIView {
    fileprivate var context: MainMIDITouchContext?
    private var slideCoordinator: MIDISlideCoordinator?
    private var buttonFrame: CGRect?

    fileprivate var slideEligible: Bool {
        guard let context else { return false }
        if case .note(_, _, .momentary) = context.message { return true }
        return false
    }

    fileprivate func beginSlideNote() -> UUID? {
        guard isUserInteractionEnabled, let context else { return nil }
        return onDown?(context)
    }

    fileprivate var slideReleaseHandler: ((UUID) -> Void)? { onUp }

    func unregisterSlideTarget() {
        slideCoordinator?.unregister(self)
    }
    private var onDown: ((MainMIDITouchContext) -> UUID?)?
    private var onUp: ((UUID) -> Void)?
    private var onTogglePress: ((MainMIDITouchContext, UUID?) -> Void)?
    private var activeTouch: UITouch?
    private var activationToken: UUID?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isMultipleTouchEnabled = false
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            cancelActiveTouch()
            unregisterSlideTarget()
        } else {
            slideCoordinator?.register(self)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        context: MainMIDITouchContext,
        slideCoordinator: MIDISlideCoordinator,
        buttonFrame: CGRect,
        activeToken: UUID?,
        isEnabled: Bool,
        onDown: @escaping (MainMIDITouchContext) -> UUID?,
        onUp: @escaping (UUID) -> Void,
        onTogglePress: @escaping (MainMIDITouchContext, UUID?) -> Void
    ) {
        if self.context != context || self.buttonFrame != buttonFrame ||
            self.slideCoordinator !== slideCoordinator || !isEnabled {
            self.slideCoordinator?.cancel()
        }
        if activeTouch != nil &&
            (self.context != context || !isEnabled ||
             (context.mode == .momentary && activationToken != activeToken)) {
            cancelActiveTouch()
        }

        if self.slideCoordinator !== slideCoordinator {
            unregisterSlideTarget()
        }
        self.slideCoordinator = slideCoordinator
        self.buttonFrame = buttonFrame
        self.context = context
        self.onDown = onDown
        self.onUp = onUp
        self.onTogglePress = onTogglePress
        isUserInteractionEnabled = isEnabled
        isMultipleTouchEnabled = slideEligible
        slideCoordinator.register(self)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isUserInteractionEnabled, let context else { return }
        if slideEligible {
            for touch in touches where touch.type == .direct {
                slideCoordinator?.begin(touch, from: self)
            }
            return
        }

        guard activeTouch == nil, let touch = touches.first else { return }
        activeTouch = touch
        activationToken = onDown?(context)
        if context.mode == .toggle {
            onTogglePress?(context, activationToken)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches { slideCoordinator?.move(touch) }
        guard let activeTouch,
              touches.contains(where: { $0 === activeTouch }),
              !bounds.contains(activeTouch.location(in: self)) else { return }
        cancelActiveTouch()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches { slideCoordinator?.end(touch) }
        guard let activeTouch,
              touches.contains(where: { $0 === activeTouch }) else { return }
        cancelActiveTouch()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches { slideCoordinator?.end(touch) }
        guard let activeTouch,
              touches.contains(where: { $0 === activeTouch }) else { return }
        cancelActiveTouch()
    }

    // MARK: - BM:🅱️ Rejected presses have no token; stale releases cannot consume a newer activation.
    func cancelActiveTouch() {
        slideCoordinator?.cancelTouches(from: self)
        let token = activationToken
        activeTouch = nil
        activationToken = nil
        if context?.mode == .momentary, let token {
            onUp?(token)
        }
    }
}

private struct MainGridButtonBoundsClip: ViewModifier {
    let cornerRadius: CGFloat
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content.clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            content
        }
    }
}
