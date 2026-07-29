import DatabaseTypes
public struct SHACLRDFDecoder: Sendable {
    public init() {}

    public func decode(
        from dataset: RDFDataset,
        graphIRI: String
    ) throws(SHACLRDFDecodingError) -> SHACLShapesGraph {
        do {
            try dataset.validate()
        } catch let error {
            throw .invalidDataset(error)
        }
        let index = try Index(dataset.quads)
        let shapeNodes = try index.subjects(
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
    ) throws(SHACLRDFDecodingError) -> SHACLShape {
        guard !shapeStack.contains(node) else {
            throw SHACLRDFDecodingError.recursiveShape(node.description)
        }
        let nextStack = shapeStack.union([node])
        let types = Set(try index.objects(node, Vocabulary.rdfType))
        var isPropertyShape = false
        for type in types where
            try index.hasIRI(type, Vocabulary.propertyShape) {
            isPropertyShape = true
            break
        }
        let hasPath = !(try index.objects(
            node,
            Vocabulary.path
        )).isEmpty
        if isPropertyShape || hasPath {
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
    ) throws(SHACLRDFDecodingError) -> NodeShape {
        var propertyShapes: [PropertyShape] = []
        for value in try index.objects(node, Vocabulary.property) {
            propertyShapes.append(
                try decodePropertyShape(
                    value,
                    index: index,
                    shapeStack: shapeStack
                )
            )
        }
        return NodeShape(
            identifier: try shapeIdentifier(node),
            targets: try decodeTargets(node, index: index),
            constraints: try decodeConstraints(
                node,
                index: index,
                shapeStack: shapeStack
            ),
            propertyShapes: propertyShapes,
            severity: try decodeSeverity(node, index: index),
            messages: try literalStrings(
                try index.objects(node, Vocabulary.message)
            ),
            deactivated: try boolean(
                try index.firstObject(node, Vocabulary.deactivated),
                default: false
            )
        )
    }

    private func decodePropertyShape(
        _ node: RDFTerm,
        index: Index,
        shapeStack: Set<RDFTerm>
    ) throws(SHACLRDFDecodingError) -> PropertyShape {
        guard !shapeStack.contains(node) else {
            throw SHACLRDFDecodingError.recursiveShape(node.description)
        }
        let nextStack = shapeStack.union([node])
        guard let pathNode = try index.firstObject(node, Vocabulary.path) else {
            throw SHACLRDFDecodingError.missingProperty(
                subject: node.description,
                predicate: Vocabulary.path
            )
        }
        var propertyShapes: [PropertyShape] = []
        for value in try index.objects(node, Vocabulary.property) {
            propertyShapes.append(
                try decodePropertyShape(
                    value,
                    index: index,
                    shapeStack: nextStack
                )
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
            propertyShapes: propertyShapes,
            severity: try decodeSeverity(node, index: index),
            messages: try literalStrings(
                try index.objects(node, Vocabulary.message)
            ),
            deactivated: try boolean(
                try index.firstObject(node, Vocabulary.deactivated),
                default: false
            ),
            name: try optionalLiteralString(
                try index.firstObject(node, Vocabulary.name)
            ),
            shapeDescription: try optionalLiteralString(
                try index.firstObject(node, Vocabulary.description)
            ),
            order: try optionalDouble(
                try index.firstObject(node, Vocabulary.order)
            ),
            group: try optionalIRI(
                try index.firstObject(node, Vocabulary.group)
            ),
            defaultValue: try index.firstObject(node, Vocabulary.defaultValue)
        )
    }

    private func decodeTargets(
        _ node: RDFTerm,
        index: Index
    ) throws(SHACLRDFDecodingError) -> [SHACLTarget] {
        var targets: [SHACLTarget] = []
        for value in try index.objects(node, Vocabulary.targetNode) {
            switch value {
            case .iri(let iri):
                targets.append(.node(.iri(iri)))
            case .blankNode(let identifier):
                targets.append(.node(.blankNode(identifier)))
            case .literal, .tripleTerm:
                throw SHACLRDFDecodingError.unsupportedFocusNode(value.description)
            }
        }
        for value in try index.objects(node, Vocabulary.targetClass) {
            targets.append(.class_(try iri(value)))
        }
        for value in try index.objects(node, Vocabulary.targetSubjectsOf) {
            targets.append(.subjectsOf(try iri(value)))
        }
        for value in try index.objects(node, Vocabulary.targetObjectsOf) {
            targets.append(.objectsOf(try iri(value)))
        }
        if try index.objects(node, Vocabulary.target).isEmpty == false {
            throw SHACLRDFDecodingError.unsupportedPredicate(Vocabulary.target)
        }
        return targets
    }

    private func decodeConstraints(
        _ node: RDFTerm,
        index: Index,
        shapeStack: Set<RDFTerm>
    ) throws(SHACLRDFDecodingError) -> [SHACLConstraint] {
        var constraints: [SHACLConstraint] = []
        for value in try index.objects(node, Vocabulary.class_) {
            constraints.append(.class_(try iri(value)))
        }
        for value in try index.objects(node, Vocabulary.datatype) {
            constraints.append(.datatype(try iri(value)))
        }
        for value in try index.objects(node, Vocabulary.nodeKind) {
            constraints.append(.nodeKind(try nodeKind(value)))
        }
        for value in try index.objects(node, Vocabulary.minCount) {
            constraints.append(.minCount(try integer(value)))
        }
        for value in try index.objects(node, Vocabulary.maxCount) {
            constraints.append(.maxCount(try integer(value)))
        }
        for value in try index.objects(node, Vocabulary.minExclusive) {
            constraints.append(.minExclusive(value))
        }
        for value in try index.objects(node, Vocabulary.maxExclusive) {
            constraints.append(.maxExclusive(value))
        }
        for value in try index.objects(node, Vocabulary.minInclusive) {
            constraints.append(.minInclusive(value))
        }
        for value in try index.objects(node, Vocabulary.maxInclusive) {
            constraints.append(.maxInclusive(value))
        }
        for value in try index.objects(node, Vocabulary.minLength) {
            constraints.append(.minLength(try integer(value)))
        }
        for value in try index.objects(node, Vocabulary.maxLength) {
            constraints.append(.maxLength(try integer(value)))
        }
        let flags = try optionalLiteralString(
            try index.firstObject(node, Vocabulary.flags)
        )
        for value in try index.objects(node, Vocabulary.pattern) {
            constraints.append(
                .pattern(try literalString(value), flags: flags)
            )
        }
        for value in try index.objects(node, Vocabulary.languageIn) {
            var languages: [String] = []
            for term in try decodeList(value, index: index) {
                languages.append(try literalString(term))
            }
            constraints.append(
                .languageIn(languages)
            )
        }
        if try boolean(
            try index.firstObject(node, Vocabulary.uniqueLang),
            default: false
        ) {
            constraints.append(.uniqueLang)
        }
        for (predicate, makeConstraint) in pathConstraintFactories {
            for value in try index.objects(node, predicate) {
                constraints.append(
                    makeConstraint(
                        try decodePath(value, index: index, pathStack: [])
                    )
                )
            }
        }
        for value in try index.objects(node, Vocabulary.not) {
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
            for value in try index.objects(node, predicate) {
                var shapes: [SHACLShape] = []
                for term in try decodeList(value, index: index) {
                    shapes.append(
                        try decodeShape(
                            term,
                            index: index,
                            shapeStack: shapeStack
                        )
                    )
                }
                constraints.append(
                    makeConstraint(shapes)
                )
            }
        }
        for value in try index.objects(node, Vocabulary.node) {
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
        for value in try index.objects(node, Vocabulary.qualifiedValueShape) {
            constraints.append(
                .qualifiedValueShape(
                    shape: try decodeShape(
                        value,
                        index: index,
                        shapeStack: shapeStack
                    ),
                    min: try optionalInteger(
                        try index.firstObject(
                            node,
                            Vocabulary.qualifiedMinCount
                        )
                    ),
                    max: try optionalInteger(
                        try index.firstObject(
                            node,
                            Vocabulary.qualifiedMaxCount
                        )
                    )
                )
            )
        }
        if try boolean(
            try index.firstObject(
                node,
                Vocabulary.qualifiedValueShapesDisjoint
            ),
            default: false
        ) {
            throw SHACLRDFDecodingError.unsupportedPredicate(
                Vocabulary.qualifiedValueShapesDisjoint
            )
        }
        if try boolean(
            try index.firstObject(node, Vocabulary.closed),
            default: false
        ) {
            var ignored: [String] = []
            if let value = try index.firstObject(
                node,
                Vocabulary.ignoredProperties
            ) {
                for term in try decodeList(value, index: index) {
                    ignored.append(try iri(term))
                }
            }
            constraints.append(.closed(ignoredProperties: ignored))
        }
        for value in try index.objects(node, Vocabulary.hasValue) {
            constraints.append(.hasValue(value))
        }
        for value in try index.objects(node, Vocabulary.in_) {
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
    ) throws(SHACLRDFDecodingError) -> SHACLPath {
        if case .iri(let value) = node {
            return .predicate(RDFPredicateIRI(value))
        }
        guard !pathStack.contains(node) else {
            throw SHACLRDFDecodingError.recursivePath(node.description)
        }
        let nextStack = pathStack.union([node])
        if let value = try index.firstObject(node, Vocabulary.inversePath) {
            return .inverse(
                try decodePath(value, index: index, pathStack: nextStack)
            )
        }
        if let value = try index.firstObject(
            node,
            Vocabulary.alternativePath
        ) {
            var alternatives: [SHACLPath] = []
            for term in try decodeList(value, index: index) {
                alternatives.append(
                    try decodePath(
                        term,
                        index: index,
                        pathStack: nextStack
                    )
                )
            }
            do {
                return .alternative(
                    try SHACLPathList(alternatives)
                )
            } catch let error {
                throw .invalidPath(error)
            }
        }
        if let value = try index.firstObject(
            node,
            Vocabulary.zeroOrMorePath
        ) {
            return .zeroOrMore(
                try decodePath(value, index: index, pathStack: nextStack)
            )
        }
        if let value = try index.firstObject(
            node,
            Vocabulary.oneOrMorePath
        ) {
            return .oneOrMore(
                try decodePath(value, index: index, pathStack: nextStack)
            )
        }
        if let value = try index.firstObject(
            node,
            Vocabulary.zeroOrOnePath
        ) {
            return .zeroOrOne(
                try decodePath(value, index: index, pathStack: nextStack)
            )
        }
        let sequence = try decodeList(node, index: index)
        var sequencePaths: [SHACLPath] = []
        sequencePaths.reserveCapacity(sequence.count)
        for term in sequence {
            sequencePaths.append(
                try decodePath(
                    term,
                    index: index,
                    pathStack: nextStack
                )
            )
        }
        do {
            return .sequence(
                try SHACLPathList(sequencePaths)
            )
        } catch let error {
            throw .invalidPath(error)
        }
    }

    private func decodeList(
        _ head: RDFTerm,
        index: Index
    ) throws(SHACLRDFDecodingError) -> [RDFTerm] {
        if try index.hasIRI(head, Vocabulary.rdfNil) { return [] }
        var values: [RDFTerm] = []
        var visited = Set<RDFTerm>()
        var current = head
        while try !index.hasIRI(current, Vocabulary.rdfNil) {
            guard visited.insert(current).inserted,
                  let first = try index.onlyObject(
                    current,
                    Vocabulary.rdfFirst
                  ),
                  let rest = try index.onlyObject(
                    current,
                    Vocabulary.rdfRest
                  ) else {
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
    ) throws(SHACLRDFDecodingError) -> SHACLSeverity {
        guard let value = try index.firstObject(
            node,
            Vocabulary.severity
        ) else {
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
    ) throws(SHACLRDFDecodingError) {
        for predicate in index.predicates(node) where
            predicate.rawValue.hasPrefix(Vocabulary.namespace) &&
            !Vocabulary.supportedPredicates.contains(predicate.rawValue) {
            throw SHACLRDFDecodingError.unsupportedPredicate(
                predicate.rawValue
            )
        }
    }

    private func shapeIdentifier(_ term: RDFTerm) throws(SHACLRDFDecodingError) -> RDFTerm {
        switch term {
        case .iri, .blankNode:
            return term
        case .literal, .tripleTerm:
            throw SHACLRDFDecodingError.invalidShapeIdentifier(
                term.description
            )
        }
    }

    private func iri(_ term: RDFTerm) throws(SHACLRDFDecodingError) -> String {
        guard case .iri(let value) = term else {
            throw SHACLRDFDecodingError.invalidIRI(term.description)
        }
        return value.rawValue
    }

    private func optionalIRI(_ term: RDFTerm?) throws(SHACLRDFDecodingError) -> String? {
        guard let term else { return nil }
        return try iri(term)
    }

    private func literalString(_ term: RDFTerm) throws(SHACLRDFDecodingError) -> String {
        guard case .literal(let value) = term else {
            throw SHACLRDFDecodingError.invalidLiteral(term.description)
        }
        return value.lexicalForm
    }

    private func literalStrings(_ terms: [RDFTerm]) throws(SHACLRDFDecodingError) -> [String] {
        var values: [String] = []
        values.reserveCapacity(terms.count)
        for term in terms {
            values.append(try literalString(term))
        }
        return values
    }

    private func optionalLiteralString(_ term: RDFTerm?) throws(SHACLRDFDecodingError) -> String? {
        guard let term else { return nil }
        return try literalString(term)
    }

    private func integer(_ term: RDFTerm) throws(SHACLRDFDecodingError) -> Int {
        let value = try literalString(term)
        guard let integer = Int(value), integer >= 0 else {
            throw SHACLRDFDecodingError.invalidInteger(value)
        }
        return integer
    }

    private func optionalInteger(_ term: RDFTerm?) throws(SHACLRDFDecodingError) -> Int? {
        guard let term else { return nil }
        return try integer(term)
    }

    private func optionalDouble(_ term: RDFTerm?) throws(SHACLRDFDecodingError) -> Double? {
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
    ) throws(SHACLRDFDecodingError) -> Bool {
        guard let term else { return defaultValue }
        let value = try literalString(term)
        switch value {
        case "true", "1": return true
        case "false", "0": return false
        default: throw SHACLRDFDecodingError.invalidBoolean(value)
        }
    }

    private func nodeKind(_ term: RDFTerm) throws(SHACLRDFDecodingError) -> SHACLNodeKind {
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
        private struct PredicateEntry {
            let predicate: RDFIRI
            var objects: [RDFTerm]
        }

        private struct SubjectEntry {
            let subject: RDFTerm
            var predicates: [PredicateEntry]
        }

        private struct VocabularyEntry {
            let rawValue: String
            let iri: RDFIRI
        }

        private var values: [SubjectEntry]
        private let vocabularyIRIs: [VocabularyEntry]

        init(_ quads: [RDFQuad]) throws(SHACLRDFDecodingError) {
            var vocabularyIRIs: [VocabularyEntry] = []
            vocabularyIRIs.reserveCapacity(Vocabulary.allIRIs.count)
            for rawValue in Vocabulary.allIRIs {
                do {
                    vocabularyIRIs.append(
                        VocabularyEntry(
                            rawValue: rawValue,
                            iri: try RDFIRI(rawValue)
                        )
                    )
                } catch {
                    throw .invalidVocabularyIRI(rawValue)
                }
            }
            vocabularyIRIs.sort { $0.rawValue < $1.rawValue }
            self.vocabularyIRIs = vocabularyIRIs

            // The index sorts integer positions rather than materializing a
            // second RDF payload. RDF terms retain their existing storage.
            var orderedPositions = Array(quads.indices)
            orderedPositions.sort { left, right in
                let leftQuad = quads[left]
                let rightQuad = quads[right]
                if leftQuad.subject.term != rightQuad.subject.term {
                    return leftQuad.subject.term < rightQuad.subject.term
                }
                if leftQuad.predicate.iri != rightQuad.predicate.iri {
                    return leftQuad.predicate.iri < rightQuad.predicate.iri
                }
                return leftQuad.object < rightQuad.object
            }

            var values: [SubjectEntry] = []
            for position in orderedPositions {
                let quad = quads[position]
                if values.last?.subject != quad.subject.term {
                    values.append(
                        SubjectEntry(subject: quad.subject.term, predicates: [])
                    )
                }
                let subjectIndex = values.index(before: values.endIndex)
                if values[subjectIndex].predicates.last?.predicate
                    != quad.predicate.iri {
                    values[subjectIndex].predicates.append(
                        PredicateEntry(
                            predicate: quad.predicate.iri,
                            objects: []
                        )
                    )
                }
                let predicateIndex = values[subjectIndex].predicates.index(
                    before: values[subjectIndex].predicates.endIndex
                )
                values[subjectIndex].predicates[predicateIndex].objects.append(
                    quad.object
                )
            }
            self.values = values
        }

        func objects(
            _ subject: RDFTerm,
            _ predicate: String
        ) throws(SHACLRDFDecodingError) -> [RDFTerm] {
            guard let predicateIRI = vocabularyIRI(for: predicate) else {
                throw .unregisteredVocabularyIRI(predicate)
            }
            guard let subjectIndex = subjectIndex(for: subject) else {
                return []
            }
            let predicates = values[subjectIndex].predicates
            guard let predicateIndex = predicateIndex(
                for: predicateIRI,
                in: predicates
            ) else {
                return []
            }
            return predicates[predicateIndex].objects
        }

        func firstObject(
            _ subject: RDFTerm,
            _ predicate: String
        ) throws(SHACLRDFDecodingError) -> RDFTerm? {
            try objects(subject, predicate).first
        }

        func onlyObject(
            _ subject: RDFTerm,
            _ predicate: String
        ) throws(SHACLRDFDecodingError) -> RDFTerm? {
            let matches = try objects(subject, predicate)
            return matches.count == 1 ? matches[0] : nil
        }

        func predicates(_ subject: RDFTerm) -> [RDFIRI] {
            guard let index = subjectIndex(for: subject) else { return [] }
            return values[index].predicates.map { $0.predicate }
        }

        func subjects(
            predicate: String,
            objects: [String]
        ) throws(SHACLRDFDecodingError) -> [RDFTerm] {
            guard let predicateIRI = vocabularyIRI(for: predicate) else {
                throw .unregisteredVocabularyIRI(predicate)
            }
            var objectIRIs: [RDFIRI] = []
            objectIRIs.reserveCapacity(objects.count)
            for object in objects {
                guard let objectIRI = vocabularyIRI(for: object) else {
                    throw .invalidVocabularyIRI(object)
                }
                objectIRIs.append(objectIRI)
            }
            objectIRIs.sort()
            return values.compactMap { entry in
                guard let predicateIndex = predicateIndex(
                    for: predicateIRI,
                    in: entry.predicates
                ) else {
                    return nil
                }
                let matches = entry.predicates[predicateIndex].objects
                return matches.contains { term in
                    if case .iri(let value) = term {
                        return contains(value, in: objectIRIs)
                    }
                    return false
                } ? entry.subject : nil
            }
        }

        func hasIRI(
            _ term: RDFTerm,
            _ rawValue: String
        ) throws(SHACLRDFDecodingError) -> Bool {
            guard case .iri(let iri) = term else {
                return false
            }
            guard let expected = vocabularyIRI(for: rawValue) else {
                throw .unregisteredVocabularyIRI(rawValue)
            }
            return iri == expected
        }

        private func vocabularyIRI(for rawValue: String) -> RDFIRI? {
            var lowerBound = 0
            var upperBound = vocabularyIRIs.count
            while lowerBound < upperBound {
                let midpoint = lowerBound + (upperBound - lowerBound) / 2
                if vocabularyIRIs[midpoint].rawValue < rawValue {
                    lowerBound = midpoint + 1
                } else {
                    upperBound = midpoint
                }
            }
            guard lowerBound < vocabularyIRIs.count,
                  vocabularyIRIs[lowerBound].rawValue == rawValue else {
                return nil
            }
            return vocabularyIRIs[lowerBound].iri
        }

        private func subjectIndex(for subject: RDFTerm) -> Int? {
            var lowerBound = 0
            var upperBound = values.count
            while lowerBound < upperBound {
                let midpoint = lowerBound + (upperBound - lowerBound) / 2
                if values[midpoint].subject < subject {
                    lowerBound = midpoint + 1
                } else {
                    upperBound = midpoint
                }
            }
            guard lowerBound < values.count,
                  values[lowerBound].subject == subject else {
                return nil
            }
            return lowerBound
        }

        private func predicateIndex(
            for predicate: RDFIRI,
            in predicates: [PredicateEntry]
        ) -> Int? {
            var lowerBound = 0
            var upperBound = predicates.count
            while lowerBound < upperBound {
                let midpoint = lowerBound + (upperBound - lowerBound) / 2
                if predicates[midpoint].predicate < predicate {
                    lowerBound = midpoint + 1
                } else {
                    upperBound = midpoint
                }
            }
            guard lowerBound < predicates.count,
                  predicates[lowerBound].predicate == predicate else {
                return nil
            }
            return lowerBound
        }

        private func contains(
            _ value: RDFIRI,
            in sortedValues: [RDFIRI]
        ) -> Bool {
            var lowerBound = 0
            var upperBound = sortedValues.count
            while lowerBound < upperBound {
                let midpoint = lowerBound + (upperBound - lowerBound) / 2
                if sortedValues[midpoint] < value {
                    lowerBound = midpoint + 1
                } else {
                    upperBound = midpoint
                }
            }
            return lowerBound < sortedValues.count
                && sortedValues[lowerBound] == value
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

        static var allIRIs: Set<String> {
            supportedPredicates.union([
                rdfType,
                rdfFirst,
                rdfRest,
                rdfNil,
                nodeShape,
                propertyShape,
                target,
            ])
        }
    }
}
