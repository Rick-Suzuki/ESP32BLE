import SwiftUI

extension KeyboardScreen {
    var currentLayoutRows: [[KeyboardCell]] {
        switch currentKeyboardMode {
        case .mode1:
            return [topRowCells, secondRowCells, thirdRowCells, fourthRowCells, fifthRowCells, bottomRowCells]
        case .mode2:
            return [mode2TopRowCells, mode2SecondRowCells, mode2ThirdRowCells, mode2FourthRowCells, mode2BottomRowCells]
        case .mode3:
            return [mode3TopRowCells, mode3SecondRowCells, mode3ThirdRowCells, mode3BottomRowCells]
        case .mode4:
            return mode4Rows
        }
    }

    var currentColumnCount: Int {
        switch currentKeyboardMode {
        case .mode1:
            return 16
        case .mode2:
            return 13
        case .mode3:
            return 10
        case .mode4:
            return 20
        }
    }
}
