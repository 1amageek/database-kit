import DatabaseTypes

/// A retained, typed row result whose retrieval is owned by its runtime.
public protocol QueryRows: AsyncSequence, Sendable where Element == QueryRow {
    static var empty: Self { get }
    var columns: [QueryColumn] { get }
    var affectedRows: UInt64? { get }
    var metadata: FieldObject { get }
}
