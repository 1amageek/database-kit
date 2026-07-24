import DatabaseTypes
import DatabaseValue

public struct DatabaseCommandRequest: DatabaseWireValue, Hashable {
    public let command: String
    public let input: ByteString
    public let budget: ExecutionBudget

    public init(
        command: String,
        input: ByteString = [],
        budget: ExecutionBudget = ExecutionBudget()
    ) {
        self.command = command
        self.input = input
        self.budget = budget
    }

    public func encode(
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try writer.writeString(command)
        try writer.writeBytes(input)
        try budget.encode(into: &writer)
    }

    public init(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) {
        self.init(
            command: try reader.readString(),
            input: try reader.readBytes(),
            budget: try ExecutionBudget(from: &reader)
        )
    }
}
