import SwiftUI

struct SettingsDocumentTableSection: View {
    enum ListMode {
        case files
        case text
        case images
        case sounds
        case pdfs
        case all
    }

    let listMode: ListMode
    let documentFiles: [URL]
    let selectedDocumentName: String
    let textURLs: [URL]
    let selectedTextFileName: String
    let imageURLs: [URL]
    let selectedImageURL: URL?
    let soundURLs: [URL]
    let selectedSoundURL: URL?
    let pdfURLs: [URL]
    let selectedPDFURL: URL?
    let allFileURLs: [URL]
    @Binding var fileScrollPositionID: String?
    @Binding var textScrollPositionID: String?
    @Binding var imageScrollPositionID: String?
    @Binding var soundScrollPositionID: String?
    @Binding var pdfScrollPositionID: String?
    @Binding var allScrollPositionID: String?
    let canDeleteDocuments: Bool
    let imagePreviewSection: AnyView
    let loadFunctionKeys: (URL) -> Void
    let loadTextFile: (URL) -> Void
    let deleteDocument: (URL) -> Void
    let duplicateDocument: (URL) -> Void
    let deleteTextFile: (URL) -> Void
    let selectImage: (URL) -> Void
    let deleteImage: (URL) -> Void
    let selectSound: (URL) -> Void
    let deleteSound: (URL) -> Void
    let selectPDF: (URL) -> Void
    let deletePDF: (URL) -> Void
    let deleteAllFile: (URL) -> Void

	// set table font size for iphone
    private var tableRowFont: Font? {
        isPad ? nil : .system(size: 15)
    }

    private let itemCountReservedHeight: CGFloat = 44

    var body: some View {
        GeometryReader { geometry in
            let availableHeight = safeHeight(geometry.size.height)
            let itemCountHeight = itemCountReservedHeight
            let previewHeight = previewReservedHeight(for: geometry.size.width)
            let listHeight = max(0, availableHeight - itemCountHeight - previewHeight)

            VStack(alignment: .leading, spacing: 0) {
                List {
                    switch listMode {
                    case .files:
                        ForEach(documentFiles, id: \.path) { fileURL in
                            documentRow(for: fileURL)
                        }
                        .scrollTargetLayout()
                    case .text:
                        ForEach(textURLs, id: \.path) { textURL in
                            textRow(for: textURL)
                        }
                        .scrollTargetLayout()
                    case .images:
                        ForEach(imageURLs, id: \.path) { imageURL in
                            imageRow(for: imageURL)
                        }
                        .scrollTargetLayout()
                    case .sounds:
                        ForEach(soundURLs, id: \.path) { soundURL in
                            soundRow(for: soundURL)
                        }
                        .scrollTargetLayout()
                    case .pdfs:
                        ForEach(pdfURLs, id: \.path) { pdfURL in
                            pdfRow(for: pdfURL)
                        }
                        .scrollTargetLayout()
                    case .all:
                        ForEach(allFileURLs, id: \.path) { fileURL in
                            allFilesRow(for: fileURL)
                        }
                        .scrollTargetLayout()
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollPosition(id: activeScrollPositionID, anchor: .top)
                .background(.clear)
                .frame(height: listHeight)

                itemCountBox
                    .frame(height: itemCountHeight)

                imagePreviewSection
                    .frame(height: previewHeight)
            }
            .task(id: layoutLogID(
                availableHeight: availableHeight,
                listHeight: listHeight,
                itemCountHeight: itemCountHeight,
                previewHeight: previewHeight
            )) {
                db("SETTINGS_TABLE_LAYOUT availableHeight=\(availableHeight) listHeight=\(listHeight) itemCountHeight=\(itemCountHeight) previewHeight=\(previewHeight)")
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.black)
        .overlay {
            Rectangle()
                .stroke(Color.white, lineWidth: 1)
        }
        .clipShape(.rect(cornerRadius: 0))
    }

    private func safeHeight(_ height: CGFloat) -> CGFloat {
        height.isFinite ? max(0, height) : 0
    }

    private func previewReservedHeight(for width: CGFloat) -> CGFloat {
        guard listMode == .images || listMode == .pdfs else { return 0 }
        let safeWidth = width.isFinite ? max(0, width) : 0
        return safeWidth / 1.3
    }

    private func layoutLogID(
        availableHeight: CGFloat,
        listHeight: CGFloat,
        itemCountHeight: CGFloat,
        previewHeight: CGFloat
    ) -> String {
        [
            roundedLayoutValue(availableHeight),
            roundedLayoutValue(listHeight),
            roundedLayoutValue(itemCountHeight),
            roundedLayoutValue(previewHeight),
            "\(listMode)",
            "\(visibleItemCount)"
        ].joined(separator: ":")
    }

    private func roundedLayoutValue(_ value: CGFloat) -> String {
        "\(Int(value.rounded()))"
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
		.frame(height: 40)
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
        case .sounds:
            return soundURLs.count
        case .pdfs:
            return pdfURLs.count
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
        case .sounds:
            return $soundScrollPositionID
        case .pdfs:
            return $pdfScrollPositionID
        case .all:
            return $allScrollPositionID
        }
    }

    private func documentRow(for fileURL: URL) -> some View {
        let isSelected = selectedDocumentName == fileURL.lastPathComponent

        return Button {
            ButtonClickFeedback.playIfEnabled()
            loadFunctionKeys(fileURL)
        } label: {
            HStack {
                Text(fileURL.lastPathComponent)
                    .font(tableRowFont)
                    .fontWeight(isSelected ? .bold : .regular)
                    .foregroundStyle(isSelected ? Color.green : .white)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()
            }
            .padding(.leading, 10)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
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
                    deleteDocument(fileURL)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    private func textRow(for textURL: URL) -> some View {
        let isSelected = selectedTextFileName == textURL.lastPathComponent

        return Button {
            ButtonClickFeedback.playIfEnabled()
            loadTextFile(textURL)
        } label: {
            HStack {
                Text(textURL.lastPathComponent)
                    .font(tableRowFont)
                    .fontWeight(isSelected ? .bold : .regular)
                    .foregroundStyle(isSelected ? Color.green : .white)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()
            }
            .padding(.leading, 10)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
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
                deleteTextFile(textURL)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func imageRow(for imageURL: URL) -> some View {
        let isSelected = selectedImageURL?.lastPathComponent == imageURL.lastPathComponent

        return Button {
            ButtonClickFeedback.playIfEnabled()
            selectImage(imageURL)
        } label: {
            HStack {
                Text(imageURL.lastPathComponent)
                    .font(tableRowFont)
                    .fontWeight(isSelected ? .bold : .regular)
                    .foregroundStyle(isSelected ? Color.green : .white)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()
            }
            .padding(.leading, 10)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
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

    private func soundRow(for soundURL: URL) -> some View {
        let isSelected = selectedSoundURL?.lastPathComponent == soundURL.lastPathComponent

        return Button {
            ButtonClickFeedback.playIfEnabled()
            selectSound(soundURL)
        } label: {
            HStack {
                Text(soundURL.lastPathComponent)
                    .font(tableRowFont)
                    .fontWeight(isSelected ? .bold : .regular)
                    .foregroundStyle(isSelected ? Color.green : .white)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()
            }
            .padding(.leading, 10)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
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
                deleteSound(soundURL)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func pdfRow(for pdfURL: URL) -> some View {
        let isSelected = selectedPDFURL?.lastPathComponent == pdfURL.lastPathComponent

        return Button {
            ButtonClickFeedback.playIfEnabled()
            selectPDF(pdfURL)
        } label: {
            HStack {
                Text(pdfURL.lastPathComponent)
                    .font(tableRowFont)
                    .fontWeight(isSelected ? .bold : .regular)
                    .foregroundStyle(isSelected ? Color.green : .white)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()
            }
            .padding(.leading, 10)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
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
                deletePDF(pdfURL)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func allFilesRow(for fileURL: URL) -> some View {
        HStack {
            Text(fileURL.lastPathComponent)
                .font(tableRowFont)
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(.leading, 10)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(Color.black)
        .overlay {
            Rectangle()
                .fill(Color.gray.opacity(0.6))
                .frame(height: 1)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .contentShape(.rect)
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
}
