import DatabaseTypes
public struct SHACLRDFDecoder: Sendable {
    public init() {}

    public func decode(
        from dataset: RDFDataset,
        graphIRI: String
    ) throws -> SHACLShapesGraph {
        try dataset.validate()
        let index = Index(dataset.quads)
        let shapeNodes = index.subjects(
            predicate: Vocabulary.rdfType,
            objects: [Vocabulary.nodeShape, Vocabulary.propertyShape]
        ).sorted(by: Self.termOrder)
        var shapes: [SHACLShape] = []
        shapes.reserveCapacity(shapeNodes.count)
        for node in shapeNodes {
            shapes.append(
                try decodeShape(node, index: index, shapeStack: [])
            )
        }
        return SHACLShapesGraph(
            iri: graphIRI,
            shapes: shapes,
            prefixes: .standard,
            entailment: .none
        )
    }

    private func decodeShape(
        _ node: RDFTerm,
        index: Index,
        shapeStack: Set<RDFTerm>
    ) throws -> SHACLShape {
        guard !shapeStack.contains(node) else {
            throw SHACLRDFDecodingError.recursiveShape(node.description)
        }
        let nextStack = shapeStack.union([node])
        let types = Set(index.objects(node, Vocabulary.rdfType))
        if types.contains(where: {
            Self.hasIRI($0, Vocabulary.propertyShape)
        }) ||
            !index.objects(node, Vocabulary.path).isEmpty {
            return .property(
                try decodePropertyShape(
                    node,
                    index: index,
                    shapeStack: shapeStack
                )
            )
        }
        return .node(
            try decodeNodeShape(
                node,
                index: index,
                shapeStack: nextStack
            )
        )
    }

    private func decodeNodeShape(
        _ node: RDFTerm,
        index: Index,
        shapeStack: Set<RDFTerm>
    ) throws -> NodeShape {
        NodeShape(
            identifier: try shapeIdentifier(node),
            targets: try decodeTargets(node, index: index),
            constraints: try decodeConstraints(
                node,
                index: index,
                shapeStack: shapeStack
            ),
            propertyShapes: try index.objects(node, Vocabulary.property).map {
                try decodePropertyShape(
                    $0,
                    index: index,
                    shapeStack: shapeStack
                )
            },
            severity: try decodeSeverity(node, index: index),
            messages: try literalStrings(
                index.objects(node, Vocabulary.message)
            ),
            deactivated: try boolean(
                index.firstObject(node, Vocabulary.deactivated),
                default: false
            )
        )
    }

    private func decodePropertyShape(
        _ node: RDFTerm,
        index: Index,
        shapeStack: Set<RDFTerm>
    ) throws -> PropertyShape {
        guard !shapeStack.contains(node) else {
            throw SHACLRDFDecodingError.recursiveShape(node.description)
        }
        let nextStack = shapeStack.union([node])
        guard let pathNode = index.firstObject(node, Vocabulary.path) else {
            throw SHACLRDFDecodingError.missingProperty(
                subject: node.description,
                predicate: Vocabulary.path
            )
        }
        return PropertyShape(
            identifier: try shapeIdentifier(node),
            path: try decodePath(pathNode, index: index, pathStack: []),
            targets: try decodeTargets(node, index: index),
            constraints: try decodeConstraints(
                node,
                index: index,
                shapeStack: nextStack
            ),
            propertyShapes: try index.objects(node, Vocabulary.property).map {
                try decodePropertyShape(
                    $0,
                    index: index,
                    shapeStack: nextStack
                )
            },
            severity: try decodeSeverity(node, index: index),
            messages: try literalStrings(
                index.objects(node, Vocabulary.message)
            ),
            deactivated: try boolean(
                index.firstObject(node, Vocabulary.deactivated),
                default: false
            ),
            name: try optionalLiteralString(
                index.firstObject(node, Vocabulary.name)
            ),
            shapeDescription: try optionalLiteralString(
                index.firstObject(node, Vocabulary.description)
            ),
            order: try optionalDouble(index.firstObject(node, Vocabulary.order)),
            group: try optionalIRI(index.firstObject(node, Vocabulary.group)),
            defaultValue: index.firstObject(node, Vocabulary.defaultValue)
        )
    }

    private func decodeTargets(
        _ node: RDFTerm,
        index: Index
    ) throws -> [SHACLTarget] {
        var targets: [SHACLTarget] = []
        for value in index.objects(node, Vocabulary.targetNode) {
            switch value {
            case .iri(let iri):
                targets.append(.node(.iri(iri)))
            case .blankNode(let identifier):
                targets.append(.node(.blankNode(identifier)))
            case .literal, .tripleTerm:
                throw SHACLRDFDecodingError.unsupportedFocusNode(value.description)
            }
        }
        targets.append(contentsOf: try index.objects(
            node,
            Vocabulary.targetClass
        ).map { .class_(try iri($0)) })
        targets.append(contentsOf: try index.objects(
            node,
            Vocabulary.targetSubjectsOf
        ).map { .subjectsOf(try iri($0)) })
        targets.append(contentsOf: try index.objects(
            node,
            Vocabulary.targetObjectsOf
        ).map { .objectsOf(try iri($0)) })
        if index.objects(node, Vocabulary.target).isEmpty == false {
            throw SHACLRDFDecodingError.unsupportedPredicate(Vocabulary.target)
        }
        return targets
    }

    private func decodeConstraints(
        _ node: RDFTerm,
        index: Index,
        shapeStack: Set<RDFTerm>
    ) throws -> [SHACLConstraint] {
        var constraints: [SHACLConstraint] = []
        for value in index.objects(node, Vocabulary.class_) {
            constraints.append(.class_(try iri(value)))
        }
        for value in index.objects(node, Vocabulary.datatype) {
            constraints.append(.datatype(try iri(value)))
        }
        for value in index.objects(node, Vocabulary.nodeKind) {
            constraints.append(.nodeKind(try nodeKind(value)))
        }
        for value in index.objects(node, Vocabulary.minCount) {
            constraints.append(.minCount(try integer(value)))
        }
        for value in index.objects(node, Vocabulary.maxCount) {
            constraints.append(.maxCount(try integer(value)))
        }
        for value in index.objects(node, Vocabulary.minExclusive) {
            constraints.append(.minExclusive(value))
        }
        for value in index.objects(node, Vocabulary.maxExclusive) {
            constraints.append(.maxExclusive(value))
        }
        for value in index.objects(node, Vocabulary.minInclusive) {
            constraints.append(.minInclusive(value))
        }
        for value in index.objects(node, Vocabulary.maxInclusive) {
            constraints.append(.maxInclusive(value))
        }
        for value in index.objects(node, Vocabulary.minLength) {
            constraints.append(.minLength(try integer(value)))
        }
        for value in index.objects(node, Vocabulary.maxLength) {
            constraints.append(.maxLength(try integer(value)))
        }
        let flags = try optionalLiteralString(
            index.firstObject(node, Vocabulary.flags)
        )
        for value in index.objects(node, Vocabulary.pattern) {
            constraints.append(
                .pattern(try literalString(value), flags: flags)
            )
        }
        for value in index.objects(node, Vocabulary.languageIn) {
            constraints.append(
                .languageIn(
                    try decodeList(value, index: index).map(literalString)
                )
            )
        }
        if try boolean(
            index.firstObject(node, Vocabulary.uniqueLang),
            default: false
        ) {
            constraints.append(.uniqueLang)
        }
        for (predicate, makeConstraint) in pathConstraintFactories {
            for value in index.objects(node, predicate) {
                constraints.append(
                    makeConstraint(
                        try decodePath(value, index: index, pathStack: [])
                    )
                )
            }
        }
        for value in index.objects(node, Vocabulary.not) {
            constraints.append(
                .not(
                    try decodeShape(
                        value,
                        index: index,
                        shapeStack: shapeStack
                    )
                )
            )
        }
        for (predicate, makeConstraint) in shapeListConstraintFactories {
            for value in index.objects(node, predicate) {
                constraints.append(
                    makeConstraint(
                        try decodeList(value, index: index).map {
                            try decodeShape(
                                $0,
                                index: index,
                                shapeStack: shapeStack
                            )
                        }
                    )
                )
            }
        }
        for value in index.objects(node, Vocabulary.node) {
            let shape = try decodeShape(
                value,
                index: index,
                shapeStack: shapeStack
            )
            guard case .node(let nodeShape) = shape else {
                throw SHACLRDFDecodingError.invalidIRI(value.description)
            }
            constraints.append(.node(nodeShape))
        }
        for value in index.objects(node, Vocabulary.qualifiedValueShape) {
            constraints.append(
                .qualifiedValueShape(
                    shape: try decodeShape(
                        value,
                        index: index,
                        shapeStack: shapeStack
                    ),
                    min: try optionalInteger(
                        index.firstObject(node, Vocabulary.qualifiedMinCount)
                    ),
                    max: try optionalInteger(
                        index.firstObject(node, Vocabulary.qualifiedMaxCount)
                    )
                )
            )
        }
        if try boolean(
            index.firstObject(node, Vocabulary.qualifiedValueShapesDisjoint),
            default: false
        ) {
            throw SHACLRDFDecodingError.unsupportedPredicate(
                Vocabulary.qualifiedValueShapesDisjoint
            )
        }
        if try boolean(
            index.firstObject(node, Vocabulary.closed),
            default: false
        ) {
            let ignored = try index.firstObject(
                node,
                Vocabulary.ignoredProperties
            ).map { value in
                try decodeList(value, index: index).map(iri)
            } ?? []
            constraints.append(.closed(ignoredProperties: ignored))
        }
        for value in index.objects(node, Vocabulary.hasValue) {
            constraints.append(.hasValue(value))
        }
        for value in index.objects(node, Vocabulary.in_) {
            constraints.append(
                .in_(try decodeList(value, index: index))
            )
        }
        try rejectUnknownSHACLPredicates(node, index: index)
        return constraints
    }

    private func decodePath(
        _ node: RDFTerm,
        index: Index,
        pathStack: Set<RDFTerm>
    ) throws -> SHACLPath {
        if case .iri(let value) = node {
            return .predicate(value.rawValue)
        }
        guard !pathStack.contains(node) else {
            throw SHACLRDFDecodingError.recursivePath(node.description)
        }
        let nextStack = pathStack.union([node])
        if let value = index.firstObject(node, Vocabulary.inversePath) {
            return .inverse(
                try decodePath(value, index: index, pathStack: nextStack)
            )
        }
        if let value = index.firstObject(node, Vocabulary.alternativePath) {
            return .alternative(
                try decodeList(value, index: index).map {
                    try decodePath($0, index: index, pathStack: nextStack)
                }
            )
        }
        if let value = index.firstObject(node, Vocabulary.zeroOrMorePath) {
            return .zeroOrMore(
                try decodePath(value, index: index, pathStack: nextStack)
            )
        }
        if let value = index.firstObject(node, Vocabulary.oneOrMorePath) {
            return .oneOrMore(
                try decodePath(value, index: index, pathStack: nextStack)
            )
        }
        if let value = index.firstObject(node, Vocabulary.zeroOrOnePath) {
            return .zeroOrOne(
                try decodePath(value, index: index, pathStack: nextStack)
            )
        }
        let sequence = try decodeList(node, index: index)
        return .sequence(
            try sequence.map {
                try decodePath($0, index: index, pathStack: nextStack)
            }
        )
    }

    private func decodeList(
        _ head: RDFTerm,
        index: Index
    ) throws -> [RDFTerm] {
        if Self.hasIRI(head, Vocabulary.rdfNil) { return [] }
        var values: [RDFTerm] = []
        var visited = Set<RDFTerm>()
        var current = head
        while !Self.hasIRI(current, Vocabulary.rdfNil) {
            guard visited.insert(current).inserted,
                  let first = index.onlyObject(current, Vocabulary.rdfFirst),
                  let rest = index.onlyObject(current, Vocabulary.rdfRest) else {
                throw SHACLRDFDecodingError.malformedList(current.description)
            }
            values.append(first)
            current = rest
        }
        return values
    }

    private func decodeSeverity(
        _ node: RDFTerm,
        index: Index
    ) throws -> SHACLSeverity {
        guard let value = index.firstObject(node, Vocabulary.severity) else {
            return .violation
        }
        switch try iri(value) {
        case Vocabulary.violation: return .violation
        case Vocabulary.warning: return .warning
        case Vocabulary.info: return .info
        default: throw SHACLRDFDecodingError.invalidIRI(value.description)
        }
    }

    private func rejectUnknownSHACLPredicates(
        _ node: RDFTerm,
        index: Index
    ) throws {
        for predicate in index.predicates(node) where
            predicate.rawValue.hasPrefix(Vocabulary.namespace) &&
            !Vocabulary.supportedPredicates.contains(predicate.rawValue) {
            throw SHACLRDFDecodingError.unsupportedPredicate(
                predicate.rawValue
            )
        }
    }

    private func shapeIdentifier(_ term: RDFTerm) throws -> RDFTerm {
        switch term {
        case .iri, .blankNode:
            return term
        case .literal, .tripleTerm:
            throw SHACLRDFDecodingError.invalidShapeIdentifier(
                term.description
            )
        }
    }

    private func iri(_ term: RDFTerm) throws -> String {
        guard case .iri(let value) = term else {
            throw SHACLRDFDecodingError.invalidIRI(term.description)
        }
        return value.rawValue
    }

    private func optionalIRI(_ term: RDFTerm?) throws -> String? {
        guard let term else { return nil }
        return try iri(term)
    }

    private func literalString(_ term: RDFTerm) throws -> String {
        guard case .literal(let value) = term else {
            throw SHACLRDFDecodingError.invalidLiteral(term.description)
        }
        return value.lexicalForm
    }

    private func literalStrings(_ terms: [RDFTerm]) throws -> [String] {
        try terms.map(literalString)
    }

    private func optionalLiteralString(_ term: RDFTerm?) throws -> String? {
        guard let term else { return nil }
        return try literalString(term)
    }

    private func integer(_ term: RDFTerm) throws -> Int {
        let value = try literalString(term)
        guard let integer = Int(value), integer >= 0 else {
            throw SHACLRDFDecodingError.invalidInteger(value)
        }
        return integer
    }

    private func optionalInteger(_ term: RDFTerm?) throws -> Int? {
        guard let term else { return nil }
        return try integer(term)
    }

    private func optionalDouble(_ term: RDFTerm?) throws -> Double? {
        guard let term else { return nil }
        let value = try literalString(term)
        guard let number = Double(value), number.isFinite else {
            throw SHACLRDFDecodingError.invalidNumber(value)
        }
        return number
    }

    private func boolean(
        _ term: RDFTerm?,
        default defaultValue: Bool
    ) throws -> Bool {
        guard let term else { return defaultValue }
        let value = try literalString(term)
        switch value {
        case "true", "1": return true
        case "false", "0": return false
        default: throw SHACLRDFDecodingError.invalidBoolean(value)
        }
    }

    private func nodeKind(_ term: RDFTerm) throws -> SHACLNodeKind {
        switch try iri(term) {
        case Vocabulary.blankNode: return .blankNode
        case Vocabulary.iri: return .iri
        case Vocabulary.literal: return .literal
        case Vocabulary.blankNodeOrIRI: return .blankNodeOrIRI
        case Vocabulary.blankNodeOrLiteral: return .blankNodeOrLiteral
        case Vocabulary.iriOrLiteral: return .iriOrLiteral
        default: throw SHACLRDFDecodingError.invalidIRI(term.description)
        }
    }

    private static func termOrder(_ left: RDFTerm, _ right: RDFTerm) -> Bool {
        left < right
    }

    private var pathConstraintFactories: [
        (String, (SHACLPath) -> SHACLConstraint)
    ] {
        [
            (Vocabulary.equals, SHACLConstraint.equals),
            (Vocabulary.disjoint, SHACLConstraint.disjoint),
            (Vocabulary.lessThan, SHACLConstraint.lessThan),
            (Vocabulary.lessThanOrEquals, SHACLConstraint.lessThanOrEquals)
        ]
    }

    private var shapeListConstraintFactories: [
        (String, ([SHACLShape]) -> SHACLConstraint)
    ] {
        [
            (Vocabulary.and, SHACLConstraint.and),
            (Vocabulary.or, SHACLConstraint.or),
            (Vocabulary.xone, SHACLConstraint.xone)
        ]
    }

    private struct Index {
        private var values: [RDFTerm: [RDFIRI: [RDFTerm]]] = [:]

        init(_ quads: [RDFQuad]) {
            for quad in quads {
                values[quad.subject.term, default: [:]][
                    quad.predicate.iri,
                    default: []
                ]
                    .append(quad.object)
            }
        }

        func objects(_ subject: RDFTerm, _ predicate: String) -> [RDFTerm] {
            values[subject]?[Vocabulary.requiredIRI(predicate)] ?? []
        }

        func firstObject(
            _ subject: RDFTerm,
            _ predicate: String
        ) -> RDFTerm? {
            objects(subject, predicate).first
        }

        func onlyObject(
            _ subject: RDFTerm,
            _ predicate: String
        ) -> RDFTerm? {
            let matches = objects(subject, predicate)
            return matches.count == 1 ? matches[0] : nil
        }

        func predicates(_ subject: RDFTerm) -> [RDFIRI] {
            Array(
                values[subject]?.keys
                    ?? Dictionary<RDFIRI, [RDFTerm]>().keys
            )
        }

        func subjects(
            predicate: String,
            objects: Set<String>
        ) -> Set<RDFTerm> {
            Set(values.compactMap { subject, predicates in
                let matches =
                    predicates[Vocabulary.requiredIRI(predicate)] ?? []
                return matches.contains { term in
                    if case .iri(let value) = term {
                        return objects.contains(value.rawValue)
                    }
                    return false
                } ? subject : nil
            })
        }
    }

    private enum Vocabulary {
        static let namespace = "http://www.w3.org/ns/shacl#"
        static let rdfNamespace =
            "http://www.w3.org/1999/02/22-rdf-syntax-ns#"
        static let rdfType = rdfNamespace + "type"
        static let rdfFirst = rdfNamespace + "first"
        static let rdfRest = rdfNamespace + "rest"
        static let rdfNil = rdfNamespace + "nil"
        static let nodeShape = namespace + "NodeShape"
        static let propertyShape = namespace + "PropertyShape"
        static let path = namespace + "path"
        static let property = namespace + "property"
        static let target = namespace + "target"
        static let targetNode = namespace + "targetNode"
        static let targetClass = namespace + "targetClass"
        static let targetSubjectsOf = namespace + "targetSubjectsOf"
        static let targetObjectsOf = namespace + "targetObjectsOf"
        static let severity = namespace + "severity"
        static let message = namespace + "message"
        static let deactivated = namespace + "deactivated"
        static let name = namespace + "name"
        static let description = namespace + "description"
        static let order = namespace + "order"
        static let group = namespace + "group"
        static let defaultValue = namespace + "defaultValue"
        static let class_ = namespace + "class"
        static let datatype = namespace + "datatype"
        static let nodeKind = namespace + "nodeKind"
        static let minCount = namespace + "minCount"
        static let maxCount = namespace + "maxCount"
        static let minExclusive = namespace + "minExclusive"
        static let maxExclusive = namespace + "maxExclusive"
        static let minInclusive = namespace + "minInclusive"
        static let maxInclusive = namespace + "maxInclusive"
        static let minLength = namespace + "minLength"
        static let maxLength = namespace + "maxLength"
        static let pattern = namespace + "pattern"
        static let flags = namespace + "flags"
        static let languageIn = namespace + "languageIn"
        static let uniqueLang = namespace + "uniqueLang"
        static let equals = namespace + "equals"
        static let disjoint = namespace + "disjoint"
        static let lessThan = namespace + "lessThan"
        static let lessThanOrEquals = namespace + "lessThanOrEquals"
        static let not = namespace + "not"
        static let and = namespace + "and"
        static let or = namespace + "or"
        static let xone = namespace + "xone"
        static let node = namespace + "node"
        static let qualifiedValueShape = namespace + "qualifiedValueShape"
        static let qualifiedMinCount = namespace + "qualifiedMinCount"
        static let qualifiedMaxCount = namespace + "qualifiedMaxCount"
        static let qualifiedValueShapesDisjoint =
            namespace + "qualifiedValueShapesDisjoint"
        static let closed = namespace + "closed"
        static let ignoredProperties = namespace + "ignoredProperties"
        static let hasValue = namespace + "hasValue"
        static let in_ = namespace + "in"
        static let inversePath = namespace + "inversePath"
        static let alternativePath = namespace + "alternativePath"
        static let zeroOrMorePath = namespace + "zeroOrMorePath"
        static let oneOrMorePath = namespace + "oneOrMorePath"
        static let zeroOrOnePath = namespace + "zeroOrOnePath"
        static let violation = namespace + "Violation"
        static let warning = namespace + "Warning"
        static let info = namespace + "Info"
        static let blankNode = namespace + "BlankNode"
        static let iri = namespace + "IRI"
        static let literal = namespace + "Literal"
        static let blankNodeOrIRI = namespace + "BlankNodeOrIRI"
        static let blankNodeOrLiteral = namespace + "BlankNodeOrLiteral"
        static let iriOrLiteral = namespace + "IRIOrLiteral"

        static let supportedPredicates: Set<String> = [
            path, property, targetNode, targetClass, targetSubjectsOf,
            targetObjectsOf, severity, message, deactivated, name, description,
            order, group, defaultValue, class_, datatype, nodeKind, minCount,
            maxCount, minExclusive, maxExclusive, minInclusive, maxInclusive,
            minLength, maxLength, pattern, flags, languageIn, uniqueLang,
            equals, disjoint, lessThan, lessThanOrEquals, not, and, or, xone,
            node, qualifiedValueShape, qualifiedMinCount, qualifiedMaxCount,
            qualifiedValueShapesDisjoint, closed, ignoredProperties, hasValue,
            in_, inversePath, alternativePath, zeroOrMorePath, oneOrMorePath,
            zeroOrOnePath
        ]

        static func requiredIRI(_ value: String) -> RDFIRI {
            do {
                return try RDFIRI(value)
            } catch {
                preconditionFailure(
                    "Invalid built-in SHACL vocabulary IRI: \(value)"
                )
            }
        }
    }

    private static func hasIRI(
        _ term: RDFTerm,
        _ rawValue: String
    ) -> Bool {
        guard case .iri(let iri) = term else {
            return false
        }
        return iri == Vocabulary.requiredIRI(rawValue)
    }
}
