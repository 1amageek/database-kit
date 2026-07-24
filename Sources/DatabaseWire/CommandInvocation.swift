import DatabaseTypes
public struct CommandInvocation<Command: CommandDescriptor>:
    DatabaseWireValue {
    public let input: Command.Input
    public let budget: ExecutionBudget

    public init(
        input: Command.Input,
        budget: ExecutionBudget = ExecutionBudget()
    ) {
        self.input = input
        self.budget = budget
    }

    public func encode(
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try CommandRequest.validateIdentifier(Command.identifier)
        try writer.writeString(Command.identifier)
        try Command.access.encode(into: &writer)
        try writer.writeLengthPrefixed {
            (payloadWriter: inout DatabaseWireWriter) throws(DatabaseWireError) in
            try input.encode(into: &payloadWriter)
        }
        try budget.encode(into: &writer)
    }

    public init(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) {
        let command = try reader.readString(
            maximumUTF8Bytes: CommandRequest.maximumIdentifierUTF8Bytes
        )
        try CommandRequest.validateIdentifier(command)
        guard command == Command.identifier else {
            throw .invalidCommandIdentifier(
                expected: Command.identifier,
                actual: command
            )
        }
        let actualAccess = try CommandAccess(from: &reader)
        guard actualAccess == Command.access else {
            throw .mismatchedCommandAccess(
                expected: Command.access.rawValue,
                actual: actualAccess.rawValue
            )
        }
        let input = try reader.readLengthPrefixed {
            (payloadReader: inout DatabaseWireReader) throws(DatabaseWireError) in
            try Command.Input(from: &payloadReader)
        }
        self.init(
            input: input,
            budget: try ExecutionBudget(from: &reader)
        )
    }
}
