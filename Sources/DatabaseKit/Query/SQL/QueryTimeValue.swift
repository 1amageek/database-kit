/// A SQL wall-clock time, including the distinct 24:00 endpoint.
public struct QueryTimeValue: Sendable, Hashable {
    public let microsecondsSinceMidnight: Int64

    public init(microsecondsSinceMidnight: Int64) throws(QueryValueError) {
        guard (0...86_400_000_000).contains(microsecondsSinceMidnight) else {
            throw .timeOutOfRange
        }
        self.microsecondsSinceMidnight = microsecondsSinceMidnight
    }
}
