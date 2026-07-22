public enum DatabaseRDFDirection: String, Sendable, Hashable, Comparable,
    CaseIterable
{
    case leftToRight = "ltr"
    case rightToLeft = "rtl"

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
