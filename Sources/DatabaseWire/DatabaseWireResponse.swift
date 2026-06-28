/// Status code for wire database responses.
public enum DatabaseWireResponseStatus: UInt8, Sendable, Hashable {
    case ok = 1
    case invalidRequest = 2
    case executionFailure = 3
    case unsupported = 4

    public init(from reader: inout DatabaseWireBinaryReader) throws(DatabaseWireError) {
        let tag = try reader.readUInt8()
        guard let status = DatabaseWireResponseStatus(rawValue: tag) else {
            throw DatabaseWireError.unknownResponseStatus(tag)
        }
        self = status
    }

    public func encode(into writer: inout DatabaseWireBinaryWriter) {
        writer.writeUInt8(rawValue)
    }
}

/// Top-level wire database response envelope.
public enum DatabaseWireResponse: Sendable, Hashable {
    case empty
    case record(DatabaseWireRecord?)
    case records([DatabaseWireRecord])
    case failure(status: DatabaseWireResponseStatus, message: String)

    private enum Payload: UInt8 {
        case empty = 1
        case record = 2
        case records = 3
    }

    public func encode(into writer: inout DatabaseWireBinaryWriter) throws(DatabaseWireError) {
        switch self {
        case .empty:
            DatabaseWireResponseStatus.ok.encode(into: &writer)
            writer.writeUInt8(Payload.empty.rawValue)
        case .record(let record):
            DatabaseWireResponseStatus.ok.encode(into: &writer)
            writer.writeUInt8(Payload.record.rawValue)
            if let record {
                writer.writeBool(true)
                try record.encode(into: &writer)
            } else {
                writer.writeBool(false)
            }
        case .records(let records):
            DatabaseWireResponseStatus.ok.encode(into: &writer)
            writer.writeUInt8(Payload.records.rawValue)
            try writer.writeCount(records.count)
            for record in records {
                try record.encode(into: &writer)
            }
        case .failure(let status, let message):
            status.encode(into: &writer)
            try writer.writeString(message)
        }
    }

    public init(from reader: inout DatabaseWireBinaryReader) throws(DatabaseWireError) {
        let status = try DatabaseWireResponseStatus(from: &reader)
        guard status == .ok else {
            self = .failure(status: status, message: try reader.readString())
            return
        }

        let payloadTag = try reader.readUInt8()
        guard let payload = Payload(rawValue: payloadTag) else {
            throw DatabaseWireError.unknownResponsePayload(payloadTag)
        }
        switch payload {
        case .empty:
            self = .empty
        case .record:
            if try reader.readBool() {
                self = .record(try DatabaseWireRecord(from: &reader))
            } else {
                self = .record(nil)
            }
        case .records:
            let count = try reader.readCount()
            var records: [DatabaseWireRecord] = []
            records.reserveCapacity(count)
            for _ in 0..<count {
                records.append(try DatabaseWireRecord(from: &reader))
            }
            self = .records(records)
        }
    }
}
