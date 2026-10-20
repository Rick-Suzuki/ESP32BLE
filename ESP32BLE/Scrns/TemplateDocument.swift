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
