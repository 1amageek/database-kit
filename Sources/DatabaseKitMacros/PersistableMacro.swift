import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

/// @Persistable macro implementation
///
/// Generates persistence conformance for models and raw-value enums.
///
/// **Supports all layers**:
/// - Entity layer (RDB): Structured entities with indexes
/// - DocumentLayer (DocumentDB): Flexible documents
/// - GraphLayer (GraphDB): Define nodes with relationships
///
/// **Generated code includes**:
/// - `static var persistableType: String`
/// - `static var allFields: [String]`
/// - `static var indexDescriptors: [IndexDescriptor]`
/// - `static func fieldNumber(for fieldName: String) -> Int?`
/// - `static func enumMetadata(for fieldName: String) -> EnumMetadata?`
/// - `init(...)`
///
/// **Usage**:
/// ```swift
/// @Persistable
/// struct User {
///     var id: String
///     #Index(.ordered(
///         name: "users_by_email",
///         keys: [.ascending(\User.email)],
///         unique: true
///     ))
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
        if let enumDecl = declaration.as(EnumDeclSyntax.self) {
            if let arguments = node.arguments?.as(LabeledExprListSyntax.self),
               let typeArgument = arguments.first(where: {
                   $0.label?.text == "type"
               }) {
                throw DiagnosticsError(diagnostics: [
                    Diagnostic(
                        node: Syntax(typeArgument),
                        message: MacroExpansionErrorMessage(
                            "@Persistable(type:) is only available for structs"
                        )
                    )
                ])
            }

            var hasExplicitAllCases = false
            var caseNames: [String] = []

            for member in enumDecl.memberBlock.members {
                if let variable = member.decl.as(VariableDeclSyntax.self),
                   variable.modifiers.contains(where: {
                       let name = $0.name.text
                       return name == "static" || name == "class"
                   }),
                   variable.bindings.contains(where: { binding in
                       binding.pattern.as(IdentifierPatternSyntax.self)?
                           .identifier.text == "allCases"
                   }) {
                    hasExplicitAllCases = true
                }

                guard let enumCase = member.decl.as(EnumCaseDeclSyntax.self)
                else { continue }

                if let availabilityAttribute = enumCase.attributes.compactMap({
                    element -> AttributeSyntax? in
                    guard case .attribute(let attribute) = element,
                          attribute.attributeName.trimmedDescription == "available"
                    else {
                        return nil
                    }
                    return attribute
                }).first {
                    throw DiagnosticsError(diagnostics: [
                        Diagnostic(
                            node: Syntax(availabilityAttribute),
                            message: MacroExpansionErrorMessage(
                                "@Persistable enum cases cannot have availability attributes"
                            )
                        )
                    ])
                }

                for element in enumCase.elements {
                    guard element.parameterClause == nil else {
                        throw DiagnosticsError(diagnostics: [
                            Diagnostic(
                                node: Syntax(element),
                                message: MacroExpansionErrorMessage(
                                    "@Persistable enum cases cannot have associated values"
                                )
                            )
                        ])
                    }
                    caseNames.append(element.name.trimmedDescription)
                }
            }

            guard !hasExplicitAllCases else { return [] }

            let allCases = caseNames.map { ".\($0)" }.joined(separator: ", ")
            let allCasesDecl: DeclSyntax = """
                public static var allCases: [Self] { [\(raw: allCases)] }
                """
            return [allCasesDecl]
        }

        // Extract struct name
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(
                    node: Syntax(node),
                    message: MacroExpansionErrorMessage(
                        "@Persistable can only be applied to structs and enums"
                    )
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

        // Extract all stored properties (fields) and @Relationship declarations
        var allFields: [String] = []
        var fieldInfos: [(
            name: String,
            type: String,
            hasDefault: Bool,
            defaultValue: String?,
            canonicalDefaultValue: String?,
            isTransient: Bool
        )] = []
        // Track @Restricted fields for static authorization declarations.
        var restrictedFields: [(
            fieldName: String,
            readExpr: String,
            writeExpr: String
        )] = []

        // Track typed @Relationship fields.
        var relationships: [(
            propertyName: String,
            relatedTypeName: String,
            deleteRule: String,
            cardinalityExpression: String
        )] = []

        func hasTypeLevelModifier(_ varDecl: VariableDeclSyntax) -> Bool {
            varDecl.modifiers.contains { modifier in
                let name = modifier.name.text
                return name == "static" || name == "class"
            }
        }

        func isComputedProperty(_ binding: PatternBindingSyntax) -> Bool {
            guard let accessorBlock = binding.accessorBlock else {
                return false
            }

            switch accessorBlock.accessors {
            case .getter:
                return true
            case .accessors(let accessors):
                return accessors.contains { accessor in
                    let specifier = accessor.accessorSpecifier.text
                    return specifier != "willSet" && specifier != "didSet"
                }
            }
        }

        for member in structDecl.memberBlock.members {
            if let varDecl = member.decl.as(VariableDeclSyntax.self) {
                if hasTypeLevelModifier(varDecl) {
                    continue
                }

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
                        if isComputedProperty(binding) {
                            continue
                        }

                        if let pattern = binding.pattern.as(IdentifierPatternSyntax.self) {
                            let fieldName = pattern.identifier.text
                            let fieldType =
                                binding.typeAnnotation?.type.trimmedDescription
                                ?? "Any"
                            let hasDefault = binding.initializer != nil
                            let defaultValue = binding.initializer?.value.description.trimmingCharacters(in: .whitespaces)
                            let canonicalDefaultValue = canonicalPersistedDefaultExpression(
                                for: fieldType,
                                initializer: binding.initializer?.value
                            )

                            if fieldName == "id" {
                                hasUserDefinedId = true
                            }

                            if let relAttr = relationshipAttr {
                                guard let typeSyntax = binding.typeAnnotation?.type,
                                      let parsed = parseRelationshipField(typeSyntax) else {
                                    throw DiagnosticsError(diagnostics: [
                                        Diagnostic(
                                            node: Syntax(relAttr),
                                            message: MacroExpansionErrorMessage(
                                                "@Relationship requires a PersistableReference<Target> field"
                                            )
                                        )
                                    ])
                                }

                                relationships.append((
                                    propertyName: fieldName,
                                    relatedTypeName: parsed.relatedTypeName,
                                    deleteRule: extractRelationshipDeleteRule(from: relAttr),
                                    cardinalityExpression: parsed.cardinalityExpression
                                ))

                                allFields.append(fieldName)
                                fieldInfos.append((name: fieldName, type: fieldType, hasDefault: hasDefault, defaultValue: defaultValue, canonicalDefaultValue: canonicalDefaultValue, isTransient: false))
                            }
                            // Regular field (not @Relationship)
                            else {
                                // Only add non-transient fields to allFields
                                if !isTransient {
                                    allFields.append(fieldName)
                                }
                                fieldInfos.append((name: fieldName, type: fieldType, hasDefault: hasDefault, defaultValue: defaultValue, canonicalDefaultValue: canonicalDefaultValue, isTransient: isTransient))

                                // Track @Restricted fields for static rules.
                                if let restricted = restrictedInfo {
                                    restrictedFields.append((
                                        fieldName: fieldName,
                                        readExpr: restricted.readExpr,
                                        writeExpr: restricted.writeExpr
                                    ))
                                }
                            }

                        }
                    }
                }
            }
        }

        guard hasUserDefinedId else {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(
                    node: Syntax(node),
                    message: MacroExpansionErrorMessage(
                        "@Persistable requires an explicit 'id' field whose type conforms to PersistableIdentifier"
                    )
                )
            ])
        }

        guard let identifierField = fieldInfos.first(where: {
            $0.name == "id" && !$0.isTransient
        }) else {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(
                    node: Syntax(node),
                    message: MacroExpansionErrorMessage(
                        "@Persistable requires 'id' to be a persisted field"
                    )
                )
            ])
        }

        func normalizedTypeName(_ typeName: String) -> String {
            let withoutLineComment = typeName.components(separatedBy: "//").first ?? typeName
            let withoutBlockComment = withoutLineComment.components(separatedBy: "/*").first ?? withoutLineComment
            return withoutBlockComment.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        func isOptionalType(_ typeName: String) -> Bool {
            let trimmed = normalizedTypeName(typeName)
            return trimmed.hasSuffix("?") ||
                (trimmed.hasPrefix("Optional<") && trimmed.hasSuffix(">"))
        }

        func wrappedTypeName(for typeName: String) -> String {
            let trimmed = normalizedTypeName(typeName)
            if trimmed.hasSuffix("?") {
                return String(trimmed.dropLast())
            }
            if trimmed.hasPrefix("Optional<") && trimmed.hasSuffix(">") {
                return String(trimmed.dropFirst("Optional<".count).dropLast())
            }
            return trimmed
        }

        let identifierTypeName = normalizedTypeName(identifierField.type)

        func defaultInitializationExpr(
            for fieldInfo: (name: String, type: String, hasDefault: Bool, defaultValue: String?, canonicalDefaultValue: String?, isTransient: Bool)
        ) -> String {
            if let defaultValue = fieldInfo.defaultValue {
                return defaultValue
            }

            let fieldType = normalizedTypeName(fieldInfo.type)
            if isOptionalType(fieldType) {
                return "nil"
            }
            if fieldType == "String" {
                return "\"\""
            }
            if ["Int", "Int8", "Int16", "Int32", "Int64", "UInt", "UInt8", "UInt16", "UInt32", "UInt64"].contains(fieldType) {
                return "0"
            }
            if fieldType == "Double" || fieldType == "Float" {
                return "0"
            }
            if fieldType == "Bool" {
                return "false"
            }
            if fieldType.hasPrefix("[") || fieldType.hasPrefix("Array<") {
                return "[]"
            }
            if fieldType == "ByteString" {
                return "ByteString()"
            }
            return "\(fieldType)()"
        }

        func persistableFieldDecodeExpr(
            for fieldInfo: (name: String, type: String, hasDefault: Bool, defaultValue: String?, canonicalDefaultValue: String?, isTransient: Bool)
        ) -> String {
            if fieldInfo.isTransient {
                return defaultInitializationExpr(for: fieldInfo)
            }

            let fieldType = normalizedTypeName(fieldInfo.type)
            if fieldInfo.hasDefault {
                let decodedType = isOptionalType(fieldType) ? wrappedTypeName(for: fieldType) : fieldType
                let fallback = defaultInitializationExpr(for: fieldInfo)
                return "(try input.decodeIfPresent(\(decodedType).self, for: Self.fields.\(fieldInfo.name).identity, entity: Self.persistableType)) ?? \(fallback)"
            }

            if isOptionalType(fieldType) {
                let wrappedType = wrappedTypeName(for: fieldType)
                return "try input.decodeIfPresent(\(wrappedType).self, for: Self.fields.\(fieldInfo.name).identity, entity: Self.persistableType)"
            }

            return "try input.decode(\(fieldType).self, for: Self.fields.\(fieldInfo.name).identity, entity: Self.persistableType)"
        }

        // Compile each complete index declaration into canonical field identity.
        var indexDescriptorInits: [String] = []
        var relationshipDescriptorInits: [String] = []
        var objectPropertyDescriptorInits: [String] = []

        for member in structDecl.memberBlock.members {
            if let macroDecl = member.decl.as(MacroExpansionDeclSyntax.self),
               macroDecl.macroName.text == "Index" {

                guard macroDecl.arguments.count == 1,
                      let argument = macroDecl.arguments.first,
                      argument.label == nil else {
                    throw DiagnosticsError(diagnostics: [
                        Diagnostic(
                            node: Syntax(macroDecl),
                            message: MacroExpansionErrorMessage(
                                "#Index accepts exactly one unlabeled IndexDeclaration"
                            )
                        )
                    ])
                }
                let declaration = try compileConcreteIndexDeclaration(
                    argument.expression,
                    rootType: structName,
                    node: Syntax(macroDecl)
                )
                indexDescriptorInits.append(
                    """
                    IndexDescriptor(
                        entityName: \(structName).persistableType,
                        declaration: \(declaration.trimmedDescription),
                        fieldSchemas: \(structName).fieldSchemas
                    )
                    """
                )
            }
        }

        // Extract #Directory macro call and parse path components
        var directoryPathComponents: [String] = []
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

                    // Compile a string literal into a canonical static path component.
                    if let stringLiteral = expr.as(StringLiteralExprSyntax.self),
                       let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self) {
                        let pathValue = segment.content.text
                        directoryPathComponents.append(".staticPath(\"\(pathValue)\")")
                        continue
                    }

                    if let keyPath = expr.as(KeyPathExprSyntax.self),
                       let component = keyPath.components.last,
                       let property = component.component.as(
                           KeyPathPropertyComponentSyntax.self
                       ) {
                        directoryPathComponents.append(
                            ".dynamicField(fieldName: \"\(property.declName.baseName.text)\")"
                        )
                        continue
                    }

                }
                // Only process the first #Directory declaration
                break
            }
        }

        var decls: [DeclSyntax] = []

        let identifierTypeDecl: DeclSyntax = """
            public typealias ID = \(raw: identifierTypeName)
            """
        decls.append(identifierTypeDecl)

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

        let persistedFieldInfos = fieldInfos.filter { !$0.isTransient }
        for rel in relationships {
            guard let fieldOffset = persistedFieldInfos.firstIndex(where: {
                $0.name == rel.propertyName
            }) else {
                throw DiagnosticsError(diagnostics: [
                    Diagnostic(
                        node: Syntax(structDecl),
                        message: MacroExpansionErrorMessage(
                            "@Relationship field '\(rel.propertyName)' is not persisted"
                        )
                    )
                ])
            }
            let relationshipDescriptorInit = """
                RelationshipDescriptor(
                    ownerTypeName: persistableType,
                    propertyName: "\(rel.propertyName)",
                    propertyFieldNumber: \(fieldOffset + 1),
                    relatedTypeName: \(rel.relatedTypeName).persistableType,
                    cardinality: \(rel.cardinalityExpression),
                    deleteRule: \(rel.deleteRule)
                )
            """
            relationshipDescriptorInits.append(relationshipDescriptorInit)
        }

        // Generate reverse indexes for @OWLDataProperty(to:) fields.
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
                                    entityName: \(structName).persistableType,
                                    declaration: .ordered(
                                        name: "\(reverseIndexName)",
                                        keys: [
                                            .ascending(\(structName).fields.\(fieldName).identity)
                                        ]
                                    ),
                                    fieldSchemas: \(structName).fieldSchemas
                                )
                            """
                            indexDescriptorInits.append(reverseIndexInit)
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
                        entityName: \(structName).persistableType,
                        declaration: .graph(
                            name: "\(graphIndexName)",
                            definition: .property(
                                source: \(structName).fields.\(objPropInfo.fromField).identity,
                                label: .implicit,
                                target: \(structName).fields.\(objPropInfo.toField).identity,
                                graph: nil,
                                strategy: .adjacency
                            )
                        ),
                        fieldSchemas: \(structName).fieldSchemas
                    )
                """
                indexDescriptorInits.append(graphIndexInit)

                let objPropDescriptorInit = """
                    OWLObjectPropertyDescriptor(
                        name: "\(typeName)_objectProperty",
                        iri: "\(objPropInfo.iri)",
                        fromFieldName: "\(objPropInfo.fromField)",
                        toFieldName: "\(objPropInfo.toField)"
                    )
                """
                objectPropertyDescriptorInits.append(objPropDescriptorInit)
            }
        }

        let indexDescriptorsArray = indexDescriptorInits.isEmpty
            ? "[]"
            : "[\n            \(indexDescriptorInits.joined(separator: ",\n            "))\n        ]"
        let indexDescriptorsExpression = indexDescriptorInits.isEmpty
            ? indexDescriptorsArray
            : "try \(indexDescriptorsArray)"
        let indexDescriptorsDecl: DeclSyntax = """
            public static var _persistableIndexDescriptors: [IndexDescriptor] {
                get throws(IndexDeclarationError) {
                    \(raw: indexDescriptorsExpression)
                }
            }
            """
        decls.append(indexDescriptorsDecl)

        let relationshipsArray = relationshipDescriptorInits.isEmpty
            ? "[]"
            : "[\n            \(relationshipDescriptorInits.joined(separator: ",\n            "))\n        ]"
        let relationshipsDecl: DeclSyntax = """
            public static var relationshipDescriptors: [RelationshipDescriptor] {
                \(raw: relationshipsArray)
            }
            """
        decls.append(relationshipsDecl)

        let objectPropertiesArray = objectPropertyDescriptorInits.isEmpty
            ? "[]"
            : "[\n            \(objectPropertyDescriptorInits.joined(separator: ",\n            "))\n        ]"
        let objectPropertiesDecl: DeclSyntax = """
            public static var owlObjectPropertyDescriptors: [OWLObjectPropertyDescriptor] {
                \(raw: objectPropertiesArray)
            }
            """
        decls.append(objectPropertiesDecl)

        // Generate directoryPathComponents property
        // Always generate (no default in Persistable extension to avoid conflicts with Polymorphable)
        if !directoryPathComponents.isEmpty {
            let componentsArray = "[\(directoryPathComponents.joined(separator: ", "))]"
            let directoryPathDecl: DeclSyntax = """
                public static var directoryPathComponents: [DirectoryPathComponent] { \(raw: componentsArray) }
                """
            decls.append(directoryPathDecl)
        } else {
            // Default: use persistableType as path
            let directoryPathDecl: DeclSyntax = """
                public static var directoryPathComponents: [DirectoryPathComponent] { [.staticPath(persistableType)] }
                """
            decls.append(directoryPathDecl)
        }

        // Generate directoryLayer property
        let directoryLayerDecl: DeclSyntax = """
            public static var directoryLayer: DatabaseKit.DirectoryLayer { \(raw: directoryLayerValue) }
            """
        decls.append(directoryLayerDecl)

        // Generate static field authorization declarations.
        if !restrictedFields.isEmpty {
            // Helper to add FieldAccessLevel prefix to expressions like ".roles([...])"
            func fullyQualify(_ expr: String) -> String {
                if expr.hasPrefix(".") {
                    return "FieldAccessLevel\(expr)"
                }
                return expr
            }

            var ruleEntries: [String] = []
            for field in restrictedFields {
                ruleEntries.append("""
                    FieldAccessRule(
                            field: Self.fields.\(field.fieldName).identity,
                            read: \(fullyQualify(field.readExpr)),
                            write: \(fullyQualify(field.writeExpr))
                        )
                """)
            }
            let rulesArray = "[\n            \(ruleEntries.joined(separator: ",\n            "))\n        ]"
            let fieldAccessRulesDecl: DeclSyntax = """
                public static var fieldAccessRules: [FieldAccessRule] { \(raw: rulesArray) }
                """
            decls.append(fieldAccessRulesDecl)
        } else {
            let emptyRulesDecl: DeclSyntax = """
                public static var fieldAccessRules: [FieldAccessRule] { [] }
                """
            decls.append(emptyRulesDecl)
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
                if isPlatformIntegerPersistedType(rawType) {
                    throw DiagnosticsError(diagnostics: [
                        Diagnostic(
                            node: Syntax(node),
                            message: MacroExpansionErrorMessage(
                                "@Persistable field '\(fieldInfo.name)' uses \(persistedElementType(rawType)). " +
                                "Persisted integer fields require an explicit fixed-width type."
                            )
                        )
                    ])
                }
                var (schemaType, isOptional, isArray) = mapToFieldSchemaType(rawType)
                let relationship = relationships.first {
                    $0.propertyName == fieldInfo.name
                }
                let referenceTarget: String
                if let relationship {
                    schemaType = ".reference"
                    referenceTarget = ", referenceTargetEntity: \(relationship.relatedTypeName).persistableType"
                } else {
                    referenceTarget = ""
                }
                let defaultValue = fieldInfo.canonicalDefaultValue.map {
                    ", defaultValue: \($0)"
                } ?? ""
                fieldSchemaEntries.append(
                    "FieldSchema(name: \"\(fieldInfo.name)\", fieldNumber: \(schemaFieldIndex), type: \(schemaType), isOptional: \(isOptional), isArray: \(isArray)\(referenceTarget)\(defaultValue))"
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

        var typedFieldEntries: [String] = []
        var typedFieldIndex = 0
        for fieldInfo in fieldInfos where !fieldInfo.isTransient {
            typedFieldIndex += 1
            let fieldType = fieldInfo.type.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            var (schemaType, isOptional, isArray) = mapToFieldSchemaType(
                fieldInfo.type
            )
            let relationship = relationships.first {
                $0.propertyName == fieldInfo.name
            }
            let referenceTarget: String
            if let relationship {
                schemaType = ".reference"
                referenceTarget = ", referenceTargetEntity: \(relationship.relatedTypeName).persistableType"
            } else {
                referenceTarget = ""
            }
            typedFieldEntries.append(
                """
                public static let \(fieldInfo.name) = Field<\(structName), \(fieldType)>(
                    identity: FieldIdentity(name: "\(fieldInfo.name)", number: \(typedFieldIndex)),
                    type: \(schemaType),
                    isOptional: \(isOptional),
                    isArray: \(isArray)\(referenceTarget)
                )
                """
            )
        }
        let typedFieldsBody = typedFieldEntries.joined(separator: "\n\n        ")
        let typedFieldsDecl: DeclSyntax = """
            public enum Fields {
                \(raw: typedFieldsBody)
            }
            """
        decls.append(typedFieldsDecl)

        let fieldsNamespaceDecl: DeclSyntax = """
            public static var fields: Fields.Type { Fields.self }
            """
        decls.append(fieldsNamespaceDecl)

        var persistedFieldEncodeEntries: [String] = []
        for fieldInfo in fieldInfos where !fieldInfo.isTransient {
            persistedFieldEncodeEntries.append(
                """
                try output.write(
                    Self.fields.\(fieldInfo.name).identity,
                    value: self.\(fieldInfo.name),
                    entity: Self.persistableType
                )
                """
            )
        }
        let persistedFieldEncodeBody = persistedFieldEncodeEntries.joined(
            separator: "\n        "
        )
        let persistedFieldEncoderDecl: DeclSyntax = """
            public func encodePersistedFields<Output: DatabaseKit.PersistedFieldOutput>(
                to output: inout Output
            ) throws(DatabaseKit.PersistableEncodingFailure<Output.Failure>) {
                \(raw: persistedFieldEncodeBody)
            }
            """
        decls.append(persistedFieldEncoderDecl)

        let selectedFieldEntries = fieldInfos
            .filter { !$0.isTransient }
            .map { fieldInfo in
                """
                if field.number == Self.fields.\(fieldInfo.name).identity.number ||
                   field.name == Self.fields.\(fieldInfo.name).identity.name {
                    guard field.number == Self.fields.\(fieldInfo.name).identity.number,
                          field.name == Self.fields.\(fieldInfo.name).identity.name else {
                        throw DatabaseKit.PersistableEncodingError.invalidSchema(
                            entity: Self.persistableType,
                            reason: "field identity '\\(field.name)#\\(field.number)' does not match '\\(Self.fields.\(fieldInfo.name).identity.name)#\\(Self.fields.\(fieldInfo.name).identity.number)'"
                        )
                    }
                    return try DatabaseKit.PersistableFieldEncoder.fieldValue(
                        from: self.\(fieldInfo.name)
                    )
                }
                """
            }
            .joined(separator: "\n        ")
        let selectedFieldDecl: DeclSyntax = """
            public func persistedFieldValue(
                for field: DatabaseKit.FieldIdentity
            ) throws(DatabaseKit.PersistableEncodingError) -> DatabaseTypes.FieldValue? {
                \(raw: selectedFieldEntries)
                return nil
            }
            """
        decls.append(selectedFieldDecl)

        let modelDecodeAssignments = fieldInfos
            .map { fieldInfo in
                "self.\(fieldInfo.name) = \(persistableFieldDecodeExpr(for: fieldInfo))"
            }
            .joined(separator: "\n        ")
        let persistedFieldInputInitDecl: DeclSyntax = """
            private init<Input: DatabaseKit.PersistedFieldInput>(
                _persistedFieldInput input: inout Input
            ) throws(DatabaseKit.PersistableDecodingFailure<Input.Failure>) {
                \(raw: modelDecodeAssignments)
                try input.finish(entity: Self.persistableType)
            }
            """
        decls.append(persistedFieldInputInitDecl)

        let persistedFieldInputDecl: DeclSyntax = """
            public static func decodePersistedFields<Input: DatabaseKit.PersistedFieldInput>(
                from input: inout Input
            ) throws(DatabaseKit.PersistableDecodingFailure<Input.Failure>) -> Self {
                try Self(_persistedFieldInput: &input)
            }
            """
        decls.append(persistedFieldInputDecl)

        let persistedFieldCollectionDecl: DeclSyntax = """
            public static func decodePersistedFields(
                _ fields: consuming [DatabaseKit.PersistableField]
            ) throws(DatabaseKit.PersistableDecodingError) -> Self {
                var input = try DatabaseKit.PersistedFieldCollectionInput(
                    entity: Self.persistableType,
                    fields: fields,
                    schemas: Self.fieldSchemas
                )
                return try input.decode { (
                    input: inout DatabaseKit.PersistedFieldCollectionInput
                ) throws(DatabaseKit.PersistableDecodingFailure<Never>) -> Self in
                    try Self(_persistedFieldInput: &input)
                }
            }
            """
        decls.append(persistedFieldCollectionDecl)

        let persistedObjectDecl: DeclSyntax = """
            public static func decodePersistedObject(
                _ object: DatabaseTypes.FieldObject
            ) throws(DatabaseKit.PersistableDecodingError) -> Self {
                var input = try DatabaseKit.PersistedObjectInput(
                    entity: Self.persistableType,
                    object: object,
                    schemas: Self.fieldSchemas
                )
                return try input.decode { (
                    input: inout DatabaseKit.PersistedObjectInput
                ) throws(DatabaseKit.PersistableDecodingFailure<Never>) -> Self in
                    try Self(_persistedFieldInput: &input)
                }
            }
            """
        decls.append(persistedObjectDecl)

        // Generate enum metadata through the field type's static value contract.
        let primitiveTypeNames: Set<String> = [
            "String", "Int", "Int8", "Int16", "Int32", "Int64",
            "UInt", "UInt8", "UInt16", "UInt32", "UInt64",
            "Double", "Float", "Bool",
            "UUID",
            "ExactDecimal", "ByteString", "CivilDate", "CivilTime",
            "CivilDateTime", "Timestamp", "TimeSpan", "CalendarPeriod",
            "GeographicPoint", "GeographicPosition", "Vector",
            "FieldObject", "EntityReference", "RDFTerm",
            "DatabaseTypes.ExactDecimal", "DatabaseTypes.ByteString",
            "DatabaseTypes.CivilDate", "DatabaseTypes.CivilTime",
            "DatabaseTypes.CivilDateTime", "DatabaseTypes.Timestamp",
            "DatabaseTypes.TimeSpan", "DatabaseTypes.CalendarPeriod",
            "DatabaseTypes.GeographicPoint",
            "DatabaseTypes.GeographicPosition", "DatabaseTypes.Vector",
            "DatabaseTypes.UUID", "DatabaseTypes.FieldObject",
            "DatabaseTypes.EntityReference", "DatabaseTypes.RDFTerm"
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
                enumMetadataCases.append(
                    "case \"\(fieldInfo.name)\": return \(bareType).fieldEnumMetadata(named: \"\(bareType)\")"
                )
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

        // Generate an initializer for all persisted fields.
        let initParams = fieldInfos
            .filter { !$0.isTransient }
            .map { info -> String in
                if info.hasDefault, let defaultValue = info.defaultValue {
                    return "\(info.name): \(info.type) = \(defaultValue)"
                } else {
                    return "\(info.name): \(info.type)"
                }
            }
            .joined(separator: ", ")

        let initAssignments = fieldInfos
            .filter { !$0.isTransient }
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
            // A model with no persisted fields is rejected before this point.
            let initDecl: DeclSyntax = """
                public init() {}
                """
            decls.append(initDecl)
        }

        return decls
    }

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        let requiredConformance: String
        if declaration.is(StructDeclSyntax.self) {
            requiredConformance = "Persistable"
        } else if declaration.is(EnumDeclSyntax.self) {
            requiredConformance = "PersistableEnum"
        } else {
            return []
        }

        let shouldAddConformance = protocols.contains { type in
            type.trimmedDescription.split(separator: ".").last.map(String.init)
                == requiredConformance
        }
        guard shouldAddConformance else { return [] }

        let conformanceExt: DeclSyntax = """
            extension \(type.trimmed): \(raw: requiredConformance) {}
            """

        if let extensionDecl = conformanceExt.as(ExtensionDeclSyntax.self) {
            return [extensionDecl]
        }

        return []
    }
}

/// Index macro
///
/// **Usage**:
/// ```swift
/// #Index(.ordered(
///     name: "products_by_email",
///     keys: [.ascending(\Product.email)],
///     unique: true
/// ))
/// #Index(.aggregate(
///     name: "product_count_by_category",
///     function: .count,
///     groupBy: [.ascending(\Product.category)]
/// ))
/// ```
///
/// This is a marker macro. Validation is performed, but no code is generated.
/// The @Persistable macro detects #Index calls and generates IndexDescriptor array.
public struct IndexMacro: DeclarationMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard node.arguments.count == 1,
              let argument = node.arguments.first,
              argument.label == nil else {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(
                    node: Syntax(node),
                    message: MacroExpansionErrorMessage(
                        "#Index accepts exactly one unlabeled IndexDeclaration"
                    )
                )
            ])
        }
        try validateIndexDeclarationExpression(
            argument.expression,
            node: Syntax(argument.expression)
        )
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
///     var cachedData: ByteString?  // Excluded from persistence
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

/// Maps a Swift type string to (FieldSchemaType expression, isOptional, isArray)
///
/// Handles Optional<T>, T?, [T], Array<T>, and bare types.
private func persistedElementType(_ rawType: String) -> String {
    var type = rawType.trimmingCharacters(in: .whitespaces)

    var changed = true
    while changed {
        changed = false
        if type.hasSuffix("?") {
            type = String(type.dropLast()).trimmingCharacters(in: .whitespaces)
            changed = true
        } else if type.hasPrefix("Optional<"), type.hasSuffix(">") {
            type = String(type.dropFirst("Optional<".count).dropLast())
                .trimmingCharacters(in: .whitespaces)
            changed = true
        } else if type.hasPrefix("["), type.hasSuffix("]") {
            type = String(type.dropFirst().dropLast())
                .trimmingCharacters(in: .whitespaces)
            changed = true
        } else if type.hasPrefix("Array<"), type.hasSuffix(">") {
            type = String(type.dropFirst("Array<".count).dropLast())
                .trimmingCharacters(in: .whitespaces)
            changed = true
        }
    }
    return type
}

private func isPlatformIntegerPersistedType(_ rawType: String) -> Bool {
    let type = persistedElementType(rawType)
    return type == "Int" || type == "UInt"
}

/// Converts the declared Swift member default through the same canonical value
/// cases used by persisted field encoding. The generated schema evaluates the
/// original initializer expression with its declared Swift type, so schema and
/// model decoding cannot drift onto separately authored defaults.
private func canonicalPersistedDefaultExpression(
    for rawType: String,
    initializer: ExprSyntax?
) -> String? {
    let isOptional = mapToFieldSchemaType(rawType).isOptional
    guard let initializer else {
        return isOptional ? "DatabaseTypes.FieldValue.null" : nil
    }
    if initializer.is(NilLiteralExprSyntax.self) {
        return isOptional ? "DatabaseTypes.FieldValue.null" : nil
    }

    return "((\(initializer.trimmedDescription)) as \(rawType)).fieldValue"
}

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
        schemaType = ".string"
    case "Int":
        schemaType = ".int64"
    case "Int8":
        schemaType = ".int8"
    case "Int16":
        schemaType = ".int16"
    case "Int32":
        schemaType = ".int32"
    case "Int64":
        schemaType = ".int64"
    case "UInt":
        schemaType = ".uint64"
    case "UInt8":
        schemaType = ".uint8"
    case "UInt16":
        schemaType = ".uint16"
    case "UInt32":
        schemaType = ".uint32"
    case "UInt64":
        schemaType = ".uint64"
    case "Double":
        schemaType = ".float64"
    case "Float":
        schemaType = ".float32"
    case "Bool":
        schemaType = ".bool"
    case "ExactDecimal", "DatabaseTypes.ExactDecimal":
        schemaType = ".decimal"
    case "CivilDate", "DatabaseTypes.CivilDate":
        schemaType = ".date"
    case "CivilTime", "DatabaseTypes.CivilTime":
        schemaType = ".time"
    case "CivilDateTime", "DatabaseTypes.CivilDateTime":
        schemaType = ".dateTime"
    case "Timestamp", "DatabaseTypes.Timestamp":
        schemaType = ".timestamp"
    case "TimeSpan", "DatabaseTypes.TimeSpan":
        schemaType = ".timeSpan"
    case "CalendarPeriod", "DatabaseTypes.CalendarPeriod":
        schemaType = ".calendarPeriod"
    case "GeographicPoint", "DatabaseTypes.GeographicPoint":
        schemaType = ".geographicPoint"
    case "GeographicPosition", "DatabaseTypes.GeographicPosition":
        schemaType = ".geographicPosition"
    case "Vector", "DatabaseTypes.Vector":
        schemaType = ".vector"
    case "UUID", "DatabaseTypes.UUID":
        schemaType = ".uuid"
    case "ByteString", "DatabaseTypes.ByteString":
        schemaType = ".bytes"
    case "FieldObject", "DatabaseTypes.FieldObject":
        schemaType = ".object"
    case "EntityReference", "DatabaseTypes.EntityReference":
        schemaType = ".reference"
    case "RDFTerm", "DatabaseTypes.RDFTerm":
        schemaType = ".rdfTerm"
    default:
        schemaType = "\(type).fieldSchemaType"
    }

    return (schemaType, isOptional, isArray)
}

/// Compiler plugin entry point
@main
struct DatabaseDeclarationPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        PersistableMacro.self,
        PolymorphableMacro.self,
        PolymorphicDeclarationMarkerMacro.self,
        IndexMacro.self,
        DirectoryMacro.self,
        TransientMacro.self,
        RelationshipMacro.self,
        OWLDataPropertyMacro.self,
        OWLClassMacro.self,
        OWLObjectPropertyMacro.self,
        FieldExpressionMacro.self,
    ]
}

/// Error message helper
struct MacroExpansionErrorMessage: DiagnosticMessage {
    let message: String
    let diagnosticID: MessageID
    let severity: DiagnosticSeverity

    init(_ message: String) {
        self.message = message
        self.diagnosticID = MessageID(
            domain: "DatabaseDeclarationMacros",
            id: message
        )
        self.severity = .error
    }
}
