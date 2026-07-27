import DatabaseTypes

/// Compile-time index semantics consumed by `#Index`.
///
/// Field selection is deliberately absent from this value. The declaration
/// macro receives Swift key paths separately and emits model-scoped
/// `IndexField` values. Runtime descriptors therefore retain only canonical
/// field identities.
public enum IndexDefinition: Sendable, Hashable {
    case scalar
    case count
    case sum
    case minimum
    case maximum
    case average
    case version(strategy: VersionHistoryStrategy = .keepAll)
    case countUpdates
    case countNotNull
    case bitmap
    case timeWindowLeaderboard(
        window: LeaderboardWindowType = .daily,
        windowCount: Int = 7
    )
    case distinct(precision: Int = 14)
    case percentile(compression: Double = 100)
    case vector(
        dimensions: Int,
        metric: VectorMetric = .cosine
    )
    case fullText(
        tokenizer: TokenizationStrategy = .simple,
        storePositions: Bool = true,
        ngramSize: Int = 3,
        minTermLength: Int = 2
    )
    case autocomplete(
        minPrefixLength: Int = 1,
        maxPrefixLength: Int = 10
    )
    case spatial(
        encoding: SpatialEncoding = .s2,
        level: Int = 15
    )
    case rank
    case permuted(PermutationPattern)
    case propertyGraph(
        strategy: PropertyGraphIndexStrategy = .adjacency,
        label: PropertyGraphLabelSource = .field
    )
    case rdfDataset
}

extension IndexDefinition {
    public var identifier: String {
        switch self {
        case .scalar: "scalar"
        case .count: "count"
        case .sum: "sum"
        case .minimum: "min"
        case .maximum: "max"
        case .average: "average"
        case .version: "version"
        case .countUpdates: "count_updates"
        case .countNotNull: "count_not_null"
        case .bitmap: "bitmap"
        case .timeWindowLeaderboard: "time_window_leaderboard"
        case .distinct: "distinct"
        case .percentile: "percentile"
        case .vector: "vector"
        case .fullText: "fulltext"
        case .autocomplete: "autocomplete"
        case .spatial: "spatial"
        case .rank: "rank"
        case .permuted: "permuted"
        case .propertyGraph: "graph"
        case .rdfDataset: "rdf_quad"
        }
    }

    public var subspaceStructure: SubspaceStructure {
        switch self {
        case .scalar, .minimum, .maximum, .countUpdates, .spatial, .permuted:
            .flat
        case .count, .sum, .average, .countNotNull, .distinct, .percentile:
            .aggregation
        case .version, .bitmap, .timeWindowLeaderboard, .vector, .fullText,
             .autocomplete,
             .rank, .propertyGraph, .rdfDataset:
            .hierarchical
        }
    }

    package func kindMetadata(
        fields: [IndexFieldMetadata],
        schemas: [FieldSchema]
    ) throws(IndexValidationError) -> IndexKindMetadata {
        guard fields.count == schemas.count else {
            throw .invalidConfiguration(
                index: identifier,
                reason: "Resolved field identities and schemas must have the same count"
            )
        }
        try validate(schemas: schemas)
        return IndexKindMetadata(
            identifier: identifier,
            subspaceStructure: subspaceStructure,
            fields: fields,
            metadata: try metadata(schemas: schemas)
        )
    }

    private func validate(
        schemas: [FieldSchema]
    ) throws(IndexValidationError) {
        func requireCount(_ expected: Int) throws(IndexValidationError) {
            guard schemas.count == expected else {
                throw .invalidFieldCount(
                    index: identifier,
                    expected: expected,
                    actual: schemas.count
                )
            }
        }

        func requireMinimumCount(_ minimum: Int) throws(IndexValidationError) {
            guard schemas.count >= minimum else {
                throw .invalidFieldCount(
                    index: identifier,
                    expected: minimum,
                    actual: schemas.count
                )
            }
        }

        func requireOrdered(
            _ fields: some Sequence<FieldSchema>,
            reason: String
        ) throws(IndexValidationError) {
            for field in fields where !field.supportsOrderedIndex {
                throw .unsupportedField(
                    index: identifier,
                    field: field,
                    reason: reason
                )
            }
        }

        func requireNumeric(
            _ field: FieldSchema,
            reason: String
        ) throws(IndexValidationError) {
            guard field.indexScalarType?.isNumeric == true else {
                throw .unsupportedField(
                    index: identifier,
                    field: field,
                    reason: reason
                )
            }
        }

        switch self {
        case .scalar:
            try requireMinimumCount(1)
            if schemas.count == 1, let field = schemas.first {
                guard field.supportsScalarIndex else {
                    throw .unsupportedField(
                        index: identifier,
                        field: field,
                        reason: "Scalar index requires values with canonical ordering"
                    )
                }
            } else {
                try requireOrdered(
                    schemas,
                    reason: "Composite scalar indexes require scalar fields with canonical ordering"
                )
            }

        case .count:
            try requireOrdered(
                schemas,
                reason: "Count index grouping fields require canonical ordering"
            )

        case .sum, .average:
            try requireMinimumCount(1)
            try requireOrdered(
                schemas.dropLast(),
                reason: "Aggregation grouping fields require canonical ordering"
            )
            if let value = schemas.last {
                try requireNumeric(
                    value,
                    reason: "Aggregation value field must use a supported numeric scalar"
                )
            }

        case .minimum, .maximum:
            try requireMinimumCount(1)
            try requireOrdered(
                schemas,
                reason: "Minimum and maximum indexes require canonical ordering"
            )
            guard schemas.last?.indexScalarType != nil else {
                if let value = schemas.last {
                    throw .unsupportedField(
                        index: identifier,
                        field: value,
                        reason: "Value field must use a supported index scalar"
                    )
                }
                return
            }

        case .version:
            try requireCount(1)
            switch self {
            case .version(.keepAll):
                break
            case .version(.keepLast(let count)):
                guard count > 0 else {
                    throw .invalidConfiguration(
                        index: identifier,
                        reason: "Retained version count must be positive"
                    )
                }
            case .version(.keepForDuration(let duration)):
                guard duration.isFinite, duration > 0 else {
                    throw .invalidConfiguration(
                        index: identifier,
                        reason: "Retention duration must be finite and positive"
                    )
                }
            default:
                break
            }

        case .countUpdates:
            try requireCount(1)

        case .countNotNull:
            try requireMinimumCount(1)
            try requireOrdered(
                schemas.dropLast(),
                reason: "Count-not-null grouping fields require canonical ordering"
            )

        case .bitmap:
            try requireCount(1)
            if let field = schemas.first, !field.supportsEqualityIndex {
                throw .unsupportedField(
                    index: identifier,
                    field: field,
                    reason: "Bitmap index requires a scalar equality value"
                )
            }

        case .timeWindowLeaderboard(let window, let windowCount):
            try requireMinimumCount(1)
            guard windowCount > 0 else {
                throw .invalidConfiguration(
                    index: identifier,
                    reason: "Window count must be positive"
                )
            }
            guard window.durationSeconds.isFinite, window.durationSeconds > 0 else {
                throw .invalidConfiguration(
                    index: identifier,
                    reason: "Window duration must be finite and positive"
                )
            }
            try requireOrdered(
                schemas.dropLast(),
                reason: "Leaderboard grouping fields require canonical ordering"
            )
            if let score = schemas.last,
               score.type != .int64 || score.isArray {
                throw .unsupportedField(
                    index: identifier,
                    field: score,
                    reason: "Leaderboard score field must be Int64"
                )
            }

        case .distinct(let precision):
            try requireMinimumCount(1)
            guard (4...17).contains(precision) else {
                throw .invalidConfiguration(
                    index: identifier,
                    reason: "Precision must be in 4...17"
                )
            }
            try requireOrdered(
                schemas.dropLast(),
                reason: "Distinct index grouping fields require canonical ordering"
            )
            if let value = schemas.last, !value.supportsEqualityIndex {
                throw .unsupportedField(
                    index: identifier,
                    field: value,
                    reason: "Distinct index value must support canonical equality"
                )
            }

        case .percentile(let compression):
            try requireMinimumCount(1)
            guard compression.isFinite, (1...1_000).contains(compression) else {
                throw .invalidConfiguration(
                    index: identifier,
                    reason: "Compression must be finite and in 1...1000"
                )
            }
            try requireOrdered(
                schemas.dropLast(),
                reason: "Percentile index grouping fields require canonical ordering"
            )
            if let value = schemas.last {
                try requireNumeric(
                    value,
                    reason: "Percentile value field must use a supported numeric scalar"
                )
            }

        case .vector(let dimensions, _):
            try requireCount(1)
            guard dimensions > 0 else {
                throw .invalidConfiguration(
                    index: identifier,
                    reason: "Vector dimensions must be positive"
                )
            }
            if let field = schemas.first,
               field.type != .vector || field.isArray {
                throw .unsupportedField(
                    index: identifier,
                    field: field,
                    reason: "Vector index field must use the canonical Vector primitive"
                )
            }

        case .fullText(_, _, let ngramSize, let minTermLength):
            try requireMinimumCount(1)
            guard ngramSize > 0 else {
                throw .invalidConfiguration(
                    index: identifier,
                    reason: "N-gram size must be positive"
                )
            }
            guard minTermLength > 0 else {
                throw .invalidConfiguration(
                    index: identifier,
                    reason: "Minimum term length must be positive"
                )
            }
            for field in schemas
            where field.type != .string || field.isArray {
                throw .unsupportedField(
                    index: identifier,
                    field: field,
                    reason: "Full-text index fields must be String"
                )
            }

        case .autocomplete(let minPrefixLength, let maxPrefixLength):
            try requireMinimumCount(1)
            guard minPrefixLength > 0 else {
                throw .invalidConfiguration(
                    index: identifier,
                    reason: "Minimum prefix length must be positive"
                )
            }
            guard maxPrefixLength >= minPrefixLength else {
                throw .invalidConfiguration(
                    index: identifier,
                    reason: "Maximum prefix length must not be less than the minimum"
                )
            }
            for field in schemas where field.type != .string {
                throw .unsupportedField(
                    index: identifier,
                    field: field,
                    reason: "Autocomplete index fields must be String or [String]"
                )
            }

        case .spatial(let encoding, let level):
            try requireCount(1)
            let maximumLevel = encoding == .morton ? 20 : 30
            guard (0...maximumLevel).contains(level) else {
                throw .invalidConfiguration(
                    index: identifier,
                    reason: "Level must be in 0...\(maximumLevel)"
                )
            }
            if let field = schemas.first,
               field.isArray
                || (field.type != .geographicPoint
                    && field.type != .geographicPosition) {
                throw .unsupportedField(
                    index: identifier,
                    field: field,
                    reason: "Spatial index requires a geographic point or position"
                )
            }

        case .rank:
            try requireCount(1)
            if let score = schemas.first {
                try requireNumeric(
                    score,
                    reason: "Rank score field must use a supported numeric scalar"
                )
            }

        case .permuted(let pattern):
            try requireMinimumCount(2)
            let permutation = try resolvedPermutation(from: pattern)
            guard permutation.size == schemas.count else {
                throw .invalidConfiguration(
                    index: identifier,
                    reason: "Permutation size must match the indexed field count"
                )
            }
            try requireOrdered(
                schemas,
                reason: "Permuted index requires fields with canonical ordering"
            )

        case .propertyGraph(_, let label):
            let minimumCount = label == .field ? 3 : 2
            let maximumCount = minimumCount + 1
            guard (minimumCount...maximumCount).contains(schemas.count) else {
                throw .invalidFieldCount(
                    index: identifier,
                    expected: minimumCount,
                    actual: schemas.count
                )
            }
            for field in schemas
            where field.type != .string || field.isArray {
                throw .unsupportedField(
                    index: identifier,
                    field: field,
                    reason: "Property-graph identity fields must be String"
                )
            }
        case .rdfDataset:
            guard schemas.count == 3 || schemas.count == 4 else {
                throw .invalidFieldCount(
                    index: identifier,
                    expected: 4,
                    actual: schemas.count
                )
            }
            for field in schemas.prefix(3)
            where field.type != .rdfTerm || field.isArray {
                throw .unsupportedField(
                    index: identifier,
                    field: field,
                    reason: "RDF subject, predicate, and object fields must be RDFTerm"
                )
            }
            if schemas.count == 4 {
                let graph = schemas[3]
                guard graph.type == .rdfTerm, !graph.isArray else {
                    throw .unsupportedField(
                        index: identifier,
                        field: graph,
                        reason: "RDF graph field must be RDFTerm or Optional<RDFTerm>"
                    )
                }
            }
        }
    }

    private func metadata(
        schemas: [FieldSchema]
    ) throws(IndexValidationError) -> [String: FieldValue] {
        func scalarType(for field: FieldSchema) throws(IndexValidationError) -> IndexScalarType {
            guard let type = field.indexScalarType else {
                throw .unsupportedField(
                    index: identifier,
                    field: field,
                    reason: "Field has no supported canonical index scalar type"
                )
            }
            return type
        }

        switch self {
        case .scalar, .count, .countUpdates, .countNotNull, .bitmap:
            return [:]
        case .sum, .minimum, .maximum, .average:
            guard let value = schemas.last else {
                return [:]
            }
            return ["valueType": .string(try scalarType(for: value).rawValue)]
        case .version(let strategy):
            switch strategy {
            case .keepAll:
                return ["strategy": .string("keepAll")]
            case .keepLast(let count):
                return [
                    "strategy": .string("keepLast"),
                    "strategyCount": .int64(Int64(count)),
                ]
            case .keepForDuration(let duration):
                return [
                    "strategy": .string("keepForDuration"),
                    "strategyDurationSeconds": .float64(duration),
                ]
            }
        case .timeWindowLeaderboard(let window, let windowCount):
            var result: [String: FieldValue] = [
                "windowCount": .int64(Int64(windowCount))
            ]
            switch window {
            case .hourly:
                result["window"] = .string("hourly")
            case .daily:
                result["window"] = .string("daily")
            case .weekly:
                result["window"] = .string("weekly")
            case .monthly:
                result["window"] = .string("monthly")
            case .custom(let duration):
                result["window"] = .string("custom")
                result["windowDurationSeconds"] = .float64(duration)
            }
            return result
        case .distinct(let precision):
            return ["precision": .int64(Int64(precision))]
        case .percentile(let compression):
            return ["compression": .float64(compression)]
        case .vector(let dimensions, let metric):
            return [
                "dimensions": .int64(Int64(dimensions)),
                "metric": .string(metric.rawValue),
            ]
        case .fullText(
            let tokenizer,
            let storePositions,
            let ngramSize,
            let minTermLength
        ):
            return [
                "tokenizer": .string(tokenizer.rawValue),
                "storePositions": .bool(storePositions),
                "ngramSize": .int64(Int64(ngramSize)),
                "minTermLength": .int64(Int64(minTermLength)),
            ]
        case .autocomplete(let minPrefixLength, let maxPrefixLength):
            return [
                "minPrefixLength": .int64(Int64(minPrefixLength)),
                "maxPrefixLength": .int64(Int64(maxPrefixLength)),
            ]
        case .spatial(let encoding, let level):
            return [
                "encoding": .string(encoding.rawValue),
                "level": .int64(Int64(level)),
            ]
        case .rank:
            guard let score = schemas.first else {
                return [:]
            }
            return [
                "scoreType": .string(try scalarType(for: score).rawValue),
            ]
        case .permuted(let pattern):
            let permutation = try resolvedPermutation(from: pattern)
            return [
                "permutation": .array(
                    permutation.indices.map { .int64(Int64($0)) }
                )
            ]
        case .propertyGraph(let strategy, let label):
            return [
                "strategy": .string(strategy.rawValue),
                "hasEdgeField": .bool(label == .field),
                "hasGraphField": .bool(
                    schemas.count == (label == .field ? 4 : 3)
                ),
            ]
        case .rdfDataset:
            return [:]
        }
    }
}

extension IndexDefinition {
    /// Restores built-in index semantics from validated schema metadata.
    ///
    /// Field identities remain in `IndexKindMetadata`; this value restores the
    /// behavior-changing configuration only. Unknown identifiers belong to an
    /// `IndexKind` extension and are rejected by this built-in initializer.
    public init(
        metadata kind: IndexKindMetadata
    ) throws(IndexKindMetadataError) {
        func validate(
            identifier: String,
            subspaceStructure: SubspaceStructure,
            requiredMetadata: Set<String> = [],
            optionalMetadata: Set<String> = []
        ) throws(IndexKindMetadataError) {
            try kind.validateIdentity(
                identifier: identifier,
                subspaceStructure: subspaceStructure
            )
            try kind.validateMetadataKeys(
                required: requiredMetadata,
                optional: optionalMetadata
            )
        }

        switch kind.identifier {
        case "scalar":
            try validate(identifier: "scalar", subspaceStructure: .flat)
            try kind.validateFieldCount(minimum: 1)
            self = .scalar

        case "count":
            try validate(identifier: "count", subspaceStructure: .aggregation)
            try kind.validateFieldNames()
            self = .count

        case "sum":
            try validate(
                identifier: "sum",
                subspaceStructure: .aggregation,
                requiredMetadata: ["valueType"]
            )
            try kind.validateFieldCount(minimum: 1)
            _ = try kind.requireScalarType("valueType")
            self = .sum

        case "min":
            try validate(
                identifier: "min",
                subspaceStructure: .flat,
                requiredMetadata: ["valueType"]
            )
            try kind.validateFieldCount(minimum: 1)
            _ = try kind.requireScalarType("valueType")
            self = .minimum

        case "max":
            try validate(
                identifier: "max",
                subspaceStructure: .flat,
                requiredMetadata: ["valueType"]
            )
            try kind.validateFieldCount(minimum: 1)
            _ = try kind.requireScalarType("valueType")
            self = .maximum

        case "average":
            try validate(
                identifier: "average",
                subspaceStructure: .aggregation,
                requiredMetadata: ["valueType"]
            )
            try kind.validateFieldCount(minimum: 1)
            _ = try kind.requireScalarType("valueType")
            self = .average

        case "version":
            self = try Self.versionDefinition(metadata: kind)

        case "count_updates":
            try validate(
                identifier: "count_updates",
                subspaceStructure: .flat
            )
            try kind.validateFieldCount(1)
            self = .countUpdates

        case "count_not_null":
            try validate(
                identifier: "count_not_null",
                subspaceStructure: .aggregation
            )
            try kind.validateFieldCount(minimum: 1)
            self = .countNotNull

        case "bitmap":
            try validate(identifier: "bitmap", subspaceStructure: .hierarchical)
            try kind.validateFieldCount(1)
            self = .bitmap

        case "time_window_leaderboard":
            try validate(
                identifier: "time_window_leaderboard",
                subspaceStructure: .hierarchical,
                requiredMetadata: ["window", "windowCount"],
                optionalMetadata: ["windowDurationSeconds"]
            )
            try kind.validateFieldCount(minimum: 1)
            self = try Self.timeWindowDefinition(metadata: kind)

        case "distinct":
            try validate(
                identifier: "distinct",
                subspaceStructure: .aggregation,
                requiredMetadata: ["precision"]
            )
            try kind.validateFieldCount(minimum: 1)
            let precision = try kind.requireInt("precision")
            guard (4...17).contains(precision) else {
                throw .invalidMetadata(
                    identifier: kind.identifier,
                    key: "precision"
                )
            }
            self = .distinct(precision: precision)

        case "percentile":
            try validate(
                identifier: "percentile",
                subspaceStructure: .aggregation,
                requiredMetadata: ["compression"]
            )
            try kind.validateFieldCount(minimum: 1)
            let compression = try kind.requireDouble("compression")
            guard compression.isFinite,
                  (1...1_000).contains(compression) else {
                throw .invalidMetadata(
                    identifier: kind.identifier,
                    key: "compression"
                )
            }
            self = .percentile(compression: compression)

        case "vector":
            try validate(
                identifier: "vector",
                subspaceStructure: .hierarchical,
                requiredMetadata: ["dimensions", "metric"]
            )
            try kind.validateFieldCount(1)
            let dimensions = try kind.requireInt("dimensions")
            guard dimensions > 0 else {
                throw .invalidMetadata(
                    identifier: kind.identifier,
                    key: "dimensions"
                )
            }
            let metricValue = try kind.requireString("metric")
            guard let metric = VectorMetric(rawValue: metricValue) else {
                throw .invalidMetadata(
                    identifier: kind.identifier,
                    key: "metric"
                )
            }
            self = .vector(dimensions: dimensions, metric: metric)

        case "fulltext":
            try validate(
                identifier: "fulltext",
                subspaceStructure: .hierarchical,
                requiredMetadata: [
                    "tokenizer",
                    "storePositions",
                    "ngramSize",
                    "minTermLength",
                ]
            )
            try kind.validateFieldCount(minimum: 1)
            let tokenizerValue = try kind.requireString("tokenizer")
            guard let tokenizer = TokenizationStrategy(rawValue: tokenizerValue) else {
                throw .invalidMetadata(
                    identifier: kind.identifier,
                    key: "tokenizer"
                )
            }
            let ngramSize = try kind.requireInt("ngramSize")
            guard ngramSize > 0 else {
                throw .invalidMetadata(
                    identifier: kind.identifier,
                    key: "ngramSize"
                )
            }
            let minTermLength = try kind.requireInt("minTermLength")
            guard minTermLength > 0 else {
                throw .invalidMetadata(
                    identifier: kind.identifier,
                    key: "minTermLength"
                )
            }
            self = .fullText(
                tokenizer: tokenizer,
                storePositions: try kind.requireBool("storePositions"),
                ngramSize: ngramSize,
                minTermLength: minTermLength
            )

        case "autocomplete":
            try validate(
                identifier: "autocomplete",
                subspaceStructure: .hierarchical,
                requiredMetadata: [
                    "minPrefixLength",
                    "maxPrefixLength",
                ]
            )
            try kind.validateFieldCount(minimum: 1)
            let minPrefixLength = try kind.requireInt("minPrefixLength")
            let maxPrefixLength = try kind.requireInt("maxPrefixLength")
            guard minPrefixLength > 0 else {
                throw .invalidMetadata(
                    identifier: kind.identifier,
                    key: "minPrefixLength"
                )
            }
            guard maxPrefixLength >= minPrefixLength else {
                throw .invalidMetadata(
                    identifier: kind.identifier,
                    key: "maxPrefixLength"
                )
            }
            self = .autocomplete(
                minPrefixLength: minPrefixLength,
                maxPrefixLength: maxPrefixLength
            )

        case "spatial":
            try validate(
                identifier: "spatial",
                subspaceStructure: .flat,
                requiredMetadata: ["encoding", "level"]
            )
            try kind.validateFieldCount(1)
            let encodingValue = try kind.requireString("encoding")
            guard let encoding = SpatialEncoding(rawValue: encodingValue) else {
                throw .invalidMetadata(
                    identifier: kind.identifier,
                    key: "encoding"
                )
            }
            let level = try kind.requireInt("level")
            let maximumLevel = encoding == .morton ? 20 : 30
            guard (0...maximumLevel).contains(level) else {
                throw .invalidMetadata(
                    identifier: kind.identifier,
                    key: "level"
                )
            }
            self = .spatial(encoding: encoding, level: level)

        case "rank":
            try validate(
                identifier: "rank",
                subspaceStructure: .hierarchical,
                requiredMetadata: ["scoreType"]
            )
            try kind.validateFieldCount(1)
            _ = try kind.requireScalarType("scoreType")
            self = .rank

        case "permuted":
            try validate(
                identifier: "permuted",
                subspaceStructure: .flat,
                requiredMetadata: ["permutation"]
            )
            try kind.validateFieldCount(minimum: 2)
            let permutation: Permutation
            do {
                permutation = try Permutation(
                    indices: kind.requireIntArray("permutation")
                )
            } catch {
                throw .invalidMetadata(
                    identifier: kind.identifier,
                    key: "permutation"
                )
            }
            guard permutation.size == kind.fields.count else {
                throw .invalidMetadata(
                    identifier: kind.identifier,
                    key: "permutation"
                )
            }
            self = .permuted(.ordering(permutation.indices))

        case "graph":
            try validate(
                identifier: "graph",
                subspaceStructure: .hierarchical,
                requiredMetadata: [
                    "strategy",
                    "hasEdgeField",
                    "hasGraphField",
                ]
            )
            let strategyValue = try kind.requireString("strategy")
            guard let strategy = PropertyGraphIndexStrategy(
                rawValue: strategyValue
            ) else {
                throw .invalidMetadata(
                    identifier: kind.identifier,
                    key: "strategy"
                )
            }
            let hasEdgeField = try kind.requireBool("hasEdgeField")
            let hasGraphField = try kind.requireBool("hasGraphField")
            let expectedFieldCount =
                2 + (hasEdgeField ? 1 : 0) + (hasGraphField ? 1 : 0)
            try kind.validateFieldCount(expectedFieldCount)
            self = .propertyGraph(
                strategy: strategy,
                label: hasEdgeField ? .field : .implicit
            )

        case "rdf_quad":
            try validate(
                identifier: "rdf_quad",
                subspaceStructure: .hierarchical
            )
            try kind.validateFieldCount(minimum: 3, maximum: 4)
            self = .rdfDataset

        default:
            throw .unknownIdentifier(kind.identifier)
        }
    }

    private func resolvedPermutation(
        from pattern: PermutationPattern
    ) throws(IndexValidationError) -> Permutation {
        do {
            return try pattern.resolve()
        } catch let error {
            throw .invalidConfiguration(
                index: identifier,
                reason: error.description
            )
        }
    }

    private static func versionDefinition(
        metadata kind: IndexKindMetadata
    ) throws(IndexKindMetadataError) -> IndexDefinition {
        try kind.validateIdentity(
            identifier: "version",
            subspaceStructure: .hierarchical
        )
        try kind.validateMetadataKeys(
            required: ["strategy"],
            optional: ["strategyCount", "strategyDurationSeconds"]
        )
        try kind.validateFieldCount(1)

        switch try kind.requireString("strategy") {
        case "keepAll":
            guard kind.metadata["strategyCount"] == nil,
                  kind.metadata["strategyDurationSeconds"] == nil else {
                throw .invalidMetadata(
                    identifier: kind.identifier,
                    key: "strategy"
                )
            }
            return .version(strategy: .keepAll)
        case "keepLast":
            guard kind.metadata["strategyDurationSeconds"] == nil else {
                throw .invalidMetadata(
                    identifier: kind.identifier,
                    key: "strategyDurationSeconds"
                )
            }
            let count = try kind.requireInt("strategyCount")
            guard count > 0 else {
                throw .invalidMetadata(
                    identifier: kind.identifier,
                    key: "strategyCount"
                )
            }
            return .version(strategy: .keepLast(count))
        case "keepForDuration":
            guard kind.metadata["strategyCount"] == nil else {
                throw .invalidMetadata(
                    identifier: kind.identifier,
                    key: "strategyCount"
                )
            }
            let duration = try kind.requireDouble("strategyDurationSeconds")
            guard duration.isFinite, duration > 0 else {
                throw .invalidMetadata(
                    identifier: kind.identifier,
                    key: "strategyDurationSeconds"
                )
            }
            return .version(strategy: .keepForDuration(duration))
        default:
            throw .invalidMetadata(
                identifier: kind.identifier,
                key: "strategy"
            )
        }
    }

    private static func timeWindowDefinition(
        metadata kind: IndexKindMetadata
    ) throws(IndexKindMetadataError) -> IndexDefinition {
        let window: LeaderboardWindowType
        switch try kind.requireString("window") {
        case "hourly":
            try rejectWindowDuration(kind)
            window = .hourly
        case "daily":
            try rejectWindowDuration(kind)
            window = .daily
        case "weekly":
            try rejectWindowDuration(kind)
            window = .weekly
        case "monthly":
            try rejectWindowDuration(kind)
            window = .monthly
        case "custom":
            let duration = try kind.requireDouble("windowDurationSeconds")
            guard duration.isFinite, duration > 0 else {
                throw .invalidMetadata(
                    identifier: kind.identifier,
                    key: "windowDurationSeconds"
                )
            }
            window = .custom(duration: duration)
        default:
            throw .invalidMetadata(
                identifier: kind.identifier,
                key: "window"
            )
        }

        let count = try kind.requireInt("windowCount")
        guard count > 0 else {
            throw .invalidMetadata(
                identifier: kind.identifier,
                key: "windowCount"
            )
        }
        return .timeWindowLeaderboard(window: window, windowCount: count)
    }

    private static func rejectWindowDuration(
        _ kind: IndexKindMetadata
    ) throws(IndexKindMetadataError) {
        guard kind.metadata["windowDurationSeconds"] == nil else {
            throw .unexpectedMetadata(
                identifier: kind.identifier,
                key: "windowDurationSeconds"
            )
        }
    }
}
