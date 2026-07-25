import DatabaseTypes
import Testing
@testable import DatabaseKit

@Suite("#Index Macro E2E Tests")
struct IndexMacroE2ETests {

    @Test("#Index builds descriptors for every database-kit index kind")
    func buildsDescriptorsForEveryIndexKind() throws {
        let descriptors = try IndexMacroE2ERecord.indexDescriptors
        #expect(descriptors.map(\.name) == Self.expectedSpecs.map(\.name))

        for spec in Self.expectedSpecs {
            let descriptor = try Self.descriptor(named: spec.name)
            #expect(descriptor.kindIdentifier == spec.kindIdentifier)
            #expect(descriptor.fieldNames == spec.fieldNames)
            #expect(descriptor.kind.fieldNames == spec.fieldNames)
        }
    }

    @Test("#Index descriptors survive Schema catalog type erasure")
    func descriptorsSurviveSchemaCatalogTypeErasure() throws {
        let schema = try Schema([IndexMacroE2ERecord.self])
        let entity = try #require(schema.entity(for: IndexMacroE2ERecord.self))

        #expect(entity.indexes.map(\.name) == Self.expectedSpecs.map(\.name))

        for spec in Self.expectedSpecs {
            let catalog = try #require(entity.indexes.first { $0.name == spec.name })
            #expect(catalog.kindIdentifier == spec.kindIdentifier)
            #expect(catalog.fieldNames == spec.fieldNames)
        }

        let scalar = try #require(entity.indexes.first { $0.name == "e2e_scalar_category" })
        #expect(scalar.unique == true)
        #expect(scalar.storedFieldNames == ["title"])
    }

    @Test("#Index preserves kind-specific metadata")
    func preservesKindSpecificMetadata() throws {
        let scalar = try Self.descriptor(named: "e2e_scalar_category").kind
        #expect(scalar.fieldNames == ["category", "status"])
        #expect(scalar.fields.map(\.order) == [.ascending, .descending])
        #expect(scalar.metadata.isEmpty)

        for name in [
            "e2e_sum_category_amount",
            "e2e_min_category_amount",
            "e2e_max_category_amount",
            "e2e_average_category_amount",
        ] {
            let metadata = try AggregationIndexMetadata(
                canonical: Self.descriptor(named: name).kind
            )
            #expect(metadata.groupByFieldNames == ["category"])
            #expect(metadata.valueFieldName == "amount")
            #expect(metadata.valueType == .float64)
        }

        let version = try Self.descriptor(named: "e2e_version_id").kind
        #expect(version.metadata["strategy"]?.stringValue == "keepLast")
        #expect(version.metadata["strategyCount"]?.int64Value == 5)

        let countNotNull = try Self.descriptor(
            named: "e2e_count_not_null_category_optional_tag"
        ).kind
        #expect(countNotNull.fieldNames == ["category", "optionalTag"])
        #expect(countNotNull.metadata.isEmpty)

        let leaderboard = try TimeWindowLeaderboardIndexKind<IndexMacroE2ERecord>(
            canonical: Self.descriptor(
                named: "e2e_time_window_leaderboard_category_score"
            ).kind
        )
        #expect(leaderboard.groupByFieldNames == ["category"])
        #expect(leaderboard.scoreFieldName == "score")
        #expect(leaderboard.window == .weekly)
        #expect(leaderboard.windowCount == 4)

        let distinct = try AggregationIndexMetadata(
            canonical: Self.descriptor(named: "e2e_distinct_category_user").kind
        )
        #expect(distinct.groupByFieldNames == ["category"])
        #expect(distinct.valueFieldName == "userID")
        #expect(distinct.precision == 12)

        let percentile = try AggregationIndexMetadata(
            canonical: Self.descriptor(
                named: "e2e_percentile_category_latency"
            ).kind
        )
        #expect(percentile.groupByFieldNames == ["category"])
        #expect(percentile.valueFieldName == "latency")
        #expect(percentile.compression == 50)

        let vector = try VectorIndexKind<IndexMacroE2ERecord>(
            canonical: Self.descriptor(named: "e2e_vector_embedding").kind
        )
        #expect(vector.fieldNames == ["embedding"])
        #expect(vector.dimensions == 3)
        #expect(vector.metric == .cosine)

        let fullText = try FullTextIndexKind<IndexMacroE2ERecord>(
            canonical: Self.descriptor(named: "e2e_fulltext_title_body").kind
        )
        #expect(fullText.fieldNames == ["title", "body"])
        #expect(fullText.tokenizer == .ngram)
        #expect(fullText.storePositions == false)
        #expect(fullText.ngramSize == 2)
        #expect(fullText.minTermLength == 1)

        let spatial = try SpatialIndexKind<IndexMacroE2ERecord>(
            canonical: Self.descriptor(
                named: "e2e_spatial_latitude_longitude"
            ).kind
        )
        #expect(spatial.fieldNames == ["location"])
        #expect(spatial.encoding == .s2)
        #expect(spatial.level == 12)

        let rank = try Self.descriptor(named: "e2e_rank_score").kind
        #expect(rank.fieldNames == ["score"])
        #expect(try rank.requireScalarType("scoreType") == .int64)
        #expect(try rank.requireInt("bucketSize") == 50)

        let permuted = try PermutedIndexKind<IndexMacroE2ERecord>(
            canonical: Self.descriptor(
                named: "e2e_permuted_category_status_title"
            ).kind
        )
        #expect(permuted.fieldNames == ["category", "status", "title"])
        #expect(permuted.permutation.indices == [1, 0, 2])

        let graph = try GraphIndexKind<IndexMacroE2ERecord>(
            canonical: Self.descriptor(
                named: "e2e_graph_subject_predicate_object_graph"
            ).kind
        )
        #expect(graph.fieldNames == ["subject", "predicate", "object", "graphName"])
        #expect(graph.fromField == "subject")
        #expect(graph.edgeField == "predicate")
        #expect(graph.toField == "object")
        #expect(graph.graphField == "graphName")
        #expect(graph.strategy == .hexastore)

    }

    private static let expectedSpecs: [ExpectedIndexSpec] = [
        .init(name: "e2e_scalar_category", kindIdentifier: "scalar", fieldNames: ["category", "status"]),
        .init(name: "e2e_count_category", kindIdentifier: "count", fieldNames: ["category"]),
        .init(name: "e2e_sum_category_amount", kindIdentifier: "sum", fieldNames: ["category", "amount"]),
        .init(name: "e2e_min_category_amount", kindIdentifier: "min", fieldNames: ["category", "amount"]),
        .init(name: "e2e_max_category_amount", kindIdentifier: "max", fieldNames: ["category", "amount"]),
        .init(name: "e2e_average_category_amount", kindIdentifier: "average", fieldNames: ["category", "amount"]),
        .init(name: "e2e_version_id", kindIdentifier: "version", fieldNames: ["id"]),
        .init(name: "e2e_count_updates_id", kindIdentifier: "count_updates", fieldNames: ["id"]),
        .init(name: "e2e_count_not_null_category_optional_tag", kindIdentifier: "count_not_null", fieldNames: ["category", "optionalTag"]),
        .init(name: "e2e_bitmap_status", kindIdentifier: "bitmap", fieldNames: ["status"]),
        .init(name: "e2e_time_window_leaderboard_category_score", kindIdentifier: "time_window_leaderboard", fieldNames: ["category", "score"]),
        .init(name: "e2e_distinct_category_user", kindIdentifier: "distinct", fieldNames: ["category", "userID"]),
        .init(name: "e2e_percentile_category_latency", kindIdentifier: "percentile", fieldNames: ["category", "latency"]),
        .init(name: "e2e_vector_embedding", kindIdentifier: "vector", fieldNames: ["embedding"]),
        .init(name: "e2e_fulltext_title_body", kindIdentifier: "fulltext", fieldNames: ["title", "body"]),
        .init(name: "e2e_spatial_latitude_longitude", kindIdentifier: "spatial", fieldNames: ["location"]),
        .init(name: "e2e_rank_score", kindIdentifier: "rank", fieldNames: ["score"]),
        .init(name: "e2e_permuted_category_status_title", kindIdentifier: "permuted", fieldNames: ["category", "status", "title"]),
        .init(name: "e2e_graph_subject_predicate_object_graph", kindIdentifier: "graph", fieldNames: ["subject", "predicate", "object", "graphName"]),
    ]

    private static func descriptor(named name: String) throws -> IndexDescriptor {
        try #require(
            try IndexMacroE2ERecord.indexDescriptors.first { $0.name == name }
        )
    }
}

private struct ExpectedIndexSpec: Sendable {
    let name: String
    let kindIdentifier: String
    let fieldNames: [String]

    init(name: String, kindIdentifier: String, fieldNames: [String]) {
        self.name = name
        self.kindIdentifier = kindIdentifier
        self.fieldNames = fieldNames
    }
}

@Persistable
private struct IndexMacroE2ERecord {
    var id: String = "fixture-id"
    #Index(
        .scalar,
        fields: [
            \IndexMacroE2ERecord.category,
            \IndexMacroE2ERecord.status,
        ],
        orders: [.ascending, .descending],
        storedFields: [\IndexMacroE2ERecord.title],
        unique: true,
        name: "e2e_scalar_category"
    )
    #Index(
        .count,
        groupBy: [\IndexMacroE2ERecord.category],
        name: "e2e_count_category"
    )
    #Index(
        .sum,
        groupBy: [\IndexMacroE2ERecord.category],
        value: \IndexMacroE2ERecord.amount,
        name: "e2e_sum_category_amount"
    )
    #Index(
        .minimum,
        groupBy: [\IndexMacroE2ERecord.category],
        value: \IndexMacroE2ERecord.amount,
        name: "e2e_min_category_amount"
    )
    #Index(
        .maximum,
        groupBy: [\IndexMacroE2ERecord.category],
        value: \IndexMacroE2ERecord.amount,
        name: "e2e_max_category_amount"
    )
    #Index(
        .average,
        groupBy: [\IndexMacroE2ERecord.category],
        value: \IndexMacroE2ERecord.amount,
        name: "e2e_average_category_amount"
    )
    #Index(
        .version(strategy: .keepLast(5)),
        field: \IndexMacroE2ERecord.id,
        name: "e2e_version_id"
    )
    #Index(
        .countUpdates,
        field: \IndexMacroE2ERecord.id,
        name: "e2e_count_updates_id"
    )
    #Index(
        .countNotNull,
        groupBy: [\IndexMacroE2ERecord.category],
        value: \IndexMacroE2ERecord.optionalTag,
        name: "e2e_count_not_null_category_optional_tag"
    )
    #Index(
        .bitmap,
        field: \IndexMacroE2ERecord.status,
        name: "e2e_bitmap_status"
    )
    #Index(
        .timeWindowLeaderboard(
            window: .weekly,
            windowCount: 4
        ),
        groupBy: [\IndexMacroE2ERecord.category],
        field: \IndexMacroE2ERecord.score,
        name: "e2e_time_window_leaderboard_category_score"
    )
    #Index(
        .distinct(precision: 12),
        groupBy: [\IndexMacroE2ERecord.category],
        value: \IndexMacroE2ERecord.userID,
        name: "e2e_distinct_category_user"
    )
    #Index(
        .percentile(compression: 50),
        groupBy: [\IndexMacroE2ERecord.category],
        value: \IndexMacroE2ERecord.latency,
        name: "e2e_percentile_category_latency"
    )
    #Index(
        .vector(
            dimensions: 3,
            metric: .cosine
        ),
        embedding: \IndexMacroE2ERecord.embedding,
        name: "e2e_vector_embedding"
    )
    #Index(
        .fullText(
            tokenizer: .ngram,
            storePositions: false,
            ngramSize: 2,
            minTermLength: 1
        ),
        fields: [
            \IndexMacroE2ERecord.title,
            \IndexMacroE2ERecord.body,
        ],
        name: "e2e_fulltext_title_body"
    )
    #Index(
        .spatial(
            encoding: .s2,
            level: 12
        ),
        location: \IndexMacroE2ERecord.location,
        name: "e2e_spatial_latitude_longitude"
    )
    #Index(
        .rank(bucketSize: 50),
        field: \IndexMacroE2ERecord.score,
        name: "e2e_rank_score"
    )
    #Index(
        .permuted(permutation: .swapping(0, 1, size: 3)),
        fields: [
            \IndexMacroE2ERecord.category,
            \IndexMacroE2ERecord.status,
            \IndexMacroE2ERecord.title,
        ],
        name: "e2e_permuted_category_status_title"
    )
    #Index(
        .graph(strategy: .hexastore),
        from: \IndexMacroE2ERecord.subject,
        edge: \IndexMacroE2ERecord.predicate,
        to: \IndexMacroE2ERecord.object,
        graph: \IndexMacroE2ERecord.graphName,
        name: "e2e_graph_subject_predicate_object_graph"
    )

    var category: String
    var status: String
    var title: String
    var body: String
    var amount: Double
    var score: Int64
    var latency: Double
    var userID: String
    var optionalTag: String?
    var embedding: Vector
    var location: GeographicPoint
    var subject: String
    var predicate: String
    var object: String
    var graphName: String
    var customerID: String?
}
