import SwiftUI

struct SettingsImageControlsSection: View {
    let displayName: String
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
            Text(displayName)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(1)

            HStack(spacing: 18) {
                imageControlButton(systemName: "arrow.counterclockwise.circle", action: onReset)
                imageControlButton(systemName: "shuffle.circle", action: onRandom)
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
    }

    private func imageControlButton(
        systemName: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            ButtonClickFeedback.playIfEnabled()
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 28))
                .foregroundStyle(.white)
                .opacity(isEnabled ? 1 : 0.35)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    private func repeatingImageControlButton(
        systemName: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 28))
            .foregroundStyle(.white)
            .opacity(isEnabled ? 1 : 0.35)
            .contentShape(Rectangle())
            .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard isEnabled else {
                        return
                    }
                    startRepeating(action: action)
                }
                .onEnded { _ in
                    let shouldTriggerTap = !hasRepeatedDuringCurrentPress
                    stopRepeating()

                    guard isEnabled, shouldTriggerTap else {
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
}
