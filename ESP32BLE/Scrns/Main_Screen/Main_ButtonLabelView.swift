import SwiftUI
import UIKit
import AVFoundation
import Combine
import ImageIO

extension Notification.Name {
    static let mainButtonImageFilesDidRefresh = Notification.Name("mainButtonImageFilesDidRefresh")
}

private nonisolated func mainButtonImage(at url: URL, pixelSize: CGSize) -> UIImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
          let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else { return nil }
    let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
    let swapsAxes = (5...8).contains(orientation)
    let sourceWidth = CGFloat(swapsAxes ? height.doubleValue : width.doubleValue)
    let sourceHeight = CGFloat(swapsAxes ? width.doubleValue : height.doubleValue)
    guard sourceWidth > 0, sourceHeight > 0 else { return nil }
    let scale = min(1, max(pixelSize.width / sourceWidth, pixelSize.height / sourceHeight))
    return downsampledUIImage(at: url, maxPixelDimension: max(sourceWidth, sourceHeight) * scale)
}

enum MainGridWidgetHeaderContent {
    case symbol(name: String, subtitle: String?)
    case emoji(emoji: String, subtitle: String?)
    case text(String)
    case command(String)
    case commandWithSymbol(command: String, name: String, subtitle: String?)
    case commandWithEmoji(command: String, emoji: String, subtitle: String?)
    case commandWithText(command: String, text: String)
    case none
}

struct MainScreenButtonLabelView: View {
    // Easy-to-tune size for buttons that display only a single emoji.
    private let loneEmojiScaleMultiplier: CGFloat = 1.5
    // MARK: - BM:🅱️ Horizontal foreground padding per side, proportional to the actual grid button width.
    private let mainButtonHorizontalContentPaddingRatio: CGFloat = 0.05
    let entry: FunctionKeyEntry
    let index: Int
    let widgetID: String
    let title: String
    let leftTitle: String
    let rightTitle: String
    let imageFilename: String
    let resolveImageURL: (String) -> URL?
    let isMainScreenVisible: Bool
    @Environment(\.displayScale) private var displayScale
    @Environment(\.scenePhase) private var scenePhase
    @State private var buttonImage: UIImage?
    @State private var loadedImageRequest = ""
    @State private var imageRefreshRevision = 0

    private var imageRequest: String {
        "\(imageFilename)|\(buttonSize.width)|\(buttonSize.height)|\(displayScale)|\(imageRefreshRevision)|\(isMainScreenVisible)|\(scenePhase)|\(displayMode)|\(widgetDescriptor != nil)"
    }

    private var displayedImage: UIImage? {
        loadedImageRequest == imageRequest ? buttonImage : nil
    }
    let displayMode: FunctionKeyDisplayMode
    let widgetDescriptor: MainGridWidgetDescriptor?
    let widgetHeaderContent: MainGridWidgetHeaderContent
    let rightSymbolDisplay: (name: String, subtitle: String?)?
    let rightEmojiDisplay: (emoji: String, subtitle: String?)?
    let automaticMIDILabel: MainGridAutomaticMIDILabel?
    let boxFontSize: Double
    let buttonHeight: CGFloat
    let buttonSize: CGSize
    let cornerRadius: CGFloat
    let borderWidth: CGFloat
    let usesInsetBorder: Bool
    let isGridEditModeEnabled: Bool
    let activeDragIndex: Int?
    let backgroundOpacity: Double
    @ObservedObject var sharedTimer: MainGridSharedTimerState
    @ObservedObject var ambientSoundState: MainGridAmbientSoundState
    let playSoundNamed: (String) -> Void
    let playLoopingSoundNamed: (String) -> Void
    let stopSoundPlayback: () -> Void
    let sendTimerCompletionAction: (FunctionKeyEntry) -> Bool
    let resolveSoundURL: (String) -> URL?
    let activateAudioSession: () async -> Bool
    let reportSoundError: (String, String) -> Void
    let shouldSpeakWidgetSelections: Bool
    let speakText: (String) -> Void

    // Adjust emojiScaleMultiplier to tune how much larger emoji should render than text.
    private let emojiScaleMultiplier: CGFloat = 1.5

    private var horizontalPadding: CGFloat {
        max(8, buttonSize.width * mainButtonHorizontalContentPaddingRatio)
    }

    private func isHexColorPrefix(_ text: String) -> Bool {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedText.count == 6 else {
            return false
        }

        let hexDigits = "0123456789abcdefABCDEF"
        return trimmedText.allSatisfy { hexDigits.contains($0) }
    }

    var body: some View {
        Group {
            if entry.isBlankPlaceholder || isEmptyButtonEntry {
                Group {
                    if isGridEditModeEnabled {
                        emptyButtonBorder
                    } else {
                        Color.clear
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isHiddenMainGridEntry {
                Rectangle()
                    .fill(Color.white.opacity(0.001))
                    .contentShape(Rectangle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ZStack {
					Rectangle()
						.fill(Color.white.opacity(0.001))
						.frame(width: buttonSize.width, height: buttonSize.height)

                    buttonVisualShell
                        .frame(width: buttonSize.width, height: buttonSize.height)

                    buttonContent
                        .padding(.vertical, 8)
                        .padding(.horizontal, horizontalPadding)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: imageRequest) {
            let request = imageRequest
            buttonImage = nil
            loadedImageRequest = ""
            let supportedExtensions = Set(["png", "jpg", "jpeg", "heic", "heif", "gif", "bmp", "tif", "tiff", "webp"])
            guard isMainScreenVisible, scenePhase == .active,
                  widgetDescriptor == nil, displayMode != .left,
                  !imageFilename.contains("/"),
                  !imageFilename.contains("\\"),
                  imageFilename.rangeOfCharacter(from: .newlines) == nil,
                  supportedExtensions.contains((imageFilename as NSString).pathExtension.lowercased()),
                  let url = resolveImageURL(imageFilename),
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { return }
            let pixelSize = CGSize(width: buttonSize.width * displayScale, height: buttonSize.height * displayScale)
            let image = await Task.detached(priority: .utility) {
                mainButtonImage(at: url, pixelSize: pixelSize)
            }.value
            guard !Task.isCancelled, request == imageRequest else { return }
            buttonImage = image
            loadedImageRequest = request
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: .mainButtonImageFilesDidRefresh) {
                guard !Task.isCancelled else { return }
                imageRefreshRevision &+= 1
            }
        }
    }

    private var buttonVisualShell: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(buttonBackgroundColor)

            if let image = displayedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: buttonSize.width, height: buttonSize.height)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                    .allowsHitTesting(false)
            }

            if usesInsetBorder {
                normalButtonBorder
            } else {
                normalButtonBorder
                    .padding(borderWidth / 2)
            }
        }
    }

    @ViewBuilder
    private var emptyButtonBorder: some View {
        if usesInsetBorder {
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(Color.white.opacity(0.5), lineWidth: borderWidth)
        } else {
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(Color.white.opacity(0.5), lineWidth: borderWidth)
        }
    }

    @ViewBuilder
    private var normalButtonBorder: some View {
        if usesInsetBorder {
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(borderColor, lineWidth: borderWidth)
        } else {
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(borderColor, lineWidth: borderWidth)
        }
    }

    private var isHiddenMainGridEntry: Bool {
        !isGridEditModeEnabled && entry.isHiddenInNormalMode
    }

    @ViewBuilder
    private var buttonContent: some View {
        if let widgetDescriptor {
            if displayMode == .left && usesCorrectedWidgetDisplayModes(widgetDescriptor) {
                textLabel(title: leftTitle)
            } else {
                widgetContent(descriptor: widgetDescriptor)
            }
        } else if displayedImage != nil {
            if displayMode == .both {
                textLabel(title: leftTitle)
            }
        } else if let rightSymbolDisplay {
            switch displayMode {
            case .left:
                textLabel(title: leftTitle)
            case .right:
                symbolContent(name: rightSymbolDisplay.name, subtitle: rightSymbolDisplay.subtitle)
            case .last:
                textLabel(title: lastRightTitleComponent)
            case .both:
                VStack(spacing: 6) {
                    textLabel(title: leftTitle)
                    symbolContent(name: rightSymbolDisplay.name, subtitle: rightSymbolDisplay.subtitle)
                }
            }
        } else if let rightEmojiDisplay {
            switch displayMode {
            case .left:
                textLabel(title: leftTitle)
            case .right:
                emojiContent(emoji: rightEmojiDisplay.emoji, subtitle: rightEmojiDisplay.subtitle)
            case .last:
                textLabel(title: lastRightTitleComponent)
            case .both:
                VStack(spacing: 6) {
                    textLabel(title: leftTitle)
                    emojiContent(emoji: rightEmojiDisplay.emoji, subtitle: rightEmojiDisplay.subtitle)
                }
            }
        } else if let automaticMIDILabel {
            switch displayMode {
            case .left:
                textLabel(title: leftTitle)
            case .right, .last:
                automaticMIDILabelContent(automaticMIDILabel)
            case .both:
                VStack(spacing: midiLabelGroupSpacing) {
                    textLabel(title: leftTitle)
                    automaticMIDILabelContent(automaticMIDILabel)
                }
            }
        } else {
            textLabel(title: title)
        }
    }

    private func usesCorrectedWidgetDisplayModes(_ descriptor: MainGridWidgetDescriptor) -> Bool {
        switch descriptor {
        case .clock, .day, .month, .year, .second, .minute, .hour, .dow, .date,
             .power, .add, .minus, .random, .textFileRandom, .stopwatch, .timer:
            return true
        case .ambientSound:
            return false
        }
    }
	//
	//-----------------------------------------------------------------------------------------------
	// MARK: - BM:😎 FUNCS widgetContent
	//
    @ViewBuilder
    private func widgetContent(descriptor: MainGridWidgetDescriptor) -> some View {
        switch descriptor {
        case .clock(let cityLabel):
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(spacing: 4) {
                    renderWidgetHeader()

                    Text(clockText(for: context.date, cityLabel: cityLabel))
                        .font(.system(size: boxFontSize, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.5)
                }
                .foregroundStyle(buttonTextColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .date(let cityLabel):
            TimelineView(.periodic(from: .now, by: 60)) { context in
                VStack(spacing: 4) {
                    renderWidgetHeader()

                    Text(dateValueText(for: context.date, cityLabel: cityLabel))
                        .font(.system(size: boxFontSize, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.5)
                }
                .foregroundStyle(buttonTextColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .day(let cityLabel):
            TimelineView(.periodic(from: .now, by: 60)) { context in
                VStack(spacing: 4) {
                    renderWidgetHeader()

                    Text(dayOfMonthOrdinalText(for: context.date, cityLabel: cityLabel))
                        .font(.system(size: boxFontSize, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.5)
                }
                .foregroundStyle(buttonTextColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .month(let cityLabel):
            TimelineView(.periodic(from: .now, by: 60)) { context in
                VStack(spacing: 4) {
                    renderWidgetHeader()

                    Text(monthNameText(for: context.date, cityLabel: cityLabel))
                        .font(.system(size: boxFontSize, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.5)
                }
                .foregroundStyle(buttonTextColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .year(let cityLabel):
            TimelineView(.periodic(from: .now, by: 60)) { context in
                VStack(spacing: 4) {
                    renderWidgetHeader()

                    Text(yearText(for: context.date, cityLabel: cityLabel))
                        .font(.system(size: boxFontSize, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.5)
                }
                .foregroundStyle(buttonTextColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .second(let cityLabel):
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(spacing: 4) {
                    renderWidgetHeader()

                    Text(widgetTimeComponentText(for: context.date, cityLabel: cityLabel, format: "ss"))
                        .font(.system(size: boxFontSize, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.5)
                }
                .foregroundStyle(buttonTextColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .minute(let cityLabel):
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(spacing: 4) {
                    renderWidgetHeader()

                    Text(widgetTimeComponentText(for: context.date, cityLabel: cityLabel, format: "mm"))
                        .font(.system(size: boxFontSize, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.5)
                }
                .foregroundStyle(buttonTextColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .hour(let cityLabel):
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(spacing: 4) {
                    renderWidgetHeader()

                    Text(widgetTimeComponentText(for: context.date, cityLabel: cityLabel, format: "HH"))
                        .font(.system(size: boxFontSize, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.5)
                }
                .foregroundStyle(buttonTextColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .dow(let cityLabel):
            TimelineView(.periodic(from: .now, by: 60)) { context in
                VStack(spacing: 4) {
                    renderWidgetHeader()

                    Text(dateFullWeekdayText(for: context.date, cityLabel: cityLabel))
                        .font(.system(size: boxFontSize, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.5)
                }
                .foregroundStyle(buttonTextColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .power:
            VStack(spacing: 4) {
                renderWidgetHeader()
                MainGridBatteryWidgetView(
                    fontSize: boxFontSize,
                    foregroundColor: buttonTextColor
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .add:
            VStack(spacing: 4) {
                renderWidgetHeader()
                MainGridStepUpCounterWidgetView(
                    configurationText: rightTitleWithoutColorPrefix,
                    showsTitle: false,
                    fontSize: boxFontSize,
                    foregroundColor: buttonTextColor,
                    interactionSize: buttonSize
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .minus(let initialCount):
            VStack(spacing: 4) {
                renderWidgetHeader()
                MainGridStepDownCounterWidgetView(
                    title: rightTitleWithoutColorPrefix,
                    showsTitle: false,
                    initialCount: initialCount,
                    fontSize: boxFontSize,
                    foregroundColor: buttonTextColor,
                    interactionSize: buttonSize
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .random(let minimumValue, let maximumValue):
            VStack(spacing: 4) {
                renderWidgetHeader()
                MainGridRandomNumberWidgetView(
                    title: rightTitleWithoutColorPrefix,
                    showsTitle: false,
                    minimumValue: minimumValue,
                    maximumValue: maximumValue,
                    fontSize: boxFontSize,
                    foregroundColor: buttonTextColor,
                    interactionSize: buttonSize
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .textFileRandom(let filename):
            VStack(spacing: 4) {
                renderWidgetHeader()
                MainGridRandomTextWidgetView(
                    title: rightTitleWithoutColorPrefix,
                    showsInitialTitle: false,
                    filename: filename,
                    fontSize: boxFontSize,
                    foregroundColor: buttonTextColor,
                    interactionSize: buttonSize,
                    onSelectionCommitted: shouldSpeakWidgetSelections ? { selectedText in
                        speakText(selectedText)
                    } : nil,
                    onRepeatRequested: shouldSpeakWidgetSelections ? { selectedText in
                        speakText(selectedText)
                    } : nil
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .stopwatch:
            VStack(spacing: 4) {
                renderWidgetHeader()
                MainGridStopwatchWidgetView(
                    title: rightTitleWithoutColorPrefix,
                    showsTitle: false,
                    fontSize: boxFontSize,
                    foregroundColor: buttonTextColor,
                    isInteractionEnabled: !isGridEditModeEnabled,
                    interactionSize: buttonSize
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ambientSound(let filename, let volume):
            ZStack {
                renderWidgetHeader(plainTextLineLimit: 4)
                MainGridAmbientSoundWidgetView(
                    widgetID: widgetID,
                    title: rightTitleWithoutColorPrefix,
                    showsTitle: false,
                    filename: filename,
                    volume: volume,
                    fontSize: boxFontSize,
                    foregroundColor: buttonTextColor,
                    isInteractionEnabled: !isGridEditModeEnabled,
                    interactionSize: buttonSize,
                    sharedState: ambientSoundState,
                    resolveSoundURL: resolveSoundURL,
                    activateAudioSession: activateAudioSession,
                    reportSoundError: reportSoundError
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .timer(let initialDuration, let completion):
            VStack(spacing: 4) {
                renderWidgetHeader()
                MainGridTimerWidgetView(
                    widgetID: widgetID,
                    entry: entry,
                    configurationText: rightTitleWithoutColorPrefix,
                    showsTitle: false,
                    initialDuration: initialDuration,
                    completion: completion,
                    sharedTimer: sharedTimer,
                    fontSize: boxFontSize,
                    foregroundColor: buttonTextColor,
                    interactionSize: buttonSize,
                    onTimerCompletionAction: sendTimerCompletionAction,
                    onPlayCompletionSound: playLoopingSoundNamed,
                    onStopCompletionSound: stopSoundPlayback,
                    onSpeakCompletionText: speakText
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func legacyWidgetHeaderContent(fallbackTitle: String) -> some View {
        if let rightSymbolDisplay {
            symbolContent(name: rightSymbolDisplay.name, subtitle: rightSymbolDisplay.subtitle)
        } else {
            Text(fallbackTitle)
                .font(.system(size: boxFontSize, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.4)
        }
    }

    @ViewBuilder
    private func renderWidgetHeader(plainTextLineLimit: Int = 1) -> some View {
        switch widgetHeaderContent {
        case .symbol(let name, let subtitle):
            symbolContent(name: name, subtitle: subtitle)
        case .emoji(let emoji, let subtitle):
            emojiContent(emoji: emoji, subtitle: subtitle)
        case .text(let text), .command(let text):
            widgetHeaderText(text, lineLimit: plainTextLineLimit)
        case .commandWithSymbol(let command, let name, let subtitle):
            VStack(spacing: 4) {
                widgetHeaderText(command, lineLimit: plainTextLineLimit)
                symbolContent(name: name, subtitle: subtitle)
            }
        case .commandWithEmoji(let command, let emoji, let subtitle):
            VStack(spacing: 4) {
                widgetHeaderText(command, lineLimit: plainTextLineLimit)
                emojiContent(emoji: emoji, subtitle: subtitle)
            }
        case .commandWithText(let command, let text):
            VStack(spacing: 4) {
                widgetHeaderText(command, lineLimit: plainTextLineLimit)
                widgetHeaderText(text, lineLimit: plainTextLineLimit)
            }
        case .none:
            EmptyView()
        }
    }

    private func widgetHeaderText(_ text: String, lineLimit: Int = 1) -> some View {
        Text(text)
            .font(.system(size: boxFontSize, weight: .bold, design: .rounded))
            .multilineTextAlignment(.center)
            .lineLimit(lineLimit)
            .minimumScaleFactor(0.4)
    }

    private var widgetCityLabel: String? {
        let trimmedRightTitle = rightTitleWithoutColorPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedRightTitle.isEmpty ? nil : trimmedRightTitle
    }

    private var widgetTimeZone: TimeZone? {
        guard let widgetCityLabel else {
            return nil
        }

        if let directMatch = TimeZone(identifier: widgetCityLabel) {
            return directMatch
        }

        let normalizedQuery = normalizedWidgetLocation(widgetCityLabel)
        let matchingIdentifier = TimeZone.knownTimeZoneIdentifiers.first { identifier in
            let normalizedIdentifier = normalizedWidgetLocation(identifier)
            let normalizedLastComponent = normalizedWidgetLocation(identifier.components(separatedBy: "/").last ?? identifier)
            return normalizedIdentifier == normalizedQuery ||
                normalizedLastComponent == normalizedQuery ||
                normalizedIdentifier.hasSuffix("/\(normalizedQuery)")
        }

        return matchingIdentifier.flatMap(TimeZone.init(identifier:))
    }

    private func clockText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = widgetTimeZone ?? .current
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    private func clockText(for date: Date, cityLabel: String?) -> String {
        dateTimeWidgetText(cityLabel: cityLabel) { timeZone in
            let formatter = DateFormatter()
            formatter.locale = Locale.current
            formatter.timeZone = timeZone
            formatter.dateFormat = "HH:mm:ss"
            return formatter.string(from: date)
        }
    }

    private func dateWeekdayText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = widgetTimeZone ?? .current
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    private func dateFullWeekdayText(for date: Date, cityLabel: String?) -> String {
        dateTimeWidgetText(cityLabel: cityLabel) { timeZone in
            let formatter = DateFormatter()
            formatter.locale = Locale.current
            formatter.timeZone = timeZone
            formatter.dateFormat = "EEEE"
            return formatter.string(from: date)
        }
    }

    private func widgetTimeComponentText(for date: Date, cityLabel: String?, format: String) -> String {
        dateTimeWidgetText(cityLabel: cityLabel) { timeZone in
            let formatter = DateFormatter()
            formatter.locale = Locale.current
            formatter.timeZone = timeZone
            formatter.dateFormat = format
            return formatter.string(from: date)
        }
    }

    private func parseWidgetTimerDuration(_ durationText: String) -> Int {
        let trimmedDurationText = durationText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDurationText.isEmpty else {
            return 0
        }

        if let durationInSeconds = Int(trimmedDurationText) {
            return durationInSeconds
        }

        let loweredDurationText = trimmedDurationText.lowercased()
        let numericPrefix = loweredDurationText.prefix { $0.isNumber }
        guard let numericValue = Int(numericPrefix) else {
            return 0
        }

        let suffix = loweredDurationText
            .dropFirst(numericPrefix.count)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let unit = suffix.first else {
            return numericValue
        }

        switch unit {
        case "m":
            return numericValue * 60
        case "h":
            return numericValue * 3600
        case "s":
            return numericValue
        default:
            return numericValue
        }
    }

    private func dayOfMonthOrdinalText(for date: Date, cityLabel: String?) -> String {
        dateTimeWidgetText(cityLabel: cityLabel) { timeZone in
            var calendar = Calendar.current
            calendar.timeZone = timeZone
            let day = calendar.component(.day, from: date)
            let suffix: String
            switch day % 100 {
            case 11, 12, 13:
                suffix = "th"
            default:
                switch day % 10 {
                case 1: suffix = "st"
                case 2: suffix = "nd"
                case 3: suffix = "rd"
                default: suffix = "th"
                }
            }
            return "\(day)\(suffix)"
        }
    }

    private func monthNameText(for date: Date, cityLabel: String?) -> String {
        dateTimeWidgetText(cityLabel: cityLabel) { timeZone in
            let formatter = DateFormatter()
            formatter.locale = Locale.current
            formatter.timeZone = timeZone
            formatter.dateFormat = "LLLL"
            return formatter.string(from: date)
        }
    }

    private func yearText(for date: Date, cityLabel: String?) -> String {
        dateTimeWidgetText(cityLabel: cityLabel) { timeZone in
            let formatter = DateFormatter()
            formatter.locale = Locale.current
            formatter.timeZone = timeZone
            formatter.dateFormat = "yyyy"
            return formatter.string(from: date)
        }
    }

    private func dateValueText(for date: Date, cityLabel: String?) -> String {
        dateTimeWidgetText(cityLabel: cityLabel) { timeZone in
            let formatter = DateFormatter()
            formatter.locale = Locale.current
            formatter.timeZone = timeZone
            formatter.dateFormat = "yy.MM.dd"
            return formatter.string(from: date)
        }
    }

    private func dateTimeWidgetText(
        cityLabel: String?,
        value: (TimeZone) -> String
    ) -> String {
        guard let cityLabel else {
            return value(.current)
        }

        guard let timeZone = widgetTimeZone(for: cityLabel) else {
            return "City not recognized"
        }

        return value(timeZone)
    }

    private func dateHeaderText(for date: Date, cityLabel: String?) -> String {
        let trimmedRightTitle = rightTitleWithoutColorPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedRightTitle.isEmpty {
            return trimmedRightTitle
        }

        return widgetDateCityCode(for: date, cityLabel: cityLabel)
    }

    private func dowHeaderText(for date: Date, cityLabel: String?) -> String {
        let trimmedRightTitle = rightTitleWithoutColorPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedRightTitle.isEmpty {
            return trimmedRightTitle
        }

        return ""
    }

    private func widgetDateCityCode(for date: Date, cityLabel: String?) -> String {
        let timeZone = widgetTimeZone(for: cityLabel) ?? .current
        let cityKeyCandidates = [
            cityLabel,
            timeZone.identifier.components(separatedBy: "/").last
        ]
            .compactMap { $0 }
            .map(normalizedWidgetLocation)

        let manualCityCodes: [String: String] = [
            "beijing": "BJD/PEK",
            "tokyo": "TYO/HND",
            "london": "LON",
            "new york": "NYC",
            "los angeles": "LAX",
            "sydney": "SYD",
            "melbourne": "MEL"
        ]

        for cityKey in cityKeyCandidates {
            if let mappedCode = manualCityCodes[cityKey] {
                return mappedCode.components(separatedBy: "/").first ?? mappedCode
            }
        }

        if let abbreviation = timeZone.abbreviation(for: date)?
            .components(separatedBy: "/")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !abbreviation.isEmpty,
           !abbreviation.uppercased().hasPrefix("GMT") {
            return abbreviation.uppercased()
        }

        let identifierTail = timeZone.identifier.components(separatedBy: "/").last ?? timeZone.identifier
        let compactIdentifier = identifierTail
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let words = compactIdentifier.split(separator: " ")
        let initialism = words
            .compactMap { $0.first.map { String($0).uppercased() } }
            .joined()
        if initialism.count >= 2 {
            return initialism
        }

        let lettersOnly = compactIdentifier.filter(\.isLetter).uppercased()
        if !lettersOnly.isEmpty {
            return String(lettersOnly.prefix(3))
        }

        return "LOC"
    }

    private func widgetTimeZone(for cityLabel: String?) -> TimeZone? {
        guard let cityLabel else {
            return nil
        }

        if let directMatch = TimeZone(identifier: cityLabel) {
            return directMatch
        }

        let normalizedQuery = normalizedWidgetLocation(cityLabel)
        let matchingIdentifier = TimeZone.knownTimeZoneIdentifiers.first { identifier in
            let normalizedIdentifier = normalizedWidgetLocation(identifier)
            let normalizedLastComponent = normalizedWidgetLocation(identifier.components(separatedBy: "/").last ?? identifier)
            return normalizedIdentifier == normalizedQuery ||
                normalizedLastComponent == normalizedQuery ||
                normalizedIdentifier.hasSuffix("/\(normalizedQuery)")
        }

        return matchingIdentifier.flatMap(TimeZone.init(identifier:))
    }

    private func normalizedWidgetLocation(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var rightTitleWithoutColorPrefix: String {
        let components = rightTitle.components(separatedBy: ":")

        if components.count > 1,
           let firstComponent = components.first?.trimmingCharacters(in: .whitespacesAndNewlines),
           isHexColorPrefix(firstComponent) {
            return components.dropFirst().joined(separator: ":")
        }

        return rightTitle
    }

    private var lastRightTitleComponent: String {
        let components = rightTitleWithoutColorPrefix.components(separatedBy: ":")
        guard let lastComponent = components.last?.trimmingCharacters(in: .whitespacesAndNewlines),
              !lastComponent.isEmpty else {
            return rightTitleWithoutColorPrefix
        }

        return lastComponent
    }

    private func textLabel(title: String) -> some View {
        Text(title)
            .font(.system(size: boxFontSize, weight: .bold))
            .id(boxFontSize)
            .multilineTextAlignment(.center)
            .lineLimit(4)
            .truncationMode(.tail)
            .allowsTightening(true)
            .foregroundStyle(buttonTextColor)
    }

    private var midiChannelFontSize: CGFloat {
        CGFloat(boxFontSize) * 0.6
    }

    private var midiLabelLineSpacing: CGFloat {
        max(1, CGFloat(boxFontSize) * 0.08)
    }

    private var midiLabelGroupSpacing: CGFloat {
        max(2, CGFloat(boxFontSize) * 0.12)
    }

    private func automaticMIDILabelContent(_ label: MainGridAutomaticMIDILabel) -> some View {
        VStack(spacing: midiLabelLineSpacing) {
            Text(label.title)
                .font(.system(size: boxFontSize, weight: .bold))

            if let value = label.midiValue {
                Text(value)
                    .font(.system(size: boxFontSize, weight: .semibold))
            }

            Text(label.detailText)
                .font(.system(size: midiChannelFontSize, weight: label.midiValue == nil ? .semibold : .medium))
                .minimumScaleFactor(label.midiValue == nil ? 0.5 : 1)
        }
        .id(boxFontSize)
        .multilineTextAlignment(.center)
        .lineLimit(1)
        .truncationMode(.tail)
        .allowsTightening(true)
        .foregroundStyle(label.usesControlChangeValueColor ? Color.yellow : buttonTextColor)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func symbolContent(name: String, subtitle: String?) -> some View {
        VStack(spacing: 4) {
            Image(systemName: name)
                .resizable()
                .scaledToFit()
                .foregroundStyle(symbolForegroundColor(for: name))
                .frame(
                    width: max(18, CGFloat(boxFontSize) * 1.5),
                    height: max(18, CGFloat(boxFontSize) * 1.5)
                )

            if let subtitle {
                textLabel(title: subtitle)
                    .lineLimit(2)
            }
        }
    }

    private func emojiContent(emoji: String, subtitle: String?) -> some View {
        Group {
            if let subtitle {
                VStack(spacing: 4) {
                    Text(emoji)
                        .font(.system(size: CGFloat(boxFontSize) * emojiScaleMultiplier))
                        .lineLimit(1)

                    textLabel(title: subtitle)
                        .lineLimit(2)
                }
            } else {
                Text(emoji)
                    .font(.system(size: max(18, CGFloat(boxFontSize) * loneEmojiScaleMultiplier)))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

	// MARK: - BM:🟪 color keycodes-btn
    private var buttonBackgroundColor: Color {
        guard !isEmptyButtonEntry else {
            return Color.black.opacity(backgroundOpacity)
        }

        guard let colorCode = entry.buttonColorCode,
              isHexColorPrefix(colorCode) else {
            return .clear
        }

        return Color(hex: colorCode).opacity(backgroundOpacity)
    }

    private var buttonTextColor: Color {
        .white
    }

    private var borderColor: Color {
        if isGridEditModeEnabled && activeDragIndex == index {
            return .green
        }

        return Color.white.opacity(0.8)
    }

    private func symbolForegroundColor(for name: String) -> Color {
        switch name {
        case "eye", "eye.slash":
            return .green
        default:
            return buttonTextColor
        }
    }

    private var isEmptyButtonEntry: Bool {
        let trimmedRawLine = entry.rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAlternateText = entry.alternateDisplayText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedRawLine.isEmpty && entry.sendTexts.isEmpty && trimmedAlternateText.isEmpty
    }
}

enum MainGridWidgetDescriptor {
    case clock(cityLabel: String?)
    case day(cityLabel: String?)
    case month(cityLabel: String?)
    case year(cityLabel: String?)
    case second(cityLabel: String?)
    case minute(cityLabel: String?)
    case hour(cityLabel: String?)
    case dow(cityLabel: String?)
    case date(cityLabel: String?)
    case power
    case add
    case minus(initialCount: Int)
    case random(minimumValue: Int, maximumValue: Int)
    case textFileRandom(filename: String)
    case stopwatch
    case ambientSound(filename: String, volume: MainGridAmbientSoundVolume)
    case timer(initialDuration: Int, completion: MainGridTimerCompletion?)
}

enum MainGridAmbientSoundVolume {
    case percentage(Int)
    case invalid(String)
}

enum MainGridTimerCompletion: Equatable {
    case sound(filename: String)
    case speech(text: String)
}

private struct MainGridBatteryWidgetView: View {
    let fontSize: Double
    let foregroundColor: Color
    @State private var batteryLevel: Float = UIDevice.current.batteryLevel
    @State private var batteryState: UIDevice.BatteryState = UIDevice.current.batteryState

    var body: some View {
        VStack(spacing: 4) {
            Text(batteryStateText)
                .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(batteryPercentageText)
                .font(.system(size: fontSize, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(foregroundColor)
        .frame(maxWidth: .infinity)
        .onAppear {
            UIDevice.current.isBatteryMonitoringEnabled = true
            refreshBatteryState()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryLevelDidChangeNotification)) { _ in
            refreshBatteryState()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryStateDidChangeNotification)) { _ in
            refreshBatteryState()
        }
    }

    private var batteryPercentageText: String {
        guard batteryLevel >= 0 else {
            return "--%"
        }

        return "\(Int((batteryLevel * 100).rounded()))%"
    }

    private var batteryStateText: String {
        switch batteryState {
        case .charging:
            return "charging"
        case .full:
            return "full"
        case .unplugged:
            return "battery"
        case .unknown:
            return "unknown"
        @unknown default:
            return "unknown"
        }
    }

    private func refreshBatteryState() {
        batteryLevel = UIDevice.current.batteryLevel
        batteryState = UIDevice.current.batteryState
    }
}

private struct MainGridStepUpCounterWidgetView: View {
    let configurationText: String
    let showsTitle: Bool
    let fontSize: Double
    let foregroundColor: Color
    let interactionSize: CGSize

    @State private var initialCount = 0
    @State private var currentCount = 0
    @State private var title = ""

    var body: some View {
        VStack(spacing: 4) {
            if showsTitle && !title.isEmpty {
                Text(title)
                    .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.2)
                    .multilineTextAlignment(.center)
            }

            Text("\(currentCount)")
                .font(.system(size: fontSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.2)
        }
        .foregroundStyle(foregroundColor)
        .frame(maxWidth: .infinity)
        .background(fullButtonHitArea)
        .gesture(
            TapGesture(count: 2)
                .onEnded {
                    currentCount = 0
                }
                .exclusively(before:
                    TapGesture()
                        .onEnded {
                            currentCount += 1
                        }
                )
        )
        .onAppear {
            applyConfiguration()
        }
        .onChange(of: configurationText) {
            applyConfiguration()
        }
    }

    private var fullButtonHitArea: some View {
        Color.white.opacity(0.001)
            .frame(width: interactionSize.width, height: interactionSize.height)
    }

    private func applyConfiguration() {
        let components = configurationText.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let firstComponent = components.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let parsedInitialCount = Int(firstComponent) ?? 0
        let parsedTitle: String

        if components.count > 1 {
            parsedTitle = String(components[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if Int(firstComponent) == nil {
            parsedTitle = firstComponent
        } else {
            parsedTitle = ""
        }

        initialCount = max(parsedInitialCount, 0)
        currentCount = initialCount
        title = parsedTitle
    }
}

private struct MainGridStepDownCounterWidgetView: View {
    let title: String
    let showsTitle: Bool
    let initialCount: Int
    let fontSize: Double
    let foregroundColor: Color
    let interactionSize: CGSize

    @State private var currentCount = 0

    var body: some View {
        VStack(spacing: 4) {
            if showsTitle && !title.isEmpty {
                Text(title)
                    .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.2)
                    .multilineTextAlignment(.center)
            }

            Text("\(currentCount)")
                .font(.system(size: fontSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.2)
        }
        .foregroundStyle(foregroundColor)
        .frame(maxWidth: .infinity)
        .background(fullButtonHitArea)
        .gesture(
            TapGesture(count: 2)
                .onEnded {
                    currentCount = initialCount
                }
                .exclusively(before:
                    TapGesture()
                        .onEnded {
                            currentCount = max(0, currentCount - 1)
                        }
                )
        )
        .onAppear {
            currentCount = max(initialCount, 0)
        }
        .onChange(of: initialCount) {
            currentCount = max(initialCount, 0)
        }
    }

    private var fullButtonHitArea: some View {
        Color.white.opacity(0.001)
            .frame(width: interactionSize.width, height: interactionSize.height)
    }
}

final class MainGridSharedTimerState: ObservableObject {
    struct TimerSnapshot {
        var configuredDuration = 0
        var remainingSeconds = 0
        var isRunning = false
        var isCompletionSoundLooping = false
    }

    @Published private var timerSnapshots: [String: TimerSnapshot] = [:]

    private var completions: [String: MainGridTimerCompletion?] = [:]
    private var startCompletionSoundLoopCallbacks: [String: (String) -> Void] = [:]
    private var stopCompletionSoundLoopCallbacks: [String: () -> Void] = [:]
    private var speakCompletionTextCallbacks: [String: (String) -> Void] = [:]
    private var timerCompletionActionCallbacks: [String: () -> Bool] = [:]
    private var endDates: [String: Date] = [:]
    private var tickTasks: [String: Task<Void, Never>] = [:]

    deinit {
        tickTasks.values.forEach { $0.cancel() }
    }

    func startTimer(
        widgetID: String,
        duration: Int,
        completion: MainGridTimerCompletion?,
        onTimerCompletionAction: @escaping () -> Bool,
        onPlayCompletionSound: @escaping (String) -> Void,
        onStopCompletionSound: @escaping () -> Void,
        onSpeakCompletionText: @escaping (String) -> Void
    ) {
        stopCompletionSoundLoop(widgetID: widgetID)
        cancelTickTask(widgetID: widgetID)

        let resolvedDuration = max(duration, 0)
        var snapshot = timerSnapshots[widgetID] ?? TimerSnapshot()
        snapshot.configuredDuration = resolvedDuration
        snapshot.remainingSeconds = resolvedDuration
        snapshot.isRunning = resolvedDuration > 0
        snapshot.isCompletionSoundLooping = false
        timerSnapshots[widgetID] = snapshot
        endDates[widgetID] = snapshot.isRunning ? Date().addingTimeInterval(TimeInterval(resolvedDuration)) : nil
        completions[widgetID] = normalizedCompletion(completion)
        timerCompletionActionCallbacks[widgetID] = onTimerCompletionAction
        startCompletionSoundLoopCallbacks[widgetID] = onPlayCompletionSound
        stopCompletionSoundLoopCallbacks[widgetID] = onStopCompletionSound
        speakCompletionTextCallbacks[widgetID] = onSpeakCompletionText

        guard snapshot.isRunning else {
            return
        }

        startTicking(for: widgetID)
    }

    func resumeTimer(
        widgetID: String,
        duration: Int,
        completion: MainGridTimerCompletion?,
        onTimerCompletionAction: @escaping () -> Bool,
        onPlayCompletionSound: @escaping (String) -> Void,
        onStopCompletionSound: @escaping () -> Void,
        onSpeakCompletionText: @escaping (String) -> Void
    ) {
        guard timerSnapshots[widgetID] != nil else {
            startTimer(
                widgetID: widgetID,
                duration: duration,
                completion: completion,
                onTimerCompletionAction: onTimerCompletionAction,
                onPlayCompletionSound: onPlayCompletionSound,
                onStopCompletionSound: onStopCompletionSound,
                onSpeakCompletionText: onSpeakCompletionText
            )
            return
        }

        stopCompletionSoundLoop(widgetID: widgetID)

        var snapshot = timerSnapshots[widgetID] ?? TimerSnapshot()
        if snapshot.remainingSeconds <= 0 {
            snapshot.remainingSeconds = max(duration, 0)
        }

        snapshot.configuredDuration = max(duration, 0)
        snapshot.isCompletionSoundLooping = false
        completions[widgetID] = normalizedCompletion(completion)
        timerCompletionActionCallbacks[widgetID] = onTimerCompletionAction
        startCompletionSoundLoopCallbacks[widgetID] = onPlayCompletionSound
        stopCompletionSoundLoopCallbacks[widgetID] = onStopCompletionSound
        speakCompletionTextCallbacks[widgetID] = onSpeakCompletionText

        guard snapshot.remainingSeconds > 0 else {
            snapshot.isRunning = false
            timerSnapshots[widgetID] = snapshot
            endDates[widgetID] = nil
            return
        }

        snapshot.isRunning = true
        timerSnapshots[widgetID] = snapshot
        endDates[widgetID] = Date().addingTimeInterval(TimeInterval(snapshot.remainingSeconds))
        startTicking(for: widgetID)
    }

    func pauseTimer(widgetID: String) {
        guard timerSnapshots[widgetID] != nil else {
            return
        }

        stopCompletionSoundLoop(widgetID: widgetID)
        syncRemainingFromEndDate(widgetID: widgetID)
        var snapshot = timerSnapshots[widgetID] ?? TimerSnapshot()
        snapshot.isRunning = false
        timerSnapshots[widgetID] = snapshot
        endDates[widgetID] = nil
        cancelTickTask(widgetID: widgetID)
    }

    func resetAndPauseTimer(
        widgetID: String,
        duration: Int,
        completion: MainGridTimerCompletion?,
        onTimerCompletionAction: @escaping () -> Bool,
        onPlayCompletionSound: @escaping (String) -> Void,
        onStopCompletionSound: @escaping () -> Void,
        onSpeakCompletionText: @escaping (String) -> Void
    ) {
        stopCompletionSoundLoop(widgetID: widgetID)
        cancelTickTask(widgetID: widgetID)

        let resolvedDuration = max(duration, 0)
        timerSnapshots[widgetID] = TimerSnapshot(
            configuredDuration: resolvedDuration,
            remainingSeconds: resolvedDuration,
            isRunning: false,
            isCompletionSoundLooping: false
        )
        endDates[widgetID] = nil
        completions[widgetID] = normalizedCompletion(completion)
        timerCompletionActionCallbacks[widgetID] = onTimerCompletionAction
        startCompletionSoundLoopCallbacks[widgetID] = onPlayCompletionSound
        stopCompletionSoundLoopCallbacks[widgetID] = onStopCompletionSound
        speakCompletionTextCallbacks[widgetID] = onSpeakCompletionText
    }

    func stopCompletionSoundLoop(widgetID: String) {
        guard var snapshot = timerSnapshots[widgetID], snapshot.isCompletionSoundLooping else {
            return
        }

        stopCompletionSoundLoopCallbacks[widgetID]?()
        snapshot.isCompletionSoundLooping = false
        timerSnapshots[widgetID] = snapshot
    }

    private func startTicking(for widgetID: String) {
        cancelTickTask(widgetID: widgetID)
        let task = Task { [weak self] in
            guard let self else {
                return
            }

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))

                await MainActor.run {
                    guard var snapshot = self.timerSnapshots[widgetID], snapshot.isRunning else {
                        return
                    }

                    self.syncRemainingFromEndDate(widgetID: widgetID)
                    snapshot = self.timerSnapshots[widgetID] ?? TimerSnapshot()

                    guard snapshot.remainingSeconds == 0 else {
                        return
                    }

                    snapshot.isRunning = false
                    self.timerSnapshots[widgetID] = snapshot
                    self.endDates[widgetID] = nil
                    self.cancelTickTask(widgetID: widgetID)
                    guard self.timerCompletionActionCallbacks[widgetID]?() ?? true else {
                        return
                    }

                    switch self.completions[widgetID] ?? nil {
                    case .sound(let filename):
                        self.startCompletionSoundLoopCallbacks[widgetID]?(filename)
                        snapshot.isCompletionSoundLooping = true
                        self.timerSnapshots[widgetID] = snapshot
                    case .speech(let text):
                        self.speakCompletionTextCallbacks[widgetID]?(text)
                    case nil:
                        break
                    }
                }
            }
        }
        tickTasks[widgetID] = task
    }

    private func syncRemainingFromEndDate(widgetID: String) {
        guard let endDate = endDates[widgetID] else {
            return
        }

        var snapshot = timerSnapshots[widgetID] ?? TimerSnapshot()
        snapshot.remainingSeconds = max(Int(ceil(endDate.timeIntervalSinceNow)), 0)
        timerSnapshots[widgetID] = snapshot
    }

    private func cancelTickTask(widgetID: String) {
        tickTasks[widgetID]?.cancel()
        tickTasks[widgetID] = nil
    }

    private func normalizedCompletion(_ completion: MainGridTimerCompletion?) -> MainGridTimerCompletion? {
        switch completion {
        case .sound(let filename):
            let trimmedFilename = filename.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedFilename.isEmpty ? nil : .sound(filename: trimmedFilename)
        case .speech(let text):
            let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedText.isEmpty ? nil : .speech(text: trimmedText)
        case nil:
            return nil
        }
    }

    func remainingSeconds(for widgetID: String, default defaultValue: Int) -> Int {
        timerSnapshots[widgetID]?.remainingSeconds ?? defaultValue
    }

    func isRunning(widgetID: String) -> Bool {
        timerSnapshots[widgetID]?.isRunning ?? false
    }

    func isCompletionSoundLooping(widgetID: String) -> Bool {
        timerSnapshots[widgetID]?.isCompletionSoundLooping ?? false
    }

    func hasMatchingConfiguration(
        widgetID: String,
        duration: Int,
        completion: MainGridTimerCompletion?
    ) -> Bool {
        guard let snapshot = timerSnapshots[widgetID],
              snapshot.configuredDuration == max(duration, 0) else {
            return false
        }

        return timerCompletionsMatch(
            completions[widgetID] ?? nil,
            normalizedCompletion(completion)
        )
    }

    private func timerCompletionsMatch(
        _ lhs: MainGridTimerCompletion?,
        _ rhs: MainGridTimerCompletion?
    ) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case (.sound(let lhsFilename), .sound(let rhsFilename)):
            return lhsFilename == rhsFilename
        case (.speech(let lhsText), .speech(let rhsText)):
            return lhsText == rhsText
        default:
            return false
        }
    }
}

final class MainGridAmbientSoundState: ObservableObject {
    @Published var activeWidgetID: String?
    @Published var isPlaying = false
    @Published private(set) var isPlaybackActive = false

    private var activeFilename: String?
    private var pendingWidgetID: String?
    private var player: AVAudioPlayer?
    private var playbackRequestID = UUID()

    func togglePlayback(
        widgetID: String,
        filename: String,
        volume: Float,
        resolveSoundURL: (String) -> URL?,
        activateAudioSession: () async -> Bool,
        reportSoundError: (String, String) -> Void
    ) async {
        let normalizedFilename = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedFilename.isEmpty else {
            return
        }

        if (activeWidgetID == widgetID && isPlaying) || pendingWidgetID == widgetID {
            stopPlayback()
            return
        }

        await startPlayback(
            widgetID: widgetID,
            filename: normalizedFilename,
            volume: volume,
            resolveSoundURL: resolveSoundURL,
            activateAudioSession: activateAudioSession,
            reportSoundError: reportSoundError
        )
    }

    func restartPlayback(
        widgetID: String,
        filename: String,
        volume: Float,
        resolveSoundURL: (String) -> URL?,
        activateAudioSession: () async -> Bool,
        reportSoundError: (String, String) -> Void
    ) async {
        let normalizedFilename = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedFilename.isEmpty else {
            return
        }

        if activeWidgetID == widgetID,
           activeFilename == normalizedFilename,
           isPlaying,
           let player {
            playbackRequestID = UUID()
            player.currentTime = 0
            player.play()
            return
        }

        await startPlayback(
            widgetID: widgetID,
            filename: normalizedFilename,
            volume: volume,
            resolveSoundURL: resolveSoundURL,
            activateAudioSession: activateAudioSession,
            reportSoundError: reportSoundError
        )
    }

    private func startPlayback(
        widgetID: String,
        filename: String,
        volume: Float,
        resolveSoundURL: (String) -> URL?,
        activateAudioSession: () async -> Bool,
        reportSoundError: (String, String) -> Void
    ) async {
        stopCurrentPlayer()

        let requestID = UUID()
        playbackRequestID = requestID
        pendingWidgetID = widgetID
        isPlaybackActive = true

        guard let audioURL = resolveSoundURL(filename) else {
            guard playbackRequestID == requestID else {
                return
            }
            pendingWidgetID = nil
            isPlaybackActive = false
            reportSoundError("Sound Not Found", "Couldn't find \(filename).")
            return
        }

        guard await activateAudioSession() else {
            guard playbackRequestID == requestID else {
                return
            }
            pendingWidgetID = nil
            isPlaybackActive = false
            reportSoundError("Sound Error", "Couldn't play \(filename).")
            return
        }

        guard playbackRequestID == requestID else {
            return
        }

        do {
            let player = try await MainGridSoundPlayerPreparer.shared.preparePlayer(
                at: audioURL,
                repeats: true
            )
            guard playbackRequestID == requestID else {
                return
            }
            player.volume = volume
            guard player.play() else {
                pendingWidgetID = nil
                isPlaybackActive = false
                reportSoundError("Sound Error", "Couldn't play \(filename).")
                return
            }
            self.player = player
            pendingWidgetID = nil
            isPlaybackActive = true
            activeWidgetID = widgetID
            activeFilename = filename
            isPlaying = true
        } catch {
            guard playbackRequestID == requestID else {
                return
            }
            pendingWidgetID = nil
            isPlaybackActive = false
            reportSoundError("Sound Error", "Couldn't play \(filename).")
        }
    }

    func stopPlayback() {
        playbackRequestID = UUID()
        stopCurrentPlayer()
    }

    private func stopCurrentPlayer() {
        player?.stop()
        player = nil
        pendingWidgetID = nil
        activeWidgetID = nil
        activeFilename = nil
        isPlaying = false
        isPlaybackActive = false
    }
}

private struct MainGridTimerWidgetView: View {
    let widgetID: String
    let entry: FunctionKeyEntry
    let configurationText: String
    let showsTitle: Bool
    let initialDuration: Int
    let completion: MainGridTimerCompletion?
    @ObservedObject var sharedTimer: MainGridSharedTimerState
    let fontSize: Double
    let foregroundColor: Color
    let interactionSize: CGSize
    let onTimerCompletionAction: (FunctionKeyEntry) -> Bool
    let onPlayCompletionSound: (String) -> Void
    let onStopCompletionSound: () -> Void
    let onSpeakCompletionText: (String) -> Void

    @State private var configuredDuration = 0
    @State private var title = ""

    var body: some View {
        VStack(spacing: 4) {
            if showsTitle && !title.isEmpty {
                Text(title)
                    .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                    .multilineTextAlignment(.center)
            }

            Text(formattedRemainingTime)
                .font(.system(size: fontSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .foregroundStyle(foregroundColor)
        .frame(maxWidth: .infinity)
        .background(fullButtonHitArea)
        .gesture(
            TapGesture(count: 2)
                .onEnded {
                    resetAndPause()
                }
                .exclusively(before:
                    TapGesture()
                        .onEnded {
                            togglePlayback()
                        }
                )
        )
        .onAppear {
            applyConfiguration()
        }
        .onChange(of: configurationText) {
            applyConfiguration()
        }
        .onChange(of: initialDuration) {
            applyConfiguration()
        }
        .onChange(of: completion) {
            applyConfiguration()
        }
    }

    private var fullButtonHitArea: some View {
        Color.white.opacity(0.001)
            .frame(width: interactionSize.width, height: interactionSize.height)
    }

    private var displayedRemainingSeconds: Int {
        sharedTimer.remainingSeconds(for: widgetID, default: configuredDuration)
    }

    private var formattedRemainingTime: String {
        let remainingSeconds = max(displayedRemainingSeconds, 0)
        let hours = remainingSeconds / 3600
        let minutes = (remainingSeconds % 3600) / 60
        let seconds = remainingSeconds % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }

        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func applyConfiguration() {
        configuredDuration = max(initialDuration, 0)
        title = configurationText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !sharedTimer.isRunning(widgetID: widgetID),
              !sharedTimer.isCompletionSoundLooping(widgetID: widgetID) else {
            return
        }

        guard !sharedTimer.hasMatchingConfiguration(
            widgetID: widgetID,
            duration: configuredDuration,
            completion: completion
        ) else {
            return
        }

        sharedTimer.resetAndPauseTimer(
            widgetID: widgetID,
            duration: configuredDuration,
            completion: completion,
            onTimerCompletionAction: { onTimerCompletionAction(entry) },
            onPlayCompletionSound: onPlayCompletionSound,
            onStopCompletionSound: onStopCompletionSound,
            onSpeakCompletionText: onSpeakCompletionText
        )
    }

    private func togglePlayback() {
        guard configuredDuration > 0 else {
            return
        }

        if sharedTimer.isCompletionSoundLooping(widgetID: widgetID) {
            sharedTimer.stopCompletionSoundLoop(widgetID: widgetID)
            return
        }

        if sharedTimer.isRunning(widgetID: widgetID) {
            sharedTimer.pauseTimer(widgetID: widgetID)
            return
        }

        sharedTimer.resumeTimer(
            widgetID: widgetID,
            duration: configuredDuration,
            completion: completion,
            onTimerCompletionAction: { onTimerCompletionAction(entry) },
            onPlayCompletionSound: onPlayCompletionSound,
            onStopCompletionSound: onStopCompletionSound,
            onSpeakCompletionText: onSpeakCompletionText
        )
    }

    private func resetAndPause() {
        sharedTimer.resetAndPauseTimer(
            widgetID: widgetID,
            duration: configuredDuration,
            completion: completion,
            onTimerCompletionAction: { onTimerCompletionAction(entry) },
            onPlayCompletionSound: onPlayCompletionSound,
            onStopCompletionSound: onStopCompletionSound,
            onSpeakCompletionText: onSpeakCompletionText
        )
    }
}

private struct MainGridAmbientSoundWidgetView: View {
    let widgetID: String
    let title: String
    let showsTitle: Bool
    let filename: String
    let volume: MainGridAmbientSoundVolume
    let fontSize: Double
    let foregroundColor: Color
    let isInteractionEnabled: Bool
    let interactionSize: CGSize
    @ObservedObject var sharedState: MainGridAmbientSoundState
    let resolveSoundURL: (String) -> URL?
    let activateAudioSession: () async -> Bool
    let reportSoundError: (String, String) -> Void

    var body: some View {
        interactionContent
            .contentShape(Rectangle())
            .gesture(
                TapGesture(count: 3)
                    .onEnded { }
                    .exclusively(before:
                        TapGesture(count: 2)
                            .onEnded {
                                guard isInteractionEnabled else {
                                    return
                                }
                                restartPlayback()
                            }
                            .exclusively(before:
                                TapGesture()
                                    .onEnded {
                                        guard isInteractionEnabled else {
                                            return
                                        }
                                        togglePlayback()
                                    }
                            )
                    )
            )
    }

    private func togglePlayback() {
        guard let volume = resolvedVolume else {
            return
        }

        Task {
            await sharedState.togglePlayback(
                widgetID: widgetID,
                filename: filename,
                volume: volume,
                resolveSoundURL: resolveSoundURL,
                activateAudioSession: activateAudioSession,
                reportSoundError: reportSoundError
            )
        }
    }

    private func restartPlayback() {
        guard let volume = resolvedVolume else {
            return
        }

        Task {
            await sharedState.restartPlayback(
                widgetID: widgetID,
                filename: filename,
                volume: volume,
                resolveSoundURL: resolveSoundURL,
                activateAudioSession: activateAudioSession,
                reportSoundError: reportSoundError
            )
        }
    }

    private var resolvedVolume: Float? {
        switch volume {
        case .percentage(let percentage):
            return Float(percentage) / 100.0
        case .invalid(let value):
            reportSoundError(
                "Invalid Ambient Volume",
                "Use a volume from 0 through 100. \(value) is outside that range."
            )
            return nil
        }
    }

    @ViewBuilder
    private var interactionContent: some View {
        if showsTitle {
            Text(displayTitle)
                .font(.system(size: fontSize, weight: .bold, design: .rounded))
                .lineLimit(4)
                .minimumScaleFactor(0.2)
                .multilineTextAlignment(.center)
                .foregroundStyle(foregroundColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Color.white.opacity(0.001)
                .frame(width: interactionSize.width, height: interactionSize.height)
        }
    }

    private var displayTitle: String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedTitle.isEmpty else {
            return trimmedTitle
        }
        return ""
    }
}

private struct MainGridStopwatchWidgetView: View {
    let title: String
    let showsTitle: Bool
    let fontSize: Double
    let foregroundColor: Color
    let isInteractionEnabled: Bool
    let interactionSize: CGSize

    @State private var elapsedTenths = 0
    @State private var isRunning = false
    private let ticker = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 4) {
            if showsTitle && !trimmedTitle.isEmpty {
                Text(trimmedTitle)
                    .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.2)
                    .multilineTextAlignment(.center)
            }

            Text(formattedElapsedTime)
                .font(.system(size: fontSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.2)
        }
        .foregroundStyle(foregroundColor)
        .frame(maxWidth: .infinity)
        .background(fullButtonHitArea)
        .gesture(
            TapGesture(count: 2)
                .onEnded {
                    elapsedTenths = 0
                }
                .exclusively(before:
                    TapGesture()
                        .onEnded {
                            isRunning.toggle()
                        }
                ),
            including: isInteractionEnabled ? .all : .none
        )
        .onReceive(ticker) { _ in
            guard isRunning else {
                return
            }

            elapsedTenths += 1
        }
    }

    private var fullButtonHitArea: some View {
        Color.white.opacity(0.001)
            .frame(width: interactionSize.width, height: interactionSize.height)
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var formattedElapsedTime: String {
        let totalSeconds = elapsedTenths / 10
        let tenths = elapsedTenths % 10
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d.%01d", hours, minutes, seconds, tenths)
        }

        return String(format: "%02d:%02d.%01d", minutes, seconds, tenths)
    }
}

private struct MainGridRandomNumberWidgetView: View {
    let title: String
    let showsTitle: Bool
    let minimumValue: Int
    let maximumValue: Int
    let fontSize: Double
    let foregroundColor: Color
    let interactionSize: CGSize

    @State private var displayedValue = 0
    @State private var animationTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 4) {
            if showsTitle && !trimmedTitle.isEmpty {
                Text(trimmedTitle)
                    .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.2)
                    .multilineTextAlignment(.center)
            }

            Text("\(displayedValue)")
                .font(.system(size: fontSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.2)
        }
        .foregroundStyle(foregroundColor)
        .frame(maxWidth: .infinity)
        .background(fullButtonHitArea)
        .onTapGesture {
            generateRandomValue()
        }
        .onAppear {
            displayedValue = normalizedRange.lowerBound
        }
        .onChange(of: minimumValue) {
            displayedValue = normalizedRange.lowerBound
        }
        .onChange(of: maximumValue) {
            displayedValue = normalizedRange.lowerBound
        }
        .onDisappear {
            animationTask?.cancel()
        }
    }

    private var fullButtonHitArea: some View {
        Color.white.opacity(0.001)
            .frame(width: interactionSize.width, height: interactionSize.height)
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedRange: ClosedRange<Int> {
        let lowerBound = min(minimumValue, maximumValue)
        let upperBound = max(minimumValue, maximumValue)
        return lowerBound...upperBound
    }

    private func generateRandomValue() {
        animationTask?.cancel()

        animationTask = Task {
            for _ in 0..<10 {
                guard !Task.isCancelled else {
                    return
                }

                await MainActor.run {
                    displayedValue = Int.random(in: normalizedRange)
                    ButtonClickFeedback.playIfEnabled()
                }

                try? await Task.sleep(for: .milliseconds(100))
            }

            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                displayedValue = Int.random(in: normalizedRange)
                animationTask = nil
            }
        }
    }
}

private struct MainGridRandomTextWidgetView: View {
    let title: String
    let showsInitialTitle: Bool
    let filename: String
    let fontSize: Double
    let foregroundColor: Color
    let interactionSize: CGSize
    let onSelectionCommitted: ((String) -> Void)?
    let onRepeatRequested: ((String) -> Void)?

    @State private var displayedLine = ""
    @State private var availableLines: [String] = []
    @State private var shuffledLines: [String] = []
    @State private var nextShuffledLineIndex = 0
    @State private var animationTask: Task<Void, Never>?
    @State private var hasSelectedLine = false

    var body: some View {
        Text(visibleDisplayedLine)
            .font(.system(size: fontSize, weight: .bold, design: .rounded))
            .multilineTextAlignment(.center)
            .lineLimit(4)
            .minimumScaleFactor(0.2)
            .frame(maxWidth: .infinity)
        .foregroundStyle(foregroundColor)
        .frame(maxWidth: .infinity)
        .background(fullButtonHitArea)
        .gesture(
            TapGesture(count: 2)
                .onEnded {
                    repeatDisplayedLine()
                }
                .exclusively(before:
                    TapGesture()
                        .onEnded {
                            chooseRandomLine()
                        }
                )
        )
        .task(id: "\(filename)|\(title)") {
            availableLines = loadLines()
            shuffledLines = []
            nextShuffledLineIndex = 0
            hasSelectedLine = false
            displayedLine = showsInitialTitle ? trimmedTitle : ""
        }
        .onDisappear {
            animationTask?.cancel()
        }
    }

    private var fullButtonHitArea: some View {
        Color.white.opacity(0.001)
            .frame(width: interactionSize.width, height: interactionSize.height)
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var visibleDisplayedLine: String {
        showsInitialTitle || hasSelectedLine ? displayedLine : ""
    }

    private func chooseRandomLine() {
        let lines = availableLines.isEmpty ? loadLines() : availableLines
        availableLines = lines

        guard !lines.isEmpty else {
            displayedLine = ""
            return
        }

        let previousLine = displayedLine
        let selectedLine = nextQueuedLine(from: lines, avoiding: previousLine)

        animationTask?.cancel()
        hasSelectedLine = true
        animationTask = Task {
            for _ in 0..<10 {
                guard !Task.isCancelled else {
                    return
                }

                await MainActor.run {
                    displayedLine = previewLine(from: lines, avoiding: previousLine, preferredLine: selectedLine)
                    ButtonClickFeedback.playIfEnabled()
                }

                try? await Task.sleep(for: .milliseconds(100))
            }

            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                displayedLine = selectedLine
                onSelectionCommitted?(selectedLine)
                animationTask = nil
            }
        }
    }

    private func nextQueuedLine(from lines: [String], avoiding previousLine: String) -> String {
        if shuffledLines.count != lines.count || Set(shuffledLines) != Set(lines) {
            shuffledLines = reshuffledLines(from: lines, avoidingFirst: previousLine)
            nextShuffledLineIndex = 0
        }

        guard !shuffledLines.isEmpty else {
            return ""
        }

        if nextShuffledLineIndex >= shuffledLines.count {
            shuffledLines = reshuffledLines(from: lines, avoidingFirst: previousLine)
            nextShuffledLineIndex = 0
        }

        let selectedLine = shuffledLines[nextShuffledLineIndex]
        nextShuffledLineIndex += 1
        return selectedLine
    }

    private func reshuffledLines(from lines: [String], avoidingFirst previousLine: String) -> [String] {
        guard lines.count > 1 else {
            return lines
        }

        var shuffled = lines.shuffled()
        if shuffled.first == previousLine,
           let replacementIndex = shuffled.firstIndex(where: { $0 != previousLine }) {
            shuffled.swapAt(0, replacementIndex)
        }
        return shuffled
    }

    private func previewLine(from lines: [String], avoiding previousLine: String, preferredLine: String) -> String {
        let previewCandidates = lines.filter { $0 != previousLine }
        if let previewLine = previewCandidates.randomElement() {
            return previewLine
        }

        if !preferredLine.isEmpty {
            return preferredLine
        }

        guard lines.count > 1 else {
            return lines.first ?? ""
        }

        return lines.randomElement() ?? ""
    }

    private func repeatDisplayedLine() {
        let trimmedDisplayedLine = displayedLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDisplayedLine.isEmpty else {
            return
        }

        onRepeatRequested?(trimmedDisplayedLine)
    }

    private func loadLines() -> [String] {
        guard let fileURL = textFileURL(named: filename),
              let contents = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return []
        }

        return contents
            .components(separatedBy: CharacterSet.newlines)
            .compactMap { line in
                let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedLine.isEmpty, !trimmedLine.hasPrefix("//") else {
                    return nil
                }
                return line.replacingOccurrences(of: "\r", with: "")
            }
    }

    private func textFileURL(named filename: String) -> URL? {
        let trimmedFilename = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFilename.isEmpty else {
            return nil
        }

        if let documentsDirectoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let documentFileURL = documentsDirectoryURL.appendingPathComponent(trimmedFilename)
            if FileManager.default.fileExists(atPath: documentFileURL.path) {
                return documentFileURL
            }
        }

        return Bundle.main.resourceURL?.appendingPathComponent(trimmedFilename)
    }
}
