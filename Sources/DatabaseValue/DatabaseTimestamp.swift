public struct DatabaseTimestamp: Sendable, Hashable, Comparable {
    public let secondsSinceUnixEpoch: Int64
    public let nanoseconds: UInt32

    public init(secondsSinceUnixEpoch: Int64, nanoseconds: UInt32 = 0) {
        self.secondsSinceUnixEpoch = secondsSinceUnixEpoch
        self.nanoseconds = nanoseconds
    }

    public static func < (lhs: DatabaseTimestamp, rhs: DatabaseTimestamp) -> Bool {
        if lhs.secondsSinceUnixEpoch != rhs.secondsSinceUnixEpoch {
            return lhs.secondsSinceUnixEpoch < rhs.secondsSinceUnixEpoch
        }
        return lhs.nanoseconds < rhs.nanoseconds
    }
}
