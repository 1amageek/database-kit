import DatabaseKit
import DatabaseTypes

extension DomainReadPoint: WireValue {
    func encode(
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        do {
            _ = try Base.ID(domainID)
        } catch let error {
            throw .invalidBaseIdentifier(error)
        }
        try writer.writeString(domainID)
        switch position {
        case .version(let version):
            writer.writeUInt8(0)
            writer.writeUInt64(version)
        case .opaque(let snapshot):
            guard !snapshot.isEmpty else {
                throw .invalidDomainReadPoint
            }
            writer.writeUInt8(1)
            try writer.writeBytes(snapshot)
        }
    }

    init(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) {
        let domainID = try reader.readString()
        let position: Position
        switch try reader.readUInt8() {
        case 0:
            position = .version(try reader.readUInt64())
        case 1:
            let snapshot = try reader.readBytes()
            guard !snapshot.isEmpty else {
                throw .invalidDomainReadPoint
            }
            position = .opaque(snapshot)
        case let tag:
            throw .invalidDomainReadPointPosition(tag)
        }
        do {
            try self.init(domainID: domainID, position: position)
        } catch let error {
            throw .invalidBaseIdentifier(error)
        }
    }
}

extension DatabaseReadConsistency: WireValue {
    func encode(
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        switch self {
        case .transactional(let readPoint):
            writer.writeUInt8(0)
            try readPoint.encode(into: &writer)
        case .federated(let readPoints):
            try Self.validateFederated(readPoints)
            writer.writeUInt8(1)
            try writer.writeCount(readPoints.count)
            for readPoint in readPoints {
                try readPoint.encode(into: &writer)
            }
        }
    }

    init(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) {
        switch try reader.readUInt8() {
        case 0:
            self = .transactional(try DomainReadPoint(from: &reader))
        case 1:
            let count = try reader.readCount()
            var readPoints: [DomainReadPoint] = []
            readPoints.reserveCapacity(count)
            for _ in 0..<count {
                readPoints.append(try DomainReadPoint(from: &reader))
            }
            try Self.validateFederated(readPoints)
            self = .federated(readPoints)
        case let tag:
            throw .invalidReadConsistency(tag)
        }
    }

    private static func validateFederated(
        _ readPoints: [DomainReadPoint]
    ) throws(DatabaseWireError) {
        guard !readPoints.isEmpty else {
            throw .invalidFederatedReadPoints
        }
        for (previous, current) in zip(
            readPoints,
            readPoints.dropFirst()
        ) {
            guard previous.domainID < current.domainID else {
                throw .invalidFederatedReadPoints
            }
        }
    }
}
