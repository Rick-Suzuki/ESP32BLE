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
    static let defaultButtonsBackgroundOpacity = 1.0

    var schemaVersion: Int
    var fontSize: Double
    var grid: Grid
    var backgroundImageName: String?
    var backgroundOpacity: Double
    var buttonsBackgroundOpacity: Double?

    init(
        schemaVersion: Int = ScreenConfig.currentSchemaVersion,
        fontSize: Double = ScreenConfig.defaultFontSize,
        grid: Grid,
        backgroundImageName: String? = nil,
        backgroundOpacity: Double = ScreenConfig.defaultBackgroundOpacity,
        buttonsBackgroundOpacity: Double? = ScreenConfig.defaultButtonsBackgroundOpacity
    ) {
        self.schemaVersion = schemaVersion
        self.fontSize = fontSize
        self.grid = grid
        self.backgroundImageName = backgroundImageName
        self.backgroundOpacity = min(max(backgroundOpacity, 0), 1)
        self.buttonsBackgroundOpacity = buttonsBackgroundOpacity.map { min(max($0, 0), 1) }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case fontSize
        case grid
        case backgroundImageName
        case backgroundOpacity
        case buttonsBackgroundOpacity
        case buttonBackgroundOpacity
        case gridOpacity
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? ScreenConfig.currentSchemaVersion
        let fontSize = try container.decodeIfPresent(Double.self, forKey: .fontSize) ?? ScreenConfig.defaultFontSize
        let grid = try container.decode(Grid.self, forKey: .grid)
        let backgroundImageName = try container.decodeIfPresent(String.self, forKey: .backgroundImageName)
        let backgroundOpacity = try container.decodeIfPresent(Double.self, forKey: .backgroundOpacity) ?? ScreenConfig.defaultBackgroundOpacity
        let buttonsBackgroundOpacity = try container.decodeIfPresent(Double.self, forKey: .buttonsBackgroundOpacity) ??
            container.decodeIfPresent(Double.self, forKey: .buttonBackgroundOpacity) ??
            container.decodeIfPresent(Double.self, forKey: .gridOpacity)

        self.init(
            schemaVersion: schemaVersion,
            fontSize: fontSize,
            grid: grid,
            backgroundImageName: backgroundImageName,
            backgroundOpacity: backgroundOpacity,
            buttonsBackgroundOpacity: buttonsBackgroundOpacity
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(fontSize, forKey: .fontSize)
        try container.encode(grid, forKey: .grid)
        try container.encodeIfPresent(backgroundImageName, forKey: .backgroundImageName)
        try container.encode(backgroundOpacity, forKey: .backgroundOpacity)
        try container.encodeIfPresent(buttonsBackgroundOpacity, forKey: .buttonsBackgroundOpacity)
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
    let existedBeforeSave = FileManager.default.fileExists(atPath: screenConfigURL.path)
    db("CONFIG_RECREATE_TRACE saveScreenConfig enter document=\(documentURL.lastPathComponent) config=\(screenConfigURL.lastPathComponent) existedBefore=\(existedBeforeSave) path=\(screenConfigURL.path)")
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

    guard let data = try? encoder.encode(config) else {
        db("CONFIG_RECREATE_TRACE saveScreenConfig encode_failed document=\(documentURL.lastPathComponent) config=\(screenConfigURL.lastPathComponent)")
        return false
    }

    do {
        try data.write(to: screenConfigURL, options: [.atomic])
        db("CONFIG_RECREATE_TRACE saveScreenConfig success document=\(documentURL.lastPathComponent) config=\(screenConfigURL.lastPathComponent)")
        return true
    } catch {
        db("CONFIG_RECREATE_TRACE saveScreenConfig failed document=\(documentURL.lastPathComponent) config=\(screenConfigURL.lastPathComponent) error=\(error)")
        return false
    }
}

func screenConfig(for documentURL: URL, requiredBoxCount: Int) -> ScreenConfig {
    if let config = loadScreenConfig(for: documentURL) {
        return config
    }

    return defaultScreenConfig(for: documentURL.lastPathComponent, requiredBoxCount: requiredBoxCount)
}

@discardableResult
func ensureScreenConfigFile(for documentURL: URL, requiredBoxCount: Int) -> ScreenConfig {
    if let config = loadScreenConfig(for: documentURL) {
        db("CONFIG_RECREATE_TRACE ensureScreenConfigFile existing document=\(documentURL.lastPathComponent) config=\(configFileName(forDocumentName: documentURL.lastPathComponent))")
        return config
    }

    let config = defaultScreenConfig(for: documentURL.lastPathComponent, requiredBoxCount: requiredBoxCount)
    guard FileManager.default.fileExists(atPath: documentURL.path),
          isScreenDocumentURL(documentURL) else {
        db("CONFIG_RECREATE_TRACE SKIP config=\(configFileName(forDocumentName: documentURL.lastPathComponent)) reason=missing \(documentURL.lastPathComponent)")
        return config
    }

    db("CONFIG_RECREATE_TRACE ensureScreenConfigFile creating document=\(documentURL.lastPathComponent) config=\(configFileName(forDocumentName: documentURL.lastPathComponent)) requiredBoxCount=\(requiredBoxCount)")
    _ = saveScreenConfig(config, for: documentURL)
    return config
}

func ensureScreenConfigFiles(for documentURLs: [URL]) {
    db("CONFIG_RECREATE_TRACE ensureScreenConfigFiles enter documents=\(documentURLs.map { $0.lastPathComponent }.joined(separator: ", "))")
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
