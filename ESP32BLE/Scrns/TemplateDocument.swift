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

struct TemplateCreationResult {
    let templateURL: URL
    let configurationURL: URL
    let templateFileName: String
}

enum TemplateCreationError: LocalizedError {
    case invalidSourceURL(URL)
    case sourceNameMismatch(expected: String, actual: String)
    case sourceSelectionChanged(expected: String, actual: String)
    case sourceNotFound(URL)
    case sourceIsNotRegularFile(URL)
    case unreadableSource(URL, Error)
    case invalidSourceUTF8(URL)
    case missingSourceConfiguration(URL)
    case unreadableSourceConfiguration(URL, Error)
    case emptySourceConfiguration(URL)
    case invalidSourceConfiguration(URL, Error)
    case invalidButtonCount(Int, maximum: Int)
    case invalidGrid(rows: Int, columns: Int, buttonCount: Int, maximum: Int)
    case emptyTemplateName
    case invalidTemplateName(String)
    case templateNameTooLong(String)
    case destinationOutsideDocuments(URL)
    case destinationDirectoryUnreadable(URL, Error)
    case destinationCollision(String)
    case preparationFailed(URL, Error)
    case sourceChangedDuringPreparation(URL)
    case publicationFailedAndCleanedUp(Error)
    case cleanupFailed(creationError: Error, cleanupError: Error)

    var errorDescription: String? {
        switch self {
        case .invalidSourceURL(let url):
            return "\(url.lastPathComponent) is not a screen document."
        case .sourceNameMismatch(let expected, let actual):
            return "The source screen changed from \(expected) to \(actual)."
        case .sourceSelectionChanged(let expected, let actual):
            return "The selected screen changed from \(expected) to \(actual)."
        case .sourceNotFound(let url):
            return "The source screen \(url.lastPathComponent) does not exist."
        case .sourceIsNotRegularFile(let url):
            return "The source screen \(url.lastPathComponent) is not a regular file."
        case .unreadableSource(let url, let error):
            return "The source screen \(url.lastPathComponent) could not be read: \(error.localizedDescription)"
        case .invalidSourceUTF8(let url):
            return "The source screen \(url.lastPathComponent) is not valid UTF-8."
        case .missingSourceConfiguration(let url):
            return "The source configuration \(url.lastPathComponent) does not exist."
        case .unreadableSourceConfiguration(let url, let error):
            return "The source configuration \(url.lastPathComponent) could not be read: \(error.localizedDescription)"
        case .emptySourceConfiguration(let url):
            return "The source configuration \(url.lastPathComponent) is empty."
        case .invalidSourceConfiguration(let url, let error):
            return "The source configuration \(url.lastPathComponent) is invalid: \(error.localizedDescription)"
        case .invalidButtonCount(let count, let maximum):
            return "The source screen contains \(count) button lines, but the supported maximum is \(maximum)."
        case .invalidGrid(let rows, let columns, let buttonCount, let maximum):
            return "The source grid \(rows)x\(columns) is not compatible with \(buttonCount) button lines and the supported maximum of \(maximum)."
        case .emptyTemplateName:
            return "The template name cannot be blank."
        case .invalidTemplateName(let name):
            return "\(name) is not a valid template filename."
        case .templateNameTooLong(let name):
            return "The template filename \(name) is too long."
        case .destinationOutsideDocuments(let url):
            return "The template destination \(url.lastPathComponent) is outside the Documents directory."
        case .destinationDirectoryUnreadable(let url, let error):
            return "The destination directory \(url.lastPathComponent) could not be read: \(error.localizedDescription)"
        case .destinationCollision(let fileName):
            return "A template file named \(fileName) already exists."
        case .preparationFailed(let url, let error):
            return "The template file \(url.lastPathComponent) could not be prepared: \(error.localizedDescription)"
        case .sourceChangedDuringPreparation(let url):
            return "The source file \(url.lastPathComponent) changed while the template was being prepared."
        case .publicationFailedAndCleanedUp(let error):
            return "The template could not be created and the incomplete files were removed: \(error.localizedDescription)"
        case .cleanupFailed(let creationError, let cleanupError):
            return "The template could not be created and its incomplete files could not be fully removed. Creation error: \(creationError.localizedDescription) Cleanup error: \(cleanupError.localizedDescription)"
        }
    }
}

func normalizedTemplateDocumentFileName(from requestedName: String) throws -> String {
    let trimmedName = requestedName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty else {
        throw TemplateCreationError.emptyTemplateName
    }
    guard trimmedName != ".",
          trimmedName != "..",
          !trimmedName.hasPrefix("."),
          !trimmedName.contains("/"),
          !trimmedName.contains("\\"),
          !trimmedName.contains(":"),
          !trimmedName.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
        throw TemplateCreationError.invalidTemplateName(trimmedName)
    }

    let templateSuffix = ".\(templateDocumentFileExtension)"
    let baseName: String
    if trimmedName.lowercased().hasSuffix(templateSuffix) {
        baseName = String(trimmedName.dropLast(templateSuffix.count))
    } else {
        baseName = trimmedName
    }
    guard !baseName.isEmpty,
          baseName != ".",
          baseName != "..",
          !baseName.hasPrefix(".") else {
        throw TemplateCreationError.invalidTemplateName(trimmedName)
    }

    let fileName = "\(baseName)\(templateSuffix)"
    let configurationFileName = templateConfigFileName(forTemplateDocumentName: fileName)
    let maximumFileNameByteCount = 255
    guard fileName.lengthOfBytes(using: .utf8) <= maximumFileNameByteCount,
          configurationFileName.lengthOfBytes(using: .utf8) <= maximumFileNameByteCount else {
        throw TemplateCreationError.templateNameTooLong(fileName)
    }
    return fileName
}

func createTemplateDocument(
    from sourceDocumentURL: URL,
    expectedSourceDocumentName: String,
    requestedTemplateName: String,
    description: String?,
    selectedSourceDocumentName: () -> String,
    maximumButtonCount: Int,
    effectiveButtonLineCount: (String) -> Int,
    fileManager: FileManager = .default
) throws -> TemplateCreationResult {
    guard isScreenDocumentURL(sourceDocumentURL) else {
        throw TemplateCreationError.invalidSourceURL(sourceDocumentURL)
    }
    guard sourceDocumentURL.lastPathComponent == expectedSourceDocumentName else {
        throw TemplateCreationError.sourceNameMismatch(
            expected: expectedSourceDocumentName,
            actual: sourceDocumentURL.lastPathComponent
        )
    }
    let initiallySelectedName = selectedSourceDocumentName()
    guard initiallySelectedName == expectedSourceDocumentName else {
        throw TemplateCreationError.sourceSelectionChanged(
            expected: expectedSourceDocumentName,
            actual: initiallySelectedName
        )
    }
    guard fileManager.fileExists(atPath: sourceDocumentURL.path) else {
        throw TemplateCreationError.sourceNotFound(sourceDocumentURL)
    }
    do {
        let values = try sourceDocumentURL.resourceValues(forKeys: [.isRegularFileKey])
        guard values.isRegularFile == true else {
            throw TemplateCreationError.sourceIsNotRegularFile(sourceDocumentURL)
        }
    } catch let error as TemplateCreationError {
        throw error
    } catch {
        throw TemplateCreationError.unreadableSource(sourceDocumentURL, error)
    }

    let sourceData: Data
    do {
        sourceData = try Data(contentsOf: sourceDocumentURL)
    } catch {
        throw TemplateCreationError.unreadableSource(sourceDocumentURL, error)
    }
    guard let sourceContents = String(data: sourceData, encoding: .utf8) else {
        throw TemplateCreationError.invalidSourceUTF8(sourceDocumentURL)
    }

    let buttonCount = effectiveButtonLineCount(sourceContents)
    guard maximumButtonCount > 0,
          buttonCount >= 0,
          buttonCount <= maximumButtonCount else {
        throw TemplateCreationError.invalidButtonCount(buttonCount, maximum: maximumButtonCount)
    }

    let sourceConfigurationURL = configURL(forDocumentURL: sourceDocumentURL)
    guard fileManager.fileExists(atPath: sourceConfigurationURL.path) else {
        throw TemplateCreationError.missingSourceConfiguration(sourceConfigurationURL)
    }
    let sourceConfigurationData: Data
    do {
        sourceConfigurationData = try Data(contentsOf: sourceConfigurationURL)
    } catch {
        throw TemplateCreationError.unreadableSourceConfiguration(sourceConfigurationURL, error)
    }
    guard !sourceConfigurationData.isEmpty else {
        throw TemplateCreationError.emptySourceConfiguration(sourceConfigurationURL)
    }

    let sourceConfiguration: ScreenConfig
    do {
        sourceConfiguration = try JSONDecoder().decode(ScreenConfig.self, from: sourceConfigurationData)
    } catch {
        throw TemplateCreationError.invalidSourceConfiguration(sourceConfigurationURL, error)
    }

    let grid = sourceConfiguration.grid
    let (gridCapacity, gridOverflow) = grid.rows.multipliedReportingOverflow(by: grid.columns)
    guard grid.rows > 0,
          grid.columns > 0,
          !gridOverflow,
          gridCapacity >= max(buttonCount, 1),
          gridCapacity <= maximumButtonCount else {
        throw TemplateCreationError.invalidGrid(
            rows: grid.rows,
            columns: grid.columns,
            buttonCount: buttonCount,
            maximum: maximumButtonCount
        )
    }

    let templateFileName = try normalizedTemplateDocumentFileName(from: requestedTemplateName)
    let destinationDirectoryURL = sourceDocumentURL.deletingLastPathComponent().standardizedFileURL
    let templateURL = destinationDirectoryURL.appendingPathComponent(templateFileName).standardizedFileURL
    let templateConfigurationURL = templateConfigURL(forTemplateDocumentURL: templateURL).standardizedFileURL
    guard templateURL.deletingLastPathComponent() == destinationDirectoryURL,
          templateConfigurationURL.deletingLastPathComponent() == destinationDirectoryURL else {
        throw TemplateCreationError.destinationOutsideDocuments(templateURL)
    }

    let trimmedDescription = description?.trimmingCharacters(in: .whitespacesAndNewlines)
    let templateConfiguration = TemplateConfiguration(
        screenConfig: sourceConfiguration,
        description: trimmedDescription?.isEmpty == false ? trimmedDescription : nil
    )
    let templateConfigurationData: Data
    do {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        templateConfigurationData = try encoder.encode(templateConfiguration)
    } catch {
        throw TemplateCreationError.invalidSourceConfiguration(sourceConfigurationURL, error)
    }

    try rejectTemplateCreationCollisions(
        in: destinationDirectoryURL,
        templateFileName: templateFileName,
        configurationFileName: templateConfigurationURL.lastPathComponent,
        fileManager: fileManager
    )

    let operationID = UUID().uuidString
    let preparedTemplateURL = destinationDirectoryURL.appendingPathComponent(".esp-template-create-\(operationID).template.tmp")
    let preparedConfigurationURL = destinationDirectoryURL.appendingPathComponent(".esp-template-create-\(operationID).config.tmp")
    var createdTemplate = false
    var createdConfiguration = false
    var publicationStarted = false

    do {
        do {
            try sourceData.write(to: preparedTemplateURL, options: [.atomic])
            try templateConfigurationData.write(to: preparedConfigurationURL, options: [.atomic])

            let preparedTemplateData = try Data(contentsOf: preparedTemplateURL)
            let preparedConfigurationData = try Data(contentsOf: preparedConfigurationURL)
            guard preparedTemplateData == sourceData,
                  String(data: preparedTemplateData, encoding: .utf8) != nil,
                  preparedConfigurationData == templateConfigurationData,
                  try JSONDecoder().decode(TemplateConfiguration.self, from: preparedConfigurationData) == templateConfiguration else {
                throw CocoaError(.fileReadCorruptFile)
            }
        } catch {
            throw TemplateCreationError.preparationFailed(destinationDirectoryURL, error)
        }

        let selectedNameBeforePublication = selectedSourceDocumentName()
        guard selectedNameBeforePublication == expectedSourceDocumentName else {
            throw TemplateCreationError.sourceSelectionChanged(
                expected: expectedSourceDocumentName,
                actual: selectedNameBeforePublication
            )
        }
        let currentSourceData: Data
        let currentSourceConfigurationData: Data
        do {
            currentSourceData = try Data(contentsOf: sourceDocumentURL)
            currentSourceConfigurationData = try Data(contentsOf: sourceConfigurationURL)
        } catch {
            throw TemplateCreationError.sourceChangedDuringPreparation(sourceDocumentURL)
        }
        guard currentSourceData == sourceData else {
            throw TemplateCreationError.sourceChangedDuringPreparation(sourceDocumentURL)
        }
        guard currentSourceConfigurationData == sourceConfigurationData else {
            throw TemplateCreationError.sourceChangedDuringPreparation(sourceConfigurationURL)
        }

        try rejectTemplateCreationCollisions(
            in: destinationDirectoryURL,
            templateFileName: templateFileName,
            configurationFileName: templateConfigurationURL.lastPathComponent,
            fileManager: fileManager
        )

        publicationStarted = true
        try fileManager.moveItem(at: preparedConfigurationURL, to: templateConfigurationURL)
        createdConfiguration = true
        try fileManager.moveItem(at: preparedTemplateURL, to: templateURL)
        createdTemplate = true

        let finalTemplateData = try Data(contentsOf: templateURL)
        let finalConfigurationData = try Data(contentsOf: templateConfigurationURL)
        guard finalTemplateData == sourceData,
              String(data: finalTemplateData, encoding: .utf8) != nil,
              finalConfigurationData == templateConfigurationData,
              try JSONDecoder().decode(TemplateConfiguration.self, from: finalConfigurationData) == templateConfiguration else {
            throw CocoaError(.fileReadCorruptFile)
        }
    } catch {
        let creationError = error
        do {
            try cleanupTemplateCreationFiles(
                preparedTemplateURL: preparedTemplateURL,
                preparedConfigurationURL: preparedConfigurationURL,
                createdTemplateURL: createdTemplate ? templateURL : nil,
                createdConfigurationURL: createdConfiguration ? templateConfigurationURL : nil,
                fileManager: fileManager
            )
        } catch {
            throw TemplateCreationError.cleanupFailed(
                creationError: creationError,
                cleanupError: error
            )
        }
        if publicationStarted {
            throw TemplateCreationError.publicationFailedAndCleanedUp(creationError)
        }
        throw creationError
    }

    return TemplateCreationResult(
        templateURL: templateURL,
        configurationURL: templateConfigurationURL,
        templateFileName: templateFileName
    )
}

private func templateCreationCollisionKey(_ fileName: String) -> String {
    fileName
        .precomposedStringWithCanonicalMapping
        .folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
}

private func rejectTemplateCreationCollisions(
    in directoryURL: URL,
    templateFileName: String,
    configurationFileName: String,
    fileManager: FileManager
) throws {
    let directoryURLs: [URL]
    do {
        directoryURLs = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: []
        )
    } catch {
        throw TemplateCreationError.destinationDirectoryUnreadable(directoryURL, error)
    }

    let existingKeys = Set(directoryURLs.map { templateCreationCollisionKey($0.lastPathComponent) })
    if existingKeys.contains(templateCreationCollisionKey(templateFileName)) {
        throw TemplateCreationError.destinationCollision(templateFileName)
    }
    if existingKeys.contains(templateCreationCollisionKey(configurationFileName)) {
        throw TemplateCreationError.destinationCollision(configurationFileName)
    }
}

private func cleanupTemplateCreationFiles(
    preparedTemplateURL: URL,
    preparedConfigurationURL: URL,
    createdTemplateURL: URL?,
    createdConfigurationURL: URL?,
    fileManager: FileManager
) throws {
    var firstCleanupError: Error?
    for fileURL in [
        createdTemplateURL,
        createdConfigurationURL,
        Optional(preparedTemplateURL),
        Optional(preparedConfigurationURL)
    ].compactMap({ $0 }) where fileManager.fileExists(atPath: fileURL.path) {
        do {
            try fileManager.removeItem(at: fileURL)
        } catch {
            if firstCleanupError == nil {
                firstCleanupError = error
            }
        }
    }
    if let firstCleanupError {
        throw firstCleanupError
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

struct TemplateRestoreResult {
    let templateURL: URL
    let configurationURL: URL
}

enum TemplateRestoreError: LocalizedError {
    case invalidTemplateFileName(String)
    case invalidDestinationDirectory(URL)
    case destinationIsNotRegularFile(URL)
    case destinationSnapshotFailed(URL, Error)
    case preparationFailed(URL, Error)
    case destinationChanged(URL)
    case publicationFailedAndRolledBack(Error)
    case rollbackFailed(publicationError: Error, rollbackError: Error)

    var errorDescription: String? {
        switch self {
        case .invalidTemplateFileName(let fileName):
            return "Invalid template filename in backup: \(fileName)."
        case .invalidDestinationDirectory(let url):
            return "The template restore destination \(url.path) is not available."
        case .destinationIsNotRegularFile(let url):
            return "The existing destination \(url.lastPathComponent) is not a regular file."
        case .destinationSnapshotFailed(let url, let error):
            return "The existing template pair could not be preserved at \(url.lastPathComponent): \(error.localizedDescription)"
        case .preparationFailed(let url, let error):
            return "The restored template pair could not be prepared at \(url.lastPathComponent): \(error.localizedDescription)"
        case .destinationChanged(let url):
            return "The template destination \(url.lastPathComponent) changed during restore preparation."
        case .publicationFailedAndRolledBack(let error):
            return "The template pair could not be restored. Its previous files were restored: \(error.localizedDescription)"
        case .rollbackFailed(let publicationError, let rollbackError):
            return "Critical template restore error. Publication failed (\(publicationError.localizedDescription)) and the previous pair could not be fully restored (\(rollbackError.localizedDescription))."
        }
    }
}

func templateFileNameCollisionKey(_ fileName: String) -> String {
    fileName
        .precomposedStringWithCanonicalMapping
        .folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
}

func restoreTemplateDocumentPair(
    templateFileName: String,
    templateData: Data,
    configurationData: Data?,
    to destinationDirectoryURL: URL,
    fileManager: FileManager = .default
) throws -> TemplateRestoreResult {
    let normalizedFileName: String
    do {
        normalizedFileName = try normalizedTemplateDocumentFileName(from: templateFileName)
    } catch {
        throw TemplateRestoreError.invalidTemplateFileName(templateFileName)
    }
    guard isTemplateDocumentFileName(templateFileName),
          templateFileNameCollisionKey(normalizedFileName) == templateFileNameCollisionKey(templateFileName) else {
        throw TemplateRestoreError.invalidTemplateFileName(templateFileName)
    }

    let normalizedDirectoryURL = destinationDirectoryURL.standardizedFileURL
    guard (try? normalizedDirectoryURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]).isDirectory) == true,
          (try? normalizedDirectoryURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else {
        throw TemplateRestoreError.invalidDestinationDirectory(normalizedDirectoryURL)
    }

    let templateURL = normalizedDirectoryURL
        .appendingPathComponent(templateFileName)
        .standardizedFileURL
    let configurationURL = templateConfigURL(forTemplateDocumentURL: templateURL).standardizedFileURL
    guard templateURL.deletingLastPathComponent() == normalizedDirectoryURL,
          configurationURL.deletingLastPathComponent() == normalizedDirectoryURL else {
        throw TemplateRestoreError.invalidDestinationDirectory(normalizedDirectoryURL)
    }

    let originalTemplateData = try snapshotTemplateRestoreDestination(
        at: templateURL,
        fileManager: fileManager
    )
    let originalConfigurationData = try snapshotTemplateRestoreDestination(
        at: configurationURL,
        fileManager: fileManager
    )

    let operationID = UUID().uuidString
    let preparedTemplateURL = normalizedDirectoryURL
        .appendingPathComponent(".template-restore-\(operationID).template.tmp")
    let preparedConfigurationURL = normalizedDirectoryURL
        .appendingPathComponent(".template-restore-\(operationID).config.tmp")
    defer {
        try? fileManager.removeItem(at: preparedTemplateURL)
        try? fileManager.removeItem(at: preparedConfigurationURL)
    }

    do {
        try templateData.write(to: preparedTemplateURL, options: [.atomic])
        guard try Data(contentsOf: preparedTemplateURL) == templateData else {
            throw CocoaError(.fileReadCorruptFile)
        }
        if let configurationData {
            try configurationData.write(to: preparedConfigurationURL, options: [.atomic])
            guard try Data(contentsOf: preparedConfigurationURL) == configurationData else {
                throw CocoaError(.fileReadCorruptFile)
            }
        }
    } catch {
        throw TemplateRestoreError.preparationFailed(normalizedDirectoryURL, error)
    }

    guard try templateRestoreDestinationMatchesSnapshot(
        at: templateURL,
        snapshot: originalTemplateData,
        fileManager: fileManager
    ) else {
        throw TemplateRestoreError.destinationChanged(templateURL)
    }
    guard try templateRestoreDestinationMatchesSnapshot(
        at: configurationURL,
        snapshot: originalConfigurationData,
        fileManager: fileManager
    ) else {
        throw TemplateRestoreError.destinationChanged(configurationURL)
    }

    do {
        if configurationData != nil {
            try replacePreparedTemplateFile(
                at: preparedConfigurationURL,
                destinationURL: configurationURL,
                fileManager: fileManager
            )
        } else if fileManager.fileExists(atPath: configurationURL.path) {
            try fileManager.removeItem(at: configurationURL)
        }

        try replacePreparedTemplateFile(
            at: preparedTemplateURL,
            destinationURL: templateURL,
            fileManager: fileManager
        )

        guard try Data(contentsOf: templateURL) == templateData else {
            throw CocoaError(.fileReadCorruptFile)
        }
        if let configurationData {
            guard fileManager.fileExists(atPath: configurationURL.path),
                  try Data(contentsOf: configurationURL) == configurationData else {
                throw CocoaError(.fileReadCorruptFile)
            }
        } else if fileManager.fileExists(atPath: configurationURL.path) {
            throw CocoaError(.fileWriteUnknown)
        }
    } catch {
        let publicationError = error
        do {
            try restoreTemplatePairSnapshot(
                templateURL: templateURL,
                templateData: originalTemplateData,
                configurationURL: configurationURL,
                configurationData: originalConfigurationData,
                fileManager: fileManager
            )
        } catch {
            throw TemplateRestoreError.rollbackFailed(
                publicationError: publicationError,
                rollbackError: error
            )
        }
        throw TemplateRestoreError.publicationFailedAndRolledBack(publicationError)
    }

    return TemplateRestoreResult(
        templateURL: templateURL,
        configurationURL: configurationURL
    )
}

private func snapshotTemplateRestoreDestination(
    at url: URL,
    fileManager: FileManager
) throws -> Data? {
    guard fileManager.fileExists(atPath: url.path) else { return nil }
    do {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw TemplateRestoreError.destinationIsNotRegularFile(url)
        }
        return try Data(contentsOf: url)
    } catch let error as TemplateRestoreError {
        throw error
    } catch {
        throw TemplateRestoreError.destinationSnapshotFailed(url, error)
    }
}

private func templateRestoreDestinationMatchesSnapshot(
    at url: URL,
    snapshot: Data?,
    fileManager: FileManager
) throws -> Bool {
    if let snapshot {
        guard fileManager.fileExists(atPath: url.path) else { return false }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { return false }
        return try Data(contentsOf: url) == snapshot
    }
    return !fileManager.fileExists(atPath: url.path)
}

private func restoreTemplatePairSnapshot(
    templateURL: URL,
    templateData: Data?,
    configurationURL: URL,
    configurationData: Data?,
    fileManager: FileManager
) throws {
    try restoreTemplateSnapshotFile(configurationData, at: configurationURL, fileManager: fileManager)
    try restoreTemplateSnapshotFile(templateData, at: templateURL, fileManager: fileManager)

    guard try templateRestoreDestinationMatchesSnapshot(
        at: templateURL,
        snapshot: templateData,
        fileManager: fileManager
    ), try templateRestoreDestinationMatchesSnapshot(
        at: configurationURL,
        snapshot: configurationData,
        fileManager: fileManager
    ) else {
        throw CocoaError(.fileWriteUnknown)
    }
}

private func restoreTemplateSnapshotFile(
    _ data: Data?,
    at url: URL,
    fileManager: FileManager
) throws {
    if let data {
        try data.write(to: url, options: [.atomic])
    } else if fileManager.fileExists(atPath: url.path) {
        try fileManager.removeItem(at: url)
    }
}


enum TemplateDeletionError: LocalizedError {
    case invalidTemplateURL(URL)
    case invalidParentDirectory(URL)
    case templateNotFound(URL)
    case templateIsNotRegularFile(URL)
    case configurationIsNotRegularFile(URL)
    case stagingPreparationFailed(URL, Error)
    case stagingFailedAndRolledBack(Error)
    case rollbackFailed(stagingError: Error, rollbackError: Error)
    case cleanupFailed(URL, Error)

    var errorDescription: String? {
        switch self {
        case .invalidTemplateURL(let url):
            return "\(url.lastPathComponent) is not a template document."
        case .invalidParentDirectory(let url):
            return "The template folder \(url.path) is not available."
        case .templateNotFound(let url):
            return "The template \(url.lastPathComponent) does not exist."
        case .templateIsNotRegularFile(let url):
            return "The template \(url.lastPathComponent) is not a regular file."
        case .configurationIsNotRegularFile(let url):
            return "The template configuration \(url.lastPathComponent) is not a regular file."
        case .stagingPreparationFailed(let url, let error):
            return "Template deletion could not be prepared in \(url.lastPathComponent): \(error.localizedDescription)"
        case .stagingFailedAndRolledBack(let error):
            return "The template could not be deleted. Its files were restored: \(error.localizedDescription)"
        case .rollbackFailed(let stagingError, let rollbackError):
            return "Critical template deletion error. Staging failed (\(stagingError.localizedDescription)) and the original files could not be fully restored (\(rollbackError.localizedDescription))."
        case .cleanupFailed(let url, let error):
            return "The template was staged for deletion, but cleanup of \(url.lastPathComponent) failed: \(error.localizedDescription)"
        }
    }
}

func deleteTemplateDocument(
    at templateURL: URL,
    fileManager: FileManager = .default
) throws {
    guard isTemplateDocumentURL(templateURL) else {
        throw TemplateDeletionError.invalidTemplateURL(templateURL)
    }

    let normalizedTemplateURL = templateURL.standardizedFileURL
    let parentDirectoryURL = normalizedTemplateURL.deletingLastPathComponent()
    let expectedTemplateURL = parentDirectoryURL
        .appendingPathComponent(normalizedTemplateURL.lastPathComponent)
        .standardizedFileURL
    guard expectedTemplateURL == normalizedTemplateURL,
          (try? parentDirectoryURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
        throw TemplateDeletionError.invalidParentDirectory(parentDirectoryURL)
    }

    guard fileManager.fileExists(atPath: normalizedTemplateURL.path) else {
        throw TemplateDeletionError.templateNotFound(normalizedTemplateURL)
    }
    guard (try? normalizedTemplateURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
        throw TemplateDeletionError.templateIsNotRegularFile(normalizedTemplateURL)
    }

    let configurationURL = templateConfigURL(forTemplateDocumentURL: normalizedTemplateURL)
    let configurationExists = fileManager.fileExists(atPath: configurationURL.path)
    if configurationExists,
       (try? configurationURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) != true {
        throw TemplateDeletionError.configurationIsNotRegularFile(configurationURL)
    }

    let stagingDirectoryURL = parentDirectoryURL
        .appendingPathComponent(".template-deletion-\(UUID().uuidString)", isDirectory: true)
    do {
        try fileManager.createDirectory(
            at: stagingDirectoryURL,
            withIntermediateDirectories: false
        )
    } catch {
        throw TemplateDeletionError.stagingPreparationFailed(stagingDirectoryURL, error)
    }

    let stagedTemplateURL = stagingDirectoryURL
        .appendingPathComponent(normalizedTemplateURL.lastPathComponent)
    let stagedConfigurationURL = stagingDirectoryURL
        .appendingPathComponent(configurationURL.lastPathComponent)
    var templateWasStaged = false

    do {
        try fileManager.moveItem(at: normalizedTemplateURL, to: stagedTemplateURL)
        templateWasStaged = true

        if configurationExists {
            try fileManager.moveItem(at: configurationURL, to: stagedConfigurationURL)
        }
    } catch {
        let stagingError = error
        do {
            if templateWasStaged {
                guard !fileManager.fileExists(atPath: normalizedTemplateURL.path) else {
                    throw CocoaError(.fileWriteFileExists)
                }
                try fileManager.moveItem(at: stagedTemplateURL, to: normalizedTemplateURL)
            }
            if fileManager.fileExists(atPath: stagingDirectoryURL.path) {
                try fileManager.removeItem(at: stagingDirectoryURL)
            }
        } catch {
            throw TemplateDeletionError.rollbackFailed(
                stagingError: stagingError,
                rollbackError: error
            )
        }
        throw TemplateDeletionError.stagingFailedAndRolledBack(stagingError)
    }

    do {
        try fileManager.removeItem(at: stagingDirectoryURL)
    } catch {
        throw TemplateDeletionError.cleanupFailed(stagingDirectoryURL, error)
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
