import SwiftUI
import UIKit
import Foundation

struct SettingsImageNavigationScrollRequest: Equatable {
    let targetPath: String
    let id: UUID
    let alignsToTop: Bool
}

struct SettingsPDFNavigationScrollRequest: Equatable {
    let targetPath: String
    let id: UUID
    let alignsToTop: Bool
}

struct SettingsDocumentNavigationScrollRequest: Equatable {
    let targetPath: String
    let id: UUID
    let alignsToTop: Bool
}

struct SettingsDocumentTableSection: View {
    enum ListMode: Hashable {
        case files
        case text
        case images
        case markdown
        case sounds
        case pdfs
        case templates
        case all
    }

    let listMode: ListMode
    let documentFiles: [URL]
    let activeScreenURL: URL?
    let loadedDocumentURL: URL?
    @Binding var selectedScreenSelectionPath: String?
    let textURLs: [URL]
    @Binding var selectedTextSelectionPath: String?
    let markdownURLs: [URL]
    @Binding var selectedMarkdownSelectionPath: String?
    let imageURLs: [URL]
    let previewedImageURL: URL?
    let appliedImageURL: URL?
    let backgroundChangeFeedbackID: UUID
    let soundURLs: [URL]
    let selectedSoundURL: URL?
    let pdfURLs: [URL]
    let selectedPDFURL: URL?
    let templateURLs: [URL]
    let selectedTemplateURL: URL?
    let templateDescription: String?
    let allFileURLs: [URL]
    @Binding var fileScrollPositionID: String?
    @Binding var textScrollPositionID: String?
    @Binding var markdownScrollPositionID: String?
    @Binding var imageScrollPositionID: String?
    @Binding var imageNavigationScrollRequest: SettingsImageNavigationScrollRequest?
    @Binding var pdfNavigationScrollRequest: SettingsPDFNavigationScrollRequest?
    @Binding var documentNavigationScrollRequest: SettingsDocumentNavigationScrollRequest?
    @Binding var soundScrollPositionID: String?
    @Binding var pdfScrollPositionID: String?
    @Binding var templateScrollPositionID: String?
    @Binding var allScrollPositionID: String?
    let refreshFiles: () -> Void
    let canDeleteDocuments: Bool
    let loadFunctionKeys: (URL) -> Void
    let previewScreenDocument: (URL) -> Void
    let loadTextFile: (URL) -> Void
    let loadMarkdownFile: (URL) -> Void
    let deleteDocument: (URL) -> Void
    let duplicateDocument: (URL) -> Void
    let deleteTextFile: (URL) -> Void
    let deleteMarkdownFile: (URL) -> Void
    let previewImage: (URL) -> Void
    let applyImageBackground: (URL?) -> Void
    let deleteImage: (URL) -> Void
    let selectSound: (URL) -> Void
    let deleteSound: (URL) -> Void
    let selectPDF: (URL) -> Void
    let deletePDF: (URL) -> Void
    let deleteAllFile: (URL) -> Void
    let selectTemplate: (URL) -> Void
    let applyTemplate: (URL) -> Void
    let deleteTemplate: (URL) -> Void
    let showsOuterBorder: Bool
    @State private var showsRefreshConfirmation = false
    @State private var refreshConfirmationTask: Task<Void, Never>?
    @State private var tableFeedbackMessage: String?
    @State private var tableFeedbackColor: Color = .green
    @State private var tableFeedbackTask: Task<Void, Never>?
    @State private var handledDocumentNavigationRequestID: UUID?

    // MARK: - BM:🅱️ IPHONE FILENAME FONT SIZE — Change 15 below to adjust all seven filename categories; leave iPad unchanged.
    private var tableRowFont: Font? {
        isPad ? nil : .system(size: 15)
    }

    // MARK: - BM:🅱️ IPHONE ROW HEIGHT — Change 30 to adjust compact filename rows; keep iPad at 44. The iPhone List minimum matches this value.
    private var filenameRowMinimumHeight: CGFloat {
        isPad ? 44 : 30
    }

    private struct IPhoneFilenameRowMinimumHeightModifier: ViewModifier {
        let height: CGFloat

        @ViewBuilder
        func body(content: Content) -> some View {
            if isPad {
                content
            } else {
                content.environment(\.defaultMinListRowHeight, height)
            }
        }
    }

    private var itemCountReservedHeight: CGFloat {
        isPad ? 44 : 22
    }

    var body: some View {
        GeometryReader { geometry in
            let availableHeight = safeHeight(geometry.size.height)
            let itemCountHeight = itemCountReservedHeight
            let descriptionHeight = templateDescriptionReservedHeight(for: availableHeight)
            let listHeight = max(0, availableHeight - itemCountHeight - descriptionHeight)
            let documentNavigationRequest = documentNavigationScrollRequest

            VStack(alignment: .leading, spacing: 0) {
                ScrollViewReader { scrollProxy in
                    List {
                    switch listMode {
                    case .files:
                        ForEach(documentFiles, id: \.path) { fileURL in
                            documentRow(for: fileURL)
                        }
                    case .text:
                        ForEach(textURLs, id: \.path) { textURL in
                            textRow(for: textURL)
                        }
                    case .images:
                        ForEach(imageURLs, id: \.path) { imageURL in
                            imageRow(for: imageURL)
                        }
                    case .markdown:
                        ForEach(markdownURLs, id: \.path) { markdownURL in
                            markdownRow(for: markdownURL)
                        }
                    case .sounds:
                        ForEach(soundURLs, id: \.path) { soundURL in
                            soundRow(for: soundURL)
                        }
                    case .pdfs:
                        ForEach(pdfURLs, id: \.path) { pdfURL in
                            pdfRow(for: pdfURL)
                        }
                    case .templates:
                        ForEach(templateURLs, id: \.path) { templateURL in
                            templateRow(for: templateURL)
                        }
                    case .all:
                        ForEach(allFileURLs, id: \.path) { fileURL in
                            allFilesRow(for: fileURL)
                        }
                    }
                    }
                    .scrollTargetLayout()
                    .listStyle(.plain)
                    .modifier(IPhoneFilenameRowMinimumHeightModifier(height: filenameRowMinimumHeight))
                    .scrollContentBackground(.hidden)
                    .scrollPosition(id: activeScrollPositionID)
                    .background(.clear)
                    .frame(height: listHeight)
                    .refreshable {
                        refreshFiles()
                        showRefreshConfirmation()
                    }
                    .task(id: selectionRestorationID) {
                        validateActiveScrollPosition()
                        restoreSelectedRowVisibility(using: scrollProxy)
                    }
                    .task(id: imageNavigationScrollRequest?.id) {
                        handleImageNavigationScrollRequest(using: scrollProxy)
                    }
                    .task(id: pdfNavigationScrollRequest?.id) {
                        handlePDFNavigationScrollRequest(using: scrollProxy)
                    }
                    .task(id: documentNavigationRequest?.id) {
                        guard let documentNavigationRequest else { return }
                        await Task.yield()
                        guard !Task.isCancelled else { return }
                        handleDocumentNavigationScrollRequest(
                            documentNavigationRequest,
                            using: scrollProxy
                        )
                    }
                    .onChange(of: selectedSoundURL?.path) { previousPath, selectedPath in
                        guard listMode == .sounds,
                              selectedPath != previousPath,
                              let selectedPath,
                              activeRowPaths.contains(selectedPath) else {
                            return
                        }

                        scrollProxy.scrollTo(selectedPath)
                    }
					.overlay(alignment: .top) {
                        if let tableFeedbackMessage {
                            Text(tableFeedbackMessage)
                                .font(.subheadline)
                                .foregroundStyle(tableFeedbackColor)
							.padding(.horizontal, 15)
							.padding(.vertical, 6)
							.background(
								Color.black.opacity(0.9),
								in: .rect(cornerRadius: 10)
							)
							.overlay {
								RoundedRectangle(cornerRadius: 10)
									.stroke(.white, lineWidth: 1)
							}
							.padding(.top, 8)
							.allowsHitTesting(false)
						
					} else if showsRefreshConfirmation {
						Text("Refreshed Files")
							.font(.subheadline)
							.foregroundStyle(.green)
							.padding(.horizontal, 15)
							.padding(.vertical, 6)
							.background(
								Color.black.opacity(0.9),
								in: .rect(cornerRadius: 10)
							)
							.overlay {
								RoundedRectangle(cornerRadius: 10)
									.stroke(.white, lineWidth: 1)
							}
							.padding(.top, 8)
							.allowsHitTesting(false)
					}
					}
				}
				.id(listMode)

                if descriptionHeight > 0, let templateDescription {
                    templateDescriptionSection(templateDescription)
                        .frame(height: descriptionHeight)
                }

                itemCountBox
                    .frame(height: itemCountHeight)

            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.black)
        .overlay {
            if showsOuterBorder {
                if isPad {
                    Rectangle()
                        .strokeBorder(Color.white, lineWidth: 1)
                } else {
                    Rectangle()
                        .stroke(Color.white, lineWidth: 1)
                }
            } else {
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .clipShape(.rect(cornerRadius: 0))
        .onChange(of: backgroundChangeFeedbackID) {
            showTableFeedback("changed BG")
        }
        .onChange(of: documentFiles.map(\.path)) { _, documentPaths in
            handleScreenDocumentPathsChanged(documentPaths)
        }
        .onChange(of: textURLs.map(\.path)) { _, textPaths in
            guard let selectedTextSelectionPath,
                  !textPaths.contains(selectedTextSelectionPath) else {
                return
            }
            self.selectedTextSelectionPath = nil
        }
        .onChange(of: markdownURLs.map(\.path)) { _, markdownPaths in
            guard let selectedMarkdownSelectionPath,
                  !markdownPaths.contains(selectedMarkdownSelectionPath) else {
                return
            }
            self.selectedMarkdownSelectionPath = nil
        }
        .onDisappear {
            refreshConfirmationTask?.cancel()
            tableFeedbackTask?.cancel()
        }
    }

    private func handleScreenDocumentPathsChanged(_ documentPaths: [String]) {
        guard let selectedScreenSelectionPath,
              !documentPaths.contains(selectedScreenSelectionPath) else {
            return
        }

        if let matchingDocumentURL = documentURL(matchingStandardizedPath: selectedScreenSelectionPath) {
            let selectedScrollPath = fileScrollPositionID
            let scrollMatchesRenamedDocument = selectedScrollPath.map {
                urlsRepresentSameFile(URL(fileURLWithPath: $0), matchingDocumentURL)
            } ?? false
            if scrollMatchesRenamedDocument {
                fileScrollPositionID = matchingDocumentURL.path
            }
            self.selectedScreenSelectionPath = matchingDocumentURL.path
            return
        }

        self.selectedScreenSelectionPath = nil
    }

    private func documentURL(matchingStandardizedPath path: String) -> URL? {
        let selectedURL = URL(fileURLWithPath: path)
        return documentFiles.first {
            urlsRepresentSameFile($0, selectedURL)
        }
    }

    private func urlsRepresentSameFile(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.standardizedFileURL == rhs.standardizedFileURL
    }

    private func handleDocumentNavigationScrollRequest(
        _ request: SettingsDocumentNavigationScrollRequest,
        using scrollProxy: ScrollViewProxy
    ) {
        guard documentNavigationScrollRequest?.id == request.id else {
            return
        }

        guard handledDocumentNavigationRequestID != request.id else { return }

        guard listMode == .files || listMode == .text || listMode == .markdown,
              activeRowPaths.contains(request.targetPath) else {
            return
        }

        guard documentNavigationScrollRequest?.id == request.id else {
            return
        }

        if request.alignsToTop {
            scrollProxy.scrollTo(request.targetPath, anchor: .top)
        } else {
            scrollProxy.scrollTo(request.targetPath)
        }
        handledDocumentNavigationRequestID = request.id
    }

    private func showRefreshConfirmation() {
        refreshConfirmationTask?.cancel()
        showsRefreshConfirmation = true
        refreshConfirmationTask = Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            showsRefreshConfirmation = false
        }
    }

    private func showTableFeedback(_ message: String, color: Color = .green) {
        tableFeedbackTask?.cancel()
        tableFeedbackColor = color
        tableFeedbackMessage = message
        tableFeedbackTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            tableFeedbackMessage = nil
        }
    }

    private func safeHeight(_ height: CGFloat) -> CGFloat {
        height.isFinite ? max(0, height) : 0
    }

    private func templateDescriptionReservedHeight(for availableHeight: CGFloat) -> CGFloat {
        guard !isPad,
              listMode == .templates,
              selectedTemplateURL != nil,
              templateDescription != nil else {
            return 0
        }

        let availableDescriptionHeight = max(0, availableHeight - itemCountReservedHeight)
        return min(availableDescriptionHeight, min(120, max(60, availableHeight * 0.22)))
    }

    private func templateDescriptionSection(_ description: String) -> some View {
        ScrollView {
            Text(description)
                .font(tableRowFont)
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
        }
        .background(Color.gray.opacity(0.16))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.gray)
                .frame(height: 1)
        }
    }

		//
	//----------------------------------------
	//
	private var itemCountBox: some View {
		HStack(alignment: .center) {
			Text(itemCountText)
				.font(tableRowFont)
				.bold()
				.foregroundStyle(.white)
				.multilineTextAlignment(.leading)
				.fixedSize(horizontal: false, vertical: true)
			
			Spacer()
		}
		.padding(.leading, 10)
		.frame(maxWidth: .infinity)
		.frame(height: isPad ? 40 : 22)
		.background(Color.gray.opacity(0.3))
		.overlay(alignment: .top) {
			Rectangle()
				.fill(Color.gray)
				.frame(height: 1)
		}
		.layoutPriority(1)
	}
	//
	//----------------------------------------
	//
    private var itemCountText: String {
        let count = visibleItemCount
        let noun = count == 1 ? "item" : "items"
        return "\(count) \(noun)"
    }

    private var visibleItemCount: Int {
        switch listMode {
        case .files:
            return documentFiles.count
        case .text:
            return textURLs.count
        case .images:
            return imageURLs.count
        case .markdown:
            return markdownURLs.count
        case .sounds:
            return soundURLs.count
        case .pdfs:
            return pdfURLs.count
        case .templates:
            return templateURLs.count
        case .all:
            return allFileURLs.count
        }
    }

    private var activeScrollPositionID: Binding<String?> {
        switch listMode {
        case .files:
            return $fileScrollPositionID
        case .text:
            return $textScrollPositionID
        case .images:
            return $imageScrollPositionID
        case .markdown:
            return $markdownScrollPositionID
        case .sounds:
            return $soundScrollPositionID
        case .pdfs:
            return $pdfScrollPositionID
        case .templates:
            return $templateScrollPositionID
        case .all:
            return $allScrollPositionID
        }
    }

    private var selectionRestorationID: String {
        let rowPaths = activeRowPaths.joined(separator: "\u{1F}")
        if listMode == .templates {
            return "\(listMode)-\(rowPaths)-\(selectedTemplateURL?.path ?? "")"
        }
        return "\(listMode)-\(rowPaths)"
    }

    private var selectedRowPath: String? {
        switch listMode {
        case .files:
            if let selectedScreenSelectionPath,
               let matchingDocumentURL = documentURL(matchingStandardizedPath: selectedScreenSelectionPath) {
                return matchingDocumentURL.path
            }
            return documentFiles.first(where: isActiveScreen)?.path
        case .text:
            return selectedTextSelectionPath
        case .images:
            guard let selectedImageURL = previewedImageURL ?? appliedImageURL else {
                return nil
            }
            return imageURLs.first(where: {
                urlsRepresentSameFile($0, selectedImageURL)
            })?.path
        case .markdown:
            return selectedMarkdownSelectionPath
        case .sounds:
            return selectedSoundURL?.path
        case .pdfs:
            return selectedPDFURL?.path
        case .templates:
            return selectedTemplateURL?.path
        case .all:
            return nil
        }
    }

    private var activeRowPaths: [String] {
        switch listMode {
        case .files:
            return documentFiles.map(\.path)
        case .text:
            return textURLs.map(\.path)
        case .images:
            return imageURLs.map(\.path)
        case .markdown:
            return markdownURLs.map(\.path)
        case .sounds:
            return soundURLs.map(\.path)
        case .pdfs:
            return pdfURLs.map(\.path)
        case .templates:
            return templateURLs.map(\.path)
        case .all:
            return allFileURLs.map(\.path)
        }
    }

    private func validateActiveScrollPosition() {
        let savedScrollPositionID = activeScrollPositionID.wrappedValue
        let savedIDExistsInRows = savedScrollPositionID.map { activeRowPaths.contains($0) } ?? false
        let willClearSavedID = !activeRowPaths.isEmpty &&
            savedScrollPositionID != nil &&
            !savedIDExistsInRows

        if willClearSavedID {
            activeScrollPositionID.wrappedValue = nil
        }
    }

    private func restoreSelectedRowVisibility(using scrollProxy: ScrollViewProxy) {
        guard let selectedRowPath,
              activeRowPaths.contains(selectedRowPath) else {
            return
        }

        switch listMode {
        case .images, .pdfs:
            scrollProxy.scrollTo(selectedRowPath, anchor: .bottom)
        case .files, .text, .markdown, .sounds, .templates, .all:
            scrollProxy.scrollTo(selectedRowPath)
        }
    }

    private func handleImageNavigationScrollRequest(using scrollProxy: ScrollViewProxy) {
        guard let imageNavigationScrollRequest else {
            return
        }

        guard listMode == .images,
              activeRowPaths.contains(imageNavigationScrollRequest.targetPath) else {
            self.imageNavigationScrollRequest = nil
            return
        }

        withAnimation(.easeInOut(duration: 0.35)) {
            if imageNavigationScrollRequest.alignsToTop {
                scrollProxy.scrollTo(imageNavigationScrollRequest.targetPath, anchor: .top)
            } else {
                scrollProxy.scrollTo(imageNavigationScrollRequest.targetPath)
            }
        }
        self.imageNavigationScrollRequest = nil
    }

    private func handlePDFNavigationScrollRequest(using scrollProxy: ScrollViewProxy) {
        guard let pdfNavigationScrollRequest else {
            return
        }

        guard listMode == .pdfs,
              activeRowPaths.contains(pdfNavigationScrollRequest.targetPath) else {
            self.pdfNavigationScrollRequest = nil
            return
        }

        withAnimation(.easeInOut(duration: 0.35)) {
            if pdfNavigationScrollRequest.alignsToTop {
                scrollProxy.scrollTo(pdfNavigationScrollRequest.targetPath, anchor: .top)
            } else {
                scrollProxy.scrollTo(pdfNavigationScrollRequest.targetPath)
            }
        }
        self.pdfNavigationScrollRequest = nil
    }

    private func documentRow(for fileURL: URL) -> some View {
        let isLoaded = isActiveScreen(fileURL)
        let isTemporarilySelected = selectedScreenSelectionPath.map {
            urlsRepresentSameFile(URL(fileURLWithPath: $0), fileURL)
        } ?? false
        let isHighlighted = isLoaded || isTemporarilySelected
        let rowForegroundColor: Color = isLoaded ? .green : (isTemporarilySelected ? .yellow : .white)

        return HStack {
            Text(fileURL.deletingPathExtension().lastPathComponent)
                .font(tableRowFont)
                .fontWeight(isHighlighted ? .bold : .regular)
                .foregroundStyle(rowForegroundColor)
                .multilineTextAlignment(.leading)
                .lineLimit(1)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(.leading, 10)
        .frame(maxWidth: .infinity, minHeight: filenameRowMinimumHeight, alignment: .leading)
        .background(Color.black)
        .overlay {
            Rectangle()
                .fill(Color.gray.opacity(0.6))
                .frame(height: 1)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .contentShape(.rect)
        .gesture(
            TapGesture(count: 2)
                .exclusively(before: TapGesture(count: 1))
                .onEnded { gesture in
                    switch gesture {
                    case .first:
                        handleScreenDoubleTap(fileURL)
                    case .second:
                        handleScreenSingleTap(fileURL)
                    }
                }
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            handleScreenSingleTap(fileURL)
        }
        .accessibilityAction(named: Text("Load Screen")) {
            handleScreenDoubleTap(fileURL)
        }
        .id(fileURL.path)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                duplicateDocument(fileURL)
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
            .tint(.blue)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if canDeleteDocuments {
                Button(role: .destructive) {
                    handleDocumentDeletion(fileURL)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    private func textRow(for textURL: URL) -> some View {
        let isLoaded = selectedTextSelectionPath == textURL.path &&
            loadedDocumentURL?.standardizedFileURL == textURL.standardizedFileURL

        return Button {
            ButtonClickFeedback.playIfEnabled()
            handleFileSelection(textURL) {
                loadTextFile(textURL)
            }
            showTableFeedback("copied name", color: .yellow)
        } label: {
            HStack {
                Text(textURL.lastPathComponent)
                    .font(tableRowFont)
                    .fontWeight(isLoaded ? .bold : .regular)
                    .foregroundStyle(isLoaded ? Color.green : .white)
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()
            }
            .padding(.leading, 10)
            .frame(maxWidth: .infinity, minHeight: filenameRowMinimumHeight, alignment: .leading)
            .background(Color.black)
            .overlay {
                Rectangle()
                    .fill(Color.gray.opacity(0.6))
                    .frame(height: 1)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .id(textURL.path)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button(role: .destructive) {
                handleTextFileDeletion(textURL)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func markdownRow(for markdownURL: URL) -> some View {
        let isLoaded = selectedMarkdownSelectionPath == markdownURL.path &&
            loadedDocumentURL?.standardizedFileURL == markdownURL.standardizedFileURL

        return Button {
            ButtonClickFeedback.playIfEnabled()
            handleFileSelection(markdownURL) {
                loadMarkdownFile(markdownURL)
            }
            showTableFeedback("copied name", color: .yellow)
        } label: {
            HStack {
                Text(markdownURL.lastPathComponent)
                    .font(tableRowFont)
                    .fontWeight(isLoaded ? .bold : .regular)
                    .foregroundStyle(isLoaded ? Color.green : .white)
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()
            }
            .padding(.leading, 10)
            .frame(maxWidth: .infinity, minHeight: filenameRowMinimumHeight, alignment: .leading)
            .background(Color.black)
            .overlay {
                Rectangle()
                    .fill(Color.gray.opacity(0.6))
                    .frame(height: 1)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .id(markdownURL.path)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button(role: .destructive) {
                handleMarkdownFileDeletion(markdownURL)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func imageRow(for imageURL: URL) -> some View {
        let isApplied = appliedImageURL.map {
            urlsRepresentSameFile($0, imageURL)
        } ?? false
        let isPreviewed = previewedImageURL.map {
            urlsRepresentSameFile($0, imageURL)
        } ?? false
        let isHighlighted = isApplied || isPreviewed
        let rowForegroundColor: Color = isApplied ? .green : (isPreviewed ? .yellow : .white)

        return HStack {
            Text(imageURL.lastPathComponent)
                .font(tableRowFont)
                .fontWeight(isHighlighted ? .bold : .regular)
                .foregroundStyle(rowForegroundColor)
                .multilineTextAlignment(.leading)
                .lineLimit(1)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(.leading, 10)
        .frame(maxWidth: .infinity, minHeight: filenameRowMinimumHeight, alignment: .leading)
        .background(Color.black)
        .overlay {
            Rectangle()
                .fill(Color.gray.opacity(0.6))
                .frame(height: 1)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .contentShape(.rect)
        .gesture(
            TapGesture(count: 2)
                .exclusively(before: TapGesture(count: 1))
                .onEnded { gesture in
                    switch gesture {
                    case .first:
                        handleImageBackgroundSelection(imageURL)
                    case .second:
                        handleImagePreviewSelection(imageURL)
                    }
                }
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            handleImagePreviewSelection(imageURL)
        }
        .accessibilityAction(named: Text("Set as Main Screen background")) {
            handleImageBackgroundSelection(imageURL)
        }
        .id(imageURL.path)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button(role: .destructive) {
                deleteImage(imageURL)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
	
	// MARK: - BM: Table: image taps
    private func handleImagePreviewSelection(_ imageURL: URL) {
        ButtonClickFeedback.playIfEnabled()
        handleFileSelection(imageURL) {
            previewImage(imageURL)
        }
        showTableFeedback("copied name", color: .yellow)
    }

    private func handleImageBackgroundSelection(_ imageURL: URL) {
        ButtonClickFeedback.playIfEnabled()
        applyImageBackground(imageURL)
    }

    private func soundRow(for soundURL: URL) -> some View {
        let isSelected = selectedSoundURL?.path == soundURL.path

        return Button {
            ButtonClickFeedback.playIfEnabled()
            handleFileSelection(soundURL) {
                selectSound(soundURL)
            }
            showTableFeedback("copied name", color: .yellow)
        } label: {
            HStack {
                Text(soundURL.lastPathComponent)
                    .font(tableRowFont)
                    .fontWeight(isSelected ? .bold : .regular)
                    .foregroundStyle(isSelected ? Color.yellow : .white)
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()
            }
            .padding(.leading, 10)
            .frame(maxWidth: .infinity, minHeight: filenameRowMinimumHeight, alignment: .leading)
            .background(Color.black)
            .overlay {
                Rectangle()
                    .fill(Color.gray.opacity(0.6))
                    .frame(height: 1)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .id(soundURL.path)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button(role: .destructive) {
                handleSoundDeletion(soundURL)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func pdfRow(for pdfURL: URL) -> some View {
        let isSelected = selectedPDFURL?.path == pdfURL.path

        return Button {
            ButtonClickFeedback.playIfEnabled()
            handleFileSelection(pdfURL) {
                selectPDF(pdfURL)
            }
            showTableFeedback("copied name", color: .yellow)
        } label: {
            HStack {
                Text(pdfURL.lastPathComponent)
                    .font(tableRowFont)
                    .fontWeight(isSelected ? .bold : .regular)
                    .foregroundStyle(isSelected ? Color.yellow : .white)
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()
            }
            .padding(.leading, 10)
            .frame(maxWidth: .infinity, minHeight: filenameRowMinimumHeight, alignment: .leading)
            .background(Color.black)
            .overlay {
                Rectangle()
                    .fill(Color.gray.opacity(0.6))
                    .frame(height: 1)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .id(pdfURL.path)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button(role: .destructive) {
                handlePDFDeletion(pdfURL)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func allFilesRow(for fileURL: URL) -> some View {
        Button {
            handleFileSelection(fileURL)
        } label: {
            HStack {
                Text(fileURL.lastPathComponent)
                    .font(tableRowFont)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()
            }
            .padding(.leading, 10)
            .frame(maxWidth: .infinity, minHeight: filenameRowMinimumHeight, alignment: .leading)
            .background(Color.black)
            .overlay {
                Rectangle()
                    .fill(Color.gray.opacity(0.6))
                    .frame(height: 1)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .id(fileURL.path)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button(role: .destructive) {
                deleteAllFile(fileURL)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func templateRow(for templateURL: URL) -> some View {
        let isSelected = selectedTemplateURL?.standardizedFileURL == templateURL.standardizedFileURL
        let selectionGesture = TapGesture(count: 2)
            .onEnded {
                ButtonClickFeedback.playIfEnabled()
                selectTemplate(templateURL)
                applyTemplate(templateURL)
            }
            .exclusively(
                before: TapGesture(count: 1)
                    .onEnded {
                        ButtonClickFeedback.playIfEnabled()
                        selectTemplate(templateURL)
                    }
            )

        return HStack {
            Text(templateURL.lastPathComponent)
                .font(tableRowFont)
                .fontWeight(isSelected ? .bold : .regular)
                .foregroundStyle(isSelected ? Color.yellow : .white)
                .multilineTextAlignment(.leading)
                .lineLimit(1)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(.leading, 10)
        .frame(maxWidth: .infinity, minHeight: filenameRowMinimumHeight, alignment: .leading)
        .background(Color.black)
        .overlay {
            Rectangle()
                .fill(Color.gray.opacity(0.6))
                .frame(height: 1)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .contentShape(.rect)
        .gesture(selectionGesture)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(templateURL.lastPathComponent)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction {
            ButtonClickFeedback.playIfEnabled()
            selectTemplate(templateURL)
        }
        .accessibilityAction(named: "Apply Template") {
            ButtonClickFeedback.playIfEnabled()
            selectTemplate(templateURL)
            applyTemplate(templateURL)
        }
        .id(templateURL.path)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button(role: .destructive) {
                deleteTemplate(templateURL)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func handleFileSelection(_ fileURL: URL, action: () -> Void = {}) {
        action()
        UIPasteboard.general.string = fileURL.lastPathComponent
    }

    private func handleScreenDoubleTap(_ fileURL: URL) {
        loadFunctionKeys(fileURL)

        Task { @MainActor in
            await Task.yield()
            if selectedScreenSelectionPath == fileURL.path,
               isActiveScreen(fileURL) {
                selectedScreenSelectionPath = nil
            }
            showTableFeedback("changed screen")
        }
    }

    private func isActiveScreen(_ fileURL: URL) -> Bool {
        guard let activeScreenURL else {
            return false
        }

        return urlsRepresentSameFile(activeScreenURL, fileURL)
    }

    private func handleScreenSingleTap(_ fileURL: URL) {
        ButtonClickFeedback.playIfEnabled()
        handleFileSelection(fileURL) {
            previewScreenDocument(fileURL)
        }
        selectedScreenSelectionPath = fileURL.path
        showTableFeedback("copied name", color: .yellow)
    }

    private func handleDocumentDeletion(_ fileURL: URL) {
        if selectedScreenSelectionPath == fileURL.path {
            selectedScreenSelectionPath = nil
        }
        deleteDocument(fileURL)
    }

    private func handleTextFileDeletion(_ textURL: URL) {
        deleteTextFile(textURL)
    }

    private func handleMarkdownFileDeletion(_ markdownURL: URL) {
        deleteMarkdownFile(markdownURL)
    }

    private func handleSoundDeletion(_ soundURL: URL) {
        deleteSound(soundURL)
    }

    private func handlePDFDeletion(_ pdfURL: URL) {
        deletePDF(pdfURL)
    }
}
