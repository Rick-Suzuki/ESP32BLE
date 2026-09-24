import SwiftUI
import UIKit
import QuartzCore

enum SettingsProbeCounters {
    private static var windowStart = CACurrentMediaTime()
    private static var bodyCounts: [String: Int] = [:]
    private static var fileStats: [String: FileScanStats] = [:]
    private static var lifetimeFileStats: [String: FileScanStats] = [:]
    private static var burstStart = CACurrentMediaTime()
    private static var burstStats: [String: FileScanStats] = [:]
    private static var directorySignatures: [String: String] = [:]
    private static var directoryChangeCounts: [String: Int] = [:]

    private struct FileScanStats {
        var evaluations = 0
        var scans = 0
        var totalMilliseconds = 0.0
        var maxMilliseconds = 0.0
        var directoryChanges = 0
        var lastRawCount = 0

        mutating func recordEvaluation() {
            evaluations += 1
        }

        mutating func recordScan(elapsedMilliseconds: Double, rawCount: Int, directoryChanged: Bool) {
            scans += 1
            totalMilliseconds += elapsedMilliseconds
            maxMilliseconds = max(maxMilliseconds, elapsedMilliseconds)
            lastRawCount = rawCount
            if directoryChanged {
                directoryChanges += 1
            }
        }
    }

    static func record(_ name: String, detail: String = "") {
        bodyCounts[name, default: 0] += 1
        emitSummaryIfNeeded(detail: detail)
    }

    static func recordFileEvaluation(_ category: String, detail: String = "") {
        fileStats[category, default: FileScanStats()].recordEvaluation()
        lifetimeFileStats[category, default: FileScanStats()].recordEvaluation()
        emitSummaryIfNeeded(detail: detail)
    }

    static func contentsOfDirectory(
        category: String,
        at directoryURL: URL,
        includingPropertiesForKeys keys: [URLResourceKey]
    ) -> [URL] {
        let scanStart = CACurrentMediaTime()
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )) ?? []
        let elapsedMilliseconds = (CACurrentMediaTime() - scanStart) * 1000
        let signature = directorySignature(for: urls)
        let previousSignature = directorySignatures[category]
        let directoryChanged = previousSignature != nil && previousSignature != signature
        directorySignatures[category] = signature
        if directoryChanged {
            directoryChangeCounts[category, default: 0] += 1
        }

        fileStats[category, default: FileScanStats()].recordScan(
            elapsedMilliseconds: elapsedMilliseconds,
            rawCount: urls.count,
            directoryChanged: directoryChanged
        )
        lifetimeFileStats[category, default: FileScanStats()].recordScan(
            elapsedMilliseconds: elapsedMilliseconds,
            rawCount: urls.count,
            directoryChanged: directoryChanged
        )
        burstStats[category, default: FileScanStats()].recordScan(
            elapsedMilliseconds: elapsedMilliseconds,
            rawCount: urls.count,
            directoryChanged: directoryChanged
        )

        let now = CACurrentMediaTime()
        emitBurstIfNeeded(now: now)
        emitSummaryIfNeeded(now: now, detail: "category=\(category)")
        return urls
    }

    private static func directorySignature(for urls: [URL]) -> String {
        var hash = UInt64(1469598103934665603)
        for name in urls.map(\.lastPathComponent).sorted() {
            for byte in name.utf8 {
                hash ^= UInt64(byte)
                hash &*= 1099511628211
            }
            hash ^= 0xff
            hash &*= 1099511628211
        }

        return "\(urls.count):\(hash)"
    }

    private static func emitSummaryIfNeeded(now: CFTimeInterval = CACurrentMediaTime(), detail: String) {
        let elapsed = now - windowStart
        guard elapsed >= 10 else { return }

        let categories = ["document", "text", "images", "sounds", "pdfs", "all"]
        let totalScans = categories.reduce(0) { $0 + (fileStats[$1]?.scans ?? 0) }
        let totalMilliseconds = categories.reduce(0.0) { $0 + (fileStats[$1]?.totalMilliseconds ?? 0) }
        let lifetimeScans = categories.reduce(0) { $0 + (lifetimeFileStats[$1]?.scans ?? 0) }
        let lifetimeMilliseconds = categories.reduce(0.0) { $0 + (lifetimeFileStats[$1]?.totalMilliseconds ?? 0) }

        let fileLines = categories.map { category in
            let stats = fileStats[category] ?? FileScanStats()
            let lifetime = lifetimeFileStats[category] ?? FileScanStats()
            return "\(category) eval=\(stats.evaluations) scans=\(stats.scans) totalMs=\(String(format: "%.3f", stats.totalMilliseconds)) maxMs=\(String(format: "%.3f", stats.maxMilliseconds)) lifetimeEval=\(lifetime.evaluations) lifetimeScans=\(lifetime.scans)"
        }.joined(separator: "\n")

        let bodySummary = bodyCounts
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ", ")

        let stateSummary = categories.map { category in
            let stats = lifetimeFileStats[category] ?? FileScanStats()
            return "\(category) scans=\(stats.scans) directoryChanges=\(stats.directoryChanges) rawCount=\(stats.lastRawCount)"
        }.joined(separator: "\n")

        db("[FILESCAN 10s]\n\(fileLines)\nTOTAL scans=\(totalScans) totalMs=\(String(format: "%.3f", totalMilliseconds)) lifetimeScans=\(lifetimeScans) lifetimeTotalMs=\(String(format: "%.3f", lifetimeMilliseconds)) detail=\(detail) thread=\(Thread.isMainThread ? "main" : "background")")
        db("[BODYCOUNTS 10s]\n\(bodySummary)\nthread=\(Thread.isMainThread ? "main" : "background")")
        db("[FILESCAN STATE]\n\(stateSummary)\nthread=\(Thread.isMainThread ? "main" : "background")")
        fileStats = [:]
        bodyCounts = [:]
        windowStart = now
    }

    private static func emitBurstIfNeeded(now: CFTimeInterval) {
        let elapsedMilliseconds = (now - burstStart) * 1000
        guard elapsedMilliseconds >= 500 else { return }

        let categories = ["document", "text", "images", "sounds", "pdfs", "all"]
        let totalScans = categories.reduce(0) { $0 + (burstStats[$1]?.scans ?? 0) }
        guard totalScans >= 10 else {
            burstStats = [:]
            burstStart = now
            return
        }

        let totalMilliseconds = categories.reduce(0.0) { $0 + (burstStats[$1]?.totalMilliseconds ?? 0) }
        let categorySummary = categories
            .map { "\($0)=\(burstStats[$0]?.scans ?? 0)" }
            .joined(separator: " ")
        db("[FILESCAN BURST]\nwindowMs=\(String(format: "%.1f", elapsedMilliseconds))\nscans=\(totalScans)\n\(categorySummary)\ntotalMs=\(String(format: "%.3f", totalMilliseconds))\nthread=\(Thread.isMainThread ? "main" : "background")")
        burstStats = [:]
        burstStart = now
    }
}

extension SettingsScreen {
    var availableImageURLs: [URL] {
        SettingsProbeCounters.recordFileEvaluation("images")
        guard let directoryURL = currentDocumentsDirectoryURL else {
            return []
        }

        let supportedExtensions = Set(["png", "jpg", "jpeg", "heic", "heif", "gif", "bmp", "tiff", "webp"])

        let urls = SettingsProbeCounters.contentsOfDirectory(
            category: "images",
            at: directoryURL,
            includingPropertiesForKeys: [URLResourceKey.isRegularFileKey]
        )

        return urls
            .filter { url in
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
                return values?.isRegularFile == true && supportedExtensions.contains(url.pathExtension.lowercased())
            }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
    }

    var maximumSelectableImageIndex: Int {
        availableImageURLs.count
    }

    var selectedImageURL: URL? {
        if !selectedImagePath.isEmpty,
           let imageURL = availableImageURLs.first(where: { $0.path == selectedImagePath }) {
            return imageURL
        }

        if !selectedImageName.isEmpty,
           let imageURL = availableImageURLs.first(where: {
               $0.lastPathComponent.caseInsensitiveCompare(selectedImageName) == .orderedSame
           }) {
            return imageURL
        }

        guard selectedImageIndex > 0 else { return nil }
        let imageIndex = selectedImageIndex - 1
        guard availableImageURLs.indices.contains(imageIndex) else { return nil }
        return availableImageURLs[imageIndex]
    }

    var selectedImagePosition: Int? {
        guard let selectedImageURL,
              let imageIndex = availableImageURLs.firstIndex(where: { $0.path == selectedImageURL.path }) else {
            return nil
        }

        return imageIndex + 1
    }

    var truncatedImageDisplayName: String {
        guard let selectedImagePosition else {
            return "black bg"
        }

        let imageIndex = selectedImagePosition - 1
        let name = availableImageURLs[imageIndex].lastPathComponent
        let maxCharacterCount = 20
        if name.count <= maxCharacterCount {
            return name
        }

        return String(name.prefix(maxCharacterCount)) + "..."
    }

    func persistSelectedImage(_ imageURL: URL?) {
        let persistStart = CACurrentMediaTime()
        db("[PROBE] persistSelectedImage START \(Date()) file=\(imageURL?.lastPathComponent ?? "none") thread=\(Thread.isMainThread ? "main" : "background")")
        selectedImagePath = imageURL?.path ?? ""
        selectedImageName = imageURL?.lastPathComponent ?? ""
        if let imageURL,
           let imageIndex = availableImageURLs.firstIndex(where: { $0.path == imageURL.path }) {
            selectedImageIndex = imageIndex + 1
        } else {
            selectedImageIndex = 0
        }
        db("[PROBE] persistSelectedImage END \(Date()) file=\(imageURL?.lastPathComponent ?? "none") selectedImageIndex=\(selectedImageIndex) elapsedMs=\((CACurrentMediaTime() - persistStart) * 1000) thread=\(Thread.isMainThread ? "main" : "background")")
    }
}
