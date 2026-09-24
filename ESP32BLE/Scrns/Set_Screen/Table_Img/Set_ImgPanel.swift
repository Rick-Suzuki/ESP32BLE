import SwiftUI
import UIKit
import PDFKit
import QuartzCore
import Darwin

struct SettingsImagePreviewPanel: View {
    let imageURL: URL?
    let opacitySliderValue: Double
    @State private var previewImage: UIImage?
    @State private var previewRequestID = ""

    var body: some View {
        let _ = SettingsProbeCounters.record("SettingsImagePreviewPanel.body", detail: "file=\(imageURL?.lastPathComponent ?? "none")")
        GeometryReader { geometry in
            let previewWidth = geometry.size.width
            let previewHeight = previewWidth / 1.3
            let previewMaxPixelDimension = max(previewWidth, previewHeight) * UIScreen.main.scale
            let _ = SettingsProbeCounters.record("SettingsImagePreviewPanel.geometry", detail: "file=\(imageURL?.lastPathComponent ?? "none")")

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
                db("[PROBE] SettingsImagePreviewPanel task START \(Date()) id=\(previewImageTaskID(maxPixelDimension: previewMaxPixelDimension)) file=\(imageURL?.lastPathComponent ?? "none") maxPixelDimension=\(previewMaxPixelDimension) thread=\(pthread_main_np() == 1 ? "main" : "background")")
                await loadPreviewImage(maxPixelDimension: previewMaxPixelDimension)
                db("[PROBE] SettingsImagePreviewPanel task END \(Date()) file=\(imageURL?.lastPathComponent ?? "none") hasImage=\(previewImage != nil) thread=\(pthread_main_np() == 1 ? "main" : "background")")
            }
        }
        .aspectRatio(1.3, contentMode: .fit)
    }

    private func previewImageTaskID(maxPixelDimension: CGFloat) -> String {
        "\(imageURL?.path ?? "none"):\(Int(maxPixelDimension.rounded(.up)))"
    }

    private func loadPreviewImage(maxPixelDimension: CGFloat) async {
        let previewLoadStart = CACurrentMediaTime()
        db("[PROBE] SettingsImagePreviewPanel loadPreviewImage START \(Date()) file=\(imageURL?.lastPathComponent ?? "none") maxPixelDimension=\(maxPixelDimension) thread=\(pthread_main_np() == 1 ? "main" : "background")")
        guard let imageURL else {
            previewImage = nil
            db("[PROBE] SettingsImagePreviewPanel loadPreviewImage END \(Date()) file=none elapsedMs=\((CACurrentMediaTime() - previewLoadStart) * 1000) hasImage=false thread=\(pthread_main_np() == 1 ? "main" : "background")")
            return
        }

        let requestID = previewImageTaskID(maxPixelDimension: maxPixelDimension)
        previewRequestID = requestID
        db("[SETTINGS PREVIEW] REQUEST START file=\(imageURL.lastPathComponent) requestID=\(requestID) thread=\(pthread_main_np() == 1 ? "main" : "background")")
        db("[PROBE] SettingsImagePreviewPanel downsample REQUEST \(Date()) file=\(imageURL.lastPathComponent) thread=\(pthread_main_np() == 1 ? "main" : "background")")
        let decodeTask = Task.detached(priority: .userInitiated) {
            settingsPreviewDownsampledUIImage(at: imageURL, maxPixelDimension: maxPixelDimension)
        }
        let decodedImage = await decodeTask.value

        guard !Task.isCancelled else {
            db("[SETTINGS PREVIEW] RESULT DISCARDED file=\(imageURL.lastPathComponent) reason=cancelled thread=\(pthread_main_np() == 1 ? "main" : "background")")
            return
        }

        guard previewRequestID == requestID else {
            db("[SETTINGS PREVIEW] RESULT DISCARDED file=\(imageURL.lastPathComponent) reason=stale thread=\(pthread_main_np() == 1 ? "main" : "background")")
            return
        }

        previewImage = decodedImage
        db("[SETTINGS PREVIEW] RESULT APPLY file=\(imageURL.lastPathComponent) hasImage=\(previewImage != nil) thread=\(pthread_main_np() == 1 ? "main" : "background")")
        db("[PROBE] SettingsImagePreviewPanel downsample END \(Date()) file=\(imageURL.lastPathComponent) elapsedMs=\((CACurrentMediaTime() - previewLoadStart) * 1000) hasImage=\(previewImage != nil) thread=\(pthread_main_np() == 1 ? "main" : "background")")
        db("[PROBE] SettingsImagePreviewPanel loadPreviewImage END \(Date()) file=\(imageURL.lastPathComponent) elapsedMs=\((CACurrentMediaTime() - previewLoadStart) * 1000) hasImage=\(previewImage != nil) thread=\(pthread_main_np() == 1 ? "main" : "background")")
    }
}

nonisolated private func settingsPreviewDownsampledUIImage(at url: URL, maxPixelDimension: CGFloat) -> UIImage? {
    guard maxPixelDimension > 0 else {
        return UIImage(contentsOfFile: url.path)
    }

    let imageSourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
    var stageStart = CACurrentMediaTime()
    db("[SETTINGS PREVIEW] CGImageSourceCreateWithURL START file=\(url.lastPathComponent) thread=\(pthread_main_np() == 1 ? "main" : "background")")
    let imageSource = CGImageSourceCreateWithURL(url as CFURL, imageSourceOptions)
    db("[SETTINGS PREVIEW] CGImageSourceCreateWithURL END file=\(url.lastPathComponent) elapsedMs=\((CACurrentMediaTime() - stageStart) * 1000) hasSource=\(imageSource != nil) thread=\(pthread_main_np() == 1 ? "main" : "background")")
    guard let imageSource else {
        return nil
    }

    let downsampleOptions = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceShouldCacheImmediately: false,
        kCGImageSourceThumbnailMaxPixelSize: Int(maxPixelDimension.rounded(.up))
    ] as CFDictionary

    stageStart = CACurrentMediaTime()
    db("[SETTINGS PREVIEW] THUMBNAIL START file=\(url.lastPathComponent) thread=\(pthread_main_np() == 1 ? "main" : "background")")
    guard let downsampledImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, downsampleOptions) else {
        db("[SETTINGS PREVIEW] THUMBNAIL END file=\(url.lastPathComponent) elapsedMs=\((CACurrentMediaTime() - stageStart) * 1000) hasImage=false thread=\(pthread_main_np() == 1 ? "main" : "background")")
        return nil
    }
    db("[SETTINGS PREVIEW] THUMBNAIL END file=\(url.lastPathComponent) elapsedMs=\((CACurrentMediaTime() - stageStart) * 1000) hasImage=true thread=\(pthread_main_np() == 1 ? "main" : "background")")

    return UIImage(cgImage: downsampledImage)
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
