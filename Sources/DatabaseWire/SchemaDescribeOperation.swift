public import DatabaseValue

public enum SchemaDescribeOperation: DatabaseOperation {
    public static let identifier = DatabaseOperationIdentifier.schemaDescribe
    public typealias Request = DatabaseEmpty

    public enum ValueType: UInt8, Sendable, Hashable {
        case bool = 1
        case int64 = 2
        case uint64 = 3
        case double = 4
        case decimal = 5
        case string = 6
        case bytes = 7
        case date = 8
        case timestamp = 9
        case array = 10
        case object = 11
        case reference = 12
        case rdfTerm = 13
        case uuid = 14
    }

    public enum ReferenceCardinality: UInt8, Sendable, Hashable {
        case requiredToOne = 1
        case optionalToOne = 2
        case toMany = 3
    }

    public enum ReferenceDeleteRule: UInt8, Sendable, Hashable {
        case nullify = 1
        case cascade = 2
        case deny = 3
        case noAction = 4
    }

    public struct Reference: Sendable, Hashable {
        public let targetEntity: String
        public let cardinality: ReferenceCardinality
        public let deleteRule: ReferenceDeleteRule

        public init(
            targetEntity: String,
            cardinality: ReferenceCardinality,
            deleteRule: ReferenceDeleteRule
        ) {
            self.targetEntity = targetEntity
            self.cardinality = cardinality
            self.deleteRule = deleteRule
        }

        fileprivate func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            try writer.writeString(targetEntity)
            writer.writeUInt8(cardinality.rawValue)
            writer.writeUInt8(deleteRule.rawValue)
        }

        fileprivate init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            let targetEntity = try reader.readString()
            let cardinalityRaw = try reader.readUInt8()
            guard let cardinality = ReferenceCardinality(rawValue: cardinalityRaw) else {
                throw .invalidReferenceCardinality(cardinalityRaw)
            }
            let deleteRuleRaw = try reader.readUInt8()
            guard let deleteRule = ReferenceDeleteRule(rawValue: deleteRuleRaw) else {
                throw .invalidReferenceDeleteRule(deleteRuleRaw)
            }
            self.init(
                targetEntity: targetEntity,
                cardinality: cardinality,
                deleteRule: deleteRule
            )
        }
    }

    public struct Field: Sendable, Hashable {
        public let number: UInt32
        public let name: String
        public let type: ValueType
        public let nullable: Bool
        public let reference: Reference?

        public init(
            number: UInt32,
            name: String,
            type: ValueType,
            nullable: Bool,
            reference: Reference? = nil
        ) {
            self.number = number
            self.name = name
            self.type = type
            self.nullable = nullable
            self.reference = reference
        }

        fileprivate func encode(into writer: inout DatabaseWireWriter) throws(DatabaseWireError) {
            writer.writeUInt32(number)
            try writer.writeString(name)
            writer.writeUInt8(type.rawValue)
            writer.writeBool(nullable)
            writer.writeBool(reference != nil)
            if let reference {
                try reference.encode(into: &writer)
            }
        }

        fileprivate init(from reader: inout DatabaseWireReader) throws(DatabaseWireError) {
            let number = try reader.readUInt32()
            let name = try reader.readString()
            let rawType = try reader.readUInt8()
            guard let type = ValueType(rawValue: rawType) else {
                throw .unknownFieldType(rawType)
            }
            let nullable = try reader.readBool()
            let reference = try reader.readBool()
                ? Reference(from: &reader)
                : nil
            self.init(
                number: number,
                name: name,
                type: type,
                nullable: nullable,
                reference: reference
            )
        }
    }

    public struct Index: Sendable, Hashable {
        public let name: String
        public let kind: String
        public let fields: [UInt32]
        public let options: [DatabaseObjectField]

        public init(
            name: String,
            kind: String,
            fields: [UInt32],
            options: [DatabaseObjectField] = []
        ) {
            self.name = name
            self.kind = kind
            self.fields = fields
            self.options = options
        }

        fileprivate func encode(into writer: inout DatabaseWireWriter) throws(DatabaseWireError) {
            try writer.writeString(name)
            try writer.writeString(kind)
            try writer.writeCount(fields.count)
            for field in fields { writer.writeUInt32(field) }
            try writer.writeCount(options.count)
            for option in options { try option.encode(into: &writer) }
        }

        fileprivate init(from reader: inout DatabaseWireReader) throws(DatabaseWireError) {
            let name = try reader.readString()
            let kind = try reader.readString()
            let fieldCount = try reader.readCount()
            var fields: [UInt32] = []
            fields.reserveCapacity(fieldCount)
            for _ in 0..<fieldCount { fields.append(try reader.readUInt32()) }
            let optionCount = try reader.readCount()
            var options: [DatabaseObjectField] = []
            options.reserveCapacity(optionCount)
            for _ in 0..<optionCount {
                options.append(try DatabaseObjectField(from: &reader))
            }
            self.init(name: name, kind: kind, fields: fields, options: options)
        }
    }

    public struct Entity: Sendable, Hashable {
        public let name: String
        public let fields: [Field]
        public let indexes: [Index]

        public init(name: String, fields: [Field], indexes: [Index]) {
            self.name = name
            self.fields = fields
            self.indexes = indexes
        }

        fileprivate func encode(into writer: inout DatabaseWireWriter) throws(DatabaseWireError) {
            try writer.writeString(name)
            try writer.writeCount(fields.count)
            for field in fields { try field.encode(into: &writer) }
            try writer.writeCount(indexes.count)
            for index in indexes { try index.encode(into: &writer) }
        }

        fileprivate init(from reader: inout DatabaseWireReader) throws(DatabaseWireError) {
            let name = try reader.readString()
            let fieldCount = try reader.readCount()
            var fields: [Field] = []
            fields.reserveCapacity(fieldCount)
            for _ in 0..<fieldCount { fields.append(try Field(from: &reader)) }
            let indexCount = try reader.readCount()
            var indexes: [Index] = []
            indexes.reserveCapacity(indexCount)
            for _ in 0..<indexCount { indexes.append(try Index(from: &reader)) }
            self.init(name: name, fields: fields, indexes: indexes)
        }
    }

    public struct Response: DatabaseWireValue, Hashable {
        public let version: DatabaseSchemaVersion
        public let entities: [Entity]

        public init(version: DatabaseSchemaVersion, entities: [Entity]) {
            self.version = version
            self.entities = entities
        }

        public func encode(into writer: inout DatabaseWireWriter) throws(DatabaseWireError) {
            try version.encode(into: &writer)
            try writer.writeCount(entities.count)
            for entity in entities { try entity.encode(into: &writer) }
        }

        public init(from reader: inout DatabaseWireReader) throws(DatabaseWireError) {
            let version = try DatabaseSchemaVersion(from: &reader)
            let count = try reader.readCount()
            var entities: [Entity] = []
            entities.reserveCapacity(count)
            for _ in 0..<count { entities.append(try Entity(from: &reader)) }
            self.init(version: version, entities: entities)
        }
    }
}
