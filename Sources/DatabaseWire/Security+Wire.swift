import DatabaseKit

extension Security.Access: WireValue {
    func encode(
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        guard !isEmpty, containsOnlyKnownPermissions else {
            throw .invalidSecurityAccess(rawValue)
        }
        writer.writeUInt8(rawValue)
    }

    init(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) {
        let rawValue = try reader.readUInt8()
        let access = Self(rawValue: rawValue)
        guard !access.isEmpty, access.containsOnlyKnownPermissions else {
            throw .invalidSecurityAccess(rawValue)
        }
        self = access
    }
}

extension Security.Resource: WireValue {
    func encode(
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        switch self {
        case .database:
            writer.writeUInt8(0)
        case .base(let baseID):
            writer.writeUInt8(1)
            try baseID.encode(into: &writer)
        }
    }

    init(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) {
        switch try reader.readUInt8() {
        case 0:
            self = .database
        case 1:
            self = .base(try Base.ID(from: &reader))
        case let tag:
            throw .invalidSecurityResource(tag)
        }
    }
}

extension Security.Subject: WireValue {
    func encode(
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        switch self {
        case .principal(let identifier):
            guard !identifier.isEmpty else {
                throw .emptySecuritySubject
            }
            writer.writeUInt8(0)
            try writer.writeString(identifier)
        case .principalRole(let role):
            guard !role.isEmpty else {
                throw .emptySecuritySubject
            }
            writer.writeUInt8(1)
            try writer.writeString(role)
        }
    }

    init(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) {
        let tag = try reader.readUInt8()
        let value = try reader.readString()
        guard !value.isEmpty else {
            throw .emptySecuritySubject
        }
        switch tag {
        case 0:
            self = .principal(value)
        case 1:
            self = .principalRole(value)
        default:
            throw .invalidSecuritySubject(tag)
        }
    }
}

extension Security.Grant: WireValue {
    func encode(
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try subject.encode(into: &writer)
        try resource.encode(into: &writer)
        try access.encode(into: &writer)
    }

    init(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) {
        self.init(
            subject: try Security.Subject(from: &reader),
            resource: try Security.Resource(from: &reader),
            access: try Security.Access(from: &reader)
        )
    }
}
