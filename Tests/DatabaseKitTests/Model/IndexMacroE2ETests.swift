import DatabaseTypes
import Testing
@testable import DatabaseKit

@Suite("#Index Macro E2E Tests")
struct IndexMacroE2ETests {
    @Test("#Index preserves every built-in semantic index declaration")
    func preservesBuiltInDeclarations() throws {
        let descriptors = try IndexMacroE2ERecord.indexDescriptors
        #expect(descriptors.map(\.name) == Self.expected.map(\.name))

        for expected in Self.expected {
            let descriptor = try #require(
                descriptors.first { $0.name == expected.name }
            )
            #expect(descriptor.type == expected.type)
            #expect(descriptor.fieldNames == expected.fieldNames)
        }

        let ordered = try Self.descriptor(named: "e2e_ordered_category")
        #expect(ordered.keys.map(\.order) == [.ascending, .descending])
        #expect(ordered.includedFieldNames == ["title"])
        #expect(ordered.isUnique)

        let history = try Self.descriptor(named: "e2e_history_id")
        guard case .history(_, .keepLast(let count)) =
            history.declaration.definition else {
            Issue.record("Expected history declaration")
            return
        }
        #expect(count == 5)

        let leaderboard = try Self.descriptor(named: "e2e_leaderboard")
        guard case .leaderboard(_, _, let window, let windowCount) =
            leaderboard.declaration.definition else {
            Issue.record("Expected leaderboard declaration")
            return
        }
        #expect(window == .weekly)
        #expect(windowCount == 4)

        let vector = try Self.descriptor(named: "e2e_vector_embedding")
        guard case .vector(_, let dimensions, let metric) =
            vector.declaration.definition else {
            Issue.record("Expected vector declaration")
            return
        }
        #expect(dimensions == 3)
        #expect(metric == .cosine)

        let text = try Self.descriptor(named: "e2e_text_title_body")
        guard case .text(
            _,
            .fullText(
                let tokenizer,
                let storePositions,
                let ngramSize,
                let minimumTermLength
            )
        ) = text.declaration.definition else {
            Issue.record("Expected full-text declaration")
            return
        }
        #expect(tokenizer == .ngram)
        #expect(storePositions == false)
        #expect(ngramSize == 2)
        #expect(minimumTermLength == 1)

        let graph = try Self.descriptor(named: "e2e_property_graph")
        #expect(graph.includedFieldNames == ["title"])
    }

    @Test("Schema catalog retains the complete declarations")
    func schemaCatalogRetainsDeclarations() throws {
        let schema = try Schema(
            entities: [try IndexMacroE2ERecord.schemaEntity]
        )
        let entity = try #require(schema.entity(for: IndexMacroE2ERecord.self))
        let descriptors = try IndexMacroE2ERecord.indexDescriptors
        #expect(entity.indexes == descriptors)
    }

    @Test("RDF graph indexes retain RDF field identity")
    func rdfGraphRetainsFieldIdentity() throws {
        let descriptor = try #require(try RDFDatasetRecord.indexDescriptors.first)
        #expect(descriptor.type == .graph(.rdf))
        #expect(
            descriptor.fieldNames
                == ["subject", "predicate", "object", "graph"]
        )
    }

    private static let expected: [ExpectedIndex] = [
        .init("e2e_ordered_category", .ordered, ["category", "status"]),
        .init("e2e_count_category", .aggregate(.count), ["category"]),
        .init("e2e_sum_category_amount", .aggregate(.sum), ["category", "amount"]),
        .init("e2e_min_category_amount", .aggregate(.minimum), ["category", "amount"]),
        .init("e2e_max_category_amount", .aggregate(.maximum), ["category", "amount"]),
        .init("e2e_average_category_amount", .aggregate(.average), ["category", "amount"]),
        .init("e2e_history_id", .history, ["id"]),
        .init("e2e_update_count_id", .updateCount, ["id"]),
        .init("e2e_non_null_category_tag", .aggregate(.nonNullCount), ["category", "optionalTag"]),
        .init("e2e_bitmap_status", .bitmap, ["status"]),
        .init("e2e_leaderboard", .leaderboard, ["category", "score"]),
        .init("e2e_distinct_category_user", .aggregate(.approximateDistinct), ["category", "userID"]),
        .init("e2e_percentile_category_latency", .aggregate(.percentile), ["category", "latency"]),
        .init("e2e_vector_embedding", .vector, ["embedding"]),
        .init("e2e_text_title_body", .text(.fullText), ["title", "body"]),
        .init("e2e_autocomplete_title", .text(.autocomplete), ["title"]),
        .init("e2e_spatial_location", .spatial, ["location"]),
        .init("e2e_rank_score", .rank, ["score"]),
        .init("e2e_property_graph", .graph(.property), ["subject", "predicate", "object", "graphName"]),
        .init("e2e_extension_factory", .ordered, ["category"]),
    ]

    private static func descriptor(named name: String) throws -> IndexDescriptor {
        try #require(
            try IndexMacroE2ERecord.indexDescriptors.first { $0.name == name }
        )
    }
}

private struct ExpectedIndex: Sendable {
    let name: String
    let type: IndexType
    let fieldNames: [String]

    init(_ name: String, _ type: IndexType, _ fieldNames: [String]) {
        self.name = name
        self.type = type
        self.fieldNames = fieldNames
    }
}

private extension IndexDeclaration {
    static func namedLookup(
        name: String,
        field: FieldReference
    ) -> Self {
        .ordered(name: name, keys: [.ascending(field)])
    }
}

@Persistable
private struct RDFDatasetRecord {
    #Directory<RDFDatasetRecord>("tests", "rdf-dataset")
    #Index(.graph(
        name: "rdf_dataset",
        definition: .rdf(
            subject: \RDFDatasetRecord.subject,
            predicate: \RDFDatasetRecord.predicate,
            object: \RDFDatasetRecord.object,
            graph: \RDFDatasetRecord.graph
        )
    ))

    var id: String
    var subject: RDFTerm
    var predicate: RDFTerm
    var object: RDFTerm
    var graph: RDFTerm
}

@Persistable
private struct IndexMacroE2ERecord {
    var id: String = "fixture-id"

    #Index(.ordered(
        name: "e2e_ordered_category",
        keys: [
            .ascending(\IndexMacroE2ERecord.category),
            .descending(\IndexMacroE2ERecord.status),
        ],
        includedFields: [\IndexMacroE2ERecord.title],
        unique: true
    ))
    #Index(.aggregate(
        name: "e2e_count_category",
        function: .count,
        groupBy: [.ascending(\IndexMacroE2ERecord.category)]
    ))
    #Index(.aggregate(
        name: "e2e_sum_category_amount",
        function: .sum,
        groupBy: [.ascending(\IndexMacroE2ERecord.category)],
        value: \IndexMacroE2ERecord.amount
    ))
    #Index(.aggregate(
        name: "e2e_min_category_amount",
        function: .minimum,
        groupBy: [.ascending(\IndexMacroE2ERecord.category)],
        value: \IndexMacroE2ERecord.amount
    ))
    #Index(.aggregate(
        name: "e2e_max_category_amount",
        function: .maximum,
        groupBy: [.ascending(\IndexMacroE2ERecord.category)],
        value: \IndexMacroE2ERecord.amount
    ))
    #Index(.aggregate(
        name: "e2e_average_category_amount",
        function: .average,
        groupBy: [.ascending(\IndexMacroE2ERecord.category)],
        value: \IndexMacroE2ERecord.amount
    ))
    #Index(.history(
        name: "e2e_history_id",
        version: \IndexMacroE2ERecord.id,
        retention: .keepLast(5)
    ))
    #Index(.updateCount(
        name: "e2e_update_count_id",
        field: \IndexMacroE2ERecord.id
    ))
    #Index(.aggregate(
        name: "e2e_non_null_category_tag",
        function: .nonNullCount,
        groupBy: [.ascending(\IndexMacroE2ERecord.category)],
        value: \IndexMacroE2ERecord.optionalTag
    ))
    #Index(.bitmap(
        name: "e2e_bitmap_status",
        field: \IndexMacroE2ERecord.status
    ))
    #Index(.leaderboard(
        name: "e2e_leaderboard",
        groupBy: [.ascending(\IndexMacroE2ERecord.category)],
        score: \IndexMacroE2ERecord.score,
        window: .weekly,
        windowCount: 4
    ))
    #Index(.aggregate(
        name: "e2e_distinct_category_user",
        function: .approximateDistinct(precision: 12),
        groupBy: [.ascending(\IndexMacroE2ERecord.category)],
        value: \IndexMacroE2ERecord.userID
    ))
    #Index(.aggregate(
        name: "e2e_percentile_category_latency",
        function: .percentile(compression: 50),
        groupBy: [.ascending(\IndexMacroE2ERecord.category)],
        value: \IndexMacroE2ERecord.latency
    ))
    #Index(.vector(
        name: "e2e_vector_embedding",
        embedding: \IndexMacroE2ERecord.embedding,
        dimensions: 3,
        metric: .cosine
    ))
    #Index(.text(
        name: "e2e_text_title_body",
        fields: [
            \IndexMacroE2ERecord.title,
            \IndexMacroE2ERecord.body,
        ],
        mode: .fullText(
            tokenizer: .ngram,
            storePositions: false,
            ngramSize: 2,
            minimumTermLength: 1
        )
    ))
    #Index(.text(
        name: "e2e_autocomplete_title",
        fields: [\IndexMacroE2ERecord.title],
        mode: .autocomplete(
            minimumPrefixLength: 2,
            maximumPrefixLength: 12
        )
    ))
    #Index(.spatial(
        name: "e2e_spatial_location",
        location: \IndexMacroE2ERecord.location,
        encoding: .s2,
        level: 12
    ))
    #Index(.rank(
        name: "e2e_rank_score",
        score: \IndexMacroE2ERecord.score
    ))
    #Index(.graph(
        name: "e2e_property_graph",
        definition: .property(
            source: \IndexMacroE2ERecord.subject,
            label: .field(\IndexMacroE2ERecord.predicate),
            target: \IndexMacroE2ERecord.object,
            graph: \IndexMacroE2ERecord.graphName,
            strategy: .hexastore
        ),
        includedFields: [\IndexMacroE2ERecord.title]
    ))
    #Index(.namedLookup(
        name: "e2e_extension_factory",
        field: \IndexMacroE2ERecord.category
    ))

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
}
