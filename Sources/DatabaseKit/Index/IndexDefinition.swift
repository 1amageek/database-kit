import DatabaseTypes

/// Complete logical semantics for one index, parameterized by field reference.
///
/// Source declarations use `AnyKeyPath`, polymorphic declarations use `String`,
/// and validated schemas use `FieldIdentity`. Every representation carries the
/// same semantic cases and is converted with `mapFields(_:)`.
public enum IndexDefinition<FieldReference> {
    case ordered(
        keys: [IndexKey<FieldReference>],
        includedFields: [FieldReference],
        unique: Bool
    )
    case aggregate(
        function: AggregateIndexFunction,
        groupBy: [IndexKey<FieldReference>],
        value: FieldReference?
    )
    case updateCount(field: FieldReference)
    case history(
        version: FieldReference,
        retention: VersionHistoryStrategy
    )
    case bitmap(field: FieldReference)
    case leaderboard(
        groupBy: [IndexKey<FieldReference>],
        score: FieldReference,
        window: LeaderboardWindowType,
        windowCount: Int
    )
    case vector(
        embedding: FieldReference,
        dimensions: Int,
        metric: VectorMetric
    )
    case text(
        fields: [FieldReference],
        mode: TextIndexMode
    )
    case spatial(
        location: FieldReference,
        encoding: SpatialEncoding,
        level: Int
    )
    case rank(score: FieldReference)
    case graph(
        GraphIndexDefinition<FieldReference>,
        includedFields: [FieldReference]
    )
    case custom(CustomIndexDefinition<FieldReference>)
}

extension IndexDefinition: Sendable where FieldReference: Sendable {}
extension IndexDefinition: Equatable where FieldReference: Equatable {}
extension IndexDefinition: Hashable where FieldReference: Hashable {}

public enum AggregateIndexFunction: Sendable, Hashable {
    case count
    case sum
    case minimum
    case maximum
    case average
    case nonNullCount
    case approximateDistinct(precision: Int = 14)
    case percentile(compression: Double = 100)

    public var type: AggregateFunctionType {
        switch self {
        case .count: .count
        case .sum: .sum
        case .minimum: .minimum
        case .maximum: .maximum
        case .average: .average
        case .nonNullCount: .nonNullCount
        case .approximateDistinct: .approximateDistinct
        case .percentile: .percentile
        }
    }
}

public enum TextIndexMode: Sendable, Hashable {
    case fullText(
        tokenizer: TokenizationStrategy = .simple,
        storePositions: Bool = true,
        ngramSize: Int = 3,
        minimumTermLength: Int = 2
    )
    case autocomplete(
        minimumPrefixLength: Int = 1,
        maximumPrefixLength: Int = 10
    )

    public var type: TextIndexType {
        switch self {
        case .fullText: .fullText
        case .autocomplete: .autocomplete
        }
    }
}

public enum PropertyGraphLabel<FieldReference> {
    case field(FieldReference)
    case implicit
}

extension PropertyGraphLabel: Sendable where FieldReference: Sendable {}
extension PropertyGraphLabel: Equatable where FieldReference: Equatable {}
extension PropertyGraphLabel: Hashable where FieldReference: Hashable {}

public enum GraphIndexDefinition<FieldReference> {
    case property(
        source: FieldReference,
        label: PropertyGraphLabel<FieldReference>,
        target: FieldReference,
        graph: FieldReference?,
        strategy: PropertyGraphIndexStrategy
    )
    case rdf(
        subject: FieldReference,
        predicate: FieldReference,
        object: FieldReference,
        graph: FieldReference?
    )
    case ontologyProjection(
        individualIRIBase: String,
        graph: RDFGraphName?
    )
}

extension GraphIndexDefinition: Sendable where FieldReference: Sendable {}
extension GraphIndexDefinition: Equatable where FieldReference: Equatable {}
extension GraphIndexDefinition: Hashable where FieldReference: Hashable {}

/// Extensible logical declaration for a third-party index implementation.
///
/// The custom identifier selects a separately registered runtime provider.
/// DatabaseKit preserves parameters but does not interpret their execution
/// meaning.
public struct CustomIndexDefinition<FieldReference> {
    public let identifier: String
    public let keys: [IndexKey<FieldReference>]
    public let includedFields: [FieldReference]
    public let parameters: [String: FieldValue]

    public init(
        identifier: String,
        keys: [IndexKey<FieldReference>],
        includedFields: [FieldReference] = [],
        parameters: [String: FieldValue] = [:]
    ) {
        self.identifier = identifier
        self.keys = keys
        self.includedFields = includedFields
        self.parameters = parameters
    }
}

extension CustomIndexDefinition: Sendable where FieldReference: Sendable {}
extension CustomIndexDefinition: Equatable where FieldReference: Equatable {}
extension CustomIndexDefinition: Hashable where FieldReference: Hashable {}

extension IndexDefinition {
    public var type: IndexType {
        switch self {
        case .ordered:
            .ordered
        case .aggregate(let function, _, _):
            .aggregate(function.type)
        case .updateCount:
            .updateCount
        case .history:
            .history
        case .bitmap:
            .bitmap
        case .leaderboard:
            .leaderboard
        case .vector:
            .vector
        case .text(_, let mode):
            .text(mode.type)
        case .spatial:
            .spatial
        case .rank:
            .rank
        case .graph(let definition, _):
            switch definition {
            case .property: .graph(.property)
            case .rdf: .graph(.rdf)
            case .ontologyProjection: .graph(.ontologyProjection)
            }
        case .custom(let definition):
            .custom(definition.identifier)
        }
    }

    public var keys: [IndexKey<FieldReference>] {
        switch self {
        case .ordered(let keys, _, _):
            return keys
        case .aggregate(_, let groupBy, let value):
            return value.map { groupBy + [.ascending($0)] } ?? groupBy
        case .updateCount(let field):
            return [.ascending(field)]
        case .history(let version, _):
            return [.ascending(version)]
        case .bitmap(let field):
            return [.ascending(field)]
        case .leaderboard(let groupBy, let score, _, _):
            return groupBy + [.descending(score)]
        case .vector(let embedding, _, _):
            return [.ascending(embedding)]
        case .text(let fields, _):
            return fields.map(IndexKey.ascending)
        case .spatial(let location, _, _):
            return [.ascending(location)]
        case .rank(let score):
            return [.descending(score)]
        case .graph(let definition, _):
            switch definition {
            case .property(let source, let label, let target, let graph, _):
                var result = [IndexKey.ascending(source)]
                if case .field(let field) = label {
                    result.append(.ascending(field))
                }
                result.append(.ascending(target))
                if let graph {
                    result.append(.ascending(graph))
                }
                return result
            case .rdf(let subject, let predicate, let object, let graph):
                var result = [
                    IndexKey.ascending(subject),
                    .ascending(predicate),
                    .ascending(object),
                ]
                if let graph {
                    result.append(.ascending(graph))
                }
                return result
            case .ontologyProjection:
                return []
            }
        case .custom(let definition):
            return definition.keys
        }
    }

    public var includedFields: [FieldReference] {
        switch self {
        case .ordered(_, let fields, _):
            fields
        case .graph(_, let fields):
            fields
        case .custom(let definition):
            definition.includedFields
        case .aggregate, .updateCount, .history, .bitmap, .leaderboard,
             .vector, .text, .spatial, .rank:
            []
        }
    }

    public var isUnique: Bool {
        guard case .ordered(_, _, let unique) = self else {
            return false
        }
        return unique
    }

    public func mapFields<NewFieldReference, Failure: Error>(
        _ transform: (FieldReference) throws(Failure) -> NewFieldReference
    ) throws(Failure) -> IndexDefinition<NewFieldReference> {
        switch self {
        case .ordered(let keys, let includedFields, let unique):
            return .ordered(
                keys: try keys.map { key throws(Failure) in
                    IndexKey<NewFieldReference>(
                        try transform(key.field),
                        order: key.order
                    )
                },
                includedFields: try includedFields.map(transform),
                unique: unique
            )
        case .aggregate(let function, let groupBy, let value):
            return .aggregate(
                function: function,
                groupBy: try groupBy.map { key throws(Failure) in
                    IndexKey<NewFieldReference>(
                        try transform(key.field),
                        order: key.order
                    )
                },
                value: try value.map(transform)
            )
        case .updateCount(let field):
            return .updateCount(field: try transform(field))
        case .history(let version, let retention):
            return .history(
                version: try transform(version),
                retention: retention
            )
        case .bitmap(let field):
            return .bitmap(field: try transform(field))
        case .leaderboard(let groupBy, let score, let window, let windowCount):
            return .leaderboard(
                groupBy: try groupBy.map { key throws(Failure) in
                    IndexKey<NewFieldReference>(
                        try transform(key.field),
                        order: key.order
                    )
                },
                score: try transform(score),
                window: window,
                windowCount: windowCount
            )
        case .vector(let embedding, let dimensions, let metric):
            return .vector(
                embedding: try transform(embedding),
                dimensions: dimensions,
                metric: metric
            )
        case .text(let fields, let mode):
            return .text(fields: try fields.map(transform), mode: mode)
        case .spatial(let location, let encoding, let level):
            return .spatial(
                location: try transform(location),
                encoding: encoding,
                level: level
            )
        case .rank(let score):
            return .rank(score: try transform(score))
        case .graph(let definition, let includedFields):
            return .graph(
                try definition.mapFields(transform),
                includedFields: try includedFields.map(transform)
            )
        case .custom(let definition):
            return .custom(
                CustomIndexDefinition<NewFieldReference>(
                    identifier: definition.identifier,
                    keys: try definition.keys.map { key throws(Failure) in
                        IndexKey<NewFieldReference>(
                            try transform(key.field),
                            order: key.order
                        )
                    },
                    includedFields: try definition.includedFields.map(transform),
                    parameters: definition.parameters
                )
            )
        }
    }
}

extension GraphIndexDefinition {
    fileprivate func mapFields<NewFieldReference, Failure: Error>(
        _ transform: (FieldReference) throws(Failure) -> NewFieldReference
    ) throws(Failure) -> GraphIndexDefinition<NewFieldReference> {
        switch self {
        case .property(let source, let label, let target, let graph, let strategy):
            let mappedLabel: PropertyGraphLabel<NewFieldReference>
            switch label {
            case .field(let field):
                mappedLabel = .field(try transform(field))
            case .implicit:
                mappedLabel = .implicit
            }
            return .property(
                source: try transform(source),
                label: mappedLabel,
                target: try transform(target),
                graph: try graph.map(transform),
                strategy: strategy
            )
        case .rdf(let subject, let predicate, let object, let graph):
            return .rdf(
                subject: try transform(subject),
                predicate: try transform(predicate),
                object: try transform(object),
                graph: try graph.map(transform)
            )
        case .ontologyProjection(let individualIRIBase, let graph):
            return .ontologyProjection(
                individualIRIBase: individualIRIBase,
                graph: graph
            )
        }
    }
}
