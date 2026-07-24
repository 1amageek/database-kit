import DatabaseTypes
/// Canonical metadata shared by aggregation maintenance and query runtimes.
public struct AggregationIndexMetadata: Sendable, Equatable {
    public enum Operation: String, Sendable, Equatable {
        case count
        case sum
        case average
        case minimum = "min"
        case maximum = "max"
        case distinct
        case percentile
    }

    public let operation: Operation
    public let groupByFieldNames: [String]
    public let valueFieldName: String?
    public let valueType: IndexScalarType?
    public let precision: Int?
    public let compression: Double?

    public init(
        canonical kind: IndexKindMetadata
    ) throws(IndexKindMetadataError) {
        guard let operation = Operation(rawValue: kind.identifier) else {
            throw .kindMismatch(
                expected: "aggregation index",
                actual: kind.identifier
            )
        }

        let expectedSubspace: SubspaceStructure
        switch operation {
        case .minimum, .maximum:
            expectedSubspace = .flat
        default:
            expectedSubspace = .aggregation
        }
        try kind.validateIdentity(
            identifier: operation.rawValue,
            subspaceStructure: expectedSubspace
        )

        self.operation = operation
        switch operation {
        case .count:
            try kind.validateMetadataKeys()
            try kind.validateFieldNames()
            self.groupByFieldNames = kind.fieldNames
            self.valueFieldName = nil
            self.valueType = nil
            self.precision = nil
            self.compression = nil

        case .sum, .average, .minimum, .maximum:
            try kind.validateMetadataKeys(required: ["valueType"])
            try kind.validateFieldCount(minimum: 1)
            let valueType = try kind.requireScalarType("valueType")
            if operation == .sum || operation == .average {
                guard valueType.isNumeric else {
                    throw .invalidMetadata(
                        identifier: kind.identifier,
                        key: "valueType"
                    )
                }
            }
            self.groupByFieldNames = Array(kind.fieldNames.dropLast())
            self.valueFieldName = kind.fieldNames.last
            self.valueType = valueType
            self.precision = nil
            self.compression = nil

        case .distinct:
            try kind.validateMetadataKeys(required: ["precision"])
            try kind.validateFieldCount(minimum: 1)
            let precision = try kind.requireInt("precision")
            // Six-bit persisted HLL registers fit the common 100 KB value
            // boundary through precision 17. Precision 18 cannot be represented
            // by the canonical cross-backend index layout.
            guard (4...17).contains(precision) else {
                throw .invalidMetadata(
                    identifier: kind.identifier,
                    key: "precision"
                )
            }
            self.groupByFieldNames = Array(kind.fieldNames.dropLast())
            self.valueFieldName = kind.fieldNames.last
            self.valueType = nil
            self.precision = precision
            self.compression = nil

        case .percentile:
            try kind.validateMetadataKeys(required: ["compression"])
            try kind.validateFieldCount(minimum: 1)
            let compression = try kind.requireDouble("compression")
            guard compression.isFinite,
                  (1.0...1_000.0).contains(compression) else {
                throw .invalidMetadata(
                    identifier: kind.identifier,
                    key: "compression"
                )
            }
            self.groupByFieldNames = Array(kind.fieldNames.dropLast())
            self.valueFieldName = kind.fieldNames.last
            self.valueType = nil
            self.precision = nil
            self.compression = compression
        }
    }
}
