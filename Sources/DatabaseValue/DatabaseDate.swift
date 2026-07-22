public struct DatabaseDate: Sendable, Hashable, Comparable {
    public let year: Int32
    public let month: UInt8
    public let day: UInt8

    public init(year: Int32, month: UInt8, day: UInt8) {
        self.year = year
        self.month = month
        self.day = day
    }

    public static func < (lhs: DatabaseDate, rhs: DatabaseDate) -> Bool {
        if lhs.year != rhs.year { return lhs.year < rhs.year }
        if lhs.month != rhs.month { return lhs.month < rhs.month }
        return lhs.day < rhs.day
    }
}
