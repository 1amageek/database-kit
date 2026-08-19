import DatabaseTypes
import Testing
import Foundation
import DatabaseKit

@Polymorphable
@PolymorphicDirectory("canonical-read-documents")
protocol CanonicalReadDocument:
    Polymorphable<CanonicalReadDocumentPolymorphicGroup>
{
    var id: String { get }
    var title: String { get }
}

@Persistable
struct CanonicalReadArticle: CanonicalReadDocument {
    var id: String
    var title: String
}

@Persistable
struct CanonicalReadReport: CanonicalReadDocument {
    var id: String
    var title: String
}

@Polymorphable
@PolymorphicDirectory("indexed-canonical-read-documents")
@PolymorphicIndex(
    .ordered(
        name: "IndexedCanonicalReadDocument_title",
        keys: [.ascending("title")]
    )
)
@PolymorphicIndex(
    .ordered(
        name: "IndexedCanonicalReadDocument_id",
        keys: [.ascending("id")]
    )
)
protocol IndexedCanonicalReadDocument:
    Polymorphable<IndexedCanonicalReadDocumentPolymorphicGroup>
{
    var id: String { get }
    var title: String { get }
}

@Persistable
struct IndexedCanonicalReadArticle: IndexedCanonicalReadDocument {
    var id: String
    var title: String
}

@Persistable
struct IndexedCanonicalReadReport: IndexedCanonicalReadDocument {
    var id: String
    var title: String
}

enum CanonicalReadUnindexedSchema: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var entities: [Schema.Entity] {
        get throws(SchemaEntityError) {
            [
                try CanonicalReadArticle.schemaEntity,
                try CanonicalReadReport.schemaEntity,
            ]
        }
    }
}

enum CanonicalReadIndexedSchema: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static var entities: [Schema.Entity] {
        get throws(SchemaEntityError) {
            [
                try IndexedCanonicalReadArticle.schemaEntity,
                try IndexedCanonicalReadReport.schemaEntity,
            ]
        }
    }
}

@Suite("Canonical Read QueryIR")
struct CanonicalReadQueryIRTests {
    @Test("Schema builds polymorphic group catalog")
    func schemaBuildsPolymorphicGroupCatalog() throws {
        let schema = try Schema(
            entities: [
                try CanonicalReadArticle.schemaEntity,
                try CanonicalReadReport.schemaEntity,
            ]
        )
        let group = try #require(schema.polymorphicGroup(identifier: "CanonicalReadDocument"))

        #expect(group.identifier == "CanonicalReadDocument")
        #expect(group.memberTypeNames == ["CanonicalReadArticle", "CanonicalReadReport"])
        #expect(schema.polymorphicIndexCatalog(identifier: "CanonicalReadDocument").isEmpty)
    }

    @Test("Polymorphic logical fields allow concrete field numbers to differ")
    func polymorphicLogicalFieldsAllowConcreteFieldNumbersToDiffer() throws {
        let schema = try Schema(
            entities: [
                try TitleSecondDocument.schemaEntity,
                try TitleFirstDocument.schemaEntity,
            ]
        )

        let first = try #require(
            schema.polymorphicIndexDescriptors(
                identifier: "DifferentlyOrderedDocument",
                memberType: TitleFirstDocument.self
            ).first
        )
        let second = try #require(
            schema.polymorphicIndexDescriptors(
                identifier: "DifferentlyOrderedDocument",
                memberType: TitleSecondDocument.self
            ).first
        )

        #expect(first.keys.map(\.field.number) == [1])
        #expect(second.keys.map(\.field.number) == [2])
        #expect(
            schema.polymorphicIndexCatalog(
                identifier: "DifferentlyOrderedDocument"
            ).first?.fieldNames == ["title"]
        )
    }

    @Test("Schema materializes canonical polymorphic index descriptors")
    func schemaPreservesConcretePolymorphicIndexDescriptors() throws {
        let schema = try Schema(
            entities: [
                try IndexedCanonicalReadArticle.schemaEntity,
                try IndexedCanonicalReadReport.schemaEntity,
            ]
        )

        let logicalDescriptors = schema.polymorphicIndexCatalog(
            identifier: "IndexedCanonicalReadDocument"
        )
        #expect(logicalDescriptors.map(\.name) == [
            "IndexedCanonicalReadDocument_title",
            "IndexedCanonicalReadDocument_id",
        ])
        #expect(logicalDescriptors.map(\.fieldNames) == [["title"], ["id"]])
        #expect(logicalDescriptors.map(\.type) == [.ordered, .ordered])

        let articleDescriptors = schema.polymorphicIndexDescriptors(
            identifier: "IndexedCanonicalReadDocument",
            memberType: IndexedCanonicalReadArticle.self
        )
        let reportDescriptors = schema.polymorphicIndexDescriptors(
            identifier: "IndexedCanonicalReadDocument",
            memberType: IndexedCanonicalReadReport.self
        )
        let runtimeResolvedDescriptors = schema.polymorphicIndexDescriptors(
            identifier: "IndexedCanonicalReadDocument",
            memberTypeName: IndexedCanonicalReadArticle.persistableType
        )

        let articleDescriptor = try #require(articleDescriptors.first)
        let reportDescriptor = try #require(reportDescriptors.first)
        #expect(runtimeResolvedDescriptors == articleDescriptors)
        #expect(articleDescriptor.name == "IndexedCanonicalReadDocument_title")
        #expect(articleDescriptor.fieldNames == ["title"])
        #expect(articleDescriptor.type == .ordered)

        #expect(reportDescriptor.name == "IndexedCanonicalReadDocument_title")
        #expect(reportDescriptor.fieldNames == ["title"])
        #expect(reportDescriptor.type == .ordered)
    }

    @Test("Schema preserves all concrete polymorphic descriptors per member type")
    func schemaPreservesMultipleConcretePolymorphicIndexDescriptors() throws {
        let schema = try Schema(
            entities: [
                try IndexedCanonicalReadArticle.schemaEntity,
                try IndexedCanonicalReadReport.schemaEntity,
            ]
        )

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
            #expect(descriptor.type == .ordered)
            #expect(descriptor.keys.map(\.field.name) == descriptor.fieldNames)
        }

        for descriptor in reportDescriptors {
            #expect(descriptor.type == .ordered)
            #expect(descriptor.keys.map(\.field.name) == descriptor.fieldNames)
        }
    }

    @Test("VersionedSchema includes polymorphic logical indexes in index diffs")
    func versionedSchemaIncludesPolymorphicLogicalIndexesInIndexDiffs() throws {
        let expectedNames = Set([
            "IndexedCanonicalReadDocument_title",
            "IndexedCanonicalReadDocument_id",
        ])

        #expect(try CanonicalReadIndexedSchema.allIndexDescriptors.isEmpty)
        #expect(try CanonicalReadIndexedSchema.indexNames == expectedNames)
        let changes = try CanonicalReadIndexedSchema.polymorphicIndexChanges(
            from: CanonicalReadUnindexedSchema.self
        )
        #expect(Set(changes.map(\.identity.name)) == expectedNames)
        #expect(changes.allSatisfy {
            if case .added = $0 { return true }
            return false
        })
    }

    @Test("SelectQuery replacement operations preserve unrelated fields")
    func selectQueryReplacementMethodsPreserveFields() {
        let original = SelectQuery(
            projection: .all,
            source: .table(TableRef(table: "Document")),
            accessPath: .index(
                IndexScanSource(
                    indexName: "Document_vector_embedding",
                    indexType: .vector
                )
            ),
            filter: .equal(.column(ColumnRef("status")), .literal(.string("active"))),
            orderBy: [SortKey(.column(ColumnRef("createdAt")))],
            limit: 20,
            offset: 10,
            distinct: true,
            subqueries: [NamedSubquery(name: "docs", query: SelectQuery(projection: .all, source: .table(TableRef(table: "Document"))))],
            reduced: true,
            dataset: .explicit(
                defaultGraphs: ["graph-a"],
                namedGraphs: ["graph-b"]
            )
        )

        let updated = original
            .replacing(filter: .equal(.column(ColumnRef("status")), .literal(.string("archived"))))
            .replacing(orderBy: nil)
            .replacing(limit: 1)
            .replacing(offset: nil)

        #expect(updated.source == original.source)
        #expect(updated.accessPath == original.accessPath)
        #expect(updated.subqueries == original.subqueries)
        #expect(updated.dataset == original.dataset)
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

    @Test("SelectQuery nil replacement contract distinguishes typed clear from combined preserve")
    func selectQueryNilReplacementContract() {
        let original = SelectQuery(
            projection: .all,
            source: .table(TableRef(table: "Document")),
            filter: .equal(.column(ColumnRef("status")), .literal(.string("active"))),
            orderBy: [SortKey(.column(ColumnRef("createdAt")))],
            limit: 20,
            offset: 10
        )

        let preserved = original.replacing(
            filter: nil,
            orderBy: nil,
            limit: nil,
            offset: nil
        )

        #expect(preserved.filter == original.filter)
        #expect(preserved.orderBy == original.orderBy)
        #expect(preserved.limit == original.limit)
        #expect(preserved.offset == original.offset)

        let cleared = original
            .replacing(filter: nil)
            .replacing(orderBy: nil)
            .replacing(limit: nil)
            .replacing(offset: nil)

        #expect(cleared.filter == nil)
        #expect(cleared.orderBy == nil)
        #expect(cleared.limit == nil)
        #expect(cleared.offset == nil)
    }
}
