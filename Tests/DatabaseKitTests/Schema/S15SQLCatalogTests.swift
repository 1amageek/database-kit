import DatabaseKit
import Testing

@Suite("S15 SQL catalog definition metadata")
struct S15SQLCatalogTests {
    private func relation(_ id: String = "physical", highWater: Int? = nil) throws -> SQLRelation {
        try SQLRelation(id: id, namespaceID: "ns", name: id, entityName: id,
            columns: [SQLColumn(id: "a", name: "value", fieldNumber: 3)], fieldNumberHighWaterMark: highWater)
    }

    private func definition() throws -> SQLViewDefinition {
        try SQLViewDefinition(query: SelectQuery(projection: [.wildcard()], source: .table(TableRef("physical"))),
            columns: [SQLViewColumn(id: "output", name: "value", type: .sql(.integer), isNullable: false)],
            bindings: [SQLViewSourceBinding(table: "physical", relationID: "physical",
                columns: [SQLViewColumnBinding(id: "a", name: "value", type: .sql(.integer))])])
    }

    @Test("Views and materialized views retain definitions separately from physical bindings")
    func separateViewDeclarations() throws {
        let definition = try definition()
        let view = try SQLView(id: "view-id", namespaceID: "ns", name: "visible", definition: definition)
        let materialized = try SQLMaterializedView(id: "cached-id", namespaceID: "ns", name: "cached",
            definition: definition, backingRelationID: "hidden-backing", isPopulated: false)
        let index = try SQLIndex(id: "index-id", namespaceID: "ns", name: "ordered", relationID: "physical",
            keys: [SortKey(.col("value"), direction: .descending, nulls: .last)], predicate: .bool(true),
            unique: true, nulls: .notDistinct, bindings: definition.bindings[0].columns)
        let catalog = try SQLCatalog(namespaces: [SQLNamespace(id: "ns", name: "public")],
            relations: [relation(), relation("hidden-backing")], views: [view], materializedViews: [materialized], indexes: [index])
        #expect(catalog.relations.count == 2)
        #expect(catalog.views == [view])
        #expect(catalog.materializedViews == [materialized])
        #expect(catalog.indexes == [index])
        #expect(catalog.views[0].definition.bindings[0].relationID == "physical")
        #expect(catalog.materializedViews[0].backingRelationID == "hidden-backing")
        #expect(!catalog.materializedViews[0].isPopulated)
    }

    @Test("Durable field highwater and stable sequence targets retain identity after drops")
    func durableAllocationAndSequenceMetadata() throws {
        let value = try relation(highWater: 99)
        #expect(value.fieldNumberHighWaterMark == 99)
        #expect(try relation().fieldNumberHighWaterMark == 3)
        #expect(try relation() != value)
        #expect(throws: SQLCatalogError.invalidFieldNumberHighWaterMark(2)) { try relation(highWater: 2) }
        let binding = try SQLSequenceBinding(originalName: "old.sequence", sequenceID: "stable-sequence")
        let column = try SQLColumn(id: "a", name: "value", backing: .field(number: 3),
            policy: .input(defaultExpression: .int(1)), sequenceBindings: [binding])
        #expect(column.sequenceBindings == [binding])
        #expect(throws: SQLCatalogError.invalidColumnPolicy("a")) {
            try SQLColumn(id: "a", name: "value", backing: .field(number: 3), sequenceBindings: [binding])
        }
        let composed = try SQLSequenceBinding(originalName: "\u{00E9}", sequenceID: "s")
        let decomposed = try SQLSequenceBinding(originalName: "e\u{0301}", sequenceID: "s")
        #expect(composed != decomposed)
        #expect(Set([composed, decomposed]).count == 2)
        let small = try SQLSequence(id: "small", namespaceID: "ns", name: "small", start: 1,
            increment: 1, minimum: 1, maximum: 32767, declaredType: .smallint)
        #expect(small.declaredType == .smallint)
        let defaultType = try SQLSequence(id: "small", namespaceID: "ns", name: "small", start: 1,
            increment: 1, minimum: 1, maximum: 32767)
        #expect(defaultType.declaredType == .bigint)
        #expect(small != defaultType)
        #expect(Set([small, defaultType]).count == 2)
        #expect(throws: SQLCatalogError.invalidSequenceBounds) {
            try SQLSequence(id: "small", namespaceID: "ns", name: "small", start: 1,
                increment: 1, minimum: 1, maximum: 32768, declaredType: .smallint)
        }
        #expect(throws: SQLCatalogError.invalidSequenceBounds) {
            try SQLSequence(id: "integer", namespaceID: "ns", name: "integer", start: 1,
                increment: 1, minimum: Int64(Int32.min) - 1, maximum: 100, declaredType: .integer)
        }
        #expect(throws: SQLCatalogError.invalidSequenceType) {
            try SQLSequence(id: "text", namespaceID: "ns", name: "text", start: 1,
                increment: 1, minimum: 1, maximum: 100, declaredType: .text)
        }
    }

    @Test("Catalog construction rejects missing and colliding resolved metadata")
    func invalidMetadata() throws {
        let namespace = try SQLNamespace(id: "ns", name: "public")
        let physical = try relation()
        let definition = try definition()
        let collision = try SQLView(id: "view", namespaceID: "ns", name: "physical", definition: definition)
        #expect(throws: SQLCatalogError.duplicateRelationName(namespaceID: "ns", name: "physical")) {
            try SQLCatalog(namespaces: [namespace], relations: [physical], views: [collision])
        }
        let badBacking = try SQLMaterializedView(id: "cached", namespaceID: "ns", name: "cached",
            definition: definition, backingRelationID: "missing", isPopulated: false)
        #expect(throws: SQLCatalogError.invalidMaterializedViewBacking("missing")) {
            try SQLCatalog(namespaces: [namespace], relations: [physical], materializedViews: [badBacking])
        }
        #expect(throws: SQLCatalogError.invalidIndexDefinition) {
            try SQLIndex(id: "i", namespaceID: "ns", name: "i", relationID: "physical", keys: [])
        }
        let unknownIndex = try SQLIndex(id: "i", namespaceID: "ns", name: "i", relationID: "missing", keys: [SortKey(.int(1))])
        #expect(throws: SQLCatalogError.unknownCatalogObjectID("missing")) {
            try SQLCatalog(namespaces: [namespace], relations: [physical], indexes: [unknownIndex])
        }
        let changedType = try SQLViewColumnBinding(id: "a", name: "value", type: .sql(.bigint))
        #expect(changedType != definition.bindings[0].columns[0])
        #expect(throws: SQLCatalogError.duplicateColumnID("a")) {
            try SQLViewSourceBinding(table: "physical", relationID: "physical", columns: [changedType, changedType])
        }
    }

    @Test("Foreign keys retain an exact eligible standalone unique-index dependency")
    func standaloneUniqueIndexForeignKeys() throws {
        let namespace = try SQLNamespace(id: "ns", name: "public")
        let target = try SQLRelation(id: "target", namespaceID: "ns", name: "target", entityName: "target",
            columns: [SQLColumn(id: "a", name: "a", fieldNumber: 1), SQLColumn(id: "b", name: "b", fieldNumber: 2)])
        let bindings = try [SQLViewColumnBinding(id: "a", name: "a", type: .sql(.integer)),
                            SQLViewColumnBinding(id: "b", name: "b", type: .sql(.integer))]
        func index(unique: Bool = true, predicate: Expression? = nil,
                   keys: [SortKey] = [SortKey(.col("a")), SortKey(.col("b"))],
                   relationID: String = "target") throws -> SQLIndex {
            try SQLIndex(id: "idx", namespaceID: "ns", name: "idx", relationID: relationID,
                keys: keys, predicate: predicate, unique: unique, bindings: bindings)
        }
        func catalog(_ indexes: [SQLIndex], referencedIndex: String? = "idx",
                     referencedColumns: [String] = ["b", "a"]) throws -> SQLCatalog {
            let key = try SQLForeignKey(columnIDs: ["source-b", "source-a"], referencedRelationID: "target",
                referencedColumnIDs: referencedColumns, referencedUniqueIndexID: referencedIndex)
            let constraint = try SQLConstraint(attributes: SQLConstraintAttributes(id: "fk", name: "fk"), kind: .foreignKey(key))
            let source = try SQLRelation(id: "source", namespaceID: "ns", name: "source", entityName: "source",
                columns: [SQLColumn(id: "source-b", name: "b", fieldNumber: 1),
                          SQLColumn(id: "source-a", name: "a", fieldNumber: 2)], constraints: [constraint])
            return try SQLCatalog(namespaces: [namespace], relations: [target, source], indexes: indexes)
        }
        let valid = try index()
        #expect(valid.directColumnIDs == ["a", "b"])
        let admitted = try catalog([valid])
        guard case .foreignKey(let key) = admitted.relations[1].constraints[0].kind else {
            Issue.record("Expected the retained foreign key")
            return
        }
        #expect(key.referencedUniqueIndexID == "idx")
        #expect(key.referencedColumnIDs == ["b", "a"])
        #expect(throws: SQLCatalogError.unknownCatalogObjectID("idx")) { try catalog([]) }
        #expect(throws: SQLCatalogError.invalidForeignKeyTarget("target")) { try catalog([valid], referencedIndex: nil) }
        #expect(throws: SQLCatalogError.unknownReferencedColumnID("missing")) {
            try catalog([valid], referencedColumns: ["missing", "a"])
        }
        let expressionIndex = try index(keys: [SortKey(.add(.col("a"), .int(1))), SortKey(.col("b"))])
        #expect(expressionIndex.directColumnIDs == nil)
        for invalid in [try index(unique: false), try index(predicate: .bool(true)), expressionIndex,
                        try index(keys: [SortKey(.col("a"))]), try index(relationID: "source")] {
            #expect(throws: SQLCatalogError.invalidForeignKeyTarget("target")) { try catalog([invalid]) }
        }
        let composed = try SQLForeignKey(columnIDs: ["a"], referencedRelationID: "target",
            referencedColumnIDs: ["a"], referencedUniqueIndexID: "\u{00E9}")
        let decomposed = try SQLForeignKey(columnIDs: ["a"], referencedRelationID: "target",
            referencedColumnIDs: ["a"], referencedUniqueIndexID: "e\u{0301}")
        #expect(composed != decomposed)
        #expect(Set([composed, decomposed]).count == 2)
        #expect(throws: SQLCatalogError.emptyIdentifier) {
            try SQLForeignKey(columnIDs: ["a"], referencedRelationID: "target", referencedUniqueIndexID: "")
        }
    }

}
