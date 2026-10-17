import Testing
@testable import DatabaseKit

@Suite("S13 SQL constraints and column policies")
struct S13SQLCatalogTests {
    private func attributes(_ id: String = "constraint", timing: SQLConstraintTiming = .immediate) throws -> SQLConstraintAttributes {
        try SQLConstraintAttributes(id: id, name: id, timing: timing)
    }

    private func relation(_ id: String = "r", key: [String]? = nil,
                          keyAttributes: SQLConstraintAttributes? = nil,
                          constraints: [SQLConstraint] = [], columns: [SQLColumn]? = nil) throws -> SQLRelation {
        try SQLRelation(id: id, namespaceID: "n", name: id, entityName: id,
                        columns: columns ?? [SQLColumn(id: "a", name: "a", fieldNumber: 1),
                                             SQLColumn(id: "b", name: "b", fieldNumber: 2)],
                        primaryKeyColumnIDs: key, primaryKeyConstraint: keyAttributes, constraints: constraints)
    }

    private func catalog(_ relations: [SQLRelation], sequences: [SQLSequence] = []) throws -> SQLCatalog {
        try SQLCatalog(namespaces: [SQLNamespace(id: "n", name: "public")], relations: relations, sequences: sequences)
    }

    private func sequence(_ id: String = "s", owner: SQLSequenceOwner? = nil) throws -> SQLSequence {
        try SQLSequence(id: id, namespaceID: "n", name: id, start: 1, increment: 1,
                        minimum: 1, maximum: 10, ownedBy: owner)
    }

    @Test("Primary keys have one ordered binding and stable explicit attributes")
    func primaryKeyAttributes() throws {
        let value = try relation(key: ["b", "a"])
        #expect(value.primaryKeyColumnIDs == ["b", "a"])
        #expect(value.primaryKeyConstraint?.id == "r:primary-key")
        #expect(value.primaryKeyConstraint?.name == "r_pkey")
        #expect(value.constraints.isEmpty)
        let explicit = try attributes("pk", timing: .deferrable(initiallyDeferred: true))
        #expect(try relation(key: ["a"], keyAttributes: explicit).primaryKeyConstraint == explicit)
        #expect(throws: SQLCatalogError.primaryKeyAttributesWithoutKey) {
            try relation(keyAttributes: explicit)
        }
    }

    @Test("Physical stored and virtual generated columns preserve their distinct backing")
    func columnPolicies() throws {
        let stored = try SQLColumn(id: "stored", name: "stored", backing: .field(number: 1), policy: .generated(.int(7)))
        let virtual = try SQLColumn(id: "virtual", name: "virtual", backing: .virtual(type: .sql(.integer)), policy: .generated(.col("stored")))
        #expect(stored.fieldNumber == 1)
        #expect(virtual.fieldNumber == nil)
        #expect(stored.policy == .generated(.int(7)))
        #expect(try SQLColumn(id: "plain", name: "plain", fieldNumber: 9).policy == .input(defaultExpression: nil))
        #expect(throws: SQLCatalogError.invalidColumnPolicy("bad")) {
            try SQLColumn(id: "bad", name: "bad", backing: .virtual(type: .sql(.integer)))
        }
        _ = try relation(columns: [stored, virtual])
    }

    @Test("Constraint construction rejects malformed keys and unsupported deferral")
    func intrinsicConstraints() throws {
        for ids in [[], ["a", "a"]] {
            #expect(throws: SQLCatalogError.self) {
                try SQLConstraint(attributes: attributes(), kind: .unique(columnIDs: ids, nulls: .distinct))
            }
        }
        for kind: SQLConstraintKind in [.notNull(columnID: "a"), .check(.literal(.bool(true)))] {
            #expect(throws: SQLCatalogError.invalidConstraintTiming("constraint")) {
                try SQLConstraint(attributes: attributes(timing: .deferrable(initiallyDeferred: false)), kind: kind)
            }
        }
        for nulls: SQLNullUniqueness in [.distinct, .notDistinct] {
            let constraint = try SQLConstraint(attributes: attributes(), kind: .unique(columnIDs: ["b", "a"], nulls: nulls))
            _ = try relation(constraints: [constraint])
        }
    }

    @Test("Relation validates constraint collision scopes and source references")
    func relationConstraints() throws {
        let first = try SQLConstraint(attributes: attributes("c"), kind: .notNull(columnID: "a"))
        #expect(throws: SQLCatalogError.duplicateConstraintID("c")) {
            try relation(constraints: [first, first])
        }
        let duplicateName = try SQLConstraint(attributes: SQLConstraintAttributes(id: "other", name: "c"), kind: .check(.int(1)))
        #expect(throws: SQLCatalogError.duplicateConstraintName("c")) {
            try relation(constraints: [first, duplicateName])
        }
        let missing = try SQLConstraint(attributes: attributes(), kind: .notNull(columnID: "missing"))
        #expect(throws: SQLCatalogError.unknownConstraintColumnID("missing")) {
            try relation(constraints: [missing])
        }
        let pkCollision = try SQLConstraint(attributes: attributes("r:primary-key"), kind: .check(.int(1)))
        #expect(throws: SQLCatalogError.duplicateConstraintID("r:primary-key")) {
            try relation(key: ["a"], constraints: [pkCollision])
        }
    }

    @Test("Foreign keys validate arity and DELETE action subsets")
    func foreignKeyShape() throws {
        #expect(throws: SQLCatalogError.invalidForeignKeyArity) {
            try SQLForeignKey(columnIDs: ["a", "b"], referencedRelationID: "parent", referencedColumnIDs: ["a"])
        }
        #expect(throws: SQLCatalogError.invalidReferentialActionColumns) {
            try SQLForeignKey(columnIDs: ["a"], referencedRelationID: "parent", onDelete: .cascade, onDeleteColumnIDs: ["a"])
        }
        #expect(throws: SQLCatalogError.invalidReferentialActionColumns) {
            try SQLForeignKey(columnIDs: ["a"], referencedRelationID: "parent", onDelete: .setNull, onDeleteColumnIDs: ["b"])
        }
        for match: SQLForeignKeyMatch in [.simple, .full] {
            for action: SQLReferentialAction in [.noAction, .restrict, .cascade, .setNull, .setDefault] {
                let key = try SQLForeignKey(columnIDs: ["a", "b"], referencedRelationID: "parent", match: match, onUpdate: action, onDelete: action)
                #expect(key.referencedColumnIDs == nil)
                #expect(key.match == match)
            }
        }
        _ = try SQLForeignKey(columnIDs: ["a", "b"], referencedRelationID: "parent", onDelete: .setDefault, onDeleteColumnIDs: ["b"])
    }

    @Test("Catalog resolves omitted FK targets to PK and rejects missing or deferred targets")
    func foreignKeyTargets() throws {
        let fk = try SQLConstraint(attributes: attributes(), kind: .foreignKey(SQLForeignKey(columnIDs: ["a", "b"], referencedRelationID: "parent")))
        let child = try relation("child", constraints: [fk])
        _ = try catalog([relation("parent", key: ["a", "b"]), child])
        #expect(throws: SQLCatalogError.unknownReferencedRelationID("parent")) { try catalog([child]) }
        #expect(throws: SQLCatalogError.invalidForeignKeyArity) { try catalog([relation("parent"), child]) }
        #expect(throws: SQLCatalogError.invalidForeignKeyTarget("parent")) {
            try catalog([relation("parent", key: ["a", "b"], keyAttributes: attributes("pk", timing: .deferrable(initiallyDeferred: false))), child])
        }
        let unique = try SQLConstraint(attributes: attributes("uq"), kind: .unique(columnIDs: ["a", "b"], nulls: .notDistinct))
        let explicit = try SQLConstraint(attributes: attributes(), kind: .foreignKey(SQLForeignKey(columnIDs: ["a", "b"], referencedRelationID: "parent", referencedColumnIDs: ["b", "a"])))
        _ = try catalog([relation("parent", constraints: [unique]), relation("child", constraints: [explicit])])
    }

    @Test("Sequence declaration arithmetic boundaries never wrap or repair input")
    func sequenceBounds() throws {
        let full = try SQLSequence(id: "s", namespaceID: "n", name: "s", start: .min,
                                   increment: .min, minimum: .min, maximum: .max, cycle: true)
        #expect(full.increment == .min && full.start == .min && full.cycle)
        #expect(throws: SQLCatalogError.invalidSequenceIncrement) {
            try SQLSequence(id: "s", namespaceID: "n", name: "s", start: 1, increment: 0, minimum: 1, maximum: 2)
        }
        #expect(throws: SQLCatalogError.invalidSequenceBounds) {
            try SQLSequence(id: "s", namespaceID: "n", name: "s", start: 1, increment: 1, minimum: 1, maximum: 1)
        }
        #expect(throws: SQLCatalogError.invalidSequenceStart) {
            try SQLSequence(id: "s", namespaceID: "n", name: "s", start: 0, increment: 1, minimum: 1, maximum: 2)
        }
    }

    @Test("Sequence and identity cross-references agree on one physical owner")
    func identityOwnership() throws {
        let identity = try SQLIdentityColumn(sequenceID: "s", generation: .always)
        let column = try SQLColumn(id: "a", name: "a", backing: .field(number: 1), policy: .identity(identity))
        let owner = try SQLSequenceOwner(relationID: "r", columnID: "a")
        _ = try catalog([relation(columns: [column])], sequences: [sequence(owner: owner)])
        #expect(throws: SQLCatalogError.unknownSequenceID("s")) { try catalog([relation(columns: [column])]) }
        #expect(throws: SQLCatalogError.unknownSequenceOwner) {
            try catalog([relation(columns: [column])], sequences: [sequence(owner: SQLSequenceOwner(relationID: "missing", columnID: "a"))])
        }
        #expect(throws: SQLCatalogError.conflictingSequenceOwner("other")) {
            try catalog([relation(columns: [column])], sequences: [sequence("other", owner: owner)])
        }
        #expect(throws: SQLCatalogError.duplicateSequenceName(namespaceID: "n", name: "r")) {
            try catalog([relation()], sequences: [sequence("r")])
        }
    }

    @Test("Byte-distinct identifiers remain distinct through every new declaration hash")
    func exactIdentity() throws {
        let left = "\u{00e9}"
        let right = "e\u{0301}"
        let attrs = [try attributes(left), try attributes(right)]
        #expect(Set(attrs).count == 2)
        let identities = [try SQLIdentityColumn(sequenceID: left, generation: .byDefault), try SQLIdentityColumn(sequenceID: right, generation: .byDefault)]
        #expect(Set(identities).count == 2)
        let keys = [try SQLForeignKey(columnIDs: [left], referencedRelationID: "r"), try SQLForeignKey(columnIDs: [right], referencedRelationID: "r")]
        #expect(Set(keys).count == 2)
        let unique: [SQLConstraintKind] = [.unique(columnIDs: [left], nulls: .distinct), .unique(columnIDs: [right], nulls: .distinct)]
        #expect(Set(unique).count == 2)
        #expect(Set([SQLConstraintSelection.named([left]), .named([right])]).count == 2)
        #expect(Set([SQLSequenceCommand.drop(id: left, cascade: false), .drop(id: right, cascade: false)]).count == 2)
        let values = [try sequence(left), try sequence(right)]
        #expect(Set(values).count == 2)
        #expect(try catalog([], sequences: values).sequences.count == 2)
    }
}
