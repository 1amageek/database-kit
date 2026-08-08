import DatabaseKit
import DatabaseTypes
import DatabaseWire

extension SchemaJSONCodec {
    func decodeManifest(_ root: JSONValue) throws -> SchemaManifest {
        let object = try JSONObject(root, path: "")
        try object.validateKeys(["formatVersion", "schemaVersion", "entities"])
        let formatVersion: UInt16 = try integer(
            object.required("formatVersion"),
            path: "formatVersion"
        )
        guard formatVersion == SchemaManifest.currentFormatVersion else {
            throw SchemaJSONError.invalidValue(
                path: "formatVersion",
                reason: "unsupported version \(formatVersion)"
            )
        }
        let version = try decodeVersion(
            object.required("schemaVersion"),
            path: "schemaVersion"
        )
        let entityNodes = try object.required("entities").array(path: "entities")
        try requireCollection(entityNodes.count, path: "entities")
        let entities = try entityNodes.enumerated().map {
            try decodeEntity($0.element, path: "entities[\($0.offset)]")
        }
        do {
            return SchemaManifest(schema: try Schema(entities: entities, version: version))
        } catch {
            throw SchemaJSONError.invalidSchema(reason: String(describing: error))
        }
    }
}

private extension SchemaJSONCodec {
    func decodeVersion(_ node: JSONValue, path: String) throws -> SchemaVersion {
        let object = try JSONObject(node, path: path)
        try object.validateKeys(["major", "minor", "patch"])
        return SchemaVersion(
            try integer(object, "major"),
            try integer(object, "minor"),
            try integer(object, "patch")
        )
    }

    func decodeEntity(_ node: JSONValue, path: String) throws -> Schema.Entity {
        let object = try JSONObject(node, path: path)
        try object.validateKeys([
            "name", "identifierType", "fields", "directory", "indexes",
            "relationships", "fieldAccessRules", "enumMetadata", "ontology",
            "polymorphicMembership",
        ])
        let fieldNodes = try object.required("fields").array(path: object.child("fields"))
        let indexNodes = try object.required("indexes").array(path: object.child("indexes"))
        let relationshipNodes = try object.required("relationships").array(
            path: object.child("relationships")
        )
        let accessNodes = try object.required("fieldAccessRules").array(
            path: object.child("fieldAccessRules")
        )
        try requireCollection(fieldNodes.count, path: object.child("fields"))
        try requireCollection(indexNodes.count, path: object.child("indexes"))
        try requireCollection(relationshipNodes.count, path: object.child("relationships"))
        try requireCollection(accessNodes.count, path: object.child("fieldAccessRules"))
        let directory = try decodeDirectory(
            object.required("directory"),
            path: object.child("directory")
        )
        do {
            return try Schema.Entity(
                name: object.required("name").string(path: object.child("name")),
                identifierType: try decodeIdentifierType(
                    object.required("identifierType"),
                    path: object.child("identifierType"),
                    depth: 0
                ),
                fields: try fieldNodes.enumerated().map {
                    try decodeField(
                        $0.element,
                        path: "\(object.child("fields"))[\($0.offset)]"
                    )
                },
                directoryComponents: directory.components,
                directoryLayer: directory.layer,
                indexes: try indexNodes.enumerated().map {
                    try decodeIndex(
                        $0.element,
                        path: "\(object.child("indexes"))[\($0.offset)]"
                    )
                },
                relationships: try relationshipNodes.enumerated().map {
                    try decodeRelationship(
                        $0.element,
                        path: "\(object.child("relationships"))[\($0.offset)]"
                    )
                },
                fieldAccessRules: try accessNodes.enumerated().map {
                    try decodeAccessRule(
                        $0.element,
                        path: "\(object.child("fieldAccessRules"))[\($0.offset)]"
                    )
                },
                enumMetadata: try decodeStringArrayMap(
                    object.required("enumMetadata"),
                    path: object.child("enumMetadata")
                ),
                ontology: try decodeOntology(
                    object.required("ontology"),
                    path: object.child("ontology")
                ),
                polymorphicMembership: try decodePolymorphicMembership(
                    object.required("polymorphicMembership"),
                    path: object.child("polymorphicMembership")
                )
            )
        } catch let error as SchemaJSONError {
            throw error
        } catch {
            throw SchemaJSONError.invalidValue(path: path, reason: String(describing: error))
        }
    }

    func decodeIdentifierType(
        _ node: JSONValue,
        path: String,
        depth: Int
    ) throws -> PersistableIdentifierType {
        guard depth <= limits.maximumNestingDepth else {
            throw SchemaJSONError.nestingTooDeep(maximum: limits.maximumNestingDepth)
        }
        let object = try JSONObject(node, path: path)
        let kind = try object.required("kind").string(path: object.child("kind"))
        switch kind {
        case "bool": try object.validateKeys(["kind"]); return .bool
        case "int8": try object.validateKeys(["kind"]); return .int8
        case "int16": try object.validateKeys(["kind"]); return .int16
        case "int32": try object.validateKeys(["kind"]); return .int32
        case "int64": try object.validateKeys(["kind"]); return .int64
        case "uint8": try object.validateKeys(["kind"]); return .uint8
        case "uint16": try object.validateKeys(["kind"]); return .uint16
        case "uint32": try object.validateKeys(["kind"]); return .uint32
        case "uint64": try object.validateKeys(["kind"]); return .uint64
        case "string": try object.validateKeys(["kind"]); return .string
        case "bytes": try object.validateKeys(["kind"]); return .bytes
        case "uuid": try object.validateKeys(["kind"]); return .uuid
        case "composite":
            try object.validateKeys(["kind", "components"])
            let nodes = try object.required("components").array(
                path: object.child("components")
            )
            try requireCollection(nodes.count, path: object.child("components"))
            return .composite(
                try nodes.enumerated().map {
                    try decodeIdentifierType(
                        $0.element,
                        path: "\(object.child("components"))[\($0.offset)]",
                        depth: depth + 1
                    )
                }
            )
        default: throw invalidEnum(object.child("kind"), kind)
        }
    }

    func decodeField(_ node: JSONValue, path: String) throws -> FieldSchema {
        let object = try JSONObject(node, path: path)
        try object.validateKeys([
            "name", "number", "type", "optional", "array", "referenceTargetEntity",
        ])
        let rawType = try object.required("type").string(path: object.child("type"))
        guard let type = FieldSchemaType(rawValue: rawType) else {
            throw invalidEnum(object.child("type"), rawType)
        }
        return FieldSchema(
            name: try object.required("name").string(path: object.child("name")),
            fieldNumber: try integer(object, "number"),
            type: type,
            isOptional: try object.required("optional").bool(path: object.child("optional")),
            isArray: try object.required("array").bool(path: object.child("array")),
            referenceTargetEntity: try optionalString(
                object.required("referenceTargetEntity"),
                path: object.child("referenceTargetEntity")
            )
        )
    }

    func decodeDirectory(
        _ node: JSONValue,
        path: String
    ) throws -> (components: [DirectoryPathComponent], layer: DirectoryLayer) {
        let object = try JSONObject(node, path: path)
        try object.validateKeys(["components", "layer"])
        let nodes = try object.required("components").array(path: object.child("components"))
        try requireCollection(nodes.count, path: object.child("components"))
        let components: [DirectoryPathComponent] = try nodes.enumerated().map {
            let itemPath = "\(object.child("components"))[\($0.offset)]"
            let item = try JSONObject($0.element, path: itemPath)
            try item.validateKeys(["kind", "value"])
            let kind = try item.required("kind").string(path: item.child("kind"))
            let value = try item.required("value").string(path: item.child("value"))
            switch kind {
            case "static": return .staticPath(value)
            case "field": return .dynamicField(fieldName: value)
            default: throw invalidEnum(item.child("kind"), kind)
            }
        }
        let rawLayer = try object.required("layer").string(path: object.child("layer"))
        guard let layer = DirectoryLayer(rawValue: rawLayer) else {
            throw invalidEnum(object.child("layer"), rawLayer)
        }
        return (components, layer)
    }

    func decodeIndex(_ node: JSONValue, path: String) throws -> IndexDescriptorMetadata {
        let object = try JSONObject(node, path: path)
        try object.validateKeys(["entity", "name", "kind", "options", "storedFields"])
        let kindObject = try JSONObject(object.required("kind"), path: object.child("kind"))
        try kindObject.validateKeys(["identifier", "subspace", "fields", "metadata"])
        let rawSubspace = try kindObject.required("subspace").string(
            path: kindObject.child("subspace")
        )
        guard let subspace = SubspaceStructure(rawValue: rawSubspace) else {
            throw invalidEnum(kindObject.child("subspace"), rawSubspace)
        }
        let fieldNodes = try kindObject.required("fields").array(
            path: kindObject.child("fields")
        )
        try requireCollection(fieldNodes.count, path: kindObject.child("fields"))
        return IndexDescriptorMetadata(
            entityName: try object.required("entity").string(path: object.child("entity")),
            name: try object.required("name").string(path: object.child("name")),
            kind: IndexKindMetadata(
                identifier: try kindObject.required("identifier").string(
                    path: kindObject.child("identifier")
                ),
                subspaceStructure: subspace,
                fields: try fieldNodes.enumerated().map {
                    try decodeIndexField(
                        $0.element,
                        path: "\(kindObject.child("fields"))[\($0.offset)]"
                    )
                },
                metadata: try decodeFieldValueMap(
                    kindObject.required("metadata"),
                    path: kindObject.child("metadata")
                )
            ),
            commonOptions: try decodeCommonOptions(
                object.required("options"),
                path: object.child("options")
            ),
            storedFieldNames: try stringArray(
                object.required("storedFields"),
                path: object.child("storedFields")
            )
        )
    }

    func decodeIndexField(_ node: JSONValue, path: String) throws -> IndexFieldMetadata {
        let object = try JSONObject(node, path: path)
        try object.validateKeys(["name", "number", "order"])
        let rawOrder = try object.required("order").string(path: object.child("order"))
        guard let order = IndexFieldOrder(rawValue: rawOrder) else {
            throw invalidEnum(object.child("order"), rawOrder)
        }
        return IndexFieldMetadata(
            identity: FieldIdentity(
                name: try object.required("name").string(path: object.child("name")),
                number: try integer(object, "number")
            ),
            order: order
        )
    }

    func decodeCommonOptions(_ node: JSONValue, path: String) throws -> CommonIndexOptions {
        let object = try JSONObject(node, path: path)
        try object.validateKeys(["unique", "sparse", "metadata"])
        return CommonIndexOptions(
            unique: try object.required("unique").bool(path: object.child("unique")),
            sparse: try object.required("sparse").bool(path: object.child("sparse")),
            metadata: try decodeStringMap(
                object.required("metadata"),
                path: object.child("metadata")
            )
        )
    }

    func decodeRelationship(_ node: JSONValue, path: String) throws -> RelationshipDescriptor {
        let object = try JSONObject(node, path: path)
        try object.validateKeys([
            "ownerEntity", "property", "fieldNumber", "relatedEntity", "cardinality", "deleteRule",
        ])
        let rawCardinality = try object.required("cardinality").string(
            path: object.child("cardinality")
        )
        guard let cardinality = RelationshipCardinality(rawValue: rawCardinality) else {
            throw invalidEnum(object.child("cardinality"), rawCardinality)
        }
        let rawDeleteRule = try object.required("deleteRule").string(
            path: object.child("deleteRule")
        )
        guard let deleteRule = DeleteRule(rawValue: rawDeleteRule) else {
            throw invalidEnum(object.child("deleteRule"), rawDeleteRule)
        }
        return RelationshipDescriptor(
            ownerTypeName: try object.required("ownerEntity").string(
                path: object.child("ownerEntity")
            ),
            propertyName: try object.required("property").string(path: object.child("property")),
            propertyFieldNumber: try integer(object, "fieldNumber"),
            relatedTypeName: try object.required("relatedEntity").string(
                path: object.child("relatedEntity")
            ),
            cardinality: cardinality,
            deleteRule: deleteRule
        )
    }

    func decodeAccessRule(_ node: JSONValue, path: String) throws -> FieldAccessRule {
        let object = try JSONObject(node, path: path)
        try object.validateKeys(["field", "read", "write"])
        return FieldAccessRule(
            field: try decodeFieldIdentity(
                object.required("field"),
                path: object.child("field")
            ),
            read: try decodeAccessLevel(
                object.required("read"),
                path: object.child("read")
            ),
            write: try decodeAccessLevel(
                object.required("write"),
                path: object.child("write")
            )
        )
    }

    func decodeFieldIdentity(_ node: JSONValue, path: String) throws -> FieldIdentity {
        let object = try JSONObject(node, path: path)
        try object.validateKeys(["name", "number"])
        return FieldIdentity(
            name: try object.required("name").string(path: object.child("name")),
            number: try integer(object, "number")
        )
    }

    func decodeAccessLevel(_ node: JSONValue, path: String) throws -> FieldAccessLevel {
        let object = try JSONObject(node, path: path)
        let kind = try object.required("kind").string(path: object.child("kind"))
        switch kind {
        case "public": try object.validateKeys(["kind"]); return .public
        case "authenticated": try object.validateKeys(["kind"]); return .authenticated
        case "roles":
            try object.validateKeys(["kind", "roles"])
            return .roles(Set(try stringArray(object.required("roles"), path: object.child("roles"))))
        default: throw invalidEnum(object.child("kind"), kind)
        }
    }

    func decodeOntology(_ node: JSONValue, path: String) throws -> OntologyBinding? {
        if case .null = node { return nil }
        let object = try JSONObject(node, path: path)
        let kind = try object.required("kind").string(path: object.child("kind"))
        let propertyNodes = try object.required("properties").array(
            path: object.child("properties")
        )
        try requireCollection(propertyNodes.count, path: object.child("properties"))
        let properties = try propertyNodes.enumerated().map {
            try decodeOntologyProperty(
                $0.element,
                path: "\(object.child("properties"))[\($0.offset)]"
            )
        }
        switch kind {
        case "owlClass":
            try object.validateKeys(["kind", "iri", "properties"])
            return .owlClass(
                iri: try object.required("iri").string(path: object.child("iri")),
                properties: properties
            )
        case "owlObjectProperty":
            try object.validateKeys(["kind", "iri", "fromField", "toField", "properties"])
            return .owlObjectProperty(
                iri: try object.required("iri").string(path: object.child("iri")),
                fromField: try object.required("fromField").string(path: object.child("fromField")),
                toField: try object.required("toField").string(path: object.child("toField")),
                properties: properties
            )
        default: throw invalidEnum(object.child("kind"), kind)
        }
    }

    func decodeOntologyProperty(
        _ node: JSONValue,
        path: String
    ) throws -> OWLDataPropertyDescriptor {
        let object = try JSONObject(node, path: path)
        try object.validateKeys([
            "name", "field", "iri", "label", "targetEntity", "targetField",
        ])
        return OWLDataPropertyDescriptor(
            name: try object.required("name").string(path: object.child("name")),
            fieldName: try object.required("field").string(path: object.child("field")),
            iri: try object.required("iri").string(path: object.child("iri")),
            label: try optionalString(object.required("label"), path: object.child("label")),
            targetTypeName: try optionalString(
                object.required("targetEntity"),
                path: object.child("targetEntity")
            ),
            targetFieldName: try optionalString(
                object.required("targetField"),
                path: object.child("targetField")
            )
        )
    }

    func decodePolymorphicMembership(
        _ node: JSONValue,
        path: String
    ) throws -> PolymorphicMembership? {
        if case .null = node { return nil }
        let object = try JSONObject(node, path: path)
        try object.validateKeys(["identifier", "directory", "indexes"])
        let directory = try decodeDirectory(
            object.required("directory"),
            path: object.child("directory")
        )
        let indexNodes = try object.required("indexes").array(path: object.child("indexes"))
        try requireCollection(indexNodes.count, path: object.child("indexes"))
        return PolymorphicMembership(
            identifier: try object.required("identifier").string(
                path: object.child("identifier")
            ),
            directoryComponents: directory.components,
            directoryLayer: directory.layer,
            indexes: try indexNodes.enumerated().map {
                try decodePolymorphicIndex(
                    $0.element,
                    path: "\(object.child("indexes"))[\($0.offset)]"
                )
            }
        )
    }

    func decodePolymorphicIndex(
        _ node: JSONValue,
        path: String
    ) throws -> PolymorphicIndexDefinition {
        let object = try JSONObject(node, path: path)
        try object.validateKeys(["name", "definition", "fields", "options", "storedFields"])
        let fieldNodes = try object.required("fields").array(path: object.child("fields"))
        try requireCollection(fieldNodes.count, path: object.child("fields"))
        return PolymorphicIndexDefinition(
            name: try object.required("name").string(path: object.child("name")),
            definition: try decodeIndexDefinition(
                object.required("definition"),
                path: object.child("definition")
            ),
            fields: try fieldNodes.enumerated().map {
                let itemPath = "\(object.child("fields"))[\($0.offset)]"
                let field = try JSONObject($0.element, path: itemPath)
                try field.validateKeys(["name", "order"])
                let rawOrder = try field.required("order").string(path: field.child("order"))
                guard let order = IndexFieldOrder(rawValue: rawOrder) else {
                    throw invalidEnum(field.child("order"), rawOrder)
                }
                return PolymorphicIndexField(
                    name: try field.required("name").string(path: field.child("name")),
                    order: order
                )
            },
            commonOptions: try decodeCommonOptions(
                object.required("options"),
                path: object.child("options")
            ),
            storedFieldNames: try stringArray(
                object.required("storedFields"),
                path: object.child("storedFields")
            )
        )
    }
}

extension SchemaJSONCodec {
    func integer<T: FixedWidthInteger>(
        _ object: JSONObject,
        _ name: String
    ) throws -> T {
        try integer(object.required(name), path: object.child(name))
    }

    func integer<T: FixedWidthInteger>(
        _ node: JSONValue,
        path: String
    ) throws -> T {
        let value = try node.number(path: path)
        guard isCanonicalInteger(value), let decoded = T(value) else {
            throw SchemaJSONError.invalidValue(path: path, reason: "invalid integer")
        }
        return decoded
    }

    func requireCollection(_ count: Int, path: String) throws {
        guard count <= limits.maximumCollectionCount else {
            throw SchemaJSONError.collectionTooLarge(
                path: path,
                actual: count,
                maximum: limits.maximumCollectionCount
            )
        }
    }

    func optionalString(_ node: JSONValue, path: String) throws -> String? {
        if case .null = node { return nil }
        return try node.string(path: path)
    }

    func stringArray(_ node: JSONValue, path: String) throws -> [String] {
        let values = try node.array(path: path)
        try requireCollection(values.count, path: path)
        return try values.enumerated().map {
            try $0.element.string(path: "\(path)[\($0.offset)]")
        }
    }

    func decodeStringMap(_ node: JSONValue, path: String) throws -> [String: String] {
        let fields = try objectFields(node, path: path)
        var values: [String: String] = [:]
        values.reserveCapacity(fields.count)
        for field in fields {
            values[field.key] = try field.value.string(path: "\(path).\(field.key)")
        }
        return values
    }

    func decodeStringArrayMap(
        _ node: JSONValue,
        path: String
    ) throws -> [String: [String]] {
        let fields = try objectFields(node, path: path)
        var values: [String: [String]] = [:]
        values.reserveCapacity(fields.count)
        for field in fields {
            values[field.key] = try stringArray(
                field.value,
                path: "\(path).\(field.key)"
            )
        }
        return values
    }

    func decodeFieldValueMap(
        _ node: JSONValue,
        path: String
    ) throws -> [String: FieldValue] {
        let fields = try objectFields(node, path: path)
        var values: [String: FieldValue] = [:]
        values.reserveCapacity(fields.count)
        for field in fields {
            values[field.key] = try fieldValueCodec.decode(
                field.value,
                path: "\(path).\(field.key)"
            )
        }
        return values
    }

    func objectFields(
        _ node: JSONValue,
        path: String
    ) throws -> [(key: String, value: JSONValue)] {
        guard case .object(let fields) = node else {
            throw SchemaJSONError.typeMismatch(path: path, expected: "an object")
        }
        try requireCollection(fields.count, path: path)
        return fields
    }

    func isCanonicalInteger(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        if value == "0" { return true }
        let bytes = Array(value.utf8)
        let digits: ArraySlice<UInt8>
        if bytes[0] == 0x2D {
            guard bytes.count > 1, bytes[1] != 0x30 else { return false }
            digits = bytes[1...]
        } else {
            guard bytes[0] != 0x30 else { return false }
            digits = bytes[...]
        }
        return digits.allSatisfy { (0x30...0x39).contains($0) }
    }
}
