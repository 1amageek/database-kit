import DatabaseTypes
public enum CapabilitiesDescribeOperation: DatabaseOperationDeclaration {
    public static let identifier = DatabaseOperationIdentifier.capabilitiesDescribe
    public typealias Request = EmptyOperationPayload

    public struct Feature: Sendable, Hashable {
        public let identifier: String
        public let version: UInt32

        public init(identifier: String, version: UInt32) {
            self.identifier = identifier
            self.version = version
        }

        fileprivate func encode(into writer: inout DatabaseWireWriter) throws(DatabaseWireError) {
            try writer.writeString(identifier)
            writer.writeUInt32(version)
        }

        fileprivate init(from reader: inout DatabaseWireReader) throws(DatabaseWireError) {
            self.init(identifier: try reader.readString(), version: try reader.readUInt32())
        }
    }

    public struct Response: DatabaseWireValue, Hashable {
        public let runtimeVersion: String
        public let features: [Feature]
        public let jobOperations: [DatabaseJobOperationIdentifier]

        public init(
            runtimeVersion: String,
            features: [Feature],
            jobOperations: [DatabaseJobOperationIdentifier]
        ) {
            self.runtimeVersion = runtimeVersion
            self.features = features
            self.jobOperations = jobOperations
        }

        public func encode(into writer: inout DatabaseWireWriter) throws(DatabaseWireError) {
            try Self.validateCanonicalJobOperations(jobOperations)
            try writer.writeString(runtimeVersion)
            try writer.writeCount(features.count)
            for feature in features {
                try feature.encode(into: &writer)
            }
            try writer.writeCount(jobOperations.count)
            for operation in jobOperations {
                try operation.encode(into: &writer)
            }
        }

        public init(from reader: inout DatabaseWireReader) throws(DatabaseWireError) {
            let runtimeVersion = try reader.readString()
            let count = try reader.readCount()
            var features: [Feature] = []
            features.reserveCapacity(count)
            for _ in 0..<count {
                features.append(try Feature(from: &reader))
            }
            let jobOperationCount = try reader.readCount()
            var jobOperations: [DatabaseJobOperationIdentifier] = []
            jobOperations.reserveCapacity(jobOperationCount)
            for _ in 0..<jobOperationCount {
                jobOperations.append(
                    try DatabaseJobOperationIdentifier(from: &reader)
                )
            }
            try Self.validateCanonicalJobOperations(jobOperations)
            self.init(
                runtimeVersion: runtimeVersion,
                features: features,
                jobOperations: jobOperations
            )
        }

        private static func validateCanonicalJobOperations(
            _ operations: [DatabaseJobOperationIdentifier]
        ) throws(DatabaseWireError) {
            guard operations.count > 1 else {
                return
            }
            for index in 1..<operations.count {
                guard operations[index - 1].lexicographicallyPrecedes(
                    operations[index]
                ) else {
                    throw .nonCanonicalJobOperationSet
                }
            }
        }
    }
}
