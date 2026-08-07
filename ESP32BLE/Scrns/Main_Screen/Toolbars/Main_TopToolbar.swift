import SwiftUI

struct MainScreenToolbarContent: ToolbarContent {
    private let inactiveToolbarBackgroundColor = Color(red: 0.22, green: 0.22, blue: 0.24)
    private let normalToolbarBackgroundColor = Color(red: 0.32, green: 0.32, blue: 0.34)
    private let inactiveToolbarBorderColor = Color(red: 0.30, green: 0.30, blue: 0.32)
    private let normalToolbarBorderColor = Color(red: 0.46, green: 0.46, blue: 0.48)
    private let inactiveToolbarForegroundColor = Color(red: 0.55, green: 0.55, blue: 0.57)
   
	// Larger touch target for the opacity slider so drags reliably hit the control.
    private let opacitySliderHitHeight: CGFloat = 60
    // Extra horizontal touch area on each side of the opacity slider.
    private let opacitySliderHitHorizontalPadding: CGFloat = 60
    
	let isGridEditModeEnabled: Bool
    let editingSlotIndex: Int?
    let currentFileNumber: Int
    let totalFileCount: Int
    let currentBackgroundImageNumber: Int
    let totalBackgroundImageCount: Int
    @Binding var gridBackgroundOpacity: Double
    @Binding var isEditingDocumentName: Bool
    @Binding var documentNameDraft: String
    let selectedDocumentDisplayName: String
    let isHomeDocumentSelected: Bool
    let isDocumentNameFieldFocused: FocusState<Bool>.Binding
    let openKeyboardScreen: () -> Void
    let openHomeDocument: () -> Void
    let canGoBackToPreviousDocument: Bool
    let goBackToPreviousDocument: () -> Void
    let selectPreviousDocument: () -> Void
    let selectNextDocument: () -> Void
    let selectPreviousBackgroundImage: () -> Void
    let selectRandomBackgroundImage: () -> Void
    let selectNextBackgroundImage: () -> Void
    let toggleGridEditMode: () -> Void
    let commitDocumentRename: () -> Void
    let openSettings: AnyView

    var body: some ToolbarContent {
		//
		//----------------------------------------
		//
        ToolbarItem(placement: .principal) {
            HStack(spacing: 10) {
                Button {
                    ButtonClickFeedback.playIfEnabled()
					openHomeDocument()
                } label: {
                    Image(systemName: "house")
                        .font(.system(size: 22))
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .foregroundStyle(toolbarPrincipalForegroundColor)
                .disabled(isHomeDocumentSelected)
				//
				//----------------------------------------
				//
                Button {
                    ButtonClickFeedback.playIfEnabled()
                    goBackToPreviousDocument()
                } label: {
                    Image(systemName: "arrow.uturn.backward.circle")
                        .font(.system(size: 22))
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .foregroundStyle(toolbarPrincipalForegroundColor)
                .disabled(!canGoBackToPreviousDocument)
				//
				//----------------------------------------
				//
				// MARK: - BM:⬇️⬆️ main scrn: triangles, filename
                Button {
                    ButtonClickFeedback.playIfEnabled()
                    selectPreviousDocument()
                } label: {
                    Image(systemName: "triangle.fill")
                        .font(.system(size: 20))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .foregroundStyle(toolbarPrincipalForegroundColor)
                .disabled(currentFileNumber <= 1)

				Group {
                    if isEditingDocumentName {
                        TextField("Filename", text: $documentNameDraft)
                            .font(.headline)
                            .multilineTextAlignment(.center)
                            .textFieldStyle(.roundedBorder)
                            .submitLabel(.done)
                            .focused(isDocumentNameFieldFocused)
                            .onSubmit(commitDocumentRename)
                    } else {
                        Button {
                            ButtonClickFeedback.playIfEnabled()
                            documentNameDraft = selectedDocumentDisplayName
                            isEditingDocumentName = true
                        } label: {
                            Text(selectedDocumentDisplayName)
                                .font(.headline)
                                .foregroundStyle(toolbarPrincipalForegroundColor)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .disabled(isGridEditModeEnabled)
                    }
                }
                .frame(maxWidth: .infinity)

				Button {
					ButtonClickFeedback.playIfEnabled()
					selectNextDocument()
				} label: {
					Image(systemName: "triangle.fill")
						.font(.system(size: 20))
						.rotationEffect(.degrees(90))
						.frame(width: 44, height: 44)
						.contentShape(.rect)
				}
				.buttonStyle(.plain)
				.foregroundStyle(toolbarPrincipalForegroundColor)
				.disabled(currentFileNumber >= totalFileCount)
				//
				//----------------------------------------
				// MARK: - BM:🟧 select images
				//
				Button {
					ButtonClickFeedback.playIfEnabled()
					selectPreviousBackgroundImage()
				} label: {
					Image(systemName: "triangle.fill")
						.font(.system(size: 20))
						.rotationEffect(.degrees(-90))
						.frame(width: 44, height: 44)
						.contentShape(.rect)
				}
				.buttonStyle(.plain)
				.foregroundStyle(toolbarPrincipalForegroundColor)
				.disabled(currentBackgroundImageNumber <= 1)
				
					Button {
						ButtonClickFeedback.playIfEnabled()
						selectRandomBackgroundImage()
					} label: {
						Image(systemName: "photo.fill")
							.font(.system(size: 18, weight: .semibold))
							.frame(width: 33, height: 44)
							.contentShape(.rect)
					}
					.buttonStyle(.plain)
					.foregroundStyle(toolbarPrincipalForegroundColor)
					.disabled(totalBackgroundImageCount == 0)
				
                Button {
                    ButtonClickFeedback.playIfEnabled()
					selectNextBackgroundImage()
                } label: {
                    Image(systemName: "triangle.fill")
                        .font(.system(size: 20))
                        .rotationEffect(.degrees(90))
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .foregroundStyle(toolbarPrincipalForegroundColor)
                .disabled(currentBackgroundImageNumber >= totalBackgroundImageCount)
            }
        }
		
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 12) {
                WideHitSlider(
                    value: $gridBackgroundOpacity,
                    range: 0...1,
                    visualWidth: isPad ? 30 : 100,
                    hitHorizontalPadding: opacitySliderHitHorizontalPadding,
                    hitHeight: opacitySliderHitHeight,
                    isDisabled: editingSlotIndex != nil
                )

				
				Button("KB") {
					ButtonClickFeedback.playIfEnabled()
					openKeyboardScreen()
				}
				.font(.headline)
				.foregroundStyle(keyboardButtonForegroundColor)
				.padding(.horizontal, 5)
				.frame(minHeight: 44)
				.background(toolbarButtonBackgroundColor(normalBackground: normalToolbarBackgroundColor))
				.overlay {
					RoundedRectangle(cornerRadius: 23)
						.stroke(toolbarButtonBorderColor, lineWidth: 1.5)
				}
				.clipShape(.rect(cornerRadius: 23))
				.contentShape(.rect)
				.disabled(isGridEditModeEnabled || editingSlotIndex != nil)

				
				
                Button {
                    ButtonClickFeedback.playIfEnabled()
                    toggleGridEditMode()
                } label: {
                    Text(isGridEditModeEnabled ? "done" : "edit")
                        .font(.headline)
                        .foregroundStyle(toolbarActionForegroundColor)
                        .frame(minWidth: 84, minHeight: 44)
                        .background(toolbarButtonBackgroundColor(normalBackground: editModeButtonBackgroundColor))
                        .overlay {
                            RoundedRectangle(cornerRadius: 23)
                                .stroke(toolbarButtonBorderColor, lineWidth: 1.5)
                        }
                        .clipShape(.rect(cornerRadius: 23))
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(editingSlotIndex != nil)

                openSettings
                    .disabled(isGridEditModeEnabled)
            }
        }
    }

    private var editModeButtonBackgroundColor: Color {
        return isGridEditModeEnabled ? Color.blue : normalToolbarBackgroundColor
    }

    private var toolbarButtonBorderColor: Color {
        normalToolbarBorderColor
    }

    private func toolbarButtonBackgroundColor(normalBackground: Color) -> Color {
        normalBackground
    }

    private var toolbarActionForegroundColor: Color {
        editingSlotIndex != nil ? Color(white: 0.75) : .white
    }

    private var keyboardButtonForegroundColor: Color {
        (isGridEditModeEnabled || editingSlotIndex != nil) ? inactiveToolbarForegroundColor : .white
    }

    private var toolbarPrincipalForegroundColor: Color {
        isGridEditModeEnabled ? inactiveToolbarForegroundColor : .white
    }
}

private struct WideHitSlider_OLD: View {
    @Binding var value: Double

    let range: ClosedRange<Double>
    let visualWidth: CGFloat
    let hitHorizontalPadding: CGFloat
    let hitHeight: CGFloat
    let isDisabled: Bool

    var body: some View {
        Slider(value: $value, in: range)
            .tint(.white)
            .frame(width: visualWidth)
            .frame(width: visualWidth + hitHorizontalPadding * 2, height: hitHeight)
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        guard !isDisabled else { return }
                        updateValue(for: gesture.location.x)
                    }
            )
            .disabled(isDisabled)
    }

    private func updateValue(for locationX: CGFloat) {
        let clampedX = min(max(locationX - hitHorizontalPadding, 0), visualWidth)
        let percent = Double(clampedX / visualWidth)
        value = range.lowerBound + (range.upperBound - range.lowerBound) * percent
    }
}


private struct WideHitSlider: View {
	@Binding var value: Double
	
	let range: ClosedRange<Double>
	let step: Double = 0.05 // Adjust step increment as needed
	let visualWidth: CGFloat
	let hitHorizontalPadding: CGFloat
	let hitHeight: CGFloat
	let isDisabled: Bool
	
	var body: some View {
		HStack(spacing: 16) {
			// Decrement Button
			Button(action: decrementValue) {
				Image(systemName: "minus.circle.fill")
					.resizable()
					.scaledToFit()
			}
			.disabled(isDisabled || value < 0.1 /*range.lowerBound*/)
			
			// Increment Button
			Button(action: incrementValue) {
				Image(systemName: "plus.circle.fill")
					.resizable()
					.scaledToFit()
			}
			.disabled(isDisabled || value >= range.upperBound)
		}
		.tint(.white)
		.frame(width: visualWidth)
		.frame(width: visualWidth + hitHorizontalPadding , height: hitHeight)
		.contentShape(.rect)
		.disabled(isDisabled)
	}
	
	private func decrementValue() {
		let newValue = value - step
		value = max(newValue, range.lowerBound)
	}
	
	private func incrementValue() {
		let newValue = value + step
		value = min(newValue, range.upperBound)
	}
}

