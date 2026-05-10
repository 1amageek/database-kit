import Testing
import Foundation
import QueryIR
import DatabaseClientProtocol
import Core

protocol CanonicalReadDocument: Polymorphable {
    var id: String { get }
    var title: String { get }
}

extension CanonicalReadDocument {
    static var polymorphableType: String { "CanonicalReadDocument" }
    static var polymorphicDirectoryPathComponents: [any DirectoryPathElement] {
        [Path("canonical-read-documents")]
    }
}

struct CanonicalReadArticle: Persistable, Codable, Sendable, CanonicalReadDocument {
    typealias ID = String

    var id: String
    var title: String

    static var persistableType: String { "CanonicalReadArticle" }
    static var allFields: [String] { ["id", "title"] }
    static func fieldNumber(for fieldName: String) -> Int? {
        switch fieldName {
        case "id": return 1
        case "title": return 2
        default: return nil
        }
    }
    static func enumMetadata(for fieldName: String) -> EnumMetadata? { nil }
    subscript(dynamicMember member: String) -> (any Sendable)? {
        switch member {
        case "id": return id
        case "title": return title
        default: return nil
        }
    }
}

struct CanonicalReadReport: Persistable, Codable, Sendable, CanonicalReadDocument {
    typealias ID = String

    var id: String
    var title: String

    static var persistableType: String { "CanonicalReadReport" }
    static var allFields: [String] { ["id", "title"] }
    static func fieldNumber(for fieldName: String) -> Int? {
        switch fieldName {
        case "id": return 1
        case "title": return 2
        default: return nil
        }
    }
    static func enumMetadata(for fieldName: String) -> EnumMetadata? { nil }
    subscript(dynamicMember member: String) -> (any Sendable)? {
        switch member {
        case "id": return id
        case "title": return title
        default: return nil
        }
    }
}

protocol IndexedCanonicalReadDocument: Polymorphable {
    var id: String { get }
    var title: String { get }
}

extension IndexedCanonicalReadDocument {
    static var polymorphableType: String { "IndexedCanonicalReadDocument" }
    static var polymorphicDirectoryPathComponents: [any DirectoryPathElement] {
        [Path("indexed-canonical-read-documents")]
    }
    static var polymorphicIndexDescriptors: [IndexDescriptor] {
        [
            IndexDescriptor(
                name: "IndexedCanonicalReadDocument_title",
                keyPaths: [\Self.title],
                kind: ScalarIndexKind<Self>(fields: [\Self.title])
            ),
            IndexDescriptor(
                name: "IndexedCanonicalReadDocument_id",
                keyPaths: [\Self.id],
                kind: ScalarIndexKind<Self>(fields: [\Self.id])
            )
        ]
    }
}

struct IndexedCanonicalReadArticle: Persistable, Codable, Sendable, IndexedCanonicalReadDocument {
    typealias ID = String

    var id: String
    var title: String

    static var persistableType: String { "IndexedCanonicalReadArticle" }
    static var allFields: [String] { ["id", "title"] }
    static func fieldNumber(for fieldName: String) -> Int? {
        switch fieldName {
        case "id": return 1
        case "title": return 2
        default: return nil
        }
    }
    static func enumMetadata(for fieldName: String) -> EnumMetadata? { nil }
    static func fieldName(for keyPath: PartialKeyPath<Self>) -> String {
        let description = "\(keyPath)"
        if description.hasSuffix(".id") {
            return "id"
        }
        if description.hasSuffix(".title") {
            return "title"
        }
        return description
    }
    subscript(dynamicMember member: String) -> (any Sendable)? {
        switch member {
        case "id": return id
        case "title": return title
        default: return nil
        }
    }
}

struct IndexedCanonicalReadReport: Persistable, Codable, Sendable, IndexedCanonicalReadDocument {
    typealias ID = String

    var id: String
    var title: String

    static var persistableType: String { "IndexedCanonicalReadReport" }
    static var allFields: [String] { ["id", "title"] }
    static func fieldNumber(for fieldName: String) -> Int? {
        switch fieldName {
        case "id": return 1
        case "title": return 2
        default: return nil
        }
    }
    static func enumMetadata(for fieldName: String) -> EnumMetadata? { nil }
    static func fieldName(for keyPath: PartialKeyPath<Self>) -> String {
        let description = "\(keyPath)"
        if description.hasSuffix(".id") {
            return "id"
        }
        if description.hasSuffix(".title") {
            return "title"
        }
        return description
    }
    subscript(dynamicMember member: String) -> (any Sendable)? {
        switch member {
        case "id": return id
        case "title": return title
        default: return nil
        }
    }
}

enum CanonicalReadUnindexedSchema: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static let models: [any Persistable.Type] = [
        CanonicalReadArticle.self,
        CanonicalReadReport.self,
    ]
}

enum CanonicalReadIndexedSchema: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static let models: [any Persistable.Type] = [
        IndexedCanonicalReadArticle.self,
        IndexedCanonicalReadReport.self,
    ]
}

@Suite("Canonical Read QueryIR")
struct CanonicalReadQueryIRTests {
    @Test("QueryParameterValue preserves structured arrays and objects")
    func queryParameterValueRoundTrip() throws {
        let original = QueryParameterValue.object([
            "vector": .array([.double(0.1), .double(0.2), .double(0.3)]),
            "options": .object([
                "k": .int(10),
                "metric": .string("cosine"),
                "includeScores": .bool(true)
            ])
        ])

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(QueryParameterValue.self, from: data)
        #expect(decoded == original)
    }

    @Test("SelectQuery with accessPath round-trips through QueryRequest")
    func canonicalQueryRequestRoundTrip() throws {
        let selectQuery = SelectQuery(
            projection: .all,
            source: .table(TableRef(table: "Document")),
            accessPath: .index(
                IndexScanSource(
                    indexName: "Document_vector_embedding",
                    kindIdentifier: "vector",
                    parameters: [
                        "fieldName": .string("embedding"),
                        "dimensions": .int(3),
                        "queryVector": .array([.double(0.1), .double(0.2), .double(0.3)]),
                        "k": .int(5),
                        "metric": .string("cosine")
                    ]
                )
            ),
            limit: 5
        )

        let original = QueryRequest(
            statement: .select(selectQuery),
            options: ReadExecutionOptions(
                consistency: .snapshot,
                pageSize: 20,
                continuation: QueryContinuation("cursor-token")
            ),
            partitionValues: ["tenantID": "tenant-1"]
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(QueryRequest.self, from: data)

        guard case .select(let decodedSelectQuery) = decoded.statement else {
            Issue.record("Expected select statement")
            return
        }

        #expect(decodedSelectQuery == selectQuery)
        #expect(decoded.options.consistency == .snapshot)
        #expect(decoded.options.pageSize == 20)
        #expect(decoded.options.continuation?.token == "cursor-token")
        #expect(decoded.partitionValues == ["tenantID": "tenant-1"])
    }

    @Test("SelectQuery with logical source round-trips through QueryRequest")
    func logicalSourceRoundTrip() throws {
        let selectQuery = SelectQuery(
            projection: .all,
            source: .logical(
                LogicalSourceRef(
                    kindIdentifier: BuiltinLogicalSourceKind.polymorphic,
                    identifier: "CanonicalReadDocument",
                    alias: "docs"
                )
            ),
            filter: .equal(.column(ColumnRef(column: "title")), .literal(.string("Hello")))
        )

        let request = QueryRequest(statement: .select(selectQuery))
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(QueryRequest.self, from: data)

        guard case .select(let decodedSelectQuery) = decoded.statement else {
            Issue.record("Expected select statement")
            return
        }
        #expect(decodedSelectQuery == selectQuery)
    }

    @Test("Schema builds polymorphic group catalog")
    func schemaBuildsPolymorphicGroupCatalog() throws {
        let schema = Schema([CanonicalReadArticle.self, CanonicalReadReport.self])
        let group = try #require(schema.polymorphicGroup(identifier: "CanonicalReadDocument"))

        #expect(group.identifier == "CanonicalReadDocument")
        #expect(group.memberTypeNames == ["CanonicalReadArticle", "CanonicalReadReport"])
        #expect(schema.polymorphicIndexCatalog(identifier: "CanonicalReadDocument").isEmpty)
    }

    @Test("Schema preserves concrete KeyPaths for polymorphic index descriptors")
    func schemaPreservesConcretePolymorphicIndexDescriptors() throws {
        let schema = Schema([
            IndexedCanonicalReadArticle.self,
            IndexedCanonicalReadReport.self
        ])

        let logicalDescriptors = schema.polymorphicIndexCatalog(
            identifier: "IndexedCanonicalReadDocument"
        )
        #expect(logicalDescriptors.map(\.name) == [
            "IndexedCanonicalReadDocument_title",
            "IndexedCanonicalReadDocument_id",
        ])
        #expect(logicalDescriptors.map(\.fieldNames) == [["title"], ["id"]])
        #expect(logicalDescriptors.map(\.kindIdentifier) == ["scalar", "scalar"])

        let articleDescriptors = schema.polymorphicIndexDescriptors(
            identifier: "IndexedCanonicalReadDocument",
            memberType: IndexedCanonicalReadArticle.self
        )
        let reportDescriptors = schema.polymorphicIndexDescriptors(
            identifier: "IndexedCanonicalReadDocument",
            memberType: IndexedCanonicalReadReport.self
        )

        let articleDescriptor = try #require(articleDescriptors.first)
        let reportDescriptor = try #require(reportDescriptors.first)
        let articleKeyPath = try #require(articleDescriptor.keyPaths.first)
        let reportKeyPath = try #require(reportDescriptor.keyPaths.first)

        #expect(articleDescriptor.name == "IndexedCanonicalReadDocument_title")
        #expect(articleDescriptor.fieldNames == ["title"])
        #expect(articleKeyPath is PartialKeyPath<IndexedCanonicalReadArticle>)
        #expect(!(articleKeyPath is PartialKeyPath<IndexedCanonicalReadReport>))

        #expect(reportDescriptor.name == "IndexedCanonicalReadDocument_title")
        #expect(reportDescriptor.fieldNames == ["title"])
        #expect(reportKeyPath is PartialKeyPath<IndexedCanonicalReadReport>)
        #expect(!(reportKeyPath is PartialKeyPath<IndexedCanonicalReadArticle>))
    }

    @Test("Schema preserves all concrete polymorphic descriptors per member type")
    func schemaPreservesMultipleConcretePolymorphicIndexDescriptors() throws {
        let schema = Schema([
            IndexedCanonicalReadArticle.self,
            IndexedCanonicalReadReport.self
        ])

        let articleDescriptors = schema.polymorphicIndexDescriptors(
            identifier: "IndexedCanonicalReadDocument",
            memberType: IndexedCanonicalReadArticle.self
        )
        let reportDescriptors = schema.polymorphicIndexDescriptors(
            identifier: "IndexedCanonicalReadDocument",
            memberType: IndexedCanonicalReadReport.self
        )

        #expect(articleDescriptors.map(\.name) == [
            "IndexedCanonicalReadDocument_title",
            "IndexedCanonicalReadDocument_id",
        ])
        #expect(reportDescriptors.map(\.name) == [
            "IndexedCanonicalReadDocument_title",
            "IndexedCanonicalReadDocument_id",
        ])
        #expect(articleDescriptors.map(\.fieldNames) == [["title"], ["id"]])
        #expect(reportDescriptors.map(\.fieldNames) == [["title"], ["id"]])

        for descriptor in articleDescriptors {
            let keyPath = try #require(descriptor.keyPaths.first)
            #expect(keyPath is PartialKeyPath<IndexedCanonicalReadArticle>)
            #expect(!(keyPath is PartialKeyPath<IndexedCanonicalReadReport>))
            #expect(descriptor.kind is ScalarIndexKind<IndexedCanonicalReadArticle>)
            #expect(!(descriptor.kind is ScalarIndexKind<IndexedCanonicalReadReport>))
        }

        for descriptor in reportDescriptors {
            let keyPath = try #require(descriptor.keyPaths.first)
            #expect(keyPath is PartialKeyPath<IndexedCanonicalReadReport>)
            #expect(!(keyPath is PartialKeyPath<IndexedCanonicalReadArticle>))
            #expect(descriptor.kind is ScalarIndexKind<IndexedCanonicalReadReport>)
            #expect(!(descriptor.kind is ScalarIndexKind<IndexedCanonicalReadArticle>))
        }
    }

    @Test("VersionedSchema includes polymorphic logical indexes in index diffs")
    func versionedSchemaIncludesPolymorphicLogicalIndexesInIndexDiffs() {
        let expectedNames = Set([
            "IndexedCanonicalReadDocument_title",
            "IndexedCanonicalReadDocument_id",
        ])

        #expect(CanonicalReadIndexedSchema.allIndexDescriptors.isEmpty)
        #expect(CanonicalReadIndexedSchema.indexNames == expectedNames)
        #expect(CanonicalReadIndexedSchema.indexChanges(
            from: CanonicalReadUnindexedSchema.self
        ).added == expectedNames)
    }

    @Test("QueryResponse preserves row annotations and metadata")
    func canonicalQueryResponseRoundTrip() throws {
        let original = QueryResponse(
            rows: [
                QueryRow(
                    fields: ["id": .string("doc-1"), "title": .string("Vector Search")],
                    annotations: ["distance": .double(0.12), "rank": .int64(1)],
                    version: RecordVersionToken("row-version-1")
                )
            ],
            continuation: QueryContinuation("next-page"),
            metadata: [
                "fulltext.totalCount": .int64(42),
                "fulltext.facets.category": .array([
                    .array([.string("search"), .int64(10)]),
                    .array([.string("database"), .int64(8)])
                ])
            ],
            affectedRows: nil
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(QueryResponse.self, from: data)
        #expect(decoded.rows == original.rows)
        #expect(decoded.rows.first?.version?.value == "row-version-1")
        #expect(decoded.continuation == original.continuation)
        #expect(decoded.metadata == original.metadata)
    }

    @Test("SelectQuery replacing helpers preserve unrelated fields")
    func selectQueryReplacingHelpers() {
        let original = SelectQuery(
            projection: .all,
            source: .table(TableRef(table: "Document")),
            accessPath: .index(
                IndexScanSource(
                    indexName: "Document_vector_embedding",
                    kindIdentifier: "vector"
                )
            ),
            filter: .equal(.column(ColumnRef("status")), .literal(.string("active"))),
            orderBy: [SortKey(.column(ColumnRef("createdAt")))],
            limit: 20,
            offset: 10,
            distinct: true,
            subqueries: [NamedSubquery(name: "docs", query: SelectQuery(projection: .all, source: .table(TableRef(table: "Document"))))],
            reduced: true,
            from: ["graph-a"],
            fromNamed: ["graph-b"]
        )

        let updated = original
            .replacing(filter: .equal(.column(ColumnRef("status")), .literal(.string("archived"))))
            .replacing(orderBy: nil)
            .replacing(limit: 1)
            .replacing(offset: nil)

        #expect(updated.source == original.source)
        #expect(updated.accessPath == original.accessPath)
        #expect(updated.subqueries == original.subqueries)
        #expect(updated.from == original.from)
        #expect(updated.fromNamed == original.fromNamed)
        #expect(updated.distinct == original.distinct)
        #expect(updated.reduced == original.reduced)
        #expect(updated.orderBy == nil)
        #expect(updated.limit == 1)
        #expect(updated.offset == nil)

        guard case .equal(_, let rhs) = updated.filter else {
            Issue.record("Expected updated filter")
            return
        }
        #expect(rhs == .literal(.string("archived")))
    }
}
