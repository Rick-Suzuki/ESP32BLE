import SwiftUI

struct SettingsImageControlsSection: View {
    let displayName: String
    let canGoPrevious: Bool
    let canGoNext: Bool
    let onReset: () -> Void
    let onRandom: () -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(displayName)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(1)

            HStack(spacing: 18) {
                imageControlButton(systemName: "arrow.counterclockwise.circle", action: onReset)
                imageControlButton(systemName: "shuffle.circle", action: onRandom)
                imageControlButton(
                    systemName: "arrowshape.left.circle",
                    isEnabled: canGoPrevious,
                    action: onPrevious
                )
                imageControlButton(
                    systemName: "arrowshape.right.circle",
                    isEnabled: canGoNext,
                    action: onNext
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
}
