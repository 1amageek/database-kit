/// Wire index descriptor.
public struct DatabaseWireIndexDescriptor: Sendable, Hashable {
    public let name: String
    public let kind: DatabaseWireIndexKind
    public let fields: [String]
    public let unique: Bool
    public let parameters: [DatabaseWireNamedValue]

    public init(
        name: String,
        kind: DatabaseWireIndexKind,
        fields: [String],
        unique: Bool = false,
        parameters: [DatabaseWireNamedValue] = []
    ) {
        self.name = name
        self.kind = kind
        self.fields = fields
        self.unique = unique
        self.parameters = parameters
    }

    public func encode(into writer: inout DatabaseWireBinaryWriter) throws(DatabaseWireError) {
        try writer.writeString(name)
        try kind.encode(into: &writer)
        try writer.writeCount(fields.count)
        for field in fields {
            try writer.writeString(field)
        }
        writer.writeBool(unique)
        try writer.writeCount(parameters.count)
        for parameter in parameters {
            try parameter.encode(into: &writer)
        }
    }

    public init(from reader: inout DatabaseWireBinaryReader) throws(DatabaseWireError) {
        self.name = try reader.readString()
        self.kind = try DatabaseWireIndexKind(from: &reader)
        let count = try reader.readCount()
        var fields: [String] = []
        fields.reserveCapacity(count)
        for _ in 0..<count {
            fields.append(try reader.readString())
        }
        self.fields = fields
        self.unique = try reader.readBool()
        let parameterCount = try reader.readCount()
        var parameters: [DatabaseWireNamedValue] = []
        parameters.reserveCapacity(parameterCount)
        for _ in 0..<parameterCount {
            parameters.append(try DatabaseWireNamedValue(from: &reader))
        }
        self.parameters = parameters
    }
}
