import DatabaseTypes
/// Schema evolution compatibility reporting.
///
/// Defines append-only compatibility checks for persisted schema metadata so
/// model definitions can stay annotation-light while dangerous field changes
/// are rejected during registration or migration planning.

public enum SchemaCompatibilityIssue: Error, Sendable, Equatable, CustomStringConvertible {
    case removedEntity(entityName: String)
    case removedField(entityName: String, fieldName: String, fieldNumber: Int)
    case renumberedField(entityName: String, fieldName: String, expected: Int, actual: Int)
    case changedFieldEncoding(entityName: String, fieldName: String, from: FieldSchema, to: FieldSchema)
    case nonAppendOnlyFieldAddition(entityName: String, fieldName: String, fieldNumber: Int, minimumAllowed: Int)

    public var description: String {
        switch self {
        case .removedEntity(let entityName):
            return "Entity '\(entityName)' was removed and requires a custom migration."

        case .removedField(let entityName, let fieldName, let fieldNumber):
            return "Entity '\(entityName)' removed field '\(fieldName)' (#\(fieldNumber))."

        case .renumberedField(let entityName, let fieldName, let expected, let actual):
            return "Entity '\(entityName)' changed field '\(fieldName)' from #\(expected) to #\(actual)."

        case .changedFieldEncoding(let entityName, let fieldName, let from, let to):
            return "Entity '\(entityName)' changed field '\(fieldName)' encoding from \(from) to \(to)."

        case .nonAppendOnlyFieldAddition(let entityName, let fieldName, let fieldNumber, let minimumAllowed):
            return "Entity '\(entityName)' added field '\(fieldName)' at #\(fieldNumber), but append-only additions must use field numbers >= \(minimumAllowed)."
        }
    }
}

public struct EntitySchemaCompatibilityReport: Sendable, Equatable {
    public let entityName: String
    public let addedFields: [FieldSchema]
    public let issues: [SchemaCompatibilityIssue]

    public var isCompatible: Bool {
        issues.isEmpty
    }

    public init(
        entityName: String,
        addedFields: [FieldSchema],
        issues: [SchemaCompatibilityIssue]
    ) {
        self.entityName = entityName
        self.addedFields = addedFields
        self.issues = issues
    }
}

public struct SchemaCompatibilityReport: Sendable, Equatable {
    public let addedEntities: [String]
    public let entityReports: [EntitySchemaCompatibilityReport]
    public let issues: [SchemaCompatibilityIssue]

    public var allIssues: [SchemaCompatibilityIssue] {
        issues + entityReports.flatMap { $0.issues }
    }

    public var isLightweightCompatible: Bool {
        allIssues.isEmpty
    }

    public var entitiesRequiringCustomMigration: Set<String> {
        Set(
            entityReports.compactMap { report in
                report.issues.isEmpty ? nil : report.entityName
            }
        )
    }

    public init(
        addedEntities: [String],
        entityReports: [EntitySchemaCompatibilityReport],
        issues: [SchemaCompatibilityIssue]
    ) {
        self.addedEntities = addedEntities
        self.entityReports = entityReports
        self.issues = issues
    }
}

/// A complete logical index transition between two schema generations.
public enum IndexChange: Sendable, Hashable {
    case added(IndexDescriptor)
    case removed(IndexDescriptor)
    case replaced(previous: IndexDescriptor, current: IndexDescriptor)

    public var identity: IndexIdentity {
        switch self {
        case .added(let descriptor), .removed(let descriptor):
            descriptor.identity
        case .replaced(_, let current):
            current.identity
        }
    }
}

/// A complete logical polymorphic-index transition between schema generations.
public enum PolymorphicIndexChange: Sendable, Hashable {
    case added(
        identity: PolymorphicIndexIdentity,
        declaration: IndexDeclaration<String>
    )
    case removed(
        identity: PolymorphicIndexIdentity,
        declaration: IndexDeclaration<String>
    )
    case replaced(
        identity: PolymorphicIndexIdentity,
        previous: IndexDeclaration<String>,
        current: IndexDeclaration<String>
    )

    public var identity: PolymorphicIndexIdentity {
        switch self {
        case .added(let identity, _), .removed(let identity, _),
             .replaced(let identity, _, _):
            identity
        }
    }
}

extension Schema.Entity {
    public func compatibilityReport(from previous: Schema.Entity) -> EntitySchemaCompatibilityReport {
        var issues: [SchemaCompatibilityIssue] = []

        let previousByName = Dictionary(uniqueKeysWithValues: previous.fields.map { ($0.name, $0) })
        let currentByName = Dictionary(uniqueKeysWithValues: fields.map { ($0.name, $0) })
        let maxPreviousFieldNumber = previous.fields.map { $0.fieldNumber }.max() ?? 0

        for oldField in previous.fields.sorted(by: fieldSort) {
            guard let currentField = currentByName[oldField.name] else {
                issues.append(
                    .removedField(
                        entityName: name,
                        fieldName: oldField.name,
                        fieldNumber: oldField.fieldNumber
                    )
                )
                continue
            }

            if currentField.fieldNumber != oldField.fieldNumber {
                issues.append(
                    .renumberedField(
                        entityName: name,
                        fieldName: oldField.name,
                        expected: oldField.fieldNumber,
                        actual: currentField.fieldNumber
                    )
                )
            }

            if !currentField.hasSameStorageShape(as: oldField) {
                issues.append(
                    .changedFieldEncoding(
                        entityName: name,
                        fieldName: oldField.name,
                        from: oldField,
                        to: currentField
                    )
                )
            }
        }

        let addedFields = fields
            .filter { previousByName[$0.name] == nil }
            .sorted(by: fieldSort)

        for field in addedFields where field.fieldNumber <= maxPreviousFieldNumber {
            issues.append(
                .nonAppendOnlyFieldAddition(
                    entityName: name,
                    fieldName: field.name,
                    fieldNumber: field.fieldNumber,
                    minimumAllowed: maxPreviousFieldNumber + 1
                )
            )
        }

        return EntitySchemaCompatibilityReport(
            entityName: name,
            addedFields: addedFields,
            issues: issues
        )
    }

    private func fieldSort(lhs: FieldSchema, rhs: FieldSchema) -> Bool {
        if lhs.fieldNumber != rhs.fieldNumber {
            return lhs.fieldNumber < rhs.fieldNumber
        }
        return lhs.name < rhs.name
    }

}

extension Schema {
    public func compatibilityReport(from previous: Schema) -> SchemaCompatibilityReport {
        let currentEntityNames = Set(entitiesByName.keys)
        let previousEntityNames = Set(previous.entitiesByName.keys)

        let addedEntities = currentEntityNames
            .subtracting(previousEntityNames)
            .sorted()

        let removedEntities = previousEntityNames
            .subtracting(currentEntityNames)
            .sorted()
            .map { SchemaCompatibilityIssue.removedEntity(entityName: $0) }

        let entityReports = entities
            .compactMap { entity -> EntitySchemaCompatibilityReport? in
                guard let previousEntity = previous.entity(named: entity.name) else {
                    return nil
                }
                return entity.compatibilityReport(from: previousEntity)
            }
            .sorted { $0.entityName < $1.entityName }

        return SchemaCompatibilityReport(
            addedEntities: addedEntities,
            entityReports: entityReports,
            issues: removedEntities
        )
    }

    /// Computes index changes by stable identity and full logical definition.
    public func indexChanges(from previous: Schema) -> [IndexChange] {
        var currentByIdentity: [IndexIdentity: IndexDescriptor] = [:]
        var previousByIdentity: [IndexIdentity: IndexDescriptor] = [:]
        for descriptor in indexDescriptors {
            currentByIdentity[descriptor.identity] = descriptor
        }
        for descriptor in previous.indexDescriptors {
            previousByIdentity[descriptor.identity] = descriptor
        }

        let identities = Set(currentByIdentity.keys)
            .union(previousByIdentity.keys)
            .sorted()
        var changes: [IndexChange] = []
        changes.reserveCapacity(identities.count)
        for identity in identities {
            switch (previousByIdentity[identity], currentByIdentity[identity]) {
            case (nil, let current?):
                changes.append(.added(current))
            case (let previous?, nil):
                changes.append(.removed(previous))
            case (let previous?, let current?) where previous != current:
                changes.append(.replaced(previous: previous, current: current))
            case (.some, .some), (nil, nil):
                break
            }
        }
        return changes
    }

    /// Computes polymorphic index changes by group, name, and full definition.
    public func polymorphicIndexChanges(
        from previous: Schema
    ) -> [PolymorphicIndexChange] {
        var currentByIdentity:
            [PolymorphicIndexIdentity: IndexDeclaration<String>] = [:]
        var previousByIdentity:
            [PolymorphicIndexIdentity: IndexDeclaration<String>] = [:]
        for group in polymorphicGroups {
            for declaration in group.indexes {
                currentByIdentity[
                    PolymorphicIndexIdentity(
                        groupIdentifier: group.identifier,
                        name: declaration.name
                    )
                ] = declaration
            }
        }
        for group in previous.polymorphicGroups {
            for declaration in group.indexes {
                previousByIdentity[
                    PolymorphicIndexIdentity(
                        groupIdentifier: group.identifier,
                        name: declaration.name
                    )
                ] = declaration
            }
        }

        let identities = Set(currentByIdentity.keys)
            .union(previousByIdentity.keys)
            .sorted()
        var changes: [PolymorphicIndexChange] = []
        changes.reserveCapacity(identities.count)
        for identity in identities {
            switch (previousByIdentity[identity], currentByIdentity[identity]) {
            case (nil, let current?):
                changes.append(
                    .added(identity: identity, declaration: current)
                )
            case (let previous?, nil):
                changes.append(
                    .removed(identity: identity, declaration: previous)
                )
            case (let previous?, let current?) where previous != current:
                changes.append(
                    .replaced(
                        identity: identity,
                        previous: previous,
                        current: current
                    )
                )
            case (.some, .some), (nil, nil):
                break
            }
        }
        return changes
    }
}

private extension FieldSchema {
    func hasSameStorageShape(as other: FieldSchema) -> Bool {
        type == other.type &&
        isOptional == other.isOptional &&
        isArray == other.isArray
    }
}
