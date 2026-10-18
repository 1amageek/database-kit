import DatabaseKit
import Testing

@Suite("S16 durable virtual view source declarations")
struct S16SQLViewSourceTests {
    private func binding(_ kind: SQLViewSourceKind = .informationSchema, id: String = "tables") throws -> SQLViewSourceBinding {
        try SQLViewSourceBinding(kind: kind, schema: "information_schema", table: "tables", relationID: id,
            columns: [SQLViewColumnBinding(id: "table_name", name: "table_name", type: .sql(.text))])
    }
    private func view(_ binding: SQLViewSourceBinding) throws -> SQLView {
        try SQLView(id: "v", namespaceID: "ns", name: "visible_tables",
            definition: SQLViewDefinition(query: SelectQuery(projection: [.expression(.col("table_name"))],
                source: .table(TableRef(schema: "information_schema", table: "tables"))),
                columns: [SQLViewColumn(id: "output", name: "table_name", type: .sql(.text), isNullable: true)],
                bindings: [binding]))
    }

    @Test("Source kind separates identical exact identifiers and participates in durable identity")
    func kindIdentity() throws {
        let virtual = try binding()
        let catalog = try binding(.catalog)
        #expect(virtual.kind == .informationSchema)
        #expect(virtual != catalog); #expect(Set([virtual, catalog]).count == 2)
        let defaultKind = try SQLViewSourceBinding(schema: catalog.schema, table: catalog.table,
            relationID: catalog.relationID, columns: catalog.columns)
        #expect(defaultKind == catalog)
        #expect(try binding(id: "é") != binding(id: "e\u{0301}"))
        #expect(try view(virtual).definition.bindings == [virtual])
    }

    @Test("Virtual identity bypasses physical membership while ordinary sources retain membership checks")
    func catalogMembership() throws {
        let namespace = try SQLNamespace(id: "ns", name: "public")
        let virtualView = try view(binding())
        let catalog = try SQLCatalog(namespaces: [namespace], relations: [], views: [virtualView])
        #expect(catalog.relations.isEmpty)
        #expect(catalog.views[0].definition.bindings[0].kind == .informationSchema)
        #expect(throws: SQLCatalogError.unknownCatalogObjectID("tables")) {
            try SQLCatalog(namespaces: [namespace], relations: [], views: [view(binding(.catalog))])
        }
    }

    @Test("Virtual sources preserve intrinsic identifier, duplicate column and type admission")
    func intrinsicValidation() throws {
        for name in ["", "a\u{0}b"] {
            #expect(throws: SQLCatalogError.self) {
                try SQLViewSourceBinding(kind: .informationSchema, schema: "information_schema", table: "tables", relationID: name, columns: [])
            }
        }
        let column = try SQLViewColumnBinding(id: "table_name", name: "table_name", type: .sql(.text))
        #expect(throws: SQLCatalogError.duplicateColumnID("table_name")) {
            try SQLViewSourceBinding(kind: .informationSchema, schema: "information_schema", table: "tables", relationID: "tables", columns: [column, column])
        }
        #expect(throws: SQLCatalogError.invalidViewDefinition) {
            try SQLViewColumnBinding(id: "x", name: "x", type: .sql(.timestamp(withTimeZone: false, precision: 7)))
        }
    }
}
