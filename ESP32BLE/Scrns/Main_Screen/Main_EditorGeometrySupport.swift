import Foundation
import SwiftUI

enum EditorGeometryProbeTarget: String, CaseIterable {
    case screen = "SCREEN"
    case editorContainer = "EDITOR CONTAINER"
    case fullScreenZStack = "FULL-SCREEN ZSTACK"
    case smartView = "smartView"
    case hStack = "HStack"
    case leftPanel = "LEFT PANEL"
    case commandPanel = "COMMAND PANEL"
    case buttonPanel = "BUTTON PANEL"
    case sfPanel = "SF"
    case smartScriptTextEditor = "SmartScriptTextEditor"
    case leftTop = "LEFT TOP"
    case centreCommandTop = "COMMAND TOP"
    case commandDescription = "COMMAND DESCRIPTION"
    case rightPreviewArea = "PREVIEW AREA"
    case previewFootprint = "PREVIEW FOOTPRINT"
    case actualPreviewButton = "PREVIEW BUTTON"
    case slider = "SLIDER"
    case rightControlRow = "CONTROL ROW"
    case rightControlRowCell = "CONTROL ROW CELL"
    case rightUtilityRow = "UTILITY ROW"
    case rightUtilityVisibleCell = "UTILITY CELL VISIBLE"
    case rightTableRegion = "COLOUR/SF TABLE"
    case rightTableCell = "RIGHT TABLE CELL"
    case rightTableVisibleCell = "RIGHT TABLE CELL VISIBLE"
    case testButton = "TEST"
    case testVisibleButton = "TEST VISIBLE"
    case closeButton = "CLOSE"
    case closeVisibleButton = "CLOSE VISIBLE"
    case commandTableRow = "TABLE ROW"
}

struct EditorGeometryPreferenceKey: PreferenceKey {
    static var defaultValue: [EditorGeometryProbeTarget: CGRect] = [:]

    static func reduce(
        value: inout [EditorGeometryProbeTarget: CGRect],
        nextValue: () -> [EditorGeometryProbeTarget: CGRect]
    ) {
        value.merge(nextValue()) { _, newValue in newValue }
    }
}

struct SmartIPhoneRightTableVisibleCellHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat?

    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        value = nextValue() ?? value
    }
}

struct IPadBottomToolbarFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect?

    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = nextValue() ?? value
    }
}

private struct SmartIPhoneRightTableVisibleCellHeightReader: ViewModifier {
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.background {
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: SmartIPhoneRightTableVisibleCellHeightPreferenceKey.self,
                        value: geometry.size.height
                    )
                }
            }
        } else {
            content
        }
    }
}

private struct EditorGeometryProbeModifier: ViewModifier {
    let target: EditorGeometryProbeTarget
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.background {
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: EditorGeometryPreferenceKey.self,
                        value: [target: geometry.frame(in: .global)]
                    )
                }
            }
        } else {
            content
        }
    }
}

struct IPhoneButtonBrightnessTouchOverlay: View {
    let destinationFrame: CGRect
    let onBrightnessGesture: (CGPoint, CGFloat) -> Void

    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.001))
            .frame(width: destinationFrame.width, height: destinationFrame.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        onBrightnessGesture(value.location, destinationFrame.height)
                    }
                    .onEnded { value in
                        onBrightnessGesture(value.location, destinationFrame.height)
                    }
            )
    }
}

struct IPhoneButtonBrightnessSliderFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect?

    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        if let nextValue = nextValue() {
            value = nextValue
        }
    }
}

extension View {
    func smartIPhoneRightTableVisibleCellHeightReader(isEnabled: Bool) -> some View {
        modifier(SmartIPhoneRightTableVisibleCellHeightReader(isEnabled: isEnabled))
    }

    func editorGeometryProbe(_ target: EditorGeometryProbeTarget, isEnabled: Bool) -> some View {
        modifier(EditorGeometryProbeModifier(target: target, isEnabled: isEnabled))
    }

    @ViewBuilder
    func optionalEditorGeometryProbe(_ target: EditorGeometryProbeTarget?, isEnabled: Bool) -> some View {
        if let target {
            editorGeometryProbe(target, isEnabled: isEnabled)
        } else {
            self
        }
    }

    func iPhoneButtonBrightnessSliderFrameReporter() -> some View {
        background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: IPhoneButtonBrightnessSliderFramePreferenceKey.self,
                    value: geometry.frame(in: .global)
                )
            }
        }
    }
}

struct DebugEditorGeometryOverlay: View {
    let frames: [EditorGeometryProbeTarget: CGRect]

    var body: some View {
        ScrollView(.vertical) {
            Text(lines.joined(separator: "\n"))
                .font(.system(size: 8, weight: .regular, design: .monospaced))
                .foregroundStyle(.white)
                .textSelection(.enabled)
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 330, height: 360, alignment: .topLeading)
        .background(Color.black.opacity(0.72))
        .allowsHitTesting(false)
    }

    private var lines: [String] {
        [
            "iPad BUTTON Column Geometry (.global)",
            "x y w h maxX maxY",
            "FRAMES",
            frameLine(for: .buttonPanel),
            frameLine(for: .rightPreviewArea),
            frameLine(for: .previewFootprint),
            frameLine(for: .actualPreviewButton),
            frameLine(for: .slider),
            frameLine(for: .rightTableRegion),
            frameLine(for: .rightUtilityRow),
            frameLine(for: .rightUtilityVisibleCell),
            "RELATIONSHIPS",
            deltaLine("preview.bottom -> colour.top", .rightTableRegion, .rightPreviewArea, \.minY, \.maxY),
            deltaLine("colour.bottom -> column.bottom", .buttonPanel, .rightTableRegion, \.maxY, \.maxY),
            deltaLine("preview button top - area top", .actualPreviewButton, .rightPreviewArea, \.minY, \.minY),
            deltaLine("preview button bottom - area bottom", .actualPreviewButton, .rightPreviewArea, \.maxY, \.maxY),
            deltaLine("slider top - preview area top", .slider, .rightPreviewArea, \.minY, \.minY),
            deltaLine("slider bottom - preview area bottom", .slider, .rightPreviewArea, \.maxY, \.maxY),
            "PROPORTIONS",
            proportionLine("preview / column", .rightPreviewArea, .buttonPanel),
            proportionLine("preview button / column", .actualPreviewButton, .buttonPanel),
            proportionLine("slider / column", .slider, .buttonPanel),
            proportionLine("colour / column", .rightTableRegion, .buttonPanel),
            proportionLine("utility first cell / column", .rightUtilityRow, .buttonPanel)
        ]
    }

    private func frameLine(for target: EditorGeometryProbeTarget) -> String {
        guard let frame = frames[target] else {
            return "\(target.rawValue): --"
        }

        return "\(target.rawValue): x:\(rounded(frame.minX)) y:\(rounded(frame.minY)) w:\(rounded(frame.width)) h:\(rounded(frame.height)) maxX:\(rounded(frame.maxX)) maxY:\(rounded(frame.maxY))"
    }

    private func heightLine(_ label: String, _ target: EditorGeometryProbeTarget) -> String {
        guard let frame = frames[target] else {
            return "\(label): --"
        }

        return "\(label): \(rounded(frame.height))"
    }

    private func deltaLine(
        _ label: String,
        _ firstTarget: EditorGeometryProbeTarget,
        _ secondTarget: EditorGeometryProbeTarget,
        _ firstValue: KeyPath<CGRect, CGFloat>,
        _ secondValue: KeyPath<CGRect, CGFloat>
    ) -> String {
        guard let firstFrame = frames[firstTarget],
              let secondFrame = frames[secondTarget] else {
            return "\(label): --"
        }

        return "\(label): \(rounded(firstFrame[keyPath: firstValue] - secondFrame[keyPath: secondValue]))"
    }

    private func heightDeltaLine(
        _ label: String,
        _ firstTarget: EditorGeometryProbeTarget,
        _ secondTarget: EditorGeometryProbeTarget
    ) -> String {
        guard let firstFrame = frames[firstTarget],
              let secondFrame = frames[secondTarget] else {
            return "\(label): --"
        }

        return "\(label): \(rounded(firstFrame.height - secondFrame.height))"
    }

    private func proportionLine(
        _ label: String,
        _ firstTarget: EditorGeometryProbeTarget,
        _ secondTarget: EditorGeometryProbeTarget
    ) -> String {
        guard let firstFrame = frames[firstTarget],
              let secondFrame = frames[secondTarget],
              secondFrame.height > 0 else {
            return "\(label): --"
        }

        return "\(label): \(rounded(firstFrame.height / secondFrame.height))"
    }

    private func rounded(_ value: CGFloat) -> String {
        String(format: "%.1f", Double(value))
    }
}
