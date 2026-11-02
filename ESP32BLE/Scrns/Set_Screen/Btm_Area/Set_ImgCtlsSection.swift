import SwiftUI

enum SettingsImageControlAppearance {
    static let disabledColor = Color.white.opacity(0.45)
}

struct SettingsImageControlsSection: View {
    let isImagesActive: Bool
    let canReset: Bool
    let canRandom: Bool
    let canGoPrevious: Bool
    let canGoNext: Bool
    let onReset: () -> Void
    let onRandom: () -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void
    @State private var repeatTask: Task<Void, Never>?
    @State private var hasRepeatedDuringCurrentPress = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isPad {
                Text("Image")
                    .font(settingsCompactControlFont)
                    .foregroundStyle(isImagesActive ? .white : SettingsImageControlAppearance.disabledColor)
                    .lineLimit(1)
            }

            HStack(spacing: 18) {
                imageControlButton(
                    systemName: "arrow.counterclockwise.circle",
                    isEnabled: canReset,
                    action: onReset
                )
                imageControlButton(
                    systemName: "shuffle.circle",
                    isEnabled: canRandom,
                    action: onRandom
                )
                repeatingImageControlButton(
                    systemName: "arrowshape.left.circle",
                    isEnabled: canGoPrevious,
                    action: onPrevious
                )
                repeatingImageControlButton(
                    systemName: "arrowshape.right.circle",
                    isEnabled: canGoNext,
                    action: onNext
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onDisappear {
            stopRepeating()
        }
        .onChange(of: isImagesActive) { _, isActive in
            if !isActive {
                stopRepeating()
            }
        }
    }

    private var settingsCompactControlFont: Font {
        isPad ? .headline : .system(size: 14, weight: .semibold)
    }

    private func imageControlButton(
        systemName: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        let isInteractable = isImagesActive && isEnabled

        return Button {
            guard isInteractable else { return }
            ButtonClickFeedback.playIfEnabled()
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 28))
                .foregroundStyle(controlColor)
                .opacity(controlOpacity(isEnabled: isEnabled))
        }
        .buttonStyle(.plain)
        .allowsHitTesting(isInteractable)
        .accessibilityHint(isInteractable ? "" : "Unavailable")
    }

    private func repeatingImageControlButton(
        systemName: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        let isInteractable = isImagesActive && isEnabled

        return Image(systemName: systemName)
            .font(.system(size: 28))
            .foregroundStyle(controlColor)
            .opacity(controlOpacity(isEnabled: isEnabled))
            .contentShape(Rectangle())
            .allowsHitTesting(isInteractable)
            .accessibilityHint(isInteractable ? "" : "Unavailable")
            .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard isImagesActive, isEnabled else {
                        return
                    }
                    startRepeating(action: action)
                }
                .onEnded { _ in
                    let shouldTriggerTap = !hasRepeatedDuringCurrentPress
                    stopRepeating()

                    guard isImagesActive, isEnabled, shouldTriggerTap else {
                        return
                    }

                    ButtonClickFeedback.playIfEnabled()
                    action()
                }
        )
    }

    private func startRepeating(action: @escaping () -> Void) {
        guard repeatTask == nil else {
            return
        }

        repeatTask = Task {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(0.5))
                } catch {
                    break
                }

                if Task.isCancelled {
                    break
                }

                await MainActor.run {
                    hasRepeatedDuringCurrentPress = true
                    ButtonClickFeedback.playIfEnabled()
                    action()
                }
            }
        }
    }

    private func stopRepeating() {
        repeatTask?.cancel()
        repeatTask = nil
        hasRepeatedDuringCurrentPress = false
    }

    private var controlColor: Color {
        isImagesActive ? .cyan : SettingsImageControlAppearance.disabledColor
    }

    private func controlOpacity(isEnabled: Bool) -> Double {
        guard isImagesActive else { return 1 }
        return isEnabled ? 1 : 0.35
    }
}
