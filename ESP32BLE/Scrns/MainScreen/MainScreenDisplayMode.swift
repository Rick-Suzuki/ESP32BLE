enum FunctionKeyDisplayMode: CaseIterable {
    case left
    case right
    case last
    case both

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
