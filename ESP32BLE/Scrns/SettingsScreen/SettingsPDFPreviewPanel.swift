import SwiftUI
import PDFKit

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
