import DatabaseTypes
import DatabaseValue
import Testing
@testable import Core
import FullText
import Graph
import Permuted
import Rank
import Geospatial
import Vector

@Suite("#Index Macro E2E Tests")
struct IndexMacroE2ETests {

    @Test("#Index builds descriptors for every database-kit index kind")
    func buildsDescriptorsForEveryIndexKind() throws {
        let descriptors = IndexMacroE2ERecord.indexDescriptors
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
        let schema = Schema([IndexMacroE2ERecord.self])
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
        #expect(scalar.fieldNames == ["category"])
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
        #expect(spatial.fieldNames == ["latitude", "longitude"])
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
        .init(name: "e2e_scalar_category", kindIdentifier: "scalar", fieldNames: ["category"]),
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
        .init(name: "e2e_spatial_latitude_longitude", kindIdentifier: "spatial", fieldNames: ["latitude", "longitude"]),
        .init(name: "e2e_rank_score", kindIdentifier: "rank", fieldNames: ["score"]),
        .init(name: "e2e_permuted_category_status_title", kindIdentifier: "permuted", fieldNames: ["category", "status", "title"]),
        .init(name: "e2e_graph_subject_predicate_object_graph", kindIdentifier: "graph", fieldNames: ["subject", "predicate", "object", "graphName"]),
    ]

    private static func descriptor(named name: String) throws -> IndexDescriptor {
        try #require(IndexMacroE2ERecord.indexDescriptors.first { $0.name == name })
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
    #Index(
        ScalarIndexKind<IndexMacroE2ERecord>(fields: [\.category]),
        storedFields: [\IndexMacroE2ERecord.title],
        unique: true,
        name: "e2e_scalar_category"
    )
    #Index(CountIndexKind<IndexMacroE2ERecord>(groupBy: [\.category]), name: "e2e_count_category")
    #Index(SumIndexKind<IndexMacroE2ERecord, Double>(groupBy: [\.category], value: \.amount), name: "e2e_sum_category_amount")
    #Index(MinIndexKind<IndexMacroE2ERecord, Double>(groupBy: [\.category], value: \.amount), name: "e2e_min_category_amount")
    #Index(MaxIndexKind<IndexMacroE2ERecord, Double>(groupBy: [\.category], value: \.amount), name: "e2e_max_category_amount")
    #Index(AverageIndexKind<IndexMacroE2ERecord, Double>(groupBy: [\.category], value: \.amount), name: "e2e_average_category_amount")
    #Index(VersionIndexKind<IndexMacroE2ERecord>(field: \.id, strategy: .keepLast(5)), name: "e2e_version_id")
    #Index(CountUpdatesIndexKind<IndexMacroE2ERecord>(field: \.id), name: "e2e_count_updates_id")
    #Index(CountNotNullIndexKind<IndexMacroE2ERecord>(groupBy: [\.category], value: \.optionalTag), name: "e2e_count_not_null_category_optional_tag")
    #Index(BitmapIndexKind<IndexMacroE2ERecord>(field: \.status), name: "e2e_bitmap_status")
    #Index(
        TimeWindowLeaderboardIndexKind<IndexMacroE2ERecord>(
            scoreField: \.score,
            groupBy: [\.category],
            window: .weekly,
            windowCount: 4
        ),
        name: "e2e_time_window_leaderboard_category_score"
    )
    #Index(DistinctIndexKind<IndexMacroE2ERecord>(groupBy: [\.category], value: \.userID, precision: 12), name: "e2e_distinct_category_user")
    #Index(PercentileIndexKind<IndexMacroE2ERecord, Double>(groupBy: [\.category], value: \.latency, compression: 50), name: "e2e_percentile_category_latency")
    #Index(VectorIndexKind<IndexMacroE2ERecord>(embedding: \.embedding, dimensions: 3, metric: .cosine), name: "e2e_vector_embedding")
    #Index(
        FullTextIndexKind<IndexMacroE2ERecord>(
            fields: [\.title, \.body],
            tokenizer: .ngram,
            storePositions: false,
            ngramSize: 2,
            minTermLength: 1
        ),
        name: "e2e_fulltext_title_body"
    )
    #Index(
        SpatialIndexKind<IndexMacroE2ERecord>(
            latitude: \.latitude,
            longitude: \.longitude,
            encoding: .s2,
            level: 12
        ),
        name: "e2e_spatial_latitude_longitude"
    )
    #Index(RankIndexKind<IndexMacroE2ERecord, Int64>(field: \.score, bucketSize: 50), name: "e2e_rank_score")
    #Index(
        PermutedIndexKind<IndexMacroE2ERecord>(
            fields: [\.category, \.status, \.title],
            permutation: .swapping(0, 1, size: 3)
        ),
        name: "e2e_permuted_category_status_title"
    )
    #Index(
        GraphIndexKind<IndexMacroE2ERecord>(
            from: \.subject,
            edge: \.predicate,
            to: \.object,
            graph: \.graphName,
            strategy: .hexastore
        ),
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
    var embedding: [Float]
    var latitude: Double
    var longitude: Double
    var subject: String
    var predicate: String
    var object: String
    var graphName: String
    var customerID: String?
}
