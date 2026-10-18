import DatabaseTypes

/// One request-owned COPY transfer; input bytes remain retained by their ByteString owner.
public struct SQLCopyCommand: Sendable, Hashable {
    public let target: SQLCopyTarget
    public let direction: SQLCopyDirection
    public let options: SQLCopyOptions
    public let data: ByteString?
    public init(target: SQLCopyTarget, direction: SQLCopyDirection,
                options: SQLCopyOptions = .default, data: ByteString? = nil) {
        self.target = target; self.direction = direction; self.options = options; self.data = data
    }
}
