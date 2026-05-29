import Foundation

enum FunctionKeyDisplayMode: CaseIterable {
    case left
    case right
    case last
    case both

    init?(persistedValue: String) {
        switch persistedValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "left", "left cmd":
            self = .left
        case "right", "right text":
            self = .right
        case "last", "last txt", "last text":
            self = .last
        case "both", "both text", "both texts":
            self = .both
        default:
            return nil
        }
    }

    func next() -> Self {
        switch self {
        case .left:
            return .right
        case .right:
            return .last
        case .last:
            return .both
        case .both:
            return .left
        }
    }

    var persistedValue: String {
        switch self {
        case .left:
            return "left cmd"
        case .right:
            return "right text"
        case .last:
            return "last text"
        case .both:
            return "both texts"
        }
    }

    var title: String {
        switch self {
        case .left:
            return "Left cmd"
        case .right:
            return "Right text"
        case .last:
            return "Last txt"
        case .both:
            return "Both texts"
        }
    }
}
