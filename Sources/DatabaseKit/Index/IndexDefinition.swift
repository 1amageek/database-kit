import DatabaseTypes

/// Compile-time index semantics consumed by `#Index`.
///
/// Field selection is deliberately absent from this value. The declaration
/// macro receives Swift key paths separately and emits model-scoped
/// `IndexField` values. Runtime descriptors therefore retain only canonical
/// field identities.
public enum IndexDefinition: Sendable {
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
    case spatial(
        encoding: SpatialEncoding = .s2,
        level: Int = 15
    )
    case rank(bucketSize: Int = 100)
    case permuted(permutation: Permutation)
    case graph(strategy: GraphIndexStrategy = .adjacency)
}

extension IndexDefinition {
    package var identifier: String {
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
        case .spatial: "spatial"
        case .rank: "rank"
        case .permuted: "permuted"
        case .graph: "graph"
        }
    }

    package var subspaceStructure: SubspaceStructure {
        switch self {
        case .scalar, .minimum, .maximum, .countUpdates, .spatial, .permuted:
            .flat
        case .count, .sum, .average, .countNotNull, .distinct, .percentile:
            .aggregation
        case .version, .bitmap, .timeWindowLeaderboard, .vector, .fullText,
             .rank, .graph:
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
            try requireOrdered(
                schemas,
                reason: "Scalar index requires fields with canonical ordering"
            )

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

        case .rank(let bucketSize):
            try requireCount(1)
            guard bucketSize > 0 else {
                throw .invalidConfiguration(
                    index: identifier,
                    reason: "Bucket size must be positive"
                )
            }
            if let score = schemas.first {
                try requireNumeric(
                    score,
                    reason: "Rank score field must use a supported numeric scalar"
                )
            }

        case .permuted(let permutation):
            try requireMinimumCount(2)
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

        case .graph:
            try requireMinimumCount(3)
            guard schemas.count <= 4 else {
                throw .invalidFieldCount(
                    index: identifier,
                    expected: 4,
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
        case .spatial(let encoding, let level):
            return [
                "encoding": .string(encoding.rawValue),
                "level": .int64(Int64(level)),
            ]
        case .rank(let bucketSize):
            guard let score = schemas.first else {
                return [:]
            }
            return [
                "scoreType": .string(try scalarType(for: score).rawValue),
                "bucketSize": .int64(Int64(bucketSize)),
            ]
        case .permuted(let permutation):
            return [
                "permutation": .array(
                    permutation.indices.map { .int64(Int64($0)) }
                )
            ]
        case .graph(let strategy):
            return [
                "strategy": .string(strategy.rawValue),
                "hasEdgeField": .bool(true),
                "hasGraphField": .bool(schemas.count == 4),
            ]
        }
    }
}
