import DatabaseTypes

public struct CommandRequest: DatabaseWireValue, Hashable {
    public static let maximumIdentifierUTF8Bytes = 256

    public let command: String
    public let access: CommandAccess
    public let input: ByteString
    public let budget: ExecutionBudget

    public init(
        command: String,
        access: CommandAccess,
        input: ByteString = [],
        budget: ExecutionBudget = ExecutionBudget()
    ) {
        self.command = command
        self.access = access
        self.input = input
        self.budget = budget
    }

    public func encode(
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try Self.validateIdentifier(command)
        try writer.writeString(command)
        try access.encode(into: &writer)
        try writer.writeBytes(input)
        try budget.encode(into: &writer)
    }

    public init(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) {
        self.init(
            command: try reader.readString(
                maximumUTF8Bytes: Self.maximumIdentifierUTF8Bytes
            ),
            access: try CommandAccess(from: &reader),
            input: try reader.readBytes(),
            budget: try ExecutionBudget(from: &reader)
        )
        try Self.validateIdentifier(command)
    }

    package static func validateIdentifier(
        _ identifier: String
    ) throws(DatabaseWireError) {
        guard !identifier.isEmpty else {
            throw .invalidCommandIdentifierValue
        }
        let byteCount = identifier.utf8.count
        guard byteCount <= maximumIdentifierUTF8Bytes else {
            throw .stringTooLarge(
                actual: byteCount,
                maximum: maximumIdentifierUTF8Bytes
            )
        }
    }
}
