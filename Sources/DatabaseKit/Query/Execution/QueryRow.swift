import DatabaseTypes

/// One final positional row retaining its canonical value owners.
public struct QueryRow: Sendable, Hashable {
    public let values: [QueryValue]
    public let annotations: FieldObject
    public let version: ByteString?

    public init(
        values: [QueryValue],
        annotations: FieldObject = FieldObject(),
        version: ByteString? = nil
    ) {
        self.values = values
        self.annotations = annotations
        self.version = version
    }
}
