import SwiftUI

struct SettingsDocumentTableSection: View {
    enum ListMode {
        case files
        case images
        case sounds
    }

    let listMode: ListMode
    let documentFiles: [URL]
    let selectedDocumentName: String
    let imageURLs: [URL]
    let selectedImageURL: URL?
    let soundURLs: [URL]
    let selectedSoundURL: URL?
    @Binding var fileScrollPositionID: String?
    @Binding var imageScrollPositionID: String?
    @Binding var soundScrollPositionID: String?
    let canDeleteDocuments: Bool
    let imagePreviewSection: AnyView
    let loadFunctionKeys: (URL) -> Void
    let deleteDocument: (URL) -> Void
    let duplicateDocument: (URL) -> Void
    let selectImage: (URL) -> Void
    let deleteImage: (URL) -> Void
    let selectSound: (URL) -> Void
    let deleteSound: (URL) -> Void

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
}
