import Foundation

struct ScreenConfig: Codable, Equatable {
    struct Grid: Codable, Equatable {
        var rows: Int
        var columns: Int

        init(rows: Int, columns: Int) {
            self.rows = max(rows, 1)
            self.columns = max(columns, 1)
        }
    }

    static let currentSchemaVersion = 1
    static let defaultFontSize = 20.0
    static let defaultBackgroundOpacity = 0.5

    var schemaVersion: Int
    var fontSize: Double
    var grid: Grid
    var backgroundImageName: String?
    var backgroundOpacity: Double
    var gridOpacity: Double?

    init(
        schemaVersion: Int = ScreenConfig.currentSchemaVersion,
        fontSize: Double = ScreenConfig.defaultFontSize,
        grid: Grid,
        backgroundImageName: String? = nil,
        backgroundOpacity: Double = ScreenConfig.defaultBackgroundOpacity,
        gridOpacity: Double? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.fontSize = fontSize
        self.grid = grid
        self.backgroundImageName = backgroundImageName
        self.backgroundOpacity = min(max(backgroundOpacity, 0), 1)
        self.gridOpacity = gridOpacity.map { min(max($0, 0), 1) }
    }
}

func configFileName(forDocumentName documentName: String) -> String {
    let baseName = URL(fileURLWithPath: documentName)
        .deletingPathExtension()
        .lastPathComponent
        .trimmingCharacters(in: .whitespacesAndNewlines)

    let resolvedBaseName = baseName.isEmpty ? "Screen" : baseName
    return "\(resolvedBaseName).config.json"
}

func configURL(forDocumentURL documentURL: URL) -> URL {
    documentURL
        .deletingLastPathComponent()
        .appendingPathComponent(configFileName(forDocumentName: documentURL.lastPathComponent))
}

func loadScreenConfig(for documentURL: URL) -> ScreenConfig? {
    let screenConfigURL = configURL(forDocumentURL: documentURL)
    guard FileManager.default.fileExists(atPath: screenConfigURL.path),
          let data = try? Data(contentsOf: screenConfigURL),
          !data.isEmpty else {
        return nil
    }

    return try? JSONDecoder().decode(ScreenConfig.self, from: data)
}

@discardableResult
func saveScreenConfig(_ config: ScreenConfig, for documentURL: URL) -> Bool {
    let screenConfigURL = configURL(forDocumentURL: documentURL)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

    guard let data = try? encoder.encode(config) else {
        return false
    }

    do {
        try data.write(to: screenConfigURL, options: [.atomic])
        return true
    } catch {
        return false
    }
}

func screenConfig(for documentURL: URL, requiredBoxCount: Int) -> ScreenConfig {
    if let config = loadScreenConfig(for: documentURL) {
        return config
    }

    return migratedScreenConfigFromAppStorage(
        for: documentURL.lastPathComponent,
        requiredBoxCount: requiredBoxCount
    )
}

@discardableResult
func ensureScreenConfigFile(for documentURL: URL, requiredBoxCount: Int) -> ScreenConfig {
    if let config = loadScreenConfig(for: documentURL) {
        return config
    }

    let config = migratedScreenConfigFromAppStorage(
        for: documentURL.lastPathComponent,
        requiredBoxCount: requiredBoxCount
    )
    _ = saveScreenConfig(config, for: documentURL)
    return config
}

func ensureScreenConfigFiles(for documentURLs: [URL]) {
    for documentURL in documentURLs {
        let requiredBoxCount = requiredBoxCountForScreenConfig(documentURL: documentURL)
        _ = ensureScreenConfigFile(for: documentURL, requiredBoxCount: requiredBoxCount)
    }
}

func defaultScreenConfig(for documentName: String, requiredBoxCount: Int) -> ScreenConfig {
    let resolvedGridDimensions = functionKeyGridDimensions(for: min(max(requiredBoxCount, 1), maxFunctionKeyCount))
    return ScreenConfig(
        grid: ScreenConfig.Grid(
            rows: resolvedGridDimensions.rows,
            columns: resolvedGridDimensions.columns
        )
    )
}

func migratedScreenConfigFromAppStorage(for documentName: String, requiredBoxCount: Int) -> ScreenConfig {
    defaultScreenConfig(for: documentName, requiredBoxCount: requiredBoxCount)
}

private func requiredBoxCountForScreenConfig(documentURL: URL) -> Int {
    guard let contents = try? String(contentsOf: documentURL, encoding: .utf8) else {
        return 1
    }

    let slotLines = contents
        .components(separatedBy: CharacterSet.newlines.union(.init(charactersIn: "\t")))
        .filter { line in
            let normalizedLine = line.replacingOccurrences(of: "\r", with: "")
            let trimmedLine = normalizedLine.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmedLine.isEmpty && !trimmedLine.hasPrefix("//")
        }

    return min(max(slotLines.count, 1), maxFunctionKeyCount)
}
