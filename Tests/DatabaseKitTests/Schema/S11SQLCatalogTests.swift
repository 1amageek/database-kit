import Testing
@testable import DatabaseKit

@Suite("S11 Logical SQL Catalog")
struct S11SQLCatalogTests {
    private func relation(
        id: String = "relation",
        namespaceID: String = "namespace",
        name: String = "items",
        entityName: String = "Item",
        columns: [SQLColumn]? = nil,
        primaryKeyColumnIDs: [String]? = nil
    ) throws -> SQLRelation {
        try SQLRelation(
            id: id,
            namespaceID: namespaceID,
            name: name,
            entityName: entityName,
            columns: columns ?? [SQLColumn(id: "column", name: "value", fieldNumber: 7)],
            primaryKeyColumnIDs: primaryKeyColumnIDs
        )
    }

    private func expectDistinct<Value: Hashable>(_ left: Value, _ right: Value) {
        #expect(left != right)
        #expect(Set([left, right]).count == 2)
    }

    @Test("Stable logical identities preserve physical mapping and key order")
    func stableIdentitiesAndKeyOrder() throws {
        let columns = [
            try SQLColumn(id: "first", name: "a", fieldNumber: 9),
            try SQLColumn(id: "second", name: "b", fieldNumber: 2),
        ]
        let value = try relation(columns: columns, primaryKeyColumnIDs: ["second", "first"])
        let catalog = try SQLCatalog(
            namespaces: [SQLNamespace(id: "namespace", name: "public")],
            relations: [value]
        )
        #expect(catalog.relations[0].columns == columns)
        #expect(catalog.relations[0].primaryKeyColumnIDs == ["second", "first"])
        #expect(catalog.relations[0].columns[0].fieldNumber == 9)
        #expect(try relation().primaryKeyColumnIDs == nil)
        #expect(try relation(columns: []).columns.isEmpty)
    }

    @Test("All identifier construction boundaries reject empty and NUL names")
    func malformedIdentifiersFail() throws {
        let column = try SQLColumn(id: "column", name: "value", fieldNumber: 1)
        for (invalid, error) in [("", SQLCatalogError.emptyIdentifier), ("a\u{0}b", .nulInIdentifier)] {
            #expect(throws: error) { try SQLNamespace(id: invalid, name: "public") }
            #expect(throws: error) { try SQLNamespace(id: "namespace", name: invalid) }
            #expect(throws: error) { try SQLColumn(id: invalid, name: "value", fieldNumber: 1) }
            #expect(throws: error) { try SQLColumn(id: "column", name: invalid, fieldNumber: 1) }
            #expect(throws: error) { try relation(id: invalid) }
            #expect(throws: error) { try relation(namespaceID: invalid) }
            #expect(throws: error) { try relation(name: invalid) }
            #expect(throws: error) { try relation(entityName: invalid) }
            #expect(throws: error) { try relation(columns: [column], primaryKeyColumnIDs: [invalid]) }
            #expect(throws: error) { try SQLSearchPath(entries: [.schema(invalid)]) }
        }
        for invalid in [0, -1, Int.min] {
            #expect(throws: SQLCatalogError.invalidFieldNumber(invalid)) {
                try SQLColumn(id: "column", name: "value", fieldNumber: invalid)
            }
        }
    }

    @Test("Namespace IDs and names have catalog-wide uniqueness")
    func namespaceCollisionsFail() throws {
        let first = try SQLNamespace(id: "one", name: "public")
        #expect(throws: SQLCatalogError.duplicateNamespaceID("one")) {
            try SQLCatalog(namespaces: [first, SQLNamespace(id: "one", name: "other")], relations: [])
        }
        #expect(throws: SQLCatalogError.duplicateNamespaceName("public")) {
            try SQLCatalog(namespaces: [first, SQLNamespace(id: "two", name: "public")], relations: [])
        }
    }

    @Test("Relations reject duplicate IDs, namespace names and physical bindings")
    func relationCollisionsAndReferencesFail() throws {
        let namespace = try SQLNamespace(id: "namespace", name: "public")
        let first = try relation()
        #expect(throws: SQLCatalogError.duplicateRelationID("relation")) {
            try SQLCatalog(namespaces: [namespace], relations: [first, relation(name: "other", entityName: "Other")])
        }
        #expect(throws: SQLCatalogError.duplicateRelationName(namespaceID: "namespace", name: "items")) {
            try SQLCatalog(namespaces: [namespace], relations: [first, relation(id: "other", entityName: "Other")])
        }
        #expect(throws: SQLCatalogError.unknownNamespaceID("missing")) {
            try SQLCatalog(namespaces: [namespace], relations: [relation(namespaceID: "missing")])
        }
        #expect(throws: SQLCatalogError.duplicateEntityName("Item")) {
            try SQLCatalog(namespaces: [namespace], relations: [first, relation(id: "other", name: "other")])
        }
    }

    @Test("Column ID, name and physical field number collisions are independent")
    func columnCollisionsFail() throws {
        let first = try SQLColumn(id: "first", name: "a", fieldNumber: 1)
        #expect(throws: SQLCatalogError.duplicateColumnID("first")) {
            try relation(columns: [first, SQLColumn(id: "first", name: "b", fieldNumber: 2)])
        }
        #expect(throws: SQLCatalogError.duplicateColumnName("a")) {
            try relation(columns: [first, SQLColumn(id: "second", name: "a", fieldNumber: 2)])
        }
        #expect(throws: SQLCatalogError.duplicateFieldNumber(1)) {
            try relation(columns: [first, SQLColumn(id: "second", name: "b", fieldNumber: 1)])
        }
    }

    @Test("Primary keys reject empty, duplicate and missing column references")
    func primaryKeyFailures() throws {
        #expect(throws: SQLCatalogError.emptyPrimaryKey) {
            try relation(primaryKeyColumnIDs: [])
        }
        #expect(throws: SQLCatalogError.duplicatePrimaryKeyColumnID("column")) {
            try relation(primaryKeyColumnIDs: ["column", "column"])
        }
        #expect(throws: SQLCatalogError.unknownPrimaryKeyColumnID("missing")) {
            try relation(primaryKeyColumnIDs: ["missing"])
        }
    }

    @Test("Relation names and column IDs are scoped to their semantic parent")
    func identityScopes() throws {
        let catalog = try SQLCatalog(
            namespaces: [SQLNamespace(id: "one", name: "one"), SQLNamespace(id: "two", name: "two")],
            relations: [
                relation(id: "first", namespaceID: "one", entityName: "First"),
                relation(id: "second", namespaceID: "two", entityName: "Second"),
            ]
        )
        #expect(catalog.relations.count == 2)
        #expect(catalog.relations[0].name == catalog.relations[1].name)
        #expect(catalog.relations[0].columns[0].id == catalog.relations[1].columns[0].id)
    }

    @Test("Byte-distinct Unicode identifiers coexist in catalogs")
    func exactUnicodeCatalogIdentity() throws {
        let composed = "\u{00e9}"
        let decomposed = "e\u{0301}"
        let namespaces = [
            try SQLNamespace(id: composed, name: composed),
            try SQLNamespace(id: decomposed, name: decomposed),
        ]
        let catalog = try SQLCatalog(
            namespaces: namespaces,
            relations: [
                relation(id: composed, namespaceID: composed, name: composed, entityName: composed),
                relation(id: decomposed, namespaceID: decomposed, name: decomposed, entityName: decomposed),
                relation(id: "third", namespaceID: composed, name: decomposed, entityName: "Third"),
            ]
        )
        #expect(catalog.namespaces.count == 2)
        #expect(catalog.relations.count == 3)
        #expect(throws: SQLCatalogError.unknownNamespaceID(decomposed)) {
            try SQLCatalog(namespaces: [namespaces[0]], relations: [relation(namespaceID: decomposed)])
        }
    }

    @Test("Every string-bearing declaration uses exact equality and hashing")
    func exactEqualityAndHashing() throws {
        let a = "\u{00e9}"
        let b = "e\u{0301}"
        expectDistinct(try SQLNamespace(id: a, name: "same"), try SQLNamespace(id: b, name: "same"))
        expectDistinct(try SQLNamespace(id: "same", name: a), try SQLNamespace(id: "same", name: b))
        expectDistinct(try SQLColumn(id: a, name: "same", fieldNumber: 1), try SQLColumn(id: b, name: "same", fieldNumber: 1))
        expectDistinct(try SQLColumn(id: "same", name: a, fieldNumber: 1), try SQLColumn(id: "same", name: b, fieldNumber: 1))
        expectDistinct(try relation(id: a), try relation(id: b))
        expectDistinct(try relation(namespaceID: a), try relation(namespaceID: b))
        expectDistinct(try relation(name: a), try relation(name: b))
        expectDistinct(try relation(entityName: a), try relation(entityName: b))
        expectDistinct(SQLSearchPathEntry.schema(a), SQLSearchPathEntry.schema(b))
        expectDistinct(try SQLSearchPath(entries: [.schema(a)]), try SQLSearchPath(entries: [.schema(b)]))
        expectDistinct(
            try SQLCatalog(namespaces: [SQLNamespace(id: "same", name: a)], relations: []),
            try SQLCatalog(namespaces: [SQLNamespace(id: "same", name: b)], relations: [])
        )
        let identical = try relation(primaryKeyColumnIDs: ["column"])
        #expect(Set([identical, try relation(primaryKeyColumnIDs: ["column"])]).count == 1)
    }

    @Test("Primary-key references and identity preserve exact Unicode spelling")
    func exactPrimaryKeyIdentity() throws {
        let a = "\u{00e9}"
        let b = "e\u{0301}"
        let columns = [
            try SQLColumn(id: a, name: a, fieldNumber: 1),
            try SQLColumn(id: b, name: b, fieldNumber: 2),
        ]
        let first = try relation(columns: columns, primaryKeyColumnIDs: [a])
        let second = try relation(columns: columns, primaryKeyColumnIDs: [b])
        expectDistinct(first, second)
        #expect(try relation(columns: columns, primaryKeyColumnIDs: [a, b]).primaryKeyColumnIDs?.count == 2)
        #expect(throws: SQLCatalogError.unknownPrimaryKeyColumnID(b)) {
            try relation(columns: [columns[0]], primaryKeyColumnIDs: [b])
        }
    }

    @Test("Search paths preserve defaults, empty paths, repeated entries and case")
    func searchPathDeclarations() throws {
        #expect(SQLSearchPath.default.entries == [.currentUser, .schema("public")])
        #expect(try SQLSearchPath(entries: []).entries.isEmpty)
        let entries: [SQLSearchPathEntry] = [.schema("Public"), .currentUser, .schema("Public"), .schema("public")]
        #expect(try SQLSearchPath(entries: entries).entries == entries)
        expectDistinct(SQLSearchPathEntry.currentUser, .schema("$user"))
    }

    @Test("Declaration identity preserves array order and does not infer physical schema")
    func representationOrderAndIntrinsicBoundary() throws {
        let first = try SQLColumn(id: "first", name: "a", fieldNumber: Int.max)
        let second = try SQLColumn(id: "second", name: "b", fieldNumber: 1)
        expectDistinct(
            try relation(columns: [first, second]),
            try relation(columns: [second, first])
        )
        expectDistinct(
            try relation(columns: [first, second], primaryKeyColumnIDs: ["first", "second"]),
            try relation(columns: [first, second], primaryKeyColumnIDs: ["second", "first"])
        )
        let one = try SQLNamespace(id: "one", name: "One.With.Dot")
        let two = try SQLNamespace(id: "two", name: "Two")
        let empty = try SQLCatalog(namespaces: [], relations: [])
        #expect(empty.relations.isEmpty)
        expectDistinct(
            try SQLCatalog(namespaces: [one, two], relations: []),
            try SQLCatalog(namespaces: [two, one], relations: [])
        )
        let bound = try relation(namespaceID: "one", entityName: "UnregisteredPhysicalEntity", columns: [first])
        #expect(try SQLCatalog(namespaces: [one], relations: [bound]).relations[0].columns[0].fieldNumber == Int.max)
    }
}
