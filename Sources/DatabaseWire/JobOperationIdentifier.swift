import DatabaseTypes
/// Canonical identifier for one resumable job operation.
public struct JobOperationIdentifier:
    Hashable {
    public static let maximumKindUTF8Bytes = 128

    public let family: DatabaseOperationIdentifier
    public let kind: String

    public init(
        family: DatabaseOperationIdentifier,
        kind: String
    ) throws(DatabaseWireError) {
        guard Self.supportsJobs(family) else {
            throw .invalidJobOperationFamily(family.rawValue)
        }
        guard Self.isCanonicalKind(kind) else {
            throw .invalidJobOperationKind
        }
        self.family = family
        self.kind = kind
    }

    init(
        validatedFamily family: DatabaseOperationIdentifier,
        validatedKind kind: String
    ) {
        self.family = family
        self.kind = kind
    }

    @_spi(DatabaseOperations)
    public func encode(
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        guard Self.supportsJobs(family) else {
            throw .invalidJobOperationFamily(family.rawValue)
        }
        guard Self.isCanonicalKind(kind) else {
            throw .invalidJobOperationKind
        }
        family.encode(into: &writer)
        try writer.writeString(kind)
    }

    @_spi(DatabaseOperations)
    public init(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) {
        try self.init(
            family: DatabaseOperationIdentifier(from: &reader),
            kind: reader.readString(
                maximumUTF8Bytes: Self.maximumKindUTF8Bytes
            )
        )
    }

    public func lexicographicallyPrecedes(
        _ other: JobOperationIdentifier
    ) -> Bool {
        if family.rawValue != other.family.rawValue {
            return family.rawValue < other.family.rawValue
        }
        return kind.utf8.lexicographicallyPrecedes(other.kind.utf8)
    }

    private static func supportsJobs(
        _ family: DatabaseOperationIdentifier
    ) -> Bool {
        switch family {
        case .schemaExecute,
             .baseExecute,
             .queryExecute,
             .mutationExecute,
             .graphAlgorithm,
             .ontologyExecute,
             .shaclExecute,
             .commandExecute,
             .maintenanceExecute:
            return true
        case .capabilitiesDescribe,
             .schemaDescribe,
             .compositionExecute,
             .grantExecute,
             .jobStart,
             .jobStatus,
             .jobResult,
             .jobCancel:
            return false
        }
    }

    private static func isCanonicalKind(_ kind: String) -> Bool {
        let utf8 = kind.utf8
        guard !utf8.isEmpty,
              utf8.count <= maximumKindUTF8Bytes else {
            return false
        }
        var previousWasSeparator = true
        for byte in utf8 {
            let isLowercaseLetter = byte >= 0x61 && byte <= 0x7a
            let isDigit = byte >= 0x30 && byte <= 0x39
            if isLowercaseLetter || isDigit {
                previousWasSeparator = false
                continue
            }
            guard (byte == 0x2d || byte == 0x2e),
                  !previousWasSeparator else {
                return false
            }
            previousWasSeparator = true
        }
        return !previousWasSeparator
    }
}

extension JobOperationIdentifier: WireValue {}
