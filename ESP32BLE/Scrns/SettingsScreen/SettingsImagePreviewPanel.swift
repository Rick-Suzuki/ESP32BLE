import SwiftUI
import UIKit

struct SettingsImagePreviewPanel: View {
    let imageURL: URL?
    @State private var previewImage: UIImage?

    var body: some View {
        GeometryReader { geometry in
            let previewWidth = geometry.size.width
            let previewHeight = previewWidth / 1.3

            ZStack {
                Color.black

                if let previewImage {
                    Image(uiImage: previewImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: previewWidth, height: previewHeight)
                }
            }
            .frame(width: previewWidth, height: previewHeight)
            .clipped()
            .overlay {
                Rectangle()
                    .stroke(Color.white, lineWidth: 2)
            }
        }
        .aspectRatio(1.3, contentMode: .fit)
        .task(id: imageURL?.path) {
            loadPreviewImage()
        }
    }

    private func loadPreviewImage() {
        guard let imageURL else {
            previewImage = nil
            return
        }

        previewImage = UIImage(contentsOfFile: imageURL.path)
    }
}
