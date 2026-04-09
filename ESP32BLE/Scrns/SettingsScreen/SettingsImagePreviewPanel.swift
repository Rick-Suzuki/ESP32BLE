import SwiftUI
import UIKit

struct SettingsImagePreviewPanel: View {
    let previewImage: UIImage?
    let opacitySliderValue: Double

    var body: some View {
        ZStack {
            Color.black

            if let previewImage {
                Image(uiImage: previewImage)
                    .resizable()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(opacitySliderValue)
            }
        }
        .aspectRatio(1.3, contentMode: .fit)
        .overlay {
            Rectangle()
                .stroke(Color.white, lineWidth: 2)
        }
        .clipped()
    }
}
