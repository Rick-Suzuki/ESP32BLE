enum FunctionKeyDisplayMode: CaseIterable {
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
