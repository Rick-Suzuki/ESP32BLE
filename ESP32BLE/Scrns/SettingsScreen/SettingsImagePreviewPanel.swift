import SwiftUI
import UIKit
import PDFKit

struct SettingsImagePreviewPanel: View {
    let imageURL: URL?
    let opacitySliderValue: Double
    @State private var previewImage: UIImage?

    var body: some View {
        GeometryReader { geometry in
            let previewWidth = geometry.size.width
            let previewHeight = previewWidth / 1.3
            let previewMaxPixelDimension = max(previewWidth, previewHeight) * UIScreen.main.scale

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
            .task(id: previewImageTaskID(maxPixelDimension: previewMaxPixelDimension)) {
                loadPreviewImage(maxPixelDimension: previewMaxPixelDimension)
            }
        }
        .aspectRatio(1.3, contentMode: .fit)
    }

    private func previewImageTaskID(maxPixelDimension: CGFloat) -> String {
        "\(imageURL?.path ?? "none"):\(Int(maxPixelDimension.rounded(.up)))"
    }

    private func loadPreviewImage(maxPixelDimension: CGFloat) {
        guard let imageURL else {
            previewImage = nil
            return
        }

        previewImage = downsampledUIImage(at: imageURL, maxPixelDimension: maxPixelDimension)
    }
}

struct SettingsPDFPreviewPanel: View {
    let pdfURL: URL?

    var body: some View {
        GeometryReader { geometry in
            let previewWidth = geometry.size.width
            let previewHeight = previewWidth / 1.3

            ZStack {
                Color.black

                SettingsPDFPreviewView(pdfURL: pdfURL)
                    .frame(width: previewWidth, height: previewHeight)
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

private struct SettingsPDFPreviewView: UIViewRepresentable {
    let pdfURL: URL?

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.backgroundColor = .black
        pdfView.autoScales = true
        pdfView.displayMode = .singlePage
        pdfView.displayDirection = .vertical
        pdfView.displaysPageBreaks = false
        pdfView.usePageViewController(false)
        pdfView.isUserInteractionEnabled = false
        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        guard let pdfURL else {
            pdfView.document = nil
            return
        }

        if pdfView.document?.documentURL != pdfURL {
            pdfView.document = PDFDocument(url: pdfURL)
        }

        pdfView.scaleFactor = pdfView.scaleFactorForSizeToFit
    }
}
