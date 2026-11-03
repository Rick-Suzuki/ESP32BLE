import SwiftUI
import UIKit
import WebKit
import Foundation

struct MainScreenFilePreviewOverlay: View {
    let previewedFile: MainScreen.PreviewedFile
    let onClose: () -> Void
    @State private var previewImage: UIImage?
    @State private var imageScale: CGFloat = 1
    @State private var lastImageScale: CGFloat = 1
    @State private var pinchStartScale: CGFloat = 1
    @State private var imageOffset: CGSize = .zero
    @State private var accumulatedImageOffset: CGSize = .zero

    private var plainTextPreviewFont: Font {
        guard UIDevice.current.userInterfaceIdiom == .phone else {
            return .system(.body, design: .monospaced)
        }

        return .system(
            size: UIFont.preferredFont(forTextStyle: .body).pointSize * 0.66,
            weight: .regular,
            design: .monospaced
        )
    }

    var body: some View {
        GeometryReader { geometry in
            let safeBottomInset = geometry.safeAreaInsets.bottom
            let maxPixelDimension = max(geometry.size.width, geometry.size.height) * UIScreen.main.scale

            ZStack(alignment: .bottomTrailing) {
                Color.black
                    .ignoresSafeArea()

                Group {
                    switch previewedFile {
                    case let .text(filename, contents):
                        if URL(fileURLWithPath: filename).pathExtension.lowercased() == "md" {
                            MarkdownFilePreviewWebView(markdown: contents)
                                .padding(.top, 68)
                                .padding(.bottom, safeBottomInset + 20)
                        } else {
                            ScrollView(.vertical) {
                                Text(contents)
                                    .font(plainTextPreviewFont)
                                    .foregroundStyle(.white)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 20)
                                    .padding(.top, 68)
                                    .padding(.bottom, safeBottomInset + 20)
                            }
                        }
                    case .image, .renderedImage:
                        GeometryReader { imageGeometry in
                            Group {
                                if let previewImage {
                                    Image(uiImage: previewImage)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: imageGeometry.size.width, height: imageGeometry.size.height)
                                        .scaleEffect(imageScale)
                                        .offset(imageOffset)
                                        .contentShape(Rectangle())
                                        .overlay {
                                            ImagePreviewGestureSurface(
                                                onPinchBegan: {
                                                    pinchStartScale = imageScale
                                                    lastImageScale = imageScale
                                                },
                                                onPinchChanged: { scale, location, containerSize in
                                                    updateImageMagnification(
                                                        gestureScale: scale,
                                                        location: location,
                                                        containerSize: containerSize
                                                    )
                                                },
                                                onPinchEnded: { scale, location, containerSize in
                                                    finishImageMagnification(
                                                        gestureScale: scale,
                                                        location: location,
                                                        containerSize: containerSize
                                                    )
                                                },
                                                onPanChanged: { translation, containerSize in
                                                    updateImagePan(translation: translation, containerSize: containerSize)
                                                },
                                                onPanEnded: { translation, containerSize in
                                                    finishImagePan(translation: translation, containerSize: containerSize)
                                                },
                                                onDoubleTap: resetImagePreviewTransform
                                            )
                                        }
                                } else {
                                    ProgressView()
                                        .tint(.white)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                }
                            }
                        }
                    }
                }

                Button("close") {
                    onClose()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(minWidth: 88)
                .frame(height: 44)
                .background(Color.gray.opacity(0.8))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.5), lineWidth: 1.5)
                }
                .clipShape(.rect(cornerRadius: 12))
                .padding(.trailing, 16)
                .padding(.bottom, safeBottomInset + 16)
            }
            .task(id: previewTaskID(maxPixelDimension: maxPixelDimension)) {
                loadPreviewImage(maxPixelDimension: maxPixelDimension)
            }
        }
        .ignoresSafeArea()
    }

    private func previewTaskID(maxPixelDimension: CGFloat) -> String {
        switch previewedFile {
        case let .text(filename, _):
            return "\(filename):text"
        case let .image(filename, _):
            return "\(filename):\(Int(maxPixelDimension.rounded(.up)))"
        case let .renderedImage(filename, _):
            return "\(filename):rendered"
        }
    }

    private func loadPreviewImage(maxPixelDimension: CGFloat) {
        switch previewedFile {
        case let .image(_, url):
            previewImage = downsampledUIImage(at: url, maxPixelDimension: maxPixelDimension)
            resetImagePreviewTransform()
        case let .renderedImage(_, image):
            previewImage = image
            resetImagePreviewTransform()
        default:
            previewImage = nil
            resetImagePreviewTransform()
        }
    }

    private func updateImageMagnification(
        gestureScale: CGFloat,
        location: CGPoint,
        containerSize: CGSize
    ) {
        let pinchScaleTolerance: CGFloat = 0.01

        if abs(gestureScale - 1) <= pinchScaleTolerance {
            imageScale = pinchStartScale
            imageOffset = clampedImageOffset(
                accumulatedImageOffset,
                containerSize: containerSize,
                scale: pinchStartScale
            )
            return
        }

        let newScale = max(1, pinchStartScale * gestureScale)
        let anchorPoint = CGPoint(
            x: location.x - (containerSize.width / 2),
            y: location.y - (containerSize.height / 2)
        )
        let scaleRatio = newScale / pinchStartScale
        let proposedOffset = CGSize(
            width: anchorPoint.x - (scaleRatio * (anchorPoint.x - accumulatedImageOffset.width)),
            height: anchorPoint.y - (scaleRatio * (anchorPoint.y - accumulatedImageOffset.height))
        )

        imageScale = newScale
        imageOffset = clampedImageOffset(
            proposedOffset,
            containerSize: containerSize,
            scale: newScale
        )
    }

    private func finishImageMagnification(
        gestureScale: CGFloat,
        location: CGPoint,
        containerSize: CGSize
    ) {
        updateImageMagnification(
            gestureScale: gestureScale,
            location: location,
            containerSize: containerSize
        )
        lastImageScale = imageScale
        accumulatedImageOffset = imageOffset

        if imageScale == 1 {
            imageOffset = .zero
            accumulatedImageOffset = .zero
        }
    }

    private func updateImagePan(translation: CGSize, containerSize: CGSize) {
        guard imageScale > 1 else {
            imageOffset = .zero
            accumulatedImageOffset = .zero
            return
        }

        imageOffset = clampedImageOffset(
            CGSize(
                width: accumulatedImageOffset.width + translation.width,
                height: accumulatedImageOffset.height + translation.height
            ),
            containerSize: containerSize,
            scale: imageScale
        )
    }

    private func finishImagePan(translation: CGSize, containerSize: CGSize) {
        updateImagePan(translation: translation, containerSize: containerSize)
        accumulatedImageOffset = imageOffset
    }

    private func resetImagePreviewTransform() {
        withAnimation(.easeInOut(duration: 0.2)) {
            imageScale = 1
            lastImageScale = 1
            imageOffset = .zero
            accumulatedImageOffset = .zero
        }
    }

    private func clampedImageOffset(
        _ proposedOffset: CGSize,
        containerSize: CGSize,
        scale: CGFloat
    ) -> CGSize {
        guard let previewImage else {
            return .zero
        }

        let fittedSize = aspectFitSize(for: previewImage.size, in: containerSize)
        let scaledWidth = fittedSize.width * scale
        let scaledHeight = fittedSize.height * scale
        let maximumHorizontalOffset = max(0, (scaledWidth - containerSize.width) / 2)
        let maximumVerticalOffset = max(0, (scaledHeight - containerSize.height) / 2)

        return CGSize(
            width: min(max(proposedOffset.width, -maximumHorizontalOffset), maximumHorizontalOffset),
            height: min(max(proposedOffset.height, -maximumVerticalOffset), maximumVerticalOffset)
        )
    }

    private func aspectFitSize(for imageSize: CGSize, in containerSize: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0,
              containerSize.width > 0, containerSize.height > 0 else {
            return .zero
        }

        let widthScale = containerSize.width / imageSize.width
        let heightScale = containerSize.height / imageSize.height
        let fitScale = min(widthScale, heightScale)

        return CGSize(
            width: imageSize.width * fitScale,
            height: imageSize.height * fitScale
        )
    }
}

private struct MarkdownFilePreviewWebView: UIViewRepresentable {
    let markdown: String

    private var fontScale: Double {
        UIDevice.current.userInterfaceIdiom == .phone ? 0.66 : 1.0
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.mediaTypesRequiringUserActionForPlayback = .all

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.indicatorStyle = .white
        webView.allowsBackForwardNavigationGestures = false
        load(markdown, into: webView, coordinator: context.coordinator)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedMarkdown != markdown else {
            return
        }

        load(markdown, into: webView, coordinator: context.coordinator)
    }

    private func load(_ markdown: String, into webView: WKWebView, coordinator: Coordinator) {
        coordinator.loadedMarkdown = markdown
        coordinator.allowsInitialDocumentLoad = true
        webView.loadHTMLString(
            MarkdownPreviewHTML.document(from: markdown, fontScale: fontScale),
            baseURL: nil
        )
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedMarkdown: String?
        var allowsInitialDocumentLoad = false

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            let url = navigationAction.request.url
            let isInitialDocumentLoad = allowsInitialDocumentLoad
                && navigationAction.targetFrame?.isMainFrame == true
                && navigationAction.navigationType == .other
                && url?.scheme?.lowercased() == "about"

            decisionHandler(isInitialDocumentLoad ? .allow : .cancel)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            allowsInitialDocumentLoad = false
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            allowsInitialDocumentLoad = false
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            allowsInitialDocumentLoad = false
        }
    }
}

private enum MarkdownPreviewHTML {
    private enum ListKind {
        case unordered
        case ordered
    }

    private struct Table {
        let header: [String]
        let rows: [[String]]
        let nextLineIndex: Int
    }

    static func document(from markdown: String, fontScale: Double) -> String {
        """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
        <style>
        :root { color-scheme: dark; }
        * { box-sizing: border-box; }
        html, body { margin: 0; min-height: 100%; background: #000000; color: #f2f2f7; }
        body { font: -apple-system-body; overflow-wrap: anywhere; word-break: break-word; -webkit-text-size-adjust: 100%; text-size-adjust: 100%; }
        main { padding: 0 20px 24px; font-size: \(fontScale)em; }
        h1, h2, h3, h4, h5, h6 { color: #ffffff; line-height: 1.2; margin: 1.1em 0 0.45em; font-weight: 700; }
        h1 { font-size: 1.7em; } h2 { font-size: 1.45em; } h3 { font-size: 1.25em; }
        h4 { font-size: 1.1em; } h5, h6 { font-size: 1em; }
        p { margin: 0 0 0.9em; line-height: 1.45; }
        ul, ol { margin: 0 0 0.9em; padding-left: 1.45em; line-height: 1.45; }
        li { margin: 0.22em 0; }
        .task-item { list-style: none; margin-left: -1.25em; }
        .task-checkbox { display: inline-block; width: 1.25em; color: #d1d1d6; }
        code { font-family: ui-monospace, Menlo, Monaco, monospace; background: #202124; color: #f2f2f7; border-radius: 4px; padding: 0.08em 0.28em; }
        pre { margin: 0 0 0.9em; padding: 0.75em; overflow-x: auto; background: #202124; border-radius: 8px; }
        pre code { padding: 0; background: transparent; }
        hr { border: 0; border-top: 1px solid #636366; margin: 1.25em 0; }
        .markdown-link { color: #32d7ff; text-decoration: underline; }
        .markdown-image-reference { color: #d1d1d6; font-style: italic; }
        .markdown-table-container { max-width: 100%; margin: 0 0 0.9em; overflow-x: auto; }
        table { width: 100%; min-width: max-content; border-collapse: collapse; }
        th, td { border: 1px solid #48484a; padding: 0.45em 0.65em; text-align: left; vertical-align: top; overflow-wrap: anywhere; word-break: break-word; }
        th { color: #ffffff; background: #2c2c2e; font-weight: 700; }
        </style>
        </head>
        <body><main>\(render(markdown))</main></body>
        </html>
        """
    }

    private static func render(_ markdown: String) -> String {
        let lines = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        var result = ""
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                index += 1
            } else if trimmed.hasPrefix("```") {
                index += 1
                var codeLines: [String] = []
                while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeLines.append(lines[index])
                    index += 1
                }
                if index < lines.count {
                    index += 1
                }
                result += "<pre><code>\(escape(codeLines.joined(separator: "\n")))</code></pre>"
            } else if let table = table(in: lines, at: index) {
                result += renderTable(table)
                index = table.nextLineIndex
            } else if let heading = heading(from: trimmed) {
                result += "<h\(heading.level)>\(renderInline(heading.text))</h\(heading.level)>"
                index += 1
            } else if isHorizontalRule(trimmed) {
                result += "<hr>"
                index += 1
            } else if let firstItem = listItem(from: line) {
                result += firstItem.kind == .unordered ? "<ul>" : "<ol>"
                while index < lines.count,
                      let item = listItem(from: lines[index]),
                      item.kind == firstItem.kind {
                    result += renderListItem(item.content)
                    index += 1
                }
                result += firstItem.kind == .unordered ? "</ul>" : "</ol>"
            } else {
                var paragraphLines = [trimmed]
                index += 1
                while index < lines.count {
                    let next = lines[index]
                    let nextTrimmed = next.trimmingCharacters(in: .whitespaces)
                    if nextTrimmed.isEmpty || nextTrimmed.hasPrefix("```") || heading(from: nextTrimmed) != nil || isHorizontalRule(nextTrimmed) || listItem(from: next) != nil {
                        break
                    }
                    paragraphLines.append(nextTrimmed)
                    index += 1
                }
                result += "<p>\(renderInline(paragraphLines.joined(separator: " ")))</p>"
            }
        }

        return result
    }

    private static func table(in lines: [String], at index: Int) -> Table? {
        guard index + 1 < lines.count,
              let header = tableCells(from: lines[index]),
              let separator = tableCells(from: lines[index + 1]),
              header.count == separator.count,
              header.count > 0,
              separator.allSatisfy({ isTableSeparatorCell($0) }) else {
            return nil
        }

        var rows: [[String]] = []
        var nextLineIndex = index + 2
        while nextLineIndex < lines.count,
              let row = tableCells(from: lines[nextLineIndex]) {
            rows.append(normalizedTableRow(row, columnCount: header.count))
            nextLineIndex += 1
        }

        return Table(
            header: header,
            rows: rows,
            nextLineIndex: nextLineIndex
        )
    }

    private static func tableCells(from line: String) -> [String]? {
        guard line.contains("|") else {
            return nil
        }

        var cells: [String] = []
        var currentCell = ""
        var isEscaped = false

        for character in line.trimmingCharacters(in: .whitespaces) {
            if isEscaped {
                currentCell.append(character)
                isEscaped = false
            } else if character == "\\" {
                currentCell.append(character)
                isEscaped = true
            } else if character == "|" {
                cells.append(currentCell.trimmingCharacters(in: .whitespaces))
                currentCell = ""
            } else {
                currentCell.append(character)
            }
        }
        cells.append(currentCell.trimmingCharacters(in: .whitespaces))

        if cells.first?.isEmpty == true {
            cells.removeFirst()
        }
        if cells.last?.isEmpty == true {
            cells.removeLast()
        }

        return cells.isEmpty ? nil : cells
    }

    private static func isTableSeparatorCell(_ cell: String) -> Bool {
        let trimmed = cell.trimmingCharacters(in: .whitespaces)
        let characters = Array(trimmed)
        guard characters.count >= 3 else {
            return false
        }

        let start = characters.first == ":" ? 1 : 0
        let end = characters.last == ":" ? characters.count - 1 : characters.count
        guard end - start >= 3 else {
            return false
        }
        return characters[start..<end].allSatisfy { $0 == "-" }
    }

    private static func normalizedTableRow(_ row: [String], columnCount: Int) -> [String] {
        Array(row.prefix(columnCount)) + Array(repeating: "", count: max(0, columnCount - row.count))
    }

    private static func renderTable(_ table: Table) -> String {
        let header = table.header
            .map { "<th>\(renderInline($0))</th>" }
            .joined()
        let rows = table.rows
            .map { row in
                "<tr>\(row.map { "<td>\(renderInline($0))</td>" }.joined())</tr>"
            }
            .joined()

        return "<div class=\"markdown-table-container\"><table><thead><tr>\(header)</tr></thead><tbody>\(rows)</tbody></table></div>"
    }

    private static func heading(from line: String) -> (level: Int, text: String)? {
        let characters = Array(line)
        var level = 0
        while level < characters.count, level < 6, characters[level] == "#" {
            level += 1
        }

        guard level > 0,
              level < characters.count,
              characters[level].isWhitespace else {
            return nil
        }

        return (level, String(characters[level...]).trimmingCharacters(in: .whitespaces))
    }

    private static func isHorizontalRule(_ line: String) -> Bool {
        let characters = line.filter { !$0.isWhitespace }
        guard characters.count >= 3, let marker = characters.first, marker == "-" || marker == "*" || marker == "_" else {
            return false
        }
        return characters.allSatisfy { $0 == marker }
    }

    private static func listItem(from line: String) -> (kind: ListKind, content: String)? {
        let characters = Array(line.trimmingCharacters(in: .whitespaces))
        guard !characters.isEmpty else {
            return nil
        }

        if ["-", "*", "+"].contains(characters[0]), characters.count > 1, characters[1].isWhitespace {
            return (.unordered, String(characters.dropFirst(2)).trimmingCharacters(in: .whitespaces))
        }

        var markerEnd = 0
        while markerEnd < characters.count, characters[markerEnd].isNumber {
            markerEnd += 1
        }
        guard markerEnd > 0,
              markerEnd + 1 < characters.count,
              characters[markerEnd] == "." || characters[markerEnd] == ")",
              characters[markerEnd + 1].isWhitespace else {
            return nil
        }

        return (.ordered, String(characters.dropFirst(markerEnd + 2)).trimmingCharacters(in: .whitespaces))
    }

    private static func renderListItem(_ content: String) -> String {
        if let task = taskItem(from: content) {
            let checkbox = task.isChecked ? "☑" : "☐"
            return "<li class=\"task-item\"><span class=\"task-checkbox\">\(checkbox)</span>\(renderInline(task.text))</li>"
        }
        return "<li>\(renderInline(content))</li>"
    }

    private static func taskItem(from content: String) -> (isChecked: Bool, text: String)? {
        let characters = Array(content)
        guard characters.count >= 3,
              characters[0] == "[",
              characters[2] == "]",
              characters[1] == " " || characters[1] == "x" || characters[1] == "X",
              characters.count == 3 || characters[3].isWhitespace else {
            return nil
        }

        let text = characters.count > 3
            ? String(characters.dropFirst(4)).trimmingCharacters(in: .whitespaces)
            : ""
        return (characters[1] == "x" || characters[1] == "X", text)
    }

    private static func renderInline(_ text: String) -> String {
        let characters = Array(text)
        var result = ""
        var index = 0

        while index < characters.count {
            if let image = imageReference(in: characters, at: index) {
                if let filename = imageFilename(from: image.destination) {
                    result += "<span class=\"markdown-image-reference\">\(escape(filename))</span>"
                } else {
                    result += escape(String(characters[index...image.endIndex]))
                }
                index = image.endIndex + 1
            } else if characters[index] == "`", let end = nextUnescaped("`", in: characters, after: index) {
                result += "<code>\(escape(String(characters[(index + 1)..<end])))</code>"
                index = end + 1
            } else if characters[index] == "[",
                      let closingBracket = nextUnescaped("]", in: characters, after: index),
                      closingBracket + 1 < characters.count,
                      characters[closingBracket + 1] == "(",
                      let closingParenthesis = closingParenthesis(in: characters, openingAt: closingBracket + 1) {
                result += "<span class=\"markdown-link\">\(renderInline(String(characters[(index + 1)..<closingBracket])))</span>"
                index = closingParenthesis + 1
            } else if let end = matchedDelimiter(["*", "*"], in: characters, at: index) {
                result += "<strong>\(renderInline(String(characters[(index + 2)..<end])))</strong>"
                index = end + 2
            } else if let end = matchedDelimiter(["_", "_"], in: characters, at: index) {
                result += "<strong>\(renderInline(String(characters[(index + 2)..<end])))</strong>"
                index = end + 2
            } else if let end = matchedDelimiter([characters[index]], in: characters, at: index),
                      characters[index] == "*" || characters[index] == "_" {
                result += "<em>\(renderInline(String(characters[(index + 1)..<end])))</em>"
                index = end + 1
            } else if characters[index] == "\\", index + 1 < characters.count {
                result += escape(String(characters[index + 1]))
                index += 2
            } else {
                result += escape(String(characters[index]))
                index += 1
            }
        }

        return result
    }

    private static func imageReference(in characters: [Character], at index: Int) -> (destination: String, endIndex: Int)? {
        guard index + 1 < characters.count,
              characters[index] == "!",
              characters[index + 1] == "[",
              let closingBracket = nextUnescaped("]", in: characters, after: index + 1),
              closingBracket + 1 < characters.count,
              characters[closingBracket + 1] == "(",
              let closingParenthesis = closingParenthesis(in: characters, openingAt: closingBracket + 1) else {
            return nil
        }

        return (
            String(characters[(closingBracket + 2)..<closingParenthesis]),
            closingParenthesis
        )
    }

    private static func imageFilename(from destination: String) -> String? {
        var path = destination.trimmingCharacters(in: .whitespaces)
        if path.first == "<", path.last == ">", path.count >= 2 {
            path.removeFirst()
            path.removeLast()
        }
        path = path.replacingOccurrences(of: "\\(", with: "(")
            .replacingOccurrences(of: "\\)", with: ")")
            .replacingOccurrences(of: "\\ ", with: " ")
            .replacingOccurrences(of: "\\\\", with: "\\")
        path = path.removingPercentEncoding ?? path
        path = String(path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
        path = String(path.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")

        guard let filename = path.split(separator: "/", omittingEmptySubsequences: true).last,
              !filename.isEmpty else {
            return nil
        }
        return String(filename)
    }

    private static func nextUnescaped(_ character: Character, in characters: [Character], after index: Int) -> Int? {
        guard index + 1 < characters.count else {
            return nil
        }

        for candidate in (index + 1)..<characters.count where characters[candidate] == character {
            var slashCount = 0
            var previous = candidate - 1
            while previous >= 0, characters[previous] == "\\" {
                slashCount += 1
                previous -= 1
            }
            if slashCount.isMultiple(of: 2) {
                return candidate
            }
        }
        return nil
    }

    private static func closingParenthesis(in characters: [Character], openingAt openingIndex: Int) -> Int? {
        var depth = 0
        var index = openingIndex
        while index < characters.count {
            if characters[index] == "\\" {
                index += 2
                continue
            }
            if characters[index] == "(" {
                depth += 1
            } else if characters[index] == ")" {
                depth -= 1
                if depth == 0 {
                    return index
                }
            }
            index += 1
        }
        return nil
    }

    private static func matchedDelimiter(_ delimiter: [Character], in characters: [Character], at index: Int) -> Int? {
        guard index + delimiter.count <= characters.count,
              Array(characters[index..<(index + delimiter.count)]) == delimiter else {
            return nil
        }

        let searchStart = index + delimiter.count
        guard searchStart + delimiter.count <= characters.count else {
            return nil
        }

        for candidate in searchStart...(characters.count - delimiter.count) where Array(characters[candidate..<(candidate + delimiter.count)]) == delimiter {
            if candidate == 0 || characters[candidate - 1] != "\\" {
                return candidate
            }
        }
        return nil
    }

    private static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}

private struct ImagePreviewGestureSurface: UIViewRepresentable {
    let onPinchBegan: () -> Void
    let onPinchChanged: (_ scale: CGFloat, _ location: CGPoint, _ containerSize: CGSize) -> Void
    let onPinchEnded: (_ scale: CGFloat, _ location: CGPoint, _ containerSize: CGSize) -> Void
    let onPanChanged: (_ translation: CGSize, _ containerSize: CGSize) -> Void
    let onPanEnded: (_ translation: CGSize, _ containerSize: CGSize) -> Void
    let onDoubleTap: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear

        let pinchGestureRecognizer = UIPinchGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePinch(_:))
        )
        let panGestureRecognizer = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )
        panGestureRecognizer.minimumNumberOfTouches = 1
        panGestureRecognizer.maximumNumberOfTouches = 1

        let doubleTapGestureRecognizer = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTapGestureRecognizer.numberOfTapsRequired = 2
        doubleTapGestureRecognizer.numberOfTouchesRequired = 1

        pinchGestureRecognizer.delegate = context.coordinator
        panGestureRecognizer.delegate = context.coordinator
        doubleTapGestureRecognizer.delegate = context.coordinator

        view.addGestureRecognizer(pinchGestureRecognizer)
        view.addGestureRecognizer(panGestureRecognizer)
        view.addGestureRecognizer(doubleTapGestureRecognizer)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: ImagePreviewGestureSurface

        init(_ parent: ImagePreviewGestureSurface) {
            self.parent = parent
        }

        @objc func handlePinch(_ gestureRecognizer: UIPinchGestureRecognizer) {
            let location = gestureRecognizer.location(in: gestureRecognizer.view)
            let containerSize = gestureRecognizer.view?.bounds.size ?? .zero

            switch gestureRecognizer.state {
            case .began:
                parent.onPinchBegan()
                parent.onPinchChanged(gestureRecognizer.scale, location, containerSize)
            case .changed:
                parent.onPinchChanged(gestureRecognizer.scale, location, containerSize)
            case .ended, .cancelled, .failed:
                parent.onPinchEnded(gestureRecognizer.scale, location, containerSize)
            default:
                break
            }
        }

        @objc func handlePan(_ gestureRecognizer: UIPanGestureRecognizer) {
            let translation = gestureRecognizer.translation(in: gestureRecognizer.view)
            let containerSize = gestureRecognizer.view?.bounds.size ?? .zero
            let size = CGSize(width: translation.x, height: translation.y)

            switch gestureRecognizer.state {
            case .changed:
                parent.onPanChanged(size, containerSize)
            case .ended, .cancelled, .failed:
                parent.onPanEnded(size, containerSize)
            default:
                break
            }
        }

        @objc func handleDoubleTap(_ gestureRecognizer: UITapGestureRecognizer) {
            guard gestureRecognizer.state == .ended else {
                return
            }

            parent.onDoubleTap()
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}
