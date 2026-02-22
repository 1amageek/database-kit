import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

/// @Persistable macro implementation
///
/// Generates Persistable protocol conformance with metadata methods and ID management.
///
/// **Supports all layers**:
/// - RecordLayer (RDB): Structured records with indexes
/// - DocumentLayer (DocumentDB): Flexible documents
/// - GraphLayer (GraphDB): Define nodes with relationships
///
/// **Generated code includes**:
/// - `var id: String = ULID().ulidString` (if not user-defined)
/// - `static var persistableType: String`
/// - `static var allFields: [String]`
/// - `static var indexDescriptors: [IndexDescriptor]`
/// - `static func fieldNumber(for fieldName: String) -> Int?`
/// - `static func enumMetadata(for fieldName: String) -> EnumMetadata?`
/// - `init(...)` (without `id` parameter)
///
/// **ID Behavior**:
/// - If user defines `id` field: uses that type and default value
/// - If user omits `id` field: macro adds `var id: String = ULID().ulidString`
/// - `id` is NOT included in the generated initializer
///
/// **Usage**:
/// ```swift
/// @Persistable
/// struct User {
///     #Index(ScalarIndexKind<User>(fields: [\.email]), unique: true)
///
///     var email: String
///     var name: String
/// }
/// ```
///
/// **With custom type name**:
/// ```swift
/// @Persistable(type: "User")
/// struct Member {
///     var name: String
/// }
/// ```
public struct PersistableMacro: MemberMacro, ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // Extract struct name
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(
                    node: Syntax(node),
                    message: MacroExpansionErrorMessage("@Persistable can only be applied to structs")
                )
            ])
        }

        let structName = structDecl.name.text

        // Extract custom type name from macro arguments
        var typeName: String = structName

        if let arguments = node.arguments,
           let labeledList = arguments.as(LabeledExprListSyntax.self) {
            for arg in labeledList {
                if arg.label?.text == "type",
                   let stringLiteral = arg.expression.as(StringLiteralExprSyntax.self),
                   let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self) {
                    typeName = segment.content.text
                }
            }
        }

        // Check if user defined `id` field
        var hasUserDefinedId = false
        var userIdHasDefault = false
        var userIdBinding: PatternBindingSyntax?

        // Extract all stored properties (fields) and @Relationship declarations
        var allFields: [String] = []
        var fieldInfos: [(name: String, type: String, hasDefault: Bool, defaultValue: String?, isTransient: Bool)] = []
        var fieldNumber = 1

        // Track @Restricted fields for field-level security metadata
        var restrictedFields: [(fieldName: String, readExpr: String, writeExpr: String, defaultExpr: String)] = []

        // Track @Relationship properties
        // New design: FK fields are explicit (customerID: String?, orderIDs: [String])
        // @Relationship marks FK fields and specifies the related type
        var relationships: [(propertyName: String, relatedTypeName: String, deleteRule: String, isToMany: Bool, relationshipPropertyName: String)] = []

        for member in structDecl.memberBlock.members {
            if let varDecl = member.decl.as(VariableDeclSyntax.self) {
                let isVar = varDecl.bindingSpecifier.text == "var"
                let isLet = varDecl.bindingSpecifier.text == "let"

                // Check if field has @Transient attribute
                let isTransient = varDecl.attributes.contains { attr in
                    if case .attribute(let attrSyntax) = attr {
                        return attrSyntax.attributeName.description.trimmingCharacters(in: .whitespaces) == "Transient"
                    }
                    return false
                }

                // Check if field has @Restricted attribute and extract access levels
                var restrictedInfo: (readExpr: String, writeExpr: String)? = nil
                for attr in varDecl.attributes {
                    if case .attribute(let attrSyntax) = attr,
                       attrSyntax.attributeName.description.trimmingCharacters(in: .whitespaces) == "Restricted" {
                        var readExpr = ".public"
                        var writeExpr = ".public"

                        if let arguments = attrSyntax.arguments,
                           let labeledList = arguments.as(LabeledExprListSyntax.self) {
                            for arg in labeledList {
                                if let label = arg.label?.text {
                                    let exprText = arg.expression.description.trimmingCharacters(in: .whitespaces)
                                    if label == "read" {
                                        readExpr = exprText
                                    } else if label == "write" {
                                        writeExpr = exprText
                                    }
                                }
                            }
                        }
                        restrictedInfo = (readExpr: readExpr, writeExpr: writeExpr)
                        break
                    }
                }

                // Check if field has @Relationship attribute
                // Use helper functions from RelationshipMacro.swift
                let relationshipAttr = getRelationshipAttribute(varDecl)

                if isVar || isLet {
                    for binding in varDecl.bindings {
                        if let pattern = binding.pattern.as(IdentifierPatternSyntax.self) {
                            let fieldName = pattern.identifier.text
                            let fieldType = binding.typeAnnotation?.type.description.trimmingCharacters(in: .whitespaces) ?? "Any"
                            let hasDefault = binding.initializer != nil
                            let defaultValue = binding.initializer?.value.description.trimmingCharacters(in: .whitespaces)

                            if fieldName == "id" {
                                hasUserDefinedId = true
                                userIdHasDefault = hasDefault
                                userIdBinding = binding
                            }

                            // Handle @Relationship property (marks FK field with related type)
                            // FK field is explicit: customerID: String?, orderIDs: [String]
                            if let relAttr = relationshipAttr {
                                // Extract relationship info from @Relationship attribute
                                let (relatedTypeName, deleteRule) = extractRelationshipInfo(from: relAttr)

                                // Determine if to-many based on FK field type
                                let isToMany = isToManyFKField(fieldType)

                                // Derive relationship property name from FK field name
                                // customerID -> customer, orderIDs -> orders
                                let relationshipPropertyName = deriveRelationshipPropertyName(from: fieldName, isToMany: isToMany)

                                relationships.append((
                                    propertyName: fieldName,
                                    relatedTypeName: relatedTypeName,
                                    deleteRule: deleteRule,
                                    isToMany: isToMany,
                                    relationshipPropertyName: relationshipPropertyName
                                ))

                                // FK field IS stored (not transient) - it's the actual data
                                allFields.append(fieldName)
                                fieldInfos.append((name: fieldName, type: fieldType, hasDefault: hasDefault, defaultValue: defaultValue, isTransient: false))
                            }
                            // Regular field (not @Relationship)
                            else {
                                // Only add non-transient fields to allFields
                                if !isTransient {
                                    allFields.append(fieldName)
                                }
                                fieldInfos.append((name: fieldName, type: fieldType, hasDefault: hasDefault, defaultValue: defaultValue, isTransient: isTransient))

                                // Track @Restricted fields for metadata generation
                                if let restricted = restrictedInfo {
                                    // Determine default value expression based on type
                                    let defaultExpr: String
                                    if fieldType.hasSuffix("?") || fieldType.hasPrefix("Optional<") {
                                        defaultExpr = "nil"
                                    } else if fieldType == "String" {
                                        defaultExpr = "\"\""
                                    } else if fieldType == "Int" || fieldType == "Int64" || fieldType == "Int32" || fieldType == "Int16" || fieldType == "Int8" {
                                        defaultExpr = "0"
                                    } else if fieldType == "Double" || fieldType == "Float" {
                                        defaultExpr = "0"
                                    } else if fieldType == "Bool" {
                                        defaultExpr = "false"
                                    } else if fieldType.hasPrefix("[") || fieldType.hasPrefix("Array<") {
                                        defaultExpr = "[]"
                                    } else if fieldType == "Data" {
                                        defaultExpr = "Data()"
                                    } else {
                                        // For other types, use the initializer default if available
                                        defaultExpr = defaultValue ?? "/* unknown default */"
                                    }
                                    restrictedFields.append((
                                        fieldName: fieldName,
                                        readExpr: restricted.readExpr,
                                        writeExpr: restricted.writeExpr,
                                        defaultExpr: defaultExpr
                                    ))
                                }
                            }

                            fieldNumber += 1
                        }
                    }
                }
            }
        }

        // Validate: User-defined id MUST have a default value
        // Because id is excluded from the generated initializer
        if hasUserDefinedId && !userIdHasDefault {
            let diagnosticNode: Syntax
            if let binding = userIdBinding {
                diagnosticNode = Syntax(binding)
            } else {
                diagnosticNode = Syntax(node)
            }
            throw DiagnosticsError(diagnostics: [
                Diagnostic(
                    node: diagnosticNode,
                    message: MacroExpansionErrorMessage(
                        "User-defined 'id' field must have a default value. " +
                        "The generated initializer does not include 'id' parameter. " +
                        "Example: var id: UUID = UUID() or var id: Int64 = Int64(Date().timeIntervalSince1970 * 1000)"
                    )
                )
            ])
        }

        // Extract #Index macro calls and generate descriptors
        // Also collect all keyPath strings for fieldName(for:) generation
        var descriptorInits: [String] = []  // All descriptors (Index, Relationship, etc.)
        var allIndexKeyPaths: Set<String> = []  // Collect all keyPaths for fieldName generation

        for member in structDecl.memberBlock.members {
            if let macroDecl = member.decl.as(MacroExpansionDeclSyntax.self),
               macroDecl.macroName.text == "Index" {

                // Format: #Index(IndexKind<T>(...), storedFields: [...], unique: Bool, name: String?)
                // First unlabeled argument is the IndexKind expression (type specified in IndexKind generic)
                var keyPaths: [String] = []
                var storedFieldKeyPaths: [String] = []
                var indexKindExpr: String?
                var indexKindName: String?
                var isUnique = false
                var indexName: String?

                for arg in macroDecl.arguments {
                    // First unlabeled argument: IndexKind expression (e.g., ScalarIndexKind(fields: [\.email]))
                    if arg.label == nil {
                        if let funcCall = arg.expression.as(FunctionCallExprSyntax.self) {
                            // Extract IndexKind name (e.g., "ScalarIndexKind")
                            indexKindName = funcCall.calledExpression.description.trimmingCharacters(in: .whitespaces)

                            // Extract KeyPaths from all function arguments
                            for funcArg in funcCall.arguments {
                                // Check if argument is an array of KeyPaths (e.g., fields: [\.email, \.name])
                                if let arrayExpr = funcArg.expression.as(ArrayExprSyntax.self) {
                                    for element in arrayExpr.elements {
                                        if let keyPathExpr = element.expression.as(KeyPathExprSyntax.self) {
                                            let keyPathString = extractKeyPathString(from: keyPathExpr)
                                            if !keyPathString.isEmpty {
                                                keyPaths.append(keyPathString)
                                                allIndexKeyPaths.insert(keyPathString)
                                            }
                                        }
                                    }
                                }
                                // Check if argument is a single KeyPath (e.g., value: \.price)
                                else if let keyPathExpr = funcArg.expression.as(KeyPathExprSyntax.self) {
                                    let keyPathString = extractKeyPathString(from: keyPathExpr)
                                    if !keyPathString.isEmpty {
                                        keyPaths.append(keyPathString)
                                        allIndexKeyPaths.insert(keyPathString)
                                    }
                                }
                            }

                            // Store the original expression as-is
                            indexKindExpr = arg.expression.description.trimmingCharacters(in: .whitespaces)
                        }
                    }
                    // "storedFields:" argument (KeyPath array for covering index)
                    else if let label = arg.label, label.text == "storedFields" {
                        if let arrayExpr = arg.expression.as(ArrayExprSyntax.self) {
                            for element in arrayExpr.elements {
                                if let keyPathExpr = element.expression.as(KeyPathExprSyntax.self) {
                                    let keyPathString = extractKeyPathString(from: keyPathExpr)
                                    if !keyPathString.isEmpty {
                                        storedFieldKeyPaths.append(keyPathString)
                                        allIndexKeyPaths.insert(keyPathString)
                                    }
                                }
                            }
                        }
                    }
                    // "unique:" argument
                    else if let label = arg.label, label.text == "unique" {
                        if let boolExpr = arg.expression.as(BooleanLiteralExprSyntax.self) {
                            isUnique = boolExpr.literal.text == "true"
                        }
                    }
                    // "name:" argument
                    else if let label = arg.label, label.text == "name" {
                        if let stringLiteral = arg.expression.as(StringLiteralExprSyntax.self),
                           let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self) {
                            indexName = segment.content.text
                        }
                    }
                }

                guard !keyPaths.isEmpty else { continue }

                // Generate index name if not provided
                // Use IndexKind-specific naming patterns
                let finalIndexName: String
                if let customName = indexName {
                    finalIndexName = customName
                } else {
                    let flattenedKeyPaths = keyPaths.map { $0.replacingOccurrences(of: ".", with: "_") }
                    finalIndexName = generateIndexName(
                        typeName: typeName,
                        indexKindName: indexKindName ?? "scalar",
                        fieldNames: flattenedKeyPaths
                    )
                }

                // Generate IndexDescriptor initialization with KeyPaths
                // e.g., [\User.email, \User.address.city]
                let keyPathsLiterals = keyPaths.map { "\\\(structName).\($0)" }.joined(separator: ", ")
                let kindInit = indexKindExpr ?? "ScalarIndexKind(fieldNames: [])"
                let optionsInit = isUnique ? ".init(unique: true)" : ".init()"

                // Generate storedKeyPaths and storedFieldNames if present
                let storedKeyPathsLiterals = storedFieldKeyPaths.map { "\\\(structName).\($0)" }.joined(separator: ", ")
                let storedFieldNamesLiterals = storedFieldKeyPaths.map { "\"\($0)\"" }.joined(separator: ", ")

                let descriptorInit: String
                if storedFieldKeyPaths.isEmpty {
                    descriptorInit = """
                        IndexDescriptor(
                            name: "\(finalIndexName)",
                            keyPaths: [\(keyPathsLiterals)],
                            kind: \(kindInit),
                            commonOptions: \(optionsInit)
                        )
                    """
                } else {
                    descriptorInit = """
                        IndexDescriptor(
                            name: "\(finalIndexName)",
                            keyPaths: [\(keyPathsLiterals)],
                            kind: \(kindInit),
                            commonOptions: \(optionsInit),
                            storedKeyPaths: [\(storedKeyPathsLiterals)],
                            storedFieldNames: [\(storedFieldNamesLiterals)]
                        )
                    """
                }

                descriptorInits.append(descriptorInit)
            }
        }

        // Extract #Directory macro call and parse path components
        var directoryPathComponents: [String] = []  // Generated code strings: Path("x") or Field(\Type.y)
        var directoryLayerValue: String = ".default"  // Default layer

        for member in structDecl.memberBlock.members {
            if let macroDecl = member.decl.as(MacroExpansionDeclSyntax.self),
               macroDecl.macroName.text == "Directory" {

                for arg in macroDecl.arguments {
                    // Check if this is the "layer:" labeled argument
                    if let label = arg.label, label.text == "layer" {
                        // Extract layer value (e.g., .partition, .default)
                        if let memberAccess = arg.expression.as(MemberAccessExprSyntax.self) {
                            directoryLayerValue = ".\(memberAccess.declName.baseName.text)"
                        }
                        continue
                    }

                    let expr = arg.expression

                    // Check if it's a string literal → Path("value")
                    if let stringLiteral = expr.as(StringLiteralExprSyntax.self),
                       let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self) {
                        let pathValue = segment.content.text
                        directoryPathComponents.append("Path(\"\(pathValue)\")")
                        continue
                    }

                    // Check if it's Field(\.propertyName)
                    if let functionCall = expr.as(FunctionCallExprSyntax.self) {
                        // Check for Field(...) pattern
                        let calledExpr = functionCall.calledExpression.description.trimmingCharacters(in: .whitespaces)
                        if calledExpr == "Field" {
                            if let firstArg = functionCall.arguments.first,
                               let keyPathExpr = firstArg.expression.as(KeyPathExprSyntax.self),
                               let component = keyPathExpr.components.first,
                               let property = component.component.as(KeyPathPropertyComponentSyntax.self) {
                                let fieldName = property.declName.baseName.text
                                directoryPathComponents.append("Field(\\.\(fieldName))")
                            }
                        }
                    }
                }
                // Only process the first #Directory declaration
                break
            }
        }

        var decls: [DeclSyntax] = []

        // Generate `id` field if not user-defined
        if !hasUserDefinedId {
            let idDecl: DeclSyntax = """
                public var id: String = ULID().ulidString
                """
            decls.append(idDecl)

            // Add id to allFields at the beginning
            allFields.insert("id", at: 0)
            fieldInfos.insert((name: "id", type: "String", hasDefault: true, defaultValue: "ULID().ulidString", isTransient: false), at: 0)
        }

        // Generate persistableType property
        let persistableTypeDecl: DeclSyntax = """
            public static var persistableType: String { "\(raw: typeName)" }
            """
        decls.append(persistableTypeDecl)

        // Generate allFields property
        let allFieldsArray = "[\(allFields.map { "\"\($0)\"" }.joined(separator: ", "))]"
        let allFieldsDecl: DeclSyntax = """
            public static var allFields: [String] { \(raw: allFieldsArray) }
            """
        decls.append(allFieldsDecl)

        // Generate relationship indexes and RelationshipDescriptors for @Relationship FK fields
        // FK field name IS the property name (customerID, orderIDs)
        // Index name uses the derived relationship property name (customer, orders)
        // Key structure: [indexSubspace]/[relatedId]/[ownerId]
        for rel in relationships {
            // Use relationshipPropertyName for index naming (e.g., "Order_customer")
            let relationshipIndexName = "\(typeName)_\(rel.relationshipPropertyName)"
            // FK field name is the property name itself (customerID, orderIDs)
            let fkFieldName = rel.propertyName

            // Generate IndexDescriptor for relationship index
            // Uses ScalarIndexKind for foreign key lookup
            let relationshipIndexInit = """
                IndexDescriptor(
                    name: "\(relationshipIndexName)",
                    keyPaths: [\\\(structName).\(fkFieldName)],
                    kind: ScalarIndexKind<\(structName)>(fieldNames: ["\(fkFieldName)"]),
                    commonOptions: .init()
                )
            """
            descriptorInits.append(relationshipIndexInit)

            // Generate RelationshipDescriptor
            // Uses Relationship module types (RelationshipDescriptor, DeleteRule)
            // Note: We use unqualified names because user must `import Relationship` to use @Relationship macro
            // Using "Relationship.DeleteRule" causes conflict with the @Relationship macro name
            // rel.deleteRule is in format ".nullify" so we need "DeleteRule" prefix
            let deleteRuleValue = rel.deleteRule.hasPrefix(".") ? String(rel.deleteRule.dropFirst()) : rel.deleteRule
            let relationshipDescriptorInit = """
                RelationshipDescriptor(
                    name: "\(relationshipIndexName)",
                    propertyName: "\(rel.propertyName)",
                    relatedTypeName: "\(rel.relatedTypeName)",
                    deleteRule: DeleteRule.\(deleteRuleValue),
                    isToMany: \(rel.isToMany),
                    relationshipPropertyName: "\(rel.relationshipPropertyName)"
                )
            """
            descriptorInits.append(relationshipDescriptorInit)
        }

        // Generate reverse IndexDescriptor for @OWLDataProperty(to:) / @OWLProperty(to:) fields (FK indexing)
        for member in structDecl.memberBlock.members {
            if let varDecl = member.decl.as(VariableDeclSyntax.self),
               let propertyAttr = getOWLDataPropertyAttribute(varDecl) {
                let info = extractOWLDataPropertyInfo(from: propertyAttr)
                if info.targetTypeName != nil {
                    for binding in varDecl.bindings {
                        if let pattern = binding.pattern.as(IdentifierPatternSyntax.self) {
                            let fieldName = pattern.identifier.text
                            let reverseIndexName = "\(typeName)_\(fieldName)"
                            let reverseIndexInit = """
                                IndexDescriptor(
                                    name: "\(reverseIndexName)",
                                    keyPaths: [\\\(structName).\(fieldName)],
                                    kind: ScalarIndexKind<\(structName)>(fieldNames: ["\(fieldName)"]),
                                    commonOptions: .init()
                                )
                            """
                            descriptorInits.append(reverseIndexInit)
                        }
                    }
                }
            }
        }

        // Generate graph index and OWLObjectPropertyDescriptor for @OWLObjectProperty
        if let objPropAttr = getOWLObjectPropertyAttribute(structDecl) {
            let objPropInfo = extractOWLObjectPropertyInfo(from: objPropAttr)
            if !objPropInfo.fromField.isEmpty && !objPropInfo.toField.isEmpty {
                let graphIndexName = "\(typeName)_graph_\(objPropInfo.fromField)_\(objPropInfo.toField)"
                let graphIndexInit = """
                    IndexDescriptor(
                        name: "\(graphIndexName)",
                        keyPaths: [\\\(structName).\(objPropInfo.fromField), \\\(structName).\(objPropInfo.toField)],
                        kind: GraphIndexKind<\(structName)>.adjacency(
                            source: \\.\(objPropInfo.fromField),
                            target: \\.\(objPropInfo.toField)
                        ),
                        commonOptions: .init()
                    )
                """
                descriptorInits.append(graphIndexInit)

                let objPropDescriptorInit = """
                    OWLObjectPropertyDescriptor(
                        name: "\(typeName)_objectProperty",
                        iri: "\(objPropInfo.iri)",
                        fromFieldName: "\(objPropInfo.fromField)",
                        toFieldName: "\(objPropInfo.toField)"
                    )
                """
                descriptorInits.append(objPropDescriptorInit)
            }
        }

        // Generate descriptors property (unified array for all descriptor types)
        let descriptorsArray = descriptorInits.isEmpty
            ? "[]"
            : "[\n            \(descriptorInits.joined(separator: ",\n            "))\n        ]"
        let descriptorsDecl: DeclSyntax = """
            public static var descriptors: [any Descriptor] { \(raw: descriptorsArray) }
            """
        decls.append(descriptorsDecl)

        // Generate directoryPathComponents property
        // Always generate (no default in Persistable extension to avoid conflicts with Polymorphable)
        if !directoryPathComponents.isEmpty {
            let componentsArray = "[\(directoryPathComponents.joined(separator: ", "))]"
            let directoryPathDecl: DeclSyntax = """
                public static var directoryPathComponents: [any DirectoryPathElement] { \(raw: componentsArray) }
                """
            decls.append(directoryPathDecl)
        } else {
            // Default: use persistableType as path
            let directoryPathDecl: DeclSyntax = """
                public static var directoryPathComponents: [any DirectoryPathElement] { [Path(persistableType)] }
                """
            decls.append(directoryPathDecl)
        }

        // Generate directoryLayer property
        let directoryLayerDecl: DeclSyntax = """
            public static var directoryLayer: Core.DirectoryLayer { \(raw: directoryLayerValue) }
            """
        decls.append(directoryLayerDecl)

        // Generate restrictedFieldsMetadata for field-level security
        // This provides compile-time metadata about @Restricted fields
        if !restrictedFields.isEmpty {
            // Helper to add FieldAccessLevel prefix to expressions like ".roles([...])"
            func fullyQualify(_ expr: String) -> String {
                if expr.hasPrefix(".") {
                    return "FieldAccessLevel\(expr)"
                }
                return expr
            }

            var metadataEntries: [String] = []
            for field in restrictedFields {
                metadataEntries.append("""
                    RestrictedFieldMetadata(
                            fieldName: "\(field.fieldName)",
                            readAccess: \(fullyQualify(field.readExpr)),
                            writeAccess: \(fullyQualify(field.writeExpr))
                        )
                """)
            }
            let metadataArray = "[\n            \(metadataEntries.joined(separator: ",\n            "))\n        ]"
            let restrictedMetadataDecl: DeclSyntax = """
                public static var restrictedFieldsMetadata: [RestrictedFieldMetadata] { \(raw: metadataArray) }
                """
            decls.append(restrictedMetadataDecl)

            // Generate masked(auth:) method for field masking
            var maskAssignments: [String] = []
            for field in restrictedFields {
                maskAssignments.append("""
                    if !\(fullyQualify(field.readExpr)).evaluate(auth: auth) {
                            copy.\(field.fieldName) = \(field.defaultExpr)
                        }
                """)
            }
            let maskedDecl: DeclSyntax = """
                public func masked(auth: (any AuthContext)?) -> Self {
                    var copy = self
                    \(raw: maskAssignments.joined(separator: "\n        "))
                    return copy
                }
                """
            decls.append(maskedDecl)
        } else {
            // No restricted fields - provide empty metadata and identity mask
            let emptyMetadataDecl: DeclSyntax = """
                public static var restrictedFieldsMetadata: [RestrictedFieldMetadata] { [] }
                """
            decls.append(emptyMetadataDecl)

            let identityMaskedDecl: DeclSyntax = """
                public func masked(auth: (any AuthContext)?) -> Self { self }
                """
            decls.append(identityMaskedDecl)
        }

        // Generate fieldNumber method (excludes transient fields)
        var fieldNumberCases: [String] = []
        var persistedFieldIndex = 0
        for fieldInfo in fieldInfos {
            if !fieldInfo.isTransient {
                persistedFieldIndex += 1
                fieldNumberCases.append("case \"\(fieldInfo.name)\": return \(persistedFieldIndex)")
            }
        }
        let fieldNumberBody = fieldNumberCases.isEmpty
            ? "return nil"
            : """
            switch fieldName {
                    \(fieldNumberCases.joined(separator: "\n        "))
                    default: return nil
                }
            """
        let fieldNumberDecl: DeclSyntax = """
            public static func fieldNumber(for fieldName: String) -> Int? {
                \(raw: fieldNumberBody)
            }
            """
        decls.append(fieldNumberDecl)

        // Generate fieldSchemas property
        var fieldSchemaEntries: [String] = []
        var schemaFieldIndex = 0
        for fieldInfo in fieldInfos {
            if !fieldInfo.isTransient {
                schemaFieldIndex += 1
                let rawType = fieldInfo.type
                let (schemaType, isOptional, isArray) = mapToFieldSchemaType(rawType)
                fieldSchemaEntries.append(
                    "FieldSchema(name: \"\(fieldInfo.name)\", fieldNumber: \(schemaFieldIndex), type: .\(schemaType), isOptional: \(isOptional), isArray: \(isArray))"
                )
            }
        }
        let fieldSchemasArray = fieldSchemaEntries.isEmpty
            ? "[]"
            : "[\n            \(fieldSchemaEntries.joined(separator: ",\n            "))\n        ]"
        let fieldSchemasDecl: DeclSyntax = """
            public static var fieldSchemas: [FieldSchema] { \(raw: fieldSchemasArray) }
            """
        decls.append(fieldSchemasDecl)

        // Generate enumMetadata method with runtime extraction for non-primitive fields
        let primitiveTypeNames: Set<String> = [
            "String", "Int", "Int8", "Int16", "Int32", "Int64",
            "UInt", "UInt8", "UInt16", "UInt32", "UInt64",
            "Double", "Float", "Bool", "Date", "UUID", "Data"
        ]
        var enumMetadataCases: [String] = []
        for fieldInfo in fieldInfos {
            if fieldInfo.isTransient || fieldInfo.name == "id" { continue }
            // Extract bare type name (unwrap Optional, Array)
            var bareType = fieldInfo.type.trimmingCharacters(in: .whitespaces)
            if bareType.hasSuffix("?") {
                bareType = String(bareType.dropLast())
            } else if bareType.hasPrefix("Optional<") && bareType.hasSuffix(">") {
                bareType = String(bareType.dropFirst("Optional<".count).dropLast())
            }
            if bareType.hasPrefix("[") && bareType.hasSuffix("]") {
                bareType = String(bareType.dropFirst().dropLast())
            } else if bareType.hasPrefix("Array<") && bareType.hasSuffix(">") {
                bareType = String(bareType.dropFirst("Array<".count).dropLast())
            }
            if bareType.hasSuffix("?") {
                bareType = String(bareType.dropLast())
            }
            if !primitiveTypeNames.contains(bareType) {
                enumMetadataCases.append("case \"\(fieldInfo.name)\": return EnumMetadata.extract(from: \(bareType).self)")
            }
        }
        let enumMetadataBody: String
        if enumMetadataCases.isEmpty {
            enumMetadataBody = "return nil"
        } else {
            enumMetadataBody = """
            switch fieldName {
                    \(enumMetadataCases.joined(separator: "\n        "))
                    default: return nil
                }
            """
        }
        let enumMetadataDecl: DeclSyntax = """
            public static func enumMetadata(for fieldName: String) -> EnumMetadata? {
                \(raw: enumMetadataBody)
            }
            """
        decls.append(enumMetadataDecl)

        // Generate subscript for @dynamicMemberLookup (excludes transient fields)
        // For Optional types, unwrap before returning to avoid boxing Optional<T> as `any Sendable`
        var subscriptCases: [String] = []
        for fieldInfo in fieldInfos {
            if !fieldInfo.isTransient {
                // Check if the type is Optional (ends with ? or is Optional<...>)
                let isOptional = fieldInfo.type.hasSuffix("?") ||
                                 fieldInfo.type.hasPrefix("Optional<")
                if isOptional {
                    // For Optional types, unwrap the value to avoid boxing Optional as `any Sendable`
                    subscriptCases.append("""
                    case "\(fieldInfo.name)":
                                if let value = self.\(fieldInfo.name) { return value }
                                return nil
                    """)
                } else {
                    subscriptCases.append("case \"\(fieldInfo.name)\": return self.\(fieldInfo.name)")
                }
            }
        }
        let subscriptBody = subscriptCases.isEmpty
            ? "return nil"
            : """
            switch member {
                    \(subscriptCases.joined(separator: "\n        "))
                    default: return nil
                }
            """
        let subscriptDecl: DeclSyntax = """
            public subscript(dynamicMember member: String) -> (any Sendable)? {
                \(raw: subscriptBody)
            }
            """
        decls.append(subscriptDecl)

        // Generate fieldName(for:) methods for KeyPath → String conversion
        // Include top-level fields, @Relationship properties, and all indexed keyPaths (including nested)
        var fieldNameCases: [String] = []

        // Add top-level fields (excludes transient, but includes @Relationship below)
        for fieldInfo in fieldInfos {
            if !fieldInfo.isTransient {
                fieldNameCases.append("if keyPath == \\\(structName).\(fieldInfo.name) { return \"\(fieldInfo.name)\" }")
            }
        }

        // Add @Relationship property names (needed for related() API even though they're transient)
        for rel in relationships {
            fieldNameCases.append("if keyPath == \\\(structName).\(rel.propertyName) { return \"\(rel.propertyName)\" }")
        }

        // Add nested keyPaths from #Index declarations
        for keyPathStr in allIndexKeyPaths.sorted() {
            // Skip top-level fields (already added)
            if !keyPathStr.contains(".") { continue }
            fieldNameCases.append("if keyPath == \\\(structName).\(keyPathStr) { return \"\(keyPathStr)\" }")
        }

        let fieldNameBody = fieldNameCases.joined(separator: "\n        ")

        let fieldNameDecl: DeclSyntax = """
            public static func fieldName<Value>(for keyPath: KeyPath<\(raw: structName), Value>) -> String {
                \(raw: fieldNameBody)
                return "\\(keyPath)"
            }
            """
        decls.append(fieldNameDecl)

        // Generate PartialKeyPath version
        let partialFieldNameDecl: DeclSyntax = """
            public static func fieldName(for keyPath: PartialKeyPath<\(raw: structName)>) -> String {
                \(raw: fieldNameBody)
                return "\\(keyPath)"
            }
            """
        decls.append(partialFieldNameDecl)

        // Generate AnyKeyPath version (for type-erased usage)
        let anyFieldNameDecl: DeclSyntax = """
            public static func fieldName(for keyPath: AnyKeyPath) -> String {
                if let partialKeyPath = keyPath as? PartialKeyPath<\(raw: structName)> {
                    return fieldName(for: partialKeyPath)
                }
                return "\\(keyPath)"
            }
            """
        decls.append(anyFieldNameDecl)

        // Generate init without `id` parameter and transient fields
        // Only include fields that are NOT `id` and NOT @Transient
        let initParams = fieldInfos
            .filter { $0.name != "id" && !$0.isTransient }
            .map { info -> String in
                if info.hasDefault, let defaultValue = info.defaultValue {
                    return "\(info.name): \(info.type) = \(defaultValue)"
                } else {
                    return "\(info.name): \(info.type)"
                }
            }
            .joined(separator: ", ")

        let initAssignments = fieldInfos
            .filter { $0.name != "id" && !$0.isTransient }
            .map { "self.\($0.name) = \($0.name)" }
            .joined(separator: "\n        ")

        if !initAssignments.isEmpty {
            let initDecl: DeclSyntax = """
                public init(\(raw: initParams)) {
                    \(raw: initAssignments)
                }
                """
            decls.append(initDecl)
        } else {
            // No fields other than id
            let initDecl: DeclSyntax = """
                public init() {}
                """
            decls.append(initDecl)
        }

        // Generate CodingKeys enum with explicit intValue for Protobuf field numbers
        // This ensures consistent field numbering even when Optional fields are nil
        // (Swift's synthesized Codable skips nil values, which would shift field numbers)
        let codableFieldInfos = fieldInfos.filter { !$0.isTransient }
        let codingKeyCases = codableFieldInfos.map { "case \($0.name)" }

        // Generate intValue computed property
        var intValueCases: [String] = []
        for (index, field) in codableFieldInfos.enumerated() {
            intValueCases.append("case .\(field.name): return \(index + 1)")
        }

        // Generate init?(intValue:)
        var initIntValueCases: [String] = []
        for (index, field) in codableFieldInfos.enumerated() {
            initIntValueCases.append("case \(index + 1): self = .\(field.name)")
        }

        let codingKeysDecl: DeclSyntax = """
            private enum CodingKeys: String, CodingKey {
                \(raw: codingKeyCases.joined(separator: "\n            "))

                var intValue: Int? {
                    switch self {
                    \(raw: intValueCases.joined(separator: "\n                "))
                    }
                }

                init?(intValue: Int) {
                    switch intValue {
                    \(raw: initIntValueCases.joined(separator: "\n                "))
                    default: return nil
                    }
                }
            }
            """
        decls.append(codingKeysDecl)

        return decls
    }

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        let conformanceExt: DeclSyntax = """
            extension \(type.trimmed): Persistable, Codable, Sendable {}
            """

        if let extensionDecl = conformanceExt.as(ExtensionDeclSyntax.self) {
            return [extensionDecl]
        }

        return []

        // Note: Snapshot extensions cannot be generated by ExtensionMacro
        // because macros can only extend the type they're attached to.
        // Users access relationships via:
        // - snapshot.ref(RelatedType.self, \.fkField) for to-one
        // - snapshot.refs(RelatedType.self, \.fkArrayField) for to-many
    }
}

/// Index macro
///
/// **Usage**:
/// ```swift
/// // IndexKind with KeyPaths in constructor (type specified in IndexKind generic)
/// #Index(ScalarIndexKind<Product>(fields: [\.email]), unique: true)
/// #Index(ScalarIndexKind<Product>(fields: [\.category, \.price]))
/// #Index(CountIndexKind<Product>(groupBy: [\.category]))
/// #Index(SumIndexKind<Product>(groupBy: [\.category], value: \.price))
/// ```
///
/// This is a marker macro. Validation is performed, but no code is generated.
/// The @Persistable macro detects #Index calls and generates IndexDescriptor array.
public struct IndexMacro: DeclarationMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // First argument must be an IndexKind expression (unlabeled)
        guard let firstArg = node.arguments.first else {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(
                    node: Syntax(node),
                    message: MacroExpansionErrorMessage("#Index requires an IndexKind (e.g., ScalarIndexKind<T>(fields: [\\.email]))")
                )
            ])
        }

        // Validate that first argument is unlabeled and is a function call (IndexKind initializer)
        guard firstArg.label == nil else {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(
                    node: Syntax(firstArg),
                    message: MacroExpansionErrorMessage("First argument must be an IndexKind (e.g., ScalarIndexKind<T>(fields: [\\.email]))")
                )
            ])
        }

        guard let _ = firstArg.expression.as(FunctionCallExprSyntax.self) else {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(
                    node: Syntax(firstArg.expression),
                    message: MacroExpansionErrorMessage("First argument must be an IndexKind initializer (e.g., ScalarIndexKind<T>(fields: [\\.email]))")
                )
            ])
        }

        // Marker macro - no code generation
        return []
    }
}

/// @Transient macro implementation
///
/// Marker macro that excludes a property from persistence.
/// The actual exclusion logic is in @Persistable macro which detects @Transient.
///
/// **Usage**:
/// ```swift
/// @Persistable
/// struct User {
///     var email: String
///
///     @Transient
///     var cachedData: Data?  // Excluded from persistence
/// }
/// ```
public struct TransientMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // Validate that @Transient is applied to a variable declaration
        guard let varDecl = declaration.as(VariableDeclSyntax.self) else {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(
                    node: Syntax(node),
                    message: MacroExpansionErrorMessage("@Transient can only be applied to properties")
                )
            ])
        }

        // Validate that the property has a default value
        for binding in varDecl.bindings {
            if binding.initializer == nil {
                // Check if it's an optional type (which implicitly has nil default)
                if let typeAnnotation = binding.typeAnnotation,
                   typeAnnotation.type.is(OptionalTypeSyntax.self) ||
                   typeAnnotation.type.is(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
                    // Optional types are OK without explicit initializer
                    continue
                }

                throw DiagnosticsError(diagnostics: [
                    Diagnostic(
                        node: Syntax(binding),
                        message: MacroExpansionErrorMessage(
                            "@Transient property must have a default value. " +
                            "It is excluded from the generated initializer."
                        )
                    )
                ])
            }
        }

        // Marker macro - no code generation
        return []
    }
}

// MARK: - Helper Functions

/// Extracts field name string from KeyPath expression
/// e.g., \.email → "email", \.address.city → "address.city"
private func extractKeyPathString(from keyPathExpr: KeyPathExprSyntax) -> String {
    var pathComponents: [String] = []
    for component in keyPathExpr.components {
        if let property = component.component.as(KeyPathPropertyComponentSyntax.self) {
            pathComponents.append(property.declName.baseName.text)
        }
    }
    return pathComponents.joined(separator: ".")
}

/// Generates index name based on IndexKind type and field names
/// Mirrors the indexName computed property in each IndexKind implementation
private func generateIndexName(typeName: String, indexKindName: String, fieldNames: [String]) -> String {
    // Remove generic parameter if present (e.g., "ScalarIndexKind<Product>" → "ScalarIndexKind")
    let kindBaseName = indexKindName.components(separatedBy: "<").first ?? indexKindName

    switch kindBaseName {
    case "ScalarIndexKind":
        // Format: {TypeName}_{field1}_{field2}
        return "\(typeName)_\(fieldNames.joined(separator: "_"))"

    case "CountIndexKind":
        // Format: {TypeName}_count_{field1}_{field2}
        return "\(typeName)_count_\(fieldNames.joined(separator: "_"))"

    case "SumIndexKind":
        // Format: {TypeName}_sum_{groupFields}__{valueField}
        // Last field is the value field
        if fieldNames.count > 1 {
            let groupFields = Array(fieldNames.dropLast())
            let valueField = fieldNames.last!
            return "\(typeName)_sum_\(groupFields.joined(separator: "_"))__\(valueField)"
        }
        return "\(typeName)_sum_\(fieldNames.joined(separator: "_"))"

    case "MinIndexKind":
        // Format: {TypeName}_min_{groupFields}__{valueField}
        if fieldNames.count > 1 {
            let groupFields = Array(fieldNames.dropLast())
            let valueField = fieldNames.last!
            return "\(typeName)_min_\(groupFields.joined(separator: "_"))__\(valueField)"
        }
        return "\(typeName)_min_\(fieldNames.joined(separator: "_"))"

    case "MaxIndexKind":
        // Format: {TypeName}_max_{groupFields}__{valueField}
        if fieldNames.count > 1 {
            let groupFields = Array(fieldNames.dropLast())
            let valueField = fieldNames.last!
            return "\(typeName)_max_\(groupFields.joined(separator: "_"))__\(valueField)"
        }
        return "\(typeName)_max_\(fieldNames.joined(separator: "_"))"

    case "AverageIndexKind":
        // Format: {TypeName}_avg_{groupFields}__{valueField}
        if fieldNames.count > 1 {
            let groupFields = Array(fieldNames.dropLast())
            let valueField = fieldNames.last!
            return "\(typeName)_avg_\(groupFields.joined(separator: "_"))__\(valueField)"
        }
        return "\(typeName)_avg_\(fieldNames.joined(separator: "_"))"

    case "VersionIndexKind":
        // Format: {TypeName}_version_{field}
        return "\(typeName)_version_\(fieldNames.joined(separator: "_"))"

    default:
        // Default pattern for custom/third-party IndexKinds
        // Format: {TypeName}_{kindIdentifier}_{fields}
        let kindIdentifier = kindBaseName
            .replacingOccurrences(of: "IndexKind", with: "")
            .lowercased()
        if kindIdentifier.isEmpty {
            return "\(typeName)_\(fieldNames.joined(separator: "_"))"
        }
        return "\(typeName)_\(kindIdentifier)_\(fieldNames.joined(separator: "_"))"
    }
}

/// Maps a Swift type string to (FieldSchemaType name, isOptional, isArray)
///
/// Handles Optional<T>, T?, [T], Array<T>, and bare types.
private func mapToFieldSchemaType(_ rawType: String) -> (schemaType: String, isOptional: Bool, isArray: Bool) {
    var type = rawType.trimmingCharacters(in: .whitespaces)

    // Unwrap Optional
    var isOptional = false
    if type.hasSuffix("?") {
        isOptional = true
        type = String(type.dropLast())
    } else if type.hasPrefix("Optional<") && type.hasSuffix(">") {
        isOptional = true
        type = String(type.dropFirst("Optional<".count).dropLast())
    }

    // Unwrap Array
    var isArray = false
    if type.hasPrefix("[") && type.hasSuffix("]") {
        isArray = true
        type = String(type.dropFirst().dropLast())
    } else if type.hasPrefix("Array<") && type.hasSuffix(">") {
        isArray = true
        type = String(type.dropFirst("Array<".count).dropLast())
    }

    // Unwrap inner Optional (e.g., [String?])
    if type.hasSuffix("?") {
        type = String(type.dropLast())
    }

    let schemaType: String
    switch type {
    case "String":
        schemaType = "string"
    case "Int":
        schemaType = "int"
    case "Int8":
        schemaType = "int8"
    case "Int16":
        schemaType = "int16"
    case "Int32":
        schemaType = "int32"
    case "Int64":
        schemaType = "int64"
    case "UInt":
        schemaType = "uint"
    case "UInt8":
        schemaType = "uint8"
    case "UInt16":
        schemaType = "uint16"
    case "UInt32":
        schemaType = "uint32"
    case "UInt64":
        schemaType = "uint64"
    case "Double":
        schemaType = "double"
    case "Float":
        schemaType = "float"
    case "Bool":
        schemaType = "bool"
    case "Date":
        schemaType = "date"
    case "UUID":
        schemaType = "uuid"
    case "Data":
        schemaType = "data"
    default:
        // Non-primitive type: resolve at runtime via RawRepresentable check.
        // FieldSchemaType.resolve(TypeName.self) returns .enum if RawRepresentable, .nested otherwise.
        schemaType = "resolve(\(type).self)"
    }

    return (schemaType, isOptional, isArray)
}

/// Compiler plugin entry point
@main
struct FDBModelMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        PersistableMacro.self,
        PolymorphableMacro.self,
        IndexMacro.self,
        DirectoryMacro.self,
        TransientMacro.self,
        ReferenceMacro.self,
    ]
}

/// Error message helper
struct MacroExpansionErrorMessage: DiagnosticMessage {
    let message: String
    let diagnosticID: MessageID
    let severity: DiagnosticSeverity

    init(_ message: String) {
        self.message = message
        self.diagnosticID = MessageID(domain: "FDBModelMacros", id: message)
        self.severity = .error
    }
}
