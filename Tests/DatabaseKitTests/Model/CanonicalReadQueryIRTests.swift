import DatabaseTypes
import Testing
import Foundation
import DatabaseKit
import DatabaseKit

protocol CanonicalReadDocument: Polymorphable {
    var id: String { get }
    var title: String { get }
}

extension CanonicalReadDocument {
    static var polymorphableType: String { "CanonicalReadDocument" }
    static var polymorphicDirectoryPathComponents: [DirectoryPathComponent] {
        [.staticPath("canonical-read-documents")]
    }
}

struct CanonicalReadArticle: Persistable, Sendable, CanonicalReadDocument {
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

struct CanonicalReadReport: Persistable, Sendable, CanonicalReadDocument {
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
    static var polymorphicDirectoryPathComponents: [DirectoryPathComponent] {
        [.staticPath("indexed-canonical-read-documents")]
    }
    static var polymorphicIndexes: [PolymorphicIndexDefinition] {
        [
            PolymorphicIndexDefinition(
                name: "IndexedCanonicalReadDocument_title",
                definition: .scalar,
                fields: [.init(name: "title")]
            ),
            PolymorphicIndexDefinition(
                name: "IndexedCanonicalReadDocument_id",
                definition: .scalar,
                fields: [.init(name: "id")]
            )
        ]
    }
}

struct IndexedCanonicalReadArticle: Persistable, Sendable, IndexedCanonicalReadDocument {
    typealias ID = String

    var id: String
    var title: String

    static var persistableType: String { "IndexedCanonicalReadArticle" }
    static var allFields: [String] { ["id", "title"] }
    static var fieldSchemas: [FieldSchema] {
        [
            FieldSchema(name: "id", fieldNumber: 1, type: .string),
            FieldSchema(name: "title", fieldNumber: 2, type: .string),
        ]
    }
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

struct IndexedCanonicalReadReport: Persistable, Sendable, IndexedCanonicalReadDocument {
    typealias ID = String

    var id: String
    var title: String

    static var persistableType: String { "IndexedCanonicalReadReport" }
    static var allFields: [String] { ["id", "title"] }
    static var fieldSchemas: [FieldSchema] {
        [
            FieldSchema(name: "id", fieldNumber: 1, type: .string),
            FieldSchema(name: "title", fieldNumber: 2, type: .string),
        ]
    }
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

@Polymorphable
protocol DifferentlyOrderedDocument: Polymorphable {
    var id: String { get }
    var title: String { get }

    #PolymorphicIndex(
        .scalar,
        fields: ["title"],
        name: "DifferentlyOrderedDocument_title"
    )
}

@Persistable
struct TitleSecondDocument: DifferentlyOrderedDocument {
    var id: String
    var title: String
}

@Persistable
struct TitleFirstDocument: DifferentlyOrderedDocument {
    var title: String
    var id: String
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

        #expect(first.kind.fields.map(\.number) == [1])
        #expect(second.kind.fields.map(\.number) == [2])
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
        #expect(articleDescriptor.name == "IndexedCanonicalReadDocument_title")
        #expect(articleDescriptor.fieldNames == ["title"])
        #expect(articleDescriptor.kind.identifier == "scalar")
        #expect(articleDescriptor.kind.subspaceStructure == .flat)
        #expect(articleDescriptor.kind.metadata.isEmpty)

        #expect(reportDescriptor.name == "IndexedCanonicalReadDocument_title")
        #expect(reportDescriptor.fieldNames == ["title"])
        #expect(reportDescriptor.kind.identifier == "scalar")
        #expect(reportDescriptor.kind.subspaceStructure == .flat)
        #expect(reportDescriptor.kind.metadata.isEmpty)
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
            #expect(descriptor.kind.identifier == "scalar")
            #expect(descriptor.kind.subspaceStructure == .flat)
            #expect(descriptor.kind.fieldNames == descriptor.fieldNames)
            #expect(descriptor.kind.metadata.isEmpty)
        }

        for descriptor in reportDescriptors {
            #expect(descriptor.kind.identifier == "scalar")
            #expect(descriptor.kind.subspaceStructure == .flat)
            #expect(descriptor.kind.fieldNames == descriptor.fieldNames)
            #expect(descriptor.kind.metadata.isEmpty)
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
        #expect(try CanonicalReadIndexedSchema.indexChanges(
            from: CanonicalReadUnindexedSchema.self
        ).added == expectedNames)
    }

    @Test("SelectQuery replacement operations preserve unrelated fields")
    func selectQueryReplacementMethodsPreserveFields() {
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
