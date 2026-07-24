import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

/// @Persistable macro implementation
///
/// Generates Persistable protocol conformance and static model metadata.
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

        // Extract all stored properties (fields) and @Relationship declarations
        var allFields: [String] = []
        var fieldInfos: [(name: String, type: String, hasDefault: Bool, defaultValue: String?, isTransient: Bool)] = []
        // Track @Restricted fields for field-level security metadata
        var restrictedFields: [(fieldName: String, readExpr: String, writeExpr: String, defaultExpr: String)] = []

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
                            let fieldType = binding.typeAnnotation?.type.description.trimmingCharacters(in: .whitespaces) ?? "Any"
                            let hasDefault = binding.initializer != nil
                            let defaultValue = binding.initializer?.value.description.trimmingCharacters(in: .whitespaces)

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
                                    } else if fieldType == "ByteString" {
                                        defaultExpr = "ByteString()"
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

        func defaultInitializationExpr(
            for fieldInfo: (name: String, type: String, hasDefault: Bool, defaultValue: String?, isTransient: Bool)
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
            for fieldInfo: (name: String, type: String, hasDefault: Bool, defaultValue: String?, isTransient: Bool)
        ) -> String {
            if fieldInfo.isTransient {
                return defaultInitializationExpr(for: fieldInfo)
            }

            let fieldType = normalizedTypeName(fieldInfo.type)
            if fieldInfo.hasDefault {
                let decodedType = isOptionalType(fieldType) ? wrappedTypeName(for: fieldType) : fieldType
                let fallback = defaultInitializationExpr(for: fieldInfo)
                return "(try decoder.decodeIfPresent(\(decodedType).self, for: \"\(fieldInfo.name)\")) ?? \(fallback)"
            }

            if isOptionalType(fieldType) {
                let wrappedType = wrappedTypeName(for: fieldType)
                return "try decoder.decodeIfPresent(\(wrappedType).self, for: \"\(fieldInfo.name)\")"
            }

            return "try decoder.decode(\(fieldType).self, for: \"\(fieldInfo.name)\")"
        }

        // Extract #Index macro calls and generate descriptors
        // Also collect all keyPath strings for fieldName(for:) generation
        var descriptorInits: [String] = []  // All descriptors (Index, Relationship, etc.)
        var indexDescriptorInits: [String] = []
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
                            var extractedKeyPaths: [String] = []
                            var keyPathsByArgumentLabel: [String: [String]] = [:]
                            for funcArg in funcCall.arguments {
                                var argumentKeyPaths: [String] = []

                                // Check if argument is an array of KeyPaths (e.g., fields: [\.email, \.name])
                                if let arrayExpr = funcArg.expression.as(ArrayExprSyntax.self) {
                                    for element in arrayExpr.elements {
                                        if let keyPathExpr = element.expression.as(KeyPathExprSyntax.self) {
                                            let keyPathString = extractKeyPathString(from: keyPathExpr)
                                            if !keyPathString.isEmpty {
                                                argumentKeyPaths.append(keyPathString)
                                            }
                                        }
                                    }
                                }
                                // Check if argument is a single KeyPath (e.g., value: \.price)
                                else if let keyPathExpr = funcArg.expression.as(KeyPathExprSyntax.self) {
                                    let keyPathString = extractKeyPathString(from: keyPathExpr)
                                    if !keyPathString.isEmpty {
                                        argumentKeyPaths.append(keyPathString)
                                    }
                                }

                                if let label = funcArg.label?.text {
                                    keyPathsByArgumentLabel[label, default: []].append(contentsOf: argumentKeyPaths)
                                }
                                extractedKeyPaths.append(contentsOf: argumentKeyPaths)
                            }

                            let selectedKeyPaths: [String]
                            if indexKindName?.contains("TimeWindowLeaderboardIndexKind") == true {
                                selectedKeyPaths = (keyPathsByArgumentLabel["groupBy"] ?? []) +
                                    (keyPathsByArgumentLabel["scoreField"] ?? [])
                            } else {
                                selectedKeyPaths = extractedKeyPaths
                            }
                            keyPaths.append(contentsOf: selectedKeyPaths)
                            for keyPath in selectedKeyPaths {
                                allIndexKeyPaths.insert(keyPath)
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

                let isCountIndex = indexKindName?
                    .components(separatedBy: "<")
                    .first?
                    .trimmingCharacters(in: .whitespacesAndNewlines) == "CountIndexKind"
                guard !keyPaths.isEmpty || isCountIndex else { continue }

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
                let keyPathsExpression: String
                if keyPaths.isEmpty {
                    keyPathsExpression = "[PartialKeyPath<\(structName)>]()"
                } else {
                    let keyPathsLiterals = keyPaths
                        .map { "\\\(structName).\($0)" }
                        .joined(separator: ", ")
                    keyPathsExpression = "[\(keyPathsLiterals)]"
                }
                let kindInit = indexKindExpr ?? "ScalarIndexKind(fieldNames: [])"
                let optionsInit = isUnique ? ".init(unique: true)" : ".init()"

                // Generate stored field names if present.
                let storedFieldNamesLiterals = storedFieldKeyPaths.map { "\"\($0)\"" }.joined(separator: ", ")

                let descriptorInit: String
                if storedFieldKeyPaths.isEmpty {
                    descriptorInit = """
                        IndexDescriptor(
                            name: "\(finalIndexName)",
                            keyPaths: \(keyPathsExpression),
                            kind: \(kindInit),
                            commonOptions: \(optionsInit)
                        )
                    """
                } else {
                    descriptorInit = """
                        IndexDescriptor(
                            name: "\(finalIndexName)",
                            keyPaths: \(keyPathsExpression),
                            kind: \(kindInit),
                            commonOptions: \(optionsInit),
                            storedFieldNames: [\(storedFieldNamesLiterals)]
                        )
                    """
                }

                descriptorInits.append(descriptorInit)
                indexDescriptorInits.append(descriptorInit)
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

                    // Check if it's Field(\.propertyName) or Field<T>(\.propertyName)
                    if let functionCall = expr.as(FunctionCallExprSyntax.self) {
                        let calledBaseName: String?
                        if let identExpr = functionCall.calledExpression.as(DeclReferenceExprSyntax.self) {
                            calledBaseName = identExpr.baseName.text
                        } else if let genericExpr = functionCall.calledExpression.as(GenericSpecializationExprSyntax.self),
                                  let identExpr = genericExpr.expression.as(DeclReferenceExprSyntax.self) {
                            calledBaseName = identExpr.baseName.text
                        } else {
                            calledBaseName = nil
                        }
                        if calledBaseName == "Field" {
                            if let firstArg = functionCall.arguments.first,
                               let keyPathExpr = firstArg.expression.as(KeyPathExprSyntax.self),
                               let component = keyPathExpr.components.first,
                               let property = component.component.as(KeyPathPropertyComponentSyntax.self) {
                                let fieldName = property.declName.baseName.text
                                directoryPathComponents.append(".dynamicField(fieldName: \"\(fieldName)\")")
                            }
                        }
                    }
                }
                // Only process the first #Directory declaration
                break
            }
        }

        var decls: [DeclSyntax] = []

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
            descriptorInits.append(relationshipDescriptorInit)
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
                                    name: "\(reverseIndexName)",
                                    keyPaths: [\\\(structName).\(fieldName)],
                                    kind: ScalarIndexKind<\(structName)>(fieldNames: ["\(fieldName)"]),
                                    commonOptions: .init()
                                )
                            """
                            descriptorInits.append(reverseIndexInit)
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
                indexDescriptorInits.append(graphIndexInit)

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

        // Generate _persistableDescriptors (macro-generated descriptors from #Index, @Relationship, @OWLObjectProperty)
        // NOTE: This is NOT `descriptors` — the unified `descriptors` property is provided by
        // protocol extensions in Persistable (default) and OWLClassEntity (constrained override).
        // This separation allows independent macros to contribute descriptors without coupling.
        let descriptorsArray = descriptorInits.isEmpty
            ? "[]"
            : "[\n            \(descriptorInits.joined(separator: ",\n            "))\n        ]"
        let descriptorsExpression = indexDescriptorInits.isEmpty
            ? descriptorsArray
            : "try \(descriptorsArray)"
        let descriptorsDecl: DeclSyntax = """
            public static var _persistableDescriptors: [any Descriptor] {
                get throws(IndexDeclarationError) {
                    \(raw: descriptorsExpression)
                }
            }
            """
        decls.append(descriptorsDecl)

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
                    schemaType = "reference"
                    referenceTarget = ", referenceTargetEntity: \(relationship.relatedTypeName).persistableType"
                } else {
                    referenceTarget = ""
                }
                fieldSchemaEntries.append(
                    "FieldSchema(name: \"\(fieldInfo.name)\", fieldNumber: \(schemaFieldIndex), type: .\(schemaType), isOptional: \(isOptional), isArray: \(isArray)\(referenceTarget))"
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

        let recordDecodeAssignments = fieldInfos
            .map { fieldInfo in
                "self.\(fieldInfo.name) = \(persistableFieldDecodeExpr(for: fieldInfo))"
            }
            .joined(separator: "\n        ")
        let recordDecodableInitDecl: DeclSyntax = """
            private init(_persistableFieldDecoder decoder: DatabaseKit.PersistableFieldDecoder) throws {
                \(raw: recordDecodeAssignments)
            }
            """
        decls.append(recordDecodableInitDecl)

        let recordDecoderDecl: DeclSyntax = """
            public static func decodePersistedFields(_ fields: [DatabaseKit.PersistableField]) throws -> Self {
                let decoder = try DatabaseKit.PersistableFieldDecoder(
                    entity: persistableType,
                    fields: fields,
                    schemas: fieldSchemas
                )
                return try Self(_persistableFieldDecoder: decoder)
            }
            """
        decls.append(recordDecoderDecl)

        // Generate enumMetadata method with runtime extraction for non-primitive fields
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
        // Include top-level fields and all indexed keyPaths (including nested)
        var fieldNameCases: [String] = []

        // Add top-level fields (excludes transient, but includes @Relationship below)
        for fieldInfo in fieldInfos {
            if !fieldInfo.isTransient {
                fieldNameCases.append("if keyPath == \\\(structName).\(fieldInfo.name) { return \"\(fieldInfo.name)\" }")
            }
        }

        // Add nested keyPaths from #Index declarations
        for keyPathStr in allIndexKeyPaths.sorted() {
            // Skip top-level fields (already added)
            if !keyPathStr.contains(".") { continue }
            fieldNameCases.append("if keyPath == \\\(structName).\(keyPathStr) { return \"\(keyPathStr)\" }")
        }

        let fieldNameBody = fieldNameCases.joined(separator: "\n        ")

        // Generate value-type-based dispatch for uniquely-typed fields.
        //
        // Release builds with Whole-Module Optimization can share computed
        // KeyPath accessors across generic specializations. When a polymorphic
        // protocol extension creates `\Self.field` via generic context, the
        // resulting KeyPath has identity that differs from a literal
        // `\ConcreteType.field`, so the identity-based dispatch above and the
        // `_fieldName(fromKeyPathDescription:)` parser both miss (the
        // description is `\Type.<computed 0xADDR (ValueType)>`).
        //
        // Bridge that gap by emitting type-based dispatch for fields whose
        // value type is unique within the struct. We deliberately only emit
        // these for *uniquely-typed* fields so multiple same-typed fields
        // cannot collide. Two-typed fields fall back to identity/description.
        func canonicalTypeString(_ raw: String) -> String {
            var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            while s.hasSuffix("?") {
                s = "Optional<" + String(s.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines) + ">"
            }
            if s.hasPrefix("[") && s.hasSuffix("]") {
                let inner = String(s.dropFirst().dropLast())
                var depth = 0
                var colonIndex: String.Index? = nil
                for idx in inner.indices {
                    let c = inner[idx]
                    if c == "<" || c == "[" || c == "(" { depth += 1 }
                    else if c == ">" || c == "]" || c == ")" { depth -= 1 }
                    else if c == ":" && depth == 0 {
                        colonIndex = idx
                        break
                    }
                }
                if let colonIndex {
                    let key = inner[..<colonIndex].trimmingCharacters(in: .whitespacesAndNewlines)
                    let value = inner[inner.index(after: colonIndex)...].trimmingCharacters(in: .whitespacesAndNewlines)
                    s = "Dictionary<\(key), \(value)>"
                } else {
                    s = "Array<\(inner.trimmingCharacters(in: .whitespacesAndNewlines))>"
                }
            }
            return s
        }

        var canonicalTypeCounts: [String: Int] = [:]
        for fieldInfo in fieldInfos where !fieldInfo.isTransient {
            canonicalTypeCounts[canonicalTypeString(fieldInfo.type), default: 0] += 1
        }
        var valueTypeDispatchCases: [String] = []
        var partialKeyPathTypeDispatchCases: [String] = []
        for fieldInfo in fieldInfos where !fieldInfo.isTransient {
            let canonical = canonicalTypeString(fieldInfo.type)
            guard canonicalTypeCounts[canonical] == 1 else { continue }
            let fieldType = fieldInfo.type.trimmingCharacters(in: .whitespacesAndNewlines)
            valueTypeDispatchCases.append("if Value.self == (\(fieldType)).self { return \"\(fieldInfo.name)\" }")
            partialKeyPathTypeDispatchCases.append("if keyPath as? KeyPath<\(structName), \(fieldType)> != nil { return \"\(fieldInfo.name)\" }")
        }
        let valueTypeDispatchBody = valueTypeDispatchCases.joined(separator: "\n        ")
        let partialKeyPathTypeDispatchBody = partialKeyPathTypeDispatchCases.joined(separator: "\n        ")

        let fieldNameDecl: DeclSyntax = """
            public static func fieldName<Value>(for keyPath: KeyPath<\(raw: structName), Value>) -> String {
                \(raw: fieldNameBody)
                \(raw: valueTypeDispatchBody)
                let description = "\\(keyPath)"
                return _fieldName(fromKeyPathDescription: description) ?? description
            }
            """
        decls.append(fieldNameDecl)

        // Generate PartialKeyPath version
        let partialFieldNameDecl: DeclSyntax = """
            public static func fieldName(for keyPath: PartialKeyPath<\(raw: structName)>) -> String {
                \(raw: fieldNameBody)
                \(raw: partialKeyPathTypeDispatchBody)
                let description = "\\(keyPath)"
                return _fieldName(fromKeyPathDescription: description) ?? description
            }
            """
        decls.append(partialFieldNameDecl)

        // Generate AnyKeyPath version (for type-erased usage)
        let anyFieldNameDecl: DeclSyntax = """
            public static func fieldName(for keyPath: AnyKeyPath) -> String {
                if let partialKeyPath = keyPath as? PartialKeyPath<\(raw: structName)> {
                    return fieldName(for: partialKeyPath)
                }
                let description = "\\(keyPath)"
                return _fieldName(fromKeyPathDescription: description) ?? description
            }
            """
        decls.append(anyFieldNameDecl)

        let fieldNameFallbackDecl: DeclSyntax = """
            private static func _fieldName(fromKeyPathDescription description: String) -> String? {
                let parts = description.split(separator: ".").map(String.init)
                for index in parts.indices {
                    let component = parts[index].hasPrefix("\\\\")
                        ? String(parts[index].dropFirst())
                        : parts[index]
                    guard allFields.contains(component) else {
                        continue
                    }
                    var fieldPathParts = Array(parts[index...])
                    fieldPathParts[0] = component
                    return fieldPathParts.joined(separator: ".")
                }
                return nil
            }
            """
        decls.append(fieldNameFallbackDecl)

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
        let conformanceExt: DeclSyntax = """
            extension \(type.trimmed): Persistable, Sendable {}
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
        if fieldNames.isEmpty {
            return "\(typeName)_count"
        }
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
        schemaType = "int64"
    case "Int8":
        schemaType = "int8"
    case "Int16":
        schemaType = "int16"
    case "Int32":
        schemaType = "int32"
    case "Int64":
        schemaType = "int64"
    case "UInt":
        schemaType = "uint64"
    case "UInt8":
        schemaType = "uint8"
    case "UInt16":
        schemaType = "uint16"
    case "UInt32":
        schemaType = "uint32"
    case "UInt64":
        schemaType = "uint64"
    case "Double":
        schemaType = "float64"
    case "Float":
        schemaType = "float32"
    case "Bool":
        schemaType = "bool"
    case "ExactDecimal", "DatabaseTypes.ExactDecimal":
        schemaType = "decimal"
    case "CivilDate", "DatabaseTypes.CivilDate":
        schemaType = "date"
    case "CivilTime", "DatabaseTypes.CivilTime":
        schemaType = "time"
    case "CivilDateTime", "DatabaseTypes.CivilDateTime":
        schemaType = "dateTime"
    case "Timestamp", "DatabaseTypes.Timestamp":
        schemaType = "timestamp"
    case "TimeSpan", "DatabaseTypes.TimeSpan":
        schemaType = "timeSpan"
    case "CalendarPeriod", "DatabaseTypes.CalendarPeriod":
        schemaType = "calendarPeriod"
    case "GeographicPoint", "DatabaseTypes.GeographicPoint":
        schemaType = "geographicPoint"
    case "GeographicPosition", "DatabaseTypes.GeographicPosition":
        schemaType = "geographicPosition"
    case "Vector", "DatabaseTypes.Vector":
        schemaType = "vector"
    case "UUID", "DatabaseTypes.UUID":
        schemaType = "uuid"
    case "ByteString", "DatabaseTypes.ByteString":
        schemaType = "bytes"
    case "FieldObject", "DatabaseTypes.FieldObject":
        schemaType = "object"
    case "EntityReference", "DatabaseTypes.EntityReference":
        schemaType = "reference"
    case "RDFTerm", "DatabaseTypes.RDFTerm":
        schemaType = "rdfTerm"
    default:
        // Non-primitive type: resolve at runtime via RawRepresentable check.
        // FieldSchemaType.resolve(TypeName.self) returns .enum if RawRepresentable, .nested otherwise.
        schemaType = "resolve(\(type).self)"
    }

    return (schemaType, isOptional, isArray)
}

/// Compiler plugin entry point
@main
struct DatabaseDeclarationPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        PersistableMacro.self,
        PolymorphableMacro.self,
        IndexMacro.self,
        DirectoryMacro.self,
        TransientMacro.self,
        ReferenceMacro.self,
        RelationshipMacro.self,
        OWLDataPropertyMacro.self,
        OWLClassMacro.self,
        OWLObjectPropertyMacro.self,
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
