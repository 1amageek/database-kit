import DatabaseTypes
public enum DatabaseOperationIdentifier: UInt16, Sendable, Hashable, CaseIterable {
    case capabilitiesDescribe = 0x0101
    case schemaDescribe = 0x0102
    case schemaExecute = 0x0103
    case queryExecute = 0x0201
    case mutationExecute = 0x0301
    case graphAlgorithm = 0x0401
    case ontologyExecute = 0x0501
    case shaclExecute = 0x0601
    case commandExecute = 0x0701
    case maintenanceExecute = 0x0801
    case jobStart = 0x0901
    case jobStatus = 0x0902
    case jobResult = 0x0903
    case jobCancel = 0x0904

    func encode(into writer: inout DatabaseWireWriter) {
        writer.writeUInt16(rawValue)
    }

    init(from reader: inout DatabaseWireReader) throws(DatabaseWireError) {
        let rawValue = try reader.readUInt16()
        guard let value = Self(rawValue: rawValue) else {
            throw .invalidOperationIdentifier(rawValue)
        }
        self = value
    }
}
