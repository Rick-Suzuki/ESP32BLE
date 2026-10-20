import Foundation

let templateDocumentFileExtension = "template"
private let templateConfigurationFileSuffix = ".template.config.json"

func isTemplateDocumentURL(_ url: URL) -> Bool {
    isTemplateDocumentFileName(url.lastPathComponent)
}

func isTemplateDocumentFileName(_ fileName: String) -> Bool {
    URL(fileURLWithPath: fileName).pathExtension.lowercased() == templateDocumentFileExtension
}

func preferredTemplateDocumentURLs(from urls: [URL]) -> [URL] {
    urls
        .filter(isTemplateDocumentURL)
        .sorted {
            $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending
        }
}

func discoverTemplateDocumentURLs(
    in directoryURL: URL,
    fileManager: FileManager = .default
) -> [URL] {
    guard let urls = try? fileManager.contentsOfDirectory(
        at: directoryURL,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    ) else {
        return []
    }

    return preferredTemplateDocumentURLs(
        from: urls.filter { url in
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            return values?.isRegularFile == true
        }
    )
}

func templateConfigFileName(forTemplateDocumentName documentName: String) -> String {
    let fileName = URL(fileURLWithPath: documentName).lastPathComponent
    return "\(fileName).config.json"
}

func templateConfigURL(forTemplateDocumentURL documentURL: URL) -> URL {
    documentURL
        .deletingLastPathComponent()
        .appendingPathComponent(
            templateConfigFileName(forTemplateDocumentName: documentURL.lastPathComponent)
        )
}

func isTemplateConfigurationURL(_ url: URL) -> Bool {
    url.lastPathComponent.lowercased().hasSuffix(templateConfigurationFileSuffix)
}

struct TemplateConfiguration: Codable, Equatable {
    var screenConfig: ScreenConfig
    var description: String?

    init(screenConfig: ScreenConfig, description: String? = nil) {
        self.screenConfig = screenConfig
        self.description = description
    }

    private enum CodingKeys: String, CodingKey {
        case description
    }

    init(from decoder: Decoder) throws {
        screenConfig = try ScreenConfig(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        description = try container.decodeIfPresent(String.self, forKey: .description)
    }

    func encode(to encoder: Encoder) throws {
        try screenConfig.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(description, forKey: .description)
    }
}

enum TemplateConfigurationError: LocalizedError {
    case invalidTemplateURL(URL)
    case templateDocumentNotFound(URL)
    case configurationNotFound(URL)
    case emptyConfiguration(URL)
    case unreadableConfiguration(URL, Error)
    case invalidConfiguration(URL, Error)
    case unableToEncode(Error)
    case unableToWrite(URL, Error)

    var errorDescription: String? {
        switch self {
        case .invalidTemplateURL(let url):
            return "\(url.lastPathComponent) is not a template document."
        case .templateDocumentNotFound(let url):
            return "The template document \(url.lastPathComponent) does not exist."
        case .configurationNotFound(let url):
            return "The template configuration \(url.lastPathComponent) does not exist."
        case .emptyConfiguration(let url):
            return "The template configuration \(url.lastPathComponent) is empty."
        case .unreadableConfiguration(let url, let error):
            return "The template configuration \(url.lastPathComponent) could not be read: \(error.localizedDescription)"
        case .invalidConfiguration(let url, let error):
            return "The template configuration \(url.lastPathComponent) is invalid: \(error.localizedDescription)"
        case .unableToEncode(let error):
            return "The template configuration could not be encoded: \(error.localizedDescription)"
        case .unableToWrite(let url, let error):
            return "The template configuration \(url.lastPathComponent) could not be saved: \(error.localizedDescription)"
        }
    }
}

func loadTemplateConfiguration(for documentURL: URL) throws -> TemplateConfiguration {
    guard isTemplateDocumentURL(documentURL) else {
        throw TemplateConfigurationError.invalidTemplateURL(documentURL)
    }

    let configurationURL = templateConfigURL(forTemplateDocumentURL: documentURL)
    guard FileManager.default.fileExists(atPath: configurationURL.path) else {
        throw TemplateConfigurationError.configurationNotFound(configurationURL)
    }

    let data: Data
    do {
        data = try Data(contentsOf: configurationURL)
    } catch {
        throw TemplateConfigurationError.unreadableConfiguration(configurationURL, error)
    }

    guard !data.isEmpty else {
        throw TemplateConfigurationError.emptyConfiguration(configurationURL)
    }

    do {
        return try JSONDecoder().decode(TemplateConfiguration.self, from: data)
    } catch {
        throw TemplateConfigurationError.invalidConfiguration(configurationURL, error)
    }
}

func saveTemplateConfiguration(
    _ configuration: TemplateConfiguration,
    for documentURL: URL
) throws {
    guard isTemplateDocumentURL(documentURL) else {
        throw TemplateConfigurationError.invalidTemplateURL(documentURL)
    }

    guard FileManager.default.fileExists(atPath: documentURL.path) else {
        throw TemplateConfigurationError.templateDocumentNotFound(documentURL)
    }

    let data: Data
    do {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        data = try encoder.encode(configuration)
    } catch {
        throw TemplateConfigurationError.unableToEncode(error)
    }

    let configurationURL = templateConfigURL(forTemplateDocumentURL: documentURL)
    do {
        try data.write(to: configurationURL, options: [.atomic])
    } catch {
        throw TemplateConfigurationError.unableToWrite(configurationURL, error)
    }
}

struct TemplateApplicationResult {
    let targetDocumentURL: URL
    let templateContents: String
    let screenConfig: ScreenConfig
}

enum TemplateApplicationError: LocalizedError {
    case invalidTemplateURL(URL)
    case templateNotFound(URL)
    case templateIsNotRegularFile(URL)
    case unreadableTemplate(URL, Error)
    case invalidTemplateUTF8(URL)
    case missingTemplateConfiguration(URL)
    case invalidTemplateConfiguration(Error)
    case invalidButtonCount(Int, maximum: Int)
    case invalidGrid(rows: Int, columns: Int, buttonCount: Int, maximum: Int)
    case invalidTargetURL(URL)
    case targetNameMismatch(expected: String, actual: String)
    case targetSelectionChanged(expected: String, actual: String)
    case targetNotFound(URL)
    case targetIsNotRegularFile(URL)
    case invalidTargetUTF8(URL)
    case targetSnapshotFailed(URL, Error)
    case replacementPreparationFailed(URL, Error)
    case targetChangedDuringPreparation(URL)
    case replacementFailedAndRolledBack(Error)
    case rollbackFailed(replacementError: Error, rollbackError: Error)

    var errorDescription: String? {
        switch self {
        case .invalidTemplateURL(let url):
            return "\(url.lastPathComponent) is not a template document."
        case .templateNotFound(let url):
            return "The template document \(url.lastPathComponent) does not exist."
        case .templateIsNotRegularFile(let url):
            return "The template document \(url.lastPathComponent) is not a regular file."
        case .unreadableTemplate(let url, let error):
            return "The template document \(url.lastPathComponent) could not be read: \(error.localizedDescription)"
        case .invalidTemplateUTF8(let url):
            return "The template document \(url.lastPathComponent) is not valid UTF-8."
        case .missingTemplateConfiguration(let url):
            return "The template configuration \(url.lastPathComponent) does not exist."
        case .invalidTemplateConfiguration(let error):
            return "The template configuration is invalid: \(error.localizedDescription)"
        case .invalidButtonCount(let count, let maximum):
            return "The template contains \(count) button lines, but the supported maximum is \(maximum)."
        case .invalidGrid(let rows, let columns, let buttonCount, let maximum):
            return "The template grid \(rows)x\(columns) is not compatible with \(buttonCount) button lines and the supported maximum of \(maximum)."
        case .invalidTargetURL(let url):
            return "\(url.lastPathComponent) is not a screen document."
        case .targetNameMismatch(let expected, let actual):
            return "The target screen changed from \(expected) to \(actual)."
        case .targetSelectionChanged(let expected, let actual):
            return "The active screen changed from \(expected) to \(actual)."
        case .targetNotFound(let url):
            return "The target screen \(url.lastPathComponent) does not exist."
        case .targetIsNotRegularFile(let url):
            return "The target screen \(url.lastPathComponent) is not a regular file."
        case .invalidTargetUTF8(let url):
            return "The target screen \(url.lastPathComponent) is not valid UTF-8."
        case .targetSnapshotFailed(let url, let error):
            return "The original target file \(url.lastPathComponent) could not be preserved: \(error.localizedDescription)"
        case .replacementPreparationFailed(let url, let error):
            return "The replacement for \(url.lastPathComponent) could not be prepared: \(error.localizedDescription)"
        case .targetChangedDuringPreparation(let url):
            return "The target file \(url.lastPathComponent) changed while the replacement was being prepared."
        case .replacementFailedAndRolledBack(let error):
            return "The template replacement failed and the original screen was restored: \(error.localizedDescription)"
        case .rollbackFailed(let replacementError, let rollbackError):
            return "The template replacement failed and the original screen could not be fully restored. Replacement error: \(replacementError.localizedDescription) Rollback error: \(rollbackError.localizedDescription)"
        }
    }
}

func applyTemplateDocument(
    at templateURL: URL,
    to targetDocumentURL: URL,
    expectedTargetDocumentName: String,
    activeTargetDocumentName: () -> String,
    maximumButtonCount: Int,
    effectiveButtonLineCount: (String) -> Int,
    fileManager: FileManager = .default
) throws -> TemplateApplicationResult {
    guard isTemplateDocumentURL(templateURL) else {
        throw TemplateApplicationError.invalidTemplateURL(templateURL)
    }
    guard fileManager.fileExists(atPath: templateURL.path) else {
        throw TemplateApplicationError.templateNotFound(templateURL)
    }
    do {
        let values = try templateURL.resourceValues(forKeys: [.isRegularFileKey])
        guard values.isRegularFile == true else {
            throw TemplateApplicationError.templateIsNotRegularFile(templateURL)
        }
    } catch let error as TemplateApplicationError {
        throw error
    } catch {
        throw TemplateApplicationError.unreadableTemplate(templateURL, error)
    }

    let templateData: Data
    do {
        templateData = try Data(contentsOf: templateURL)
    } catch {
        throw TemplateApplicationError.unreadableTemplate(templateURL, error)
    }
    guard let templateContents = String(data: templateData, encoding: .utf8) else {
        throw TemplateApplicationError.invalidTemplateUTF8(templateURL)
    }

    let templateConfiguration: TemplateConfiguration
    do {
        templateConfiguration = try loadTemplateConfiguration(for: templateURL)
    } catch TemplateConfigurationError.configurationNotFound(let configurationURL) {
        throw TemplateApplicationError.missingTemplateConfiguration(configurationURL)
    } catch {
        throw TemplateApplicationError.invalidTemplateConfiguration(error)
    }

    let buttonCount = effectiveButtonLineCount(templateContents)
    guard maximumButtonCount > 0,
          buttonCount >= 0,
          buttonCount <= maximumButtonCount else {
        throw TemplateApplicationError.invalidButtonCount(buttonCount, maximum: maximumButtonCount)
    }

    let grid = templateConfiguration.screenConfig.grid
    let (gridCapacity, gridOverflow) = grid.rows.multipliedReportingOverflow(by: grid.columns)
    guard grid.rows > 0,
          grid.columns > 0,
          !gridOverflow,
          gridCapacity >= max(buttonCount, 1),
          gridCapacity <= maximumButtonCount else {
        throw TemplateApplicationError.invalidGrid(
            rows: grid.rows,
            columns: grid.columns,
            buttonCount: buttonCount,
            maximum: maximumButtonCount
        )
    }

    guard isScreenDocumentURL(targetDocumentURL) else {
        throw TemplateApplicationError.invalidTargetURL(targetDocumentURL)
    }
    guard targetDocumentURL.lastPathComponent == expectedTargetDocumentName else {
        throw TemplateApplicationError.targetNameMismatch(
            expected: expectedTargetDocumentName,
            actual: targetDocumentURL.lastPathComponent
        )
    }
    let selectedName = activeTargetDocumentName()
    guard selectedName == expectedTargetDocumentName else {
        throw TemplateApplicationError.targetSelectionChanged(
            expected: expectedTargetDocumentName,
            actual: selectedName
        )
    }
    guard fileManager.fileExists(atPath: targetDocumentURL.path) else {
        throw TemplateApplicationError.targetNotFound(targetDocumentURL)
    }
    do {
        let values = try targetDocumentURL.resourceValues(forKeys: [.isRegularFileKey])
        guard values.isRegularFile == true else {
            throw TemplateApplicationError.targetIsNotRegularFile(targetDocumentURL)
        }
    } catch let error as TemplateApplicationError {
        throw error
    } catch {
        throw TemplateApplicationError.targetSnapshotFailed(targetDocumentURL, error)
    }

    let targetConfigURL = configURL(forDocumentURL: targetDocumentURL)
    let originalTargetData: Data
    let originalConfigData: Data?
    do {
        originalTargetData = try Data(contentsOf: targetDocumentURL)
        guard String(data: originalTargetData, encoding: .utf8) != nil else {
            throw TemplateApplicationError.invalidTargetUTF8(targetDocumentURL)
        }
        if fileManager.fileExists(atPath: targetConfigURL.path) {
            originalConfigData = try Data(contentsOf: targetConfigURL)
        } else {
            originalConfigData = nil
        }
    } catch let error as TemplateApplicationError {
        throw error
    } catch {
        throw TemplateApplicationError.targetSnapshotFailed(targetDocumentURL, error)
    }

    let replacementConfigData: Data
    do {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        replacementConfigData = try encoder.encode(templateConfiguration.screenConfig)
    } catch {
        throw TemplateApplicationError.invalidTemplateConfiguration(error)
    }

    let targetDirectoryURL = targetDocumentURL.deletingLastPathComponent()
    let operationID = UUID().uuidString
    let preparedDocumentURL = targetDirectoryURL.appendingPathComponent(".esp-template-\(operationID).screen.tmp")
    let preparedConfigURL = targetDirectoryURL.appendingPathComponent(".esp-template-\(operationID).config.tmp")

    defer {
        try? fileManager.removeItem(at: preparedDocumentURL)
        try? fileManager.removeItem(at: preparedConfigURL)
    }

    do {
        try templateData.write(to: preparedDocumentURL, options: [.atomic])
        try replacementConfigData.write(to: preparedConfigURL, options: [.atomic])

        let preparedTemplateData = try Data(contentsOf: preparedDocumentURL)
        guard preparedTemplateData == templateData,
              String(data: preparedTemplateData, encoding: .utf8) != nil else {
            throw TemplateApplicationError.replacementPreparationFailed(
                preparedDocumentURL,
                CocoaError(.fileReadCorruptFile)
            )
        }
        let preparedConfigData = try Data(contentsOf: preparedConfigURL)
        guard preparedConfigData == replacementConfigData,
              try JSONDecoder().decode(ScreenConfig.self, from: preparedConfigData) == templateConfiguration.screenConfig else {
            throw TemplateApplicationError.replacementPreparationFailed(
                preparedConfigURL,
                CocoaError(.fileReadCorruptFile)
            )
        }
    } catch let error as TemplateApplicationError {
        throw error
    } catch {
        throw TemplateApplicationError.replacementPreparationFailed(targetDirectoryURL, error)
    }

    let selectedNameImmediatelyBeforeReplacement = activeTargetDocumentName()
    guard selectedNameImmediatelyBeforeReplacement == expectedTargetDocumentName else {
        throw TemplateApplicationError.targetSelectionChanged(
            expected: expectedTargetDocumentName,
            actual: selectedNameImmediatelyBeforeReplacement
        )
    }

    do {
        guard try Data(contentsOf: targetDocumentURL) == originalTargetData else {
            throw TemplateApplicationError.targetChangedDuringPreparation(targetDocumentURL)
        }
        let configStillMatches: Bool
        if let originalConfigData {
            if fileManager.fileExists(atPath: targetConfigURL.path) {
                configStillMatches = try Data(contentsOf: targetConfigURL) == originalConfigData
            } else {
                configStillMatches = false
            }
        } else {
            configStillMatches = !fileManager.fileExists(atPath: targetConfigURL.path)
        }
        guard configStillMatches else {
            throw TemplateApplicationError.targetChangedDuringPreparation(targetConfigURL)
        }
    } catch let error as TemplateApplicationError {
        throw error
    } catch {
        throw TemplateApplicationError.targetSnapshotFailed(targetDocumentURL, error)
    }

    do {
        try replacePreparedTemplateFile(
            at: preparedDocumentURL,
            destinationURL: targetDocumentURL,
            fileManager: fileManager
        )
        try replacePreparedTemplateFile(
            at: preparedConfigURL,
            destinationURL: targetConfigURL,
            fileManager: fileManager
        )

        let finalTargetData = try Data(contentsOf: targetDocumentURL)
        let finalConfigData = try Data(contentsOf: targetConfigURL)
        guard finalTargetData == templateData,
              String(data: finalTargetData, encoding: .utf8) != nil,
              finalConfigData == replacementConfigData,
              try JSONDecoder().decode(ScreenConfig.self, from: finalConfigData) == templateConfiguration.screenConfig else {
            throw CocoaError(.fileReadCorruptFile)
        }
    } catch {
        let replacementError = error
        do {
            try restoreTemplateApplicationTarget(
                documentURL: targetDocumentURL,
                originalDocumentData: originalTargetData,
                configURL: targetConfigURL,
                originalConfigData: originalConfigData,
                fileManager: fileManager
            )
        } catch {
            throw TemplateApplicationError.rollbackFailed(
                replacementError: replacementError,
                rollbackError: error
            )
        }
        throw TemplateApplicationError.replacementFailedAndRolledBack(replacementError)
    }

    return TemplateApplicationResult(
        targetDocumentURL: targetDocumentURL,
        templateContents: templateContents,
        screenConfig: templateConfiguration.screenConfig
    )
}

private func replacePreparedTemplateFile(
    at preparedURL: URL,
    destinationURL: URL,
    fileManager: FileManager
) throws {
    if fileManager.fileExists(atPath: destinationURL.path) {
        _ = try fileManager.replaceItemAt(destinationURL, withItemAt: preparedURL)
    } else {
        try fileManager.moveItem(at: preparedURL, to: destinationURL)
    }
}

private func restoreTemplateApplicationTarget(
    documentURL: URL,
    originalDocumentData: Data,
    configURL: URL,
    originalConfigData: Data?,
    fileManager: FileManager
) throws {
    try originalDocumentData.write(to: documentURL, options: [.atomic])

    if let originalConfigData {
        try originalConfigData.write(to: configURL, options: [.atomic])
    } else if fileManager.fileExists(atPath: configURL.path) {
        try fileManager.removeItem(at: configURL)
    }

    guard try Data(contentsOf: documentURL) == originalDocumentData else {
        throw CocoaError(.fileReadCorruptFile)
    }
    if let originalConfigData {
        guard fileManager.fileExists(atPath: configURL.path),
              try Data(contentsOf: configURL) == originalConfigData else {
            throw CocoaError(.fileReadCorruptFile)
        }
    } else if fileManager.fileExists(atPath: configURL.path) {
        throw CocoaError(.fileWriteUnknown)
    }
}
