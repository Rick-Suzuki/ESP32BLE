import SwiftUI
import UIKit
import PDFKit

struct SettingsImagePreviewPanel: View {
    let imageURL: URL?
    let opacitySliderValue: Double
    let usesSinglePixelBorder: Bool
    let usesAspectFill: Bool
    @Environment(\.displayScale) private var displayScale
    @State private var previewImage: UIImage?
    @State private var previewRequestID = ""
    @State private var zoomScale: CGFloat = 1
    @State private var panOffset: CGSize = .zero
    @GestureState private var activeMagnification: CGFloat = 1
    @GestureState private var activeDragTranslation: CGSize = .zero
    @GestureState private var isMagnifying = false

    // MARK: - BM:🅱️ NO-IMAGE PREVIEW LABEL FONT SIZE
    // Controls the centered no-image preview label.
    private let blackPreviewLabelFont: Font = .system(size: 16, weight: .medium)

    // MARK: - BM:🅱️ IMAGE EDITOR MAXIMUM ZOOM
    // 🐞 USER ADJUSTABLE: Maximum image editor zoom.
    // Change 5.0 to your preferred maximum zoom level.
    private let maximumImageZoom: CGFloat = 5.0

    var body: some View {
        GeometryReader { geometry in
            let previewWidth = geometry.size.width
            let previewHeight = geometry.size.height
            let previewMaxPixelDimension = max(previewWidth, previewHeight) * UIScreen.main.scale

            ZStack {
                Color.black

                if let previewImage {
                    zoomablePreviewImage(
                        previewImage,
                        viewportSize: geometry.size
                    )
                }

                if imageURL == nil {
                    Text("No image selected")
                        .font(blackPreviewLabelFont)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(width: previewWidth, height: previewHeight)
            .clipped()
            .overlay {
                Rectangle()
                    .stroke(Color.white, lineWidth: usesSinglePixelBorder ? 1 / displayScale : 2)
            }
            .task(id: previewImageTaskID(maxPixelDimension: previewMaxPixelDimension)) {
                await loadPreviewImage(maxPixelDimension: previewMaxPixelDimension)
            }
            .onChange(of: imageURL?.path) { _, _ in
                resetImageGestureState()
            }
        }
    }

    // MARK: - BM:🅱️ IMAGE PREVIEW ZOOM AND PAN

    private func zoomablePreviewImage(
        _ image: UIImage,
        viewportSize: CGSize
    ) -> some View {
        let effectiveScale = effectiveZoomScale
        let renderedOffset = clampedPanOffset(
            offsetByAdding(panOffset, isMagnifying ? .zero : activeDragTranslation),
            imageSize: image.size,
            viewportSize: viewportSize,
            zoomScale: effectiveScale
        )

        return Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: usesAspectFill ? .fill : .fit)
            .frame(width: viewportSize.width, height: viewportSize.height)
            .scaleEffect(effectiveScale, anchor: .center)
            .offset(renderedOffset)
            .opacity(opacitySliderValue)
            .contentShape(.rect)
            .simultaneousGesture(magnificationGesture(imageSize: image.size, viewportSize: viewportSize))
            .simultaneousGesture(panGesture(imageSize: image.size, viewportSize: viewportSize))
    }

    private var effectiveZoomScale: CGFloat {
        min(maximumImageZoom, max(1, zoomScale * activeMagnification))
    }

    private func magnificationGesture(
        imageSize: CGSize,
        viewportSize: CGSize
    ) -> some Gesture {
        MagnifyGesture()
            .updating($activeMagnification) { value, magnification, _ in
                magnification = value.magnification
            }
            .updating($isMagnifying) { _, isMagnifying, _ in
                isMagnifying = true
            }
            .onEnded { value in
                zoomScale = min(maximumImageZoom, max(1, zoomScale * value.magnification))
                panOffset = clampedPanOffset(
                    panOffset,
                    imageSize: imageSize,
                    viewportSize: viewportSize,
                    zoomScale: zoomScale
                )
            }
    }

    private func panGesture(
        imageSize: CGSize,
        viewportSize: CGSize
    ) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($activeDragTranslation) { value, translation, _ in
                translation = isMagnifying ? .zero : value.translation
            }
            .onEnded { value in
                guard !isMagnifying else {
                    return
                }

                panOffset = clampedPanOffset(
                    offsetByAdding(panOffset, value.translation),
                    imageSize: imageSize,
                    viewportSize: viewportSize,
                    zoomScale: effectiveZoomScale
                )
            }
    }

    private func clampedPanOffset(
        _ offset: CGSize,
        imageSize: CGSize,
        viewportSize: CGSize,
        zoomScale: CGFloat
    ) -> CGSize {
        guard imageSize.width > 0,
              imageSize.height > 0,
              viewportSize.width > 0,
              viewportSize.height > 0 else {
            return .zero
        }

        let horizontalScale = viewportSize.width / imageSize.width
        let verticalScale = viewportSize.height / imageSize.height
        let baseFactor = usesAspectFill
            ? max(horizontalScale, verticalScale)
            : min(horizontalScale, verticalScale)
        let scaledWidth = imageSize.width * baseFactor * zoomScale
        let scaledHeight = imageSize.height * baseFactor * zoomScale
        let maximumPanX = max(0, (scaledWidth - viewportSize.width) / 2)
        let maximumPanY = max(0, (scaledHeight - viewportSize.height) / 2)

        return CGSize(
            width: min(max(offset.width, -maximumPanX), maximumPanX),
            height: min(max(offset.height, -maximumPanY), maximumPanY)
        )
    }

    private func resetImageGestureState() {
        zoomScale = 1
        panOffset = .zero
    }

    private func offsetByAdding(_ lhs: CGSize, _ rhs: CGSize) -> CGSize {
        CGSize(
            width: lhs.width + rhs.width,
            height: lhs.height + rhs.height
        )
    }

    private func previewImageTaskID(maxPixelDimension: CGFloat) -> String {
        "\(imageURL?.path ?? "none"):\(Int(maxPixelDimension.rounded(.up)))"
    }

    private func loadPreviewImage(maxPixelDimension: CGFloat) async {
        guard let imageURL else {
            previewImage = nil
            resetImageGestureState()
            return
        }

        let requestID = previewImageTaskID(maxPixelDimension: maxPixelDimension)
        previewRequestID = requestID
        let decodeTask = Task.detached(priority: .userInitiated) {
            settingsPreviewDownsampledUIImage(at: imageURL, maxPixelDimension: maxPixelDimension)
        }
        let decodedImage = await decodeTask.value

        guard !Task.isCancelled else {
            return
        }

        guard previewRequestID == requestID else {
            return
        }

        previewImage = decodedImage
        if decodedImage == nil {
            resetImageGestureState()
        }
    }
}

nonisolated private func settingsPreviewDownsampledUIImage(at url: URL, maxPixelDimension: CGFloat) -> UIImage? {
    guard maxPixelDimension > 0 else {
        return UIImage(contentsOfFile: url.path)
    }

    let imageSourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
    let imageSource = CGImageSourceCreateWithURL(url as CFURL, imageSourceOptions)
    guard let imageSource else {
        return nil
    }

    let downsampleOptions = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceShouldCacheImmediately: false,
        kCGImageSourceThumbnailMaxPixelSize: Int(maxPixelDimension.rounded(.up))
    ] as CFDictionary

    guard let downsampledImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, downsampleOptions) else {
        return nil
    }

    return UIImage(cgImage: downsampledImage)
}

struct SettingsPDFPreviewPanel: View {
    let pdfURL: URL?
    let usesSinglePixelBorder: Bool
    let usesWidthFit: Bool
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black

                SettingsPDFPreviewView(
                    pdfURL: pdfURL,
                    fitsPageWidth: usesWidthFit
                )
                    .frame(width: geometry.size.width, height: geometry.size.height)

                if pdfURL == nil {
                    Text("No PDF selected")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .overlay {
                Rectangle()
                    .stroke(Color.white, lineWidth: usesSinglePixelBorder ? 1 / displayScale : 2)
            }
        }
    }
}

private struct SettingsPDFPreviewView: UIViewRepresentable {
    let pdfURL: URL?
    let fitsPageWidth: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> PDFView {
        let pdfView: PDFView
        if fitsPageWidth {
            let widthFittingPDFView = SettingsWidthFittingPDFView()
            widthFittingPDFView.onLayout = { [weak coordinator = context.coordinator] pdfView in
                coordinator?.applyWidthFitIfNeeded(to: pdfView)
            }
            pdfView = widthFittingPDFView
        } else {
            pdfView = PDFView()
        }

        pdfView.backgroundColor = .black
        pdfView.autoScales = !fitsPageWidth
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
            context.coordinator.resetWidthFit()
            return
        }

        if pdfView.document?.documentURL != pdfURL {
            pdfView.document = PDFDocument(url: pdfURL)
            context.coordinator.resetWidthFit()
        }

        if fitsPageWidth {
            context.coordinator.applyWidthFitIfNeeded(to: pdfView)
        } else {
            pdfView.scaleFactor = pdfView.scaleFactorForSizeToFit
        }
    }

    final class Coordinator {
        private var fittedDocumentURL: URL?
        private var fittedViewportSize = CGSize.zero

        func resetWidthFit() {
            fittedDocumentURL = nil
            fittedViewportSize = .zero
        }

        // MARK: - BM:🅱️ IPHONE PDF INITIAL WIDTH FIT
        func applyWidthFitIfNeeded(to pdfView: PDFView) {
            guard let document = pdfView.document,
                  let firstPage = document.page(at: 0) else {
                return
            }

            let viewportSize = pdfView.bounds.size
            guard viewportSize.width > 0,
                  viewportSize.height > 0 else {
                return
            }

            let documentURL = document.documentURL
            guard fittedDocumentURL != documentURL || fittedViewportSize != viewportSize else {
                return
            }

            let pageBounds = firstPage.bounds(for: pdfView.displayBox)
            let normalizedRotation = ((firstPage.rotation % 360) + 360) % 360
            let pageWidth = normalizedRotation.isMultiple(of: 180)
                ? pageBounds.width
                : pageBounds.height
            guard pageWidth > 0 else {
                return
            }

            let widthFitScale = viewportSize.width / pageWidth
            guard widthFitScale.isFinite, widthFitScale > 0 else {
                return
            }

            if abs(pdfView.scaleFactor - widthFitScale) > .ulpOfOne {
                pdfView.scaleFactor = widthFitScale
            }
            fittedDocumentURL = documentURL
            fittedViewportSize = viewportSize
        }
    }
}

private final class SettingsWidthFittingPDFView: PDFView {
    var onLayout: ((PDFView) -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?(self)
    }
}
