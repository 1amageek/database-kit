public struct DatabaseTypedCommandRequest<Command: DatabaseCommandDescriptor>:
    DatabaseWireValue {
    public let input: Command.Input
    public let budget: DatabaseExecutionBudget

    public init(
        input: Command.Input,
        budget: DatabaseExecutionBudget = DatabaseExecutionBudget()
    ) {
        self.input = input
        self.budget = budget
    }

    public func encode(
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try writer.writeString(Command.identifier)
        try writer.writeLengthPrefixed {
            (payloadWriter: inout DatabaseWireWriter) throws(DatabaseWireError) in
            try input.encode(into: &payloadWriter)
        }
        try budget.encode(into: &writer)
    }

    public init(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) {
        let command = try reader.readString()
        guard command == Command.identifier else {
            throw .invalidCommandIdentifier(
                expected: Command.identifier,
                actual: command
            )
        }
        let input = try reader.readLengthPrefixed {
            (payloadReader: inout DatabaseWireReader) throws(DatabaseWireError) in
            try Command.Input(from: &payloadReader)
        }
        self.init(
            input: input,
            budget: try DatabaseExecutionBudget(from: &reader)
        )
    }
}
