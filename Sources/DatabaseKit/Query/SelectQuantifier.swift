public enum SelectQuantifier: Sendable, Hashable {
    case all
    case distinct
    case distinctOn([Expression])
}
