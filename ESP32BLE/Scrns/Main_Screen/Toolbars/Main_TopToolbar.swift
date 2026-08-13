//
//-----------------------------------------------------------------------------------------------
//
import SwiftUI
//
//-----------------------------------------------------------------------------------------------
// MARK: - BM:🟧 main screen - top toolbar
//
struct MainScreenToolbarContent: View {
    private let inactiveToolbarBackgroundColor = Color(red: 0.22, green: 0.22, blue: 0.24)
	private let normalToolbarBackgroundColor = Color(red: 0.32, green: 0.32, blue: 0.34).opacity(0.4)
    private let inactiveToolbarBorderColor = Color(red: 0.30, green: 0.30, blue: 0.32)
    private let normalToolbarBorderColor = Color(red: 0.46, green: 0.46, blue: 0.48)
    private let inactiveToolbarForegroundColor = Color(red: 0.55, green: 0.55, blue: 0.57)
   
	// Larger touch target for the opacity slider so drags reliably hit the control.
    private let opacitySliderHitHeight: CGFloat = 44
    // Extra horizontal touch area on each side of the opacity slider.
    private let opacitySliderHitHorizontalPadding: CGFloat = 60
    
	let isGridEditModeEnabled: Bool
    let editingSlotIndex: Int?
    let currentFileNumber: Int
    let totalFileCount: Int
    let currentBackgroundImageNumber: Int
    let totalBackgroundImageCount: Int
    @Binding var backgroundImageOpacity: Double
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
	//
	//-----------------------------------------------------------------------------------------------
	//
    var body: some View {
		//
		//----------------------------------------
		//
		HStack() {
			//
			//----------------------------------------
			// home btn
			//
				Button {
					db("ENTER MainScreenToolbarContent.homeButton current isHomeDocumentSelected=\(isHomeDocumentSelected) new=openHomeDocument thread=\(Thread.isMainThread ? "main" : "background")")
					ButtonClickFeedback.playIfEnabled()
					openHomeDocument()
					db("EXIT MainScreenToolbarContent.homeButton current isHomeDocumentSelected=\(isHomeDocumentSelected) new=openHomeDocument complete thread=\(Thread.isMainThread ? "main" : "background")")
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
			// go back btn
			//
				Button {
					db("ENTER MainScreenToolbarContent.goBackButton current canGoBackToPreviousDocument=\(canGoBackToPreviousDocument) new=goBackToPreviousDocument thread=\(Thread.isMainThread ? "main" : "background")")
					ButtonClickFeedback.playIfEnabled()
					goBackToPreviousDocument()
					db("EXIT MainScreenToolbarContent.goBackButton current canGoBackToPreviousDocument=\(canGoBackToPreviousDocument) new=goBackToPreviousDocument complete thread=\(Thread.isMainThread ? "main" : "background")")
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
			// previous btn
			//
				Button {
					db("ENTER MainScreenToolbarContent.previousDocumentButton current currentFileNumber=\(currentFileNumber) new=selectPreviousDocument thread=\(Thread.isMainThread ? "main" : "background")")
					ButtonClickFeedback.playIfEnabled()
					selectPreviousDocument()
					db("EXIT MainScreenToolbarContent.previousDocumentButton current currentFileNumber=\(currentFileNumber) new=selectPreviousDocument complete thread=\(Thread.isMainThread ? "main" : "background")")
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
			//
			//----------------------------------------
			// document name
			//
			Text(selectedDocumentDisplayName)
				.font(.headline)
				.foregroundStyle(toolbarPrincipalForegroundColor)
				.frame(maxWidth: 150)
				.lineLimit(1) // <--- Restricts text to 1 line
				.truncationMode(.tail) // Truncates with "..." if text exceeds width
			//
			//----------------------------------------
			// next doc btn
				Button {
					db("ENTER MainScreenToolbarContent.nextDocumentButton current currentFileNumber=\(currentFileNumber) new=selectNextDocument thread=\(Thread.isMainThread ? "main" : "background")")
					ButtonClickFeedback.playIfEnabled()
					selectNextDocument()
					db("EXIT MainScreenToolbarContent.nextDocumentButton current currentFileNumber=\(currentFileNumber) new=selectNextDocument complete thread=\(Thread.isMainThread ? "main" : "background")")
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
			// prev image
			//
			Spacer()
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
			.foregroundStyle(.cyan)
			.disabled(currentBackgroundImageNumber <= 1)
			//
			//----------------------------------------
			// rnd image
			//
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
			.foregroundStyle(.cyan)
			.disabled(totalBackgroundImageCount == 0)
			//
			//----------------------------------------
			// next img
			//
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
			.foregroundStyle(.cyan)
			.disabled(currentBackgroundImageNumber >= totalBackgroundImageCount)
			//
			//----------------------------------------
			// background opacity +/- btns
			//
			minusPlusBtns(
				value: $backgroundImageOpacity,
				range: 0...1,
				visualWidth: isPad ? 30 : 100,
				hitHorizontalPadding: opacitySliderHitHorizontalPadding,
				hitHeight: opacitySliderHitHeight,
				isDisabled: editingSlotIndex != nil,
				bc:.cyan
			)
			//
			//----------------------------------------
			//
			Spacer()
			//
			//----------------------------------------
			// grid opacity +/- btns
			//
			minusPlusBtns(
				value: $gridBackgroundOpacity,
				range: 0...1,
				visualWidth: isPad ? 30 : 100,
				hitHorizontalPadding: opacitySliderHitHorizontalPadding,
				hitHeight: opacitySliderHitHeight,
				isDisabled: editingSlotIndex != nil,
				bc:.yellow
			)
			//
			//----------------------------------------
			//
			Spacer()
			//
			//----------------------------------------
			// to keyboard btn
			//
			Button("KB") {
				db("ENTER MainScreenToolbarContent.keyboardButton current isGridEditModeEnabled=\(isGridEditModeEnabled) editingSlotIndex=\(String(describing: editingSlotIndex)) new=openKeyboardScreen thread=\(Thread.isMainThread ? "main" : "background")")
				ButtonClickFeedback.playIfEnabled()
				openKeyboardScreen()
				db("EXIT MainScreenToolbarContent.keyboardButton current isGridEditModeEnabled=\(isGridEditModeEnabled) editingSlotIndex=\(String(describing: editingSlotIndex)) new=openKeyboardScreen complete thread=\(Thread.isMainThread ? "main" : "background")")
			}
			.font(.headline)
			.foregroundStyle(keyboardButtonForegroundColor)
			.padding(.horizontal, 5)
			.frame(minHeight: 36)
			.frame(width: 60)

			.background(toolbarButtonBackgroundColor(normalBackground: normalToolbarBackgroundColor))
			.overlay {
				RoundedRectangle(cornerRadius: 10)
					.stroke(toolbarButtonBorderColor, lineWidth: 1.5)
			}
			.clipShape(.rect(cornerRadius: 10))
			.contentShape(.rect)
			.disabled(isGridEditModeEnabled || editingSlotIndex != nil)
			//
			//----------------------------------------
			// edit btn
			//
			Button {
				ButtonClickFeedback.playIfEnabled()
				toggleGridEditMode()
			} label: {
				Text(isGridEditModeEnabled ? "done" : "edit")
					.font(.headline)
					.foregroundStyle(toolbarActionForegroundColor)
					.frame(minWidth: 84, minHeight: 36)
					.background(toolbarButtonBackgroundColor(normalBackground: editModeButtonBackgroundColor))
					.overlay {
						RoundedRectangle(cornerRadius: 10)
							.stroke(toolbarButtonBorderColor, lineWidth: 1.5)
					}
					.clipShape(.rect(cornerRadius: 10))
					.contentShape(.rect)
			}
			.buttonStyle(.plain)
			.disabled(editingSlotIndex != nil)
			//
			//----------------------------------------
			// goto settings btn
			//
			openSettings
				.disabled(isGridEditModeEnabled)
			//
			//----------------------------------------
			//
		}   // END HS
		.frame(maxWidth: .infinity)

	}
	//
	//-----------------------------------------------------------------------------------------------
	//
    private var editModeButtonBackgroundColor: Color {
        return isGridEditModeEnabled ? Color.blue : normalToolbarBackgroundColor
    }
	//
	//----------------------------------------
	//
    private var toolbarButtonBorderColor: Color {
        normalToolbarBorderColor
    }
	//
	//----------------------------------------
	//
    private func toolbarButtonBackgroundColor(normalBackground: Color) -> Color {
        normalBackground
    }
	//
	//----------------------------------------
	//
    private var toolbarActionForegroundColor: Color {
        editingSlotIndex != nil ? Color(white: 0.75) : .white
    }
	//
	//----------------------------------------
	//
    private var keyboardButtonForegroundColor: Color {
        (isGridEditModeEnabled || editingSlotIndex != nil) ? inactiveToolbarForegroundColor : .white
    }
	//
	//----------------------------------------
	//
    private var toolbarPrincipalForegroundColor: Color {
        isGridEditModeEnabled ? inactiveToolbarForegroundColor : .white
    }
}
//
//----------------------------------------
//
private struct minusPlusBtns: View {
	@Binding var value: Double
	
	let range: ClosedRange<Double>
	let step: Double = 0.05 // Adjust step increment as needed
	let visualWidth: CGFloat
	let hitHorizontalPadding: CGFloat
	let hitHeight: CGFloat
	let isDisabled: Bool
	let bc:Color
	
	var body: some View {
		HStack(spacing: 16) {
			// Decrement Button
			Button(action: decrementValue) {
				Image(systemName: "minus.circle.fill")
					.resizable()
					.scaledToFit()
					.frame(width: 30, height: 30)
					.foregroundStyle(bc)
				}
			.disabled(isDisabled || value < 0.1 /*range.lowerBound*/)
			
			// Increment Button
			Button(action: incrementValue) {
				Image(systemName: "plus.circle.fill")
					.resizable()
					.scaledToFit()
					.frame(width: 30, height: 30)
					.foregroundStyle(bc)
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
//
//-----------------------------------------------------------------------------------------------
//
