import Foundation

struct SpeechSubstitutionRule {
    let sourceTokens: [String]
    let replacementTokens: [String]
}

enum SpeechSubstitutions {
    static let fileName = "SpeechSubstitutions.txt"

    static let defaultContents = """
    // Speech Recognition Substitutions
    // put your recognized word on the left
    // and your substitute word on the right
    // separated by tabs
    //
    // recognized word\tsubstitute word

    up\t\t\tapp
    get her\t\t\tgithub
    middy\t\t\tmidi
    you tube\t\tyoutube
    """

    static func ensureFileExists() {
        guard let documentsURL = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else {
            print("🐞 Speech substitutions Documents directory unavailable")
            return
        }

        let fileURL = documentsURL.appendingPathComponent(fileName)
        let fileManager = FileManager.default

        guard !fileManager.fileExists(atPath: fileURL.path) else {
            return
        }

        do {
            try defaultContents.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            print("🐞 Speech substitutions file creation failed: \(error.localizedDescription)")
        }
    }

    static func load(normalize: (String) -> String) -> [SpeechSubstitutionRule] {
        guard let documentsURL = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else {
            return []
        }

        let fileURL = documentsURL.appendingPathComponent(fileName)
        let fileManager = FileManager.default

        if !fileManager.fileExists(atPath: fileURL.path) {
            do {
                try defaultContents.write(to: fileURL, atomically: true, encoding: .utf8)
            } catch {
                return []
            }
        }

        guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return []
        }

        var rules: [SpeechSubstitutionRule] = []
        var sourceKeys: Set<String> = []

        for line in contents.components(separatedBy: .newlines) {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLine.isEmpty, !trimmedLine.hasPrefix("//") else {
                continue
            }

            let tabSeparatedLine = line.trimmingCharacters(in: CharacterSet(charactersIn: "\t"))
            let fields = tabSeparatedLine
                .split(separator: "\t", omittingEmptySubsequences: true)
                .map(String.init)
            guard fields.count == 2 else {
                continue
            }

            let sourceText = fields[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let replacementText = fields[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sourceText.isEmpty, !replacementText.isEmpty else {
                continue
            }

            let sourceTokens = normalize(sourceText)
                .split(whereSeparator: \.isWhitespace)
                .map(String.init)
            let replacementTokens = normalize(replacementText)
                .split(whereSeparator: \.isWhitespace)
                .map(String.init)
            guard !sourceTokens.isEmpty, !replacementTokens.isEmpty else {
                continue
            }

            let sourceKey = sourceTokens.joined(separator: " ")
            guard sourceKeys.insert(sourceKey).inserted else {
                continue
            }

            rules.append(
                SpeechSubstitutionRule(
                    sourceTokens: sourceTokens,
                    replacementTokens: replacementTokens
                )
            )
        }

        return rules
    }

    static func replacing(
        in text: String,
        rules: [SpeechSubstitutionRule],
        normalize: (String) -> String
    ) -> String? {
        guard !rules.isEmpty else {
            return nil
        }

        let inputTokens = normalize(text)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard !inputTokens.isEmpty else {
            return nil
        }

        let orderedRules = rules.enumerated().sorted { left, right in
            if left.element.sourceTokens.count != right.element.sourceTokens.count {
                return left.element.sourceTokens.count > right.element.sourceTokens.count
            }

            return left.offset < right.offset
        }

        var outputTokens: [String] = []
        outputTokens.reserveCapacity(inputTokens.count)
        var inputIndex = 0
        var didReplace = false

        while inputIndex < inputTokens.count {
            var matchedRule: SpeechSubstitutionRule?

            for (_, rule) in orderedRules {
                let endIndex = inputIndex + rule.sourceTokens.count
                guard endIndex <= inputTokens.count else {
                    continue
                }

                if Array(inputTokens[inputIndex..<endIndex]).elementsEqual(rule.sourceTokens) {
                    matchedRule = rule
                    break
                }
            }

            if let matchedRule {
                outputTokens.append(contentsOf: matchedRule.replacementTokens)
                inputIndex += matchedRule.sourceTokens.count
                didReplace = true
            } else {
                outputTokens.append(inputTokens[inputIndex])
                inputIndex += 1
            }
        }

        guard didReplace else {
            return nil
        }

        return outputTokens.joined(separator: " ")
    }
}
