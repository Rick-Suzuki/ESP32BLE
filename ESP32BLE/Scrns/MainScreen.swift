import SwiftUI

private enum FunctionKeyDisplayMode: CaseIterable {
    case left
    case right
    case both

    func next() -> Self {
        switch self {
        case .left:
            return .right
        case .right:
            return .both
        case .both:
            return .left
        }
    }

    var title: String {
        switch self {
        case .left:
            return "Left cmd"
        case .right:
            return "Right text"
        case .both:
            return "Both texts"
        }
    }
}

struct MainScreen: View {
    private let allowedVisibleBoxCounts = [
        1, 2, 4, 6, 9, 12, 15, 16, 18, 20, 24, 28, 32, 36, 42, 45, 48,
        50, 54, 56, 60, 63, 64, 70, 72, 80, 81, 84, 88, 90, 96, 99, 100
    ]
    private let displayModeButtonColor = Color(red: 0.0, green: 0.24, blue: 0.55)
    @State private var visibleBoxCount = 20
    @State private var boxFontSize = 28.0
    @State private var isBLESendEnabled = true
    @ObservedObject var ble: BLEKeyboardManager
    @State private var displayMode: FunctionKeyDisplayMode = .left
    @State private var isEditingDocumentName = false
    @State private var documentNameDraft = ""
    @State private var renameAlertMessage: String?
    @FocusState private var isDocumentNameFieldFocused: Bool
    let functionKeys: [FunctionKeyEntry]
    let documentFiles: [URL]
    let selectedDocumentName: String
    let selectedDocumentDisplayName: String
    let currentFileNumber: Int
    let totalFileCount: Int
    let refreshDocumentFiles: () -> Void
    let loadFunctionKeys: (URL) -> Void
    let renameDocument: (String) -> String?
    let deleteDocument: (URL) -> Void
    let duplicateDocument: (URL) -> Void
    let canDeleteDocuments: Bool
    let selectPreviousDocument: () -> Void
    let selectNextDocument: () -> Void
    @Binding var settingsBLEText: String

    var body: some View {
        VStack(spacing: 20) {
            GeometryReader { geometry in
                let gridDimensions = gridDimensions(for: visibleBoxCount)
                let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: gridDimensions.columns)
                let buttonHeight = geometry.size.height / CGFloat(max(gridDimensions.rows, 1))

                LazyVGrid(columns: columns, spacing: 0) {
                    ForEach(Array(functionKeys.prefix(visibleBoxCount).enumerated()), id: \.offset) { _, entry in
                        Button {
                            guard isBLESendEnabled else {
                                return
                            }

                            guard !entry.sendTexts.isEmpty else {
                                return
                            }

                            for sendText in entry.sendTexts {
                                ble.sendLine(sendText)
                            }
                        } label: {
                            Text(buttonTitle(for: entry))
                                .font(.system(size: boxFontSize, weight: .semibold))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity, minHeight: buttonHeight, maxHeight: buttonHeight)
                                .background(Color.black)
                                .overlay {
                                    Rectangle()
                                        .stroke(Color.white, lineWidth: 1)
                                }
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            displayModeButtonSection
        }
        .padding(.horizontal, 2)
        .navigationTitle("")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                documentTitle
            }

            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink("settings >") {
                    SettingsScreen(
                        ble: ble,
                        documentFiles: documentFiles,
                        selectedDocumentName: selectedDocumentName,
                        refreshDocumentFiles: refreshDocumentFiles,
                        loadFunctionKeys: loadFunctionKeys,
                        deleteDocument: deleteDocument,
                        duplicateDocument: duplicateDocument,
                        canDeleteDocuments: canDeleteDocuments,
                        bleTextToSend: $settingsBLEText
                    )
                }
            }
        }
        .task(id: isEditingDocumentName) {
            guard isEditingDocumentName else { return }
            isDocumentNameFieldFocused = true
        }
        .alert("Rename File", isPresented: renameAlertIsPresented) {
            Button("OK", role: .cancel) {
                renameAlertMessage = nil
            }
        } message: {
            Text(renameAlertMessage ?? "")
        }
    }

    private var documentTitle: some View {
        HStack(spacing: 20) {
            Button {
                selectPreviousDocument()
            } label: {
                Image(systemName: "triangle.fill")
                    .font(.system(size: 20))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .disabled(currentFileNumber <= 1)

            Text("\(currentFileNumber)")
                .font(.headline)
                .frame(minWidth: 20, alignment: .leading)

            Group {
                if isEditingDocumentName {
                    TextField("Filename", text: $documentNameDraft)
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.done)
                        .focused($isDocumentNameFieldFocused)
                        .onSubmit(commitDocumentRename)
                } else {
                    Button {
                        documentNameDraft = selectedDocumentDisplayName
                        isEditingDocumentName = true
                    } label: {
                        Text(selectedDocumentDisplayName)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)

            Button {
                selectNextDocument()
            } label: {
                Image(systemName: "triangle.fill")
                    .font(.system(size: 20))
                    .rotationEffect(.degrees(90))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .disabled(currentFileNumber >= totalFileCount)
        }
    }

    private var displayModeButtonSection: some View {
        HStack {
            HStack(spacing: 12) {
                Button {
                    decreaseVisibleBoxCount()
                } label: {
                    Image(systemName: "triangle.fill")
                        .font(.system(size: 30))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .disabled(visibleBoxCount == allowedVisibleBoxCounts.first)

                Text("num:\(visibleBoxCount)")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(minWidth: 32)

                Button {
                    increaseVisibleBoxCount()
                } label: {
                    Image(systemName: "triangle.fill")
                        .font(.system(size: 30))
                        .rotationEffect(.degrees(90))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .disabled(visibleBoxCount == allowedVisibleBoxCounts.last)
            }

            HStack(spacing: 12) {
                Button {
                    decreaseBoxFontSize()
                } label: {
                    Image(systemName: "triangle.fill")
                        .font(.system(size: 30))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .disabled(boxFontSize <= minimumBoxFontSize)

                Text("fnt:\(Int(boxFontSize))")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(minWidth: 32)

                Button {
                    increaseBoxFontSize()
                } label: {
                    Image(systemName: "triangle.fill")
                        .font(.system(size: 30))
                        .rotationEffect(.degrees(90))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .disabled(boxFontSize >= maximumBoxFontSize)
            }

            Spacer(minLength: 12)

            Button {
                isBLESendEnabled.toggle()
            } label: {
                Text(isBLESendEnabled ? "Enabled" : "Disabled")
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(isBLESendEnabled ? Color.blue : Color.gray.opacity(0.45))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isBLESendEnabled ? Color.blue : Color.gray.opacity(0.4), lineWidth: 2)
            }
            .clipShape(.rect(cornerRadius: 12))
            .frame(maxWidth: 150)

            Button {
                displayMode = displayMode.next()
            } label: {
                displayModeLabel
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(displayModeButtonColor)
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(displayModeButtonColor, lineWidth: 2)
            }
            .clipShape(.rect(cornerRadius: 12))
            .frame(maxWidth: 180)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.thinMaterial)
        .clipShape(.rect(cornerRadius: 16))
    }

    private var displayModeLabel: some View {
        VStack(spacing: 2) {
            Text(displayMode.title)
        }
    }

    private func buttonTitle(for entry: FunctionKeyEntry) -> String {
        guard entry.displayUsesAlternateText else {
            return displayText(from: entry.rawLine)
        }

        switch displayMode {
        case .left:
            return displayText(from: entry.primaryDisplayText)
        case .right:
            return displayText(from: entry.alternateDisplayText ?? entry.rawLine)
        case .both:
            return "\(displayText(from: entry.primaryDisplayText))\n\(displayText(from: entry.alternateDisplayText ?? entry.rawLine))"
        }
    }

    private func displayText(from text: String) -> String {
        text
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\t", with: "\t")
    }

    private var renameAlertIsPresented: Binding<Bool> {
        Binding(
            get: { renameAlertMessage != nil },
            set: { newValue in
                if !newValue {
                    renameAlertMessage = nil
                }
            }
        )
    }

    private var minimumBoxFontSize: Double { 12 }

    private var maximumBoxFontSize: Double { 100 }

    private func decreaseVisibleBoxCount() {
        guard let currentIndex = allowedVisibleBoxCounts.firstIndex(of: visibleBoxCount),
              currentIndex > 0 else {
            return
        }

        visibleBoxCount = allowedVisibleBoxCounts[currentIndex - 1]
    }

    private func increaseVisibleBoxCount() {
        guard let currentIndex = allowedVisibleBoxCounts.firstIndex(of: visibleBoxCount),
              currentIndex < allowedVisibleBoxCounts.count - 1 else {
            return
        }

        visibleBoxCount = allowedVisibleBoxCounts[currentIndex + 1]
    }

    private func decreaseBoxFontSize() {
        boxFontSize = max(minimumBoxFontSize, boxFontSize - 2)
    }

    private func increaseBoxFontSize() {
        boxFontSize = min(maximumBoxFontSize, boxFontSize + 2)
    }

    private func gridDimensions(for itemCount: Int) -> (columns: Int, rows: Int) {
        let preferredDimensions: [Int: (columns: Int, rows: Int)] = [
            15: (5, 3),
            18: (6, 3),
            24: (6, 4),
            28: (7, 4),
            32: (8, 4),
            45: (9, 5),
            48: (8, 6),
            50: (10, 5),
            54: (9, 6),
            60: (10, 6),
            63: (9, 7),
            70: (10, 7),
            80: (10, 8),
            84: (12, 7),
            88: (11, 8),
            96: (12, 8),
            99: (11, 9)
        ]

        if let preferred = preferredDimensions[itemCount] {
            return preferred
        }

        guard itemCount > 0 else {
            return (1, 1)
        }

        let baseColumns = Int(ceil(sqrt(Double(itemCount))))
        var columns = max(baseColumns, Int(ceil(Double(itemCount) / Double(baseColumns))))
        var rows = Int(ceil(Double(itemCount) / Double(columns)))

        if rows > columns {
            swap(&rows, &columns)
        }

        return (columns, rows)
    }

    private func commitDocumentRename() {
        let proposedName = documentNameDraft

        if let alertMessage = renameDocument(proposedName) {
            renameAlertMessage = alertMessage
            return
        }

        documentNameDraft = selectedDocumentDisplayName
        isEditingDocumentName = false
    }
}
