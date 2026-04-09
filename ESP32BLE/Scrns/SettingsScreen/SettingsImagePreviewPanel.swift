import SwiftUI
import UIKit

struct SettingsImagePreviewPanel: View {
    let previewImage: UIImage?
    let opacitySliderValue: Double

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
                        .opacity(opacitySliderValue)
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
    }
}
