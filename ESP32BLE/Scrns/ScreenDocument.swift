import Foundation

let screenDocumentFileExtension = "screen"
let legacyScreenDocumentFileExtension = "txt"

func isScreenDocumentURL(_ url: URL) -> Bool {
    isScreenDocumentFileExtension(url.pathExtension)
}

func isScreenDocumentFileName(_ fileName: String) -> Bool {
    isScreenDocumentFileExtension(URL(fileURLWithPath: fileName).pathExtension)
}

func isScreenDocumentFileExtension(_ fileExtension: String) -> Bool {
    let normalizedExtension = fileExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return normalizedExtension == screenDocumentFileExtension
}

func screenDocumentFileName(forBaseName baseName: String) -> String {
    let trimmedBaseName = baseName.trimmingCharacters(in: .whitespacesAndNewlines)
    let resolvedBaseName = trimmedBaseName.isEmpty ? "Screen" : trimmedBaseName
    return "\(resolvedBaseName).\(screenDocumentFileExtension)"
}

func screenDocumentBaseKey(for fileName: String) -> String {
    URL(fileURLWithPath: fileName)
        .deletingPathExtension()
        .lastPathComponent
        .lowercased()
}

func naturalFileURLAscending(_ lhs: URL, _ rhs: URL) -> Bool {
    let lhsBaseName = lhs.deletingPathExtension().lastPathComponent
    let rhsBaseName = rhs.deletingPathExtension().lastPathComponent
    let comparisonOptions: String.CompareOptions = [.caseInsensitive, .numeric]

    let baseNameComparison = lhsBaseName.compare(
        rhsBaseName,
        options: comparisonOptions,
        range: nil,
        locale: .current
    )
    if baseNameComparison != .orderedSame {
        return baseNameComparison == .orderedAscending
    }

    let fullNameComparison = lhs.lastPathComponent.compare(
        rhs.lastPathComponent,
        options: comparisonOptions,
        range: nil,
        locale: .current
    )
    if fullNameComparison != .orderedSame {
        return fullNameComparison == .orderedAscending
    }

    let literalNameComparison = lhs.lastPathComponent.compare(
        rhs.lastPathComponent,
        options: .literal
    )
    if literalNameComparison != .orderedSame {
        return literalNameComparison == .orderedAscending
    }

    return lhs.path.compare(rhs.path, options: .literal) == .orderedAscending
}

func legacyNaturalFileURLAscending(_ lhs: URL, _ rhs: URL) -> Bool {
    let nameComparison = lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent)
    if nameComparison != .orderedSame {
        return nameComparison == .orderedAscending
    }

    let literalNameComparison = lhs.lastPathComponent.compare(
        rhs.lastPathComponent,
        options: .literal
    )
    if literalNameComparison != .orderedSame {
        return literalNameComparison == .orderedAscending
    }

    return lhs.path.compare(rhs.path, options: .literal) == .orderedAscending
}

func preferredScreenDocumentURLs(from urls: [URL]) -> [URL] {
    urls
        .filter(isScreenDocumentURL)
        .sorted(by: naturalFileURLAscending)
}
