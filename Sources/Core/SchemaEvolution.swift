/// Schema evolution compatibility reporting.
///
/// Defines append-only compatibility checks for persisted schema metadata so
/// model definitions can stay annotation-light while dangerous field changes
/// are rejected during registration or migration planning.

public enum SchemaCompatibilityIssue: Error, Sendable, Equatable, CustomStringConvertible {
    case removedEntity(entityName: String)
    case duplicateFieldNumber(entityName: String, fieldNumber: Int, fieldNames: [String])
    case removedField(entityName: String, fieldName: String, fieldNumber: Int)
    case renumberedField(entityName: String, fieldName: String, expected: Int, actual: Int)
    case changedFieldEncoding(entityName: String, fieldName: String, from: FieldSchema, to: FieldSchema)
    case nonAppendOnlyFieldAddition(entityName: String, fieldName: String, fieldNumber: Int, minimumAllowed: Int)

    public var description: String {
        switch self {
        case .removedEntity(let entityName):
            return "Entity '\(entityName)' was removed and requires a custom migration."

        case .duplicateFieldNumber(let entityName, let fieldNumber, let fieldNames):
            let names = fieldNames.sorted().joined(separator: ", ")
            return "Entity '\(entityName)' reuses field number \(fieldNumber) for [\(names)]."

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
        issues + entityReports.flatMap(\.issues)
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

extension Schema.Entity {
    public func compatibilityReport(from previous: Schema.Entity) -> EntitySchemaCompatibilityReport {
        var issues: [SchemaCompatibilityIssue] = []
        issues.append(contentsOf: duplicateFieldNumberIssues(for: previous))
        issues.append(contentsOf: duplicateFieldNumberIssues(for: self))

        let previousByName = Dictionary(uniqueKeysWithValues: previous.fields.map { ($0.name, $0) })
        let currentByName = Dictionary(uniqueKeysWithValues: fields.map { ($0.name, $0) })
        let maxPreviousFieldNumber = previous.fields.map(\.fieldNumber).max() ?? 0

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

    private func duplicateFieldNumberIssues(for entity: Schema.Entity) -> [SchemaCompatibilityIssue] {
        let grouped = Dictionary(grouping: entity.fields, by: \.fieldNumber)
        return grouped
            .compactMap { fieldNumber, fields in
                guard fields.count > 1 else { return nil }
                return SchemaCompatibilityIssue.duplicateFieldNumber(
                    entityName: entity.name,
                    fieldNumber: fieldNumber,
                    fieldNames: fields.map(\.name).sorted()
                )
            }
            .sorted(by: issueSort)
    }

    private func fieldSort(lhs: FieldSchema, rhs: FieldSchema) -> Bool {
        if lhs.fieldNumber != rhs.fieldNumber {
            return lhs.fieldNumber < rhs.fieldNumber
        }
        return lhs.name < rhs.name
    }

    private func issueSort(lhs: SchemaCompatibilityIssue, rhs: SchemaCompatibilityIssue) -> Bool {
        lhs.description < rhs.description
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
}

private extension FieldSchema {
    func hasSameStorageShape(as other: FieldSchema) -> Bool {
        type == other.type &&
        isOptional == other.isOptional &&
        isArray == other.isArray
    }
}
