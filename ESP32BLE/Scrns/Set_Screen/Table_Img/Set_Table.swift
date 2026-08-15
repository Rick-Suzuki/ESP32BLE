import SwiftUI

struct SettingsDocumentTableSection: View {
    enum ListMode {
        case files
        case images
        case sounds
        case pdfs
        case all
    }

    let listMode: ListMode
    let documentFiles: [URL]
    let selectedDocumentName: String
    let imageURLs: [URL]
    let selectedImageURL: URL?
    let soundURLs: [URL]
    let selectedSoundURL: URL?
    let pdfURLs: [URL]
    let selectedPDFURL: URL?
    let allFileURLs: [URL]
    @Binding var fileScrollPositionID: String?
    @Binding var imageScrollPositionID: String?
    @Binding var soundScrollPositionID: String?
    @Binding var pdfScrollPositionID: String?
    @Binding var allScrollPositionID: String?
    let canDeleteDocuments: Bool
    let imagePreviewSection: AnyView
    let loadFunctionKeys: (URL) -> Void
    let deleteDocument: (URL) -> Void
    let duplicateDocument: (URL) -> Void
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            List {
                switch listMode {
                case .files:
                    ForEach(documentFiles, id: \.path) { fileURL in
                        documentRow(for: fileURL)
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

            imagePreviewSection
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.black)
        .overlay {
            Rectangle()
                .stroke(Color.white, lineWidth: 1)
        }
        .clipShape(.rect(cornerRadius: 0))
    }

    private var activeScrollPositionID: Binding<String?> {
        switch listMode {
        case .files:
            return $fileScrollPositionID
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
