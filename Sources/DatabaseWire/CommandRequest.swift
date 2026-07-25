import DatabaseKit
import DatabaseTypes

public struct CommandRequest: DatabaseWireValue, Hashable {
    public let command: CommandDeclaration
    public let input: FieldObject
    public let budget: ExecutionBudget

    public init(
        command: CommandDeclaration,
        input: FieldObject = FieldObject(),
        budget: ExecutionBudget = ExecutionBudget()
    ) {
        self.command = command
        self.input = input
        self.budget = budget
    }

    public func encode(
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try writer.writeString(command.identifier.rawValue)
        try command.access.encode(into: &writer)
        try input.encode(into: &writer)
        try budget.encode(into: &writer)
    }

    public init(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) {
        let rawIdentifier = try reader.readString(
            maximumUTF8Bytes: CommandIdentifier.maximumUTF8Bytes
        )
        let identifier: CommandIdentifier
        do {
            identifier = try CommandIdentifier(rawIdentifier)
        } catch let error {
            throw .invalidCommandIdentifier(error)
        }
        self.init(
            command: CommandDeclaration(
                identifier: identifier,
                access: try CommandAccess(from: &reader)
            ),
            input: try FieldObject(from: &reader),
            budget: try ExecutionBudget(from: &reader)
        )
    }
}
