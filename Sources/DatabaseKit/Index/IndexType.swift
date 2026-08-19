/// The semantic runtime family selected by an index declaration.
///
/// This value is the typed dispatch key shared by schema validation and the
/// execution layer. It deliberately carries no storage-layout decision.
public enum IndexType: Sendable, Hashable {
    case ordered
    case aggregate(AggregateFunctionType)
    case updateCount
    case history
    case bitmap
    case leaderboard
    case vector
    case text(TextIndexType)
    case spatial
    case rank
    case graph(GraphIndexType)
    case custom(String)

    /// A stable diagnostic spelling. Runtime dispatch uses `IndexType` itself.
    public var diagnosticName: String {
        switch self {
        case .ordered: "ordered"
        case .aggregate(let function): "aggregate.\(function.diagnosticName)"
        case .updateCount: "updateCount"
        case .history: "history"
        case .bitmap: "bitmap"
        case .leaderboard: "leaderboard"
        case .vector: "vector"
        case .text(let type): "text.\(type.diagnosticName)"
        case .spatial: "spatial"
        case .rank: "rank"
        case .graph(let type): "graph.\(type.diagnosticName)"
        case .custom(let identifier): "custom.\(identifier)"
        }
    }
}

public enum AggregateFunctionType: UInt8, Sendable, Hashable, CaseIterable {
    case count = 0
    case sum = 1
    case minimum = 2
    case maximum = 3
    case average = 4
    case nonNullCount = 5
    case approximateDistinct = 6
    case percentile = 7

    public var diagnosticName: String {
        switch self {
        case .count: "count"
        case .sum: "sum"
        case .minimum: "minimum"
        case .maximum: "maximum"
        case .average: "average"
        case .nonNullCount: "nonNullCount"
        case .approximateDistinct: "approximateDistinct"
        case .percentile: "percentile"
        }
    }
}

public enum TextIndexType: UInt8, Sendable, Hashable, CaseIterable {
    case fullText = 0
    case autocomplete = 1

    public var diagnosticName: String {
        switch self {
        case .fullText: "fullText"
        case .autocomplete: "autocomplete"
        }
    }
}

public enum GraphIndexType: UInt8, Sendable, Hashable, CaseIterable {
    case property = 0
    case rdf = 1
    case ontologyProjection = 2

    public var diagnosticName: String {
        switch self {
        case .property: "property"
        case .rdf: "rdf"
        case .ontologyProjection: "ontologyProjection"
        }
    }
}
