import Testing
@testable import Core
import FullText
import Graph
import Permuted
import Rank
import Relationship
import Spatial
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
            #expect(descriptor.fieldNames == spec.descriptorFieldNames)
            #expect(descriptor.kind.fieldNames == spec.kindFieldNames)
            #expect(descriptor.keyPaths.count == spec.descriptorFieldNames.count)
            #expect(descriptor.keyPaths.allSatisfy { $0 is PartialKeyPath<IndexMacroE2ERecord> })
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
            #expect(catalog.fieldNames == spec.kindFieldNames)
        }

        let scalar = try #require(entity.indexes.first { $0.name == "e2e_scalar_category" })
        #expect(scalar.unique == true)
        #expect(scalar.storedFieldNames == ["title"])
    }

    @Test("#Index preserves kind-specific metadata")
    func preservesKindSpecificMetadata() throws {
        let scalar = try Self.kind(ScalarIndexKind<IndexMacroE2ERecord>.self, named: "e2e_scalar_category")
        #expect(scalar.fieldNames == ["category"])

        let sum = try Self.kind(SumIndexKind<IndexMacroE2ERecord, Double>.self, named: "e2e_sum_category_amount")
        #expect(sum.groupByFieldNames == ["category"])
        #expect(sum.valueFieldName == "amount")
        #expect(sum.valueTypeName == "Double")

        let min = try Self.kind(MinIndexKind<IndexMacroE2ERecord, Double>.self, named: "e2e_min_category_amount")
        #expect(min.groupByFieldNames == ["category"])
        #expect(min.valueFieldName == "amount")

        let max = try Self.kind(MaxIndexKind<IndexMacroE2ERecord, Double>.self, named: "e2e_max_category_amount")
        #expect(max.groupByFieldNames == ["category"])
        #expect(max.valueFieldName == "amount")

        let average = try Self.kind(AverageIndexKind<IndexMacroE2ERecord, Double>.self, named: "e2e_average_category_amount")
        #expect(average.groupByFieldNames == ["category"])
        #expect(average.valueFieldName == "amount")

        let version = try Self.kind(VersionIndexKind<IndexMacroE2ERecord>.self, named: "e2e_version_id")
        #expect(version.strategy == .keepLast(5))

        let countNotNull = try Self.kind(
            CountNotNullIndexKind<IndexMacroE2ERecord>.self,
            named: "e2e_count_not_null_category_optional_tag"
        )
        #expect(countNotNull.groupByFieldNames == ["category"])
        #expect(countNotNull.valueFieldName == "optionalTag")

        let leaderboard = try Self.kind(
            TimeWindowLeaderboardIndexKind<IndexMacroE2ERecord, Int64>.self,
            named: "e2e_time_window_leaderboard_category_score"
        )
        #expect(leaderboard.groupByFieldNames == ["category"])
        #expect(leaderboard.scoreFieldName == "score")
        #expect(leaderboard.scoreTypeName == "Int64")
        #expect(leaderboard.window == .weekly)
        #expect(leaderboard.windowCount == 4)

        let distinct = try Self.kind(DistinctIndexKind<IndexMacroE2ERecord>.self, named: "e2e_distinct_category_user")
        #expect(distinct.groupByFieldNames == ["category"])
        #expect(distinct.valueFieldName == "userID")
        #expect(distinct.precision == 12)

        let percentile = try Self.kind(
            PercentileIndexKind<IndexMacroE2ERecord, Double>.self,
            named: "e2e_percentile_category_latency"
        )
        #expect(percentile.groupByFieldNames == ["category"])
        #expect(percentile.valueFieldName == "latency")
        #expect(percentile.compression == 50)

        let vector = try Self.kind(VectorIndexKind<IndexMacroE2ERecord>.self, named: "e2e_vector_embedding")
        #expect(vector.fieldNames == ["embedding"])
        #expect(vector.dimensions == 3)
        #expect(vector.metric == .cosine)

        let fullText = try Self.kind(FullTextIndexKind<IndexMacroE2ERecord>.self, named: "e2e_fulltext_title_body")
        #expect(fullText.fieldNames == ["title", "body"])
        #expect(fullText.tokenizer == .ngram)
        #expect(fullText.storePositions == false)
        #expect(fullText.ngramSize == 2)
        #expect(fullText.minTermLength == 1)

        let spatial = try Self.kind(SpatialIndexKind<IndexMacroE2ERecord>.self, named: "e2e_spatial_latitude_longitude")
        #expect(spatial.fieldNames == ["latitude", "longitude"])
        #expect(spatial.encoding == .s2)
        #expect(spatial.level == 12)

        let rank = try Self.kind(RankIndexKind<IndexMacroE2ERecord, Int64>.self, named: "e2e_rank_score")
        #expect(rank.fieldNames == ["score"])
        #expect(rank.scoreTypeName == "Int64")
        #expect(rank.bucketSize == 50)

        let permuted = try Self.kind(PermutedIndexKind<IndexMacroE2ERecord>.self, named: "e2e_permuted_category_status_title")
        #expect(permuted.fieldNames == ["category", "status", "title"])
        #expect(permuted.permutation.indices == [1, 0, 2])

        let graph = try Self.kind(GraphIndexKind<IndexMacroE2ERecord>.self, named: "e2e_graph_subject_predicate_object_graph")
        #expect(graph.fieldNames == ["subject", "predicate", "object", "graphName"])
        #expect(graph.fromField == "subject")
        #expect(graph.edgeField == "predicate")
        #expect(graph.toField == "object")
        #expect(graph.graphField == "graphName")
        #expect(graph.strategy == .hexastore)

        let relationship = try Self.kind(
            RelationshipIndexKind<IndexMacroE2ERecord, IndexMacroE2ERelatedCustomer>.self,
            named: "e2e_relationship_customer_name"
        )
        #expect(relationship.foreignKeyFieldName == "customerID")
        #expect(relationship.relatedTypeName == "IndexMacroE2ERelatedCustomer")
        #expect(relationship.relatedFieldNames == ["name"])
        #expect(relationship.fieldNames == ["customer.name"])
        #expect(relationship.isToMany == false)
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
        .init(
            name: "e2e_relationship_customer_name",
            kindIdentifier: "relationship",
            descriptorFieldNames: ["customerID"],
            kindFieldNames: ["customer.name"]
        )
    ]

    private static func descriptor(named name: String) throws -> IndexDescriptor {
        try #require(IndexMacroE2ERecord.indexDescriptors.first { $0.name == name })
    }

    private static func kind<K: IndexKind>(_ kindType: K.Type, named name: String) throws -> K {
        let descriptor = try descriptor(named: name)
        return try #require(descriptor.kind as? K)
    }
}

private struct ExpectedIndexSpec: Sendable {
    let name: String
    let kindIdentifier: String
    let descriptorFieldNames: [String]
    let kindFieldNames: [String]

    init(name: String, kindIdentifier: String, fieldNames: [String]) {
        self.name = name
        self.kindIdentifier = kindIdentifier
        self.descriptorFieldNames = fieldNames
        self.kindFieldNames = fieldNames
    }

    init(name: String, kindIdentifier: String, descriptorFieldNames: [String], kindFieldNames: [String]) {
        self.name = name
        self.kindIdentifier = kindIdentifier
        self.descriptorFieldNames = descriptorFieldNames
        self.kindFieldNames = kindFieldNames
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
        TimeWindowLeaderboardIndexKind<IndexMacroE2ERecord, Int64>(
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
            permutation: try! Permutation(indices: [1, 0, 2])
        ),
        name: "e2e_permuted_category_status_title"
    )
    #Index(
        GraphIndexKind<IndexMacroE2ERecord>.rdf(
            subject: \.subject,
            predicate: \.predicate,
            object: \.object,
            graph: \.graphName,
            strategy: .hexastore
        ),
        name: "e2e_graph_subject_predicate_object_graph"
    )
    #Index(
        RelationshipIndexKind<IndexMacroE2ERecord, IndexMacroE2ERelatedCustomer>(
            foreignKey: \.customerID,
            relatedFields: [\IndexMacroE2ERelatedCustomer.name]
        ),
        name: "e2e_relationship_customer_name"
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

@Persistable
private struct IndexMacroE2ERelatedCustomer {
    var name: String
    var tier: String
}
