// TurtleEncoder.swift
// Graph - OWLOntology → Turtle (RDF) encoder
//
// Encodes an OWLOntology into W3C Turtle syntax.
//
// Reference: W3C RDF 1.1 Turtle
// https://www.w3.org/TR/turtle/

import Foundation

/// Encodes an OWLOntology into Turtle (RDF) format.
///
/// Follows the `JSONEncoder` naming convention but does NOT conform to
/// `Swift.Encoder` — RDF triple structure is incompatible with key-value encoding.
///
/// ```swift
/// let turtle = TurtleEncoder().encode(ontology)
/// ```
public struct TurtleEncoder: Sendable {

    public init() {}

    /// Encode an OWLOntology into a Turtle string.
    public func encode(_ ontology: OWLOntology) -> String {
        let writer = TurtleWriter(ontology: ontology)
        return writer.write()
    }
}

// MARK: - Convenience

extension OWLOntology {
    /// Encode this ontology to Turtle format.
    public func toTurtle() -> String {
        TurtleEncoder().encode(self)
    }
}

// MARK: - Internal Writer

private struct TurtleWriter {

    let ontology: OWLOntology
    let prefixMap: PrefixMap

    init(ontology: OWLOntology) {
        self.ontology = ontology
        self.prefixMap = PrefixMap(fromOntologyPrefixes: ontology.prefixes)
    }

    func write() -> String {
        var lines: [String] = []

        // 1. @prefix declarations
        writePrefixes(to: &lines)

        // 2. Ontology header
        writeOntologyHeader(to: &lines)

        // 3. Build subject blocks from entities + axioms
        var blocks: [String: SubjectBlock] = [:]
        var standaloneBlocks: [StandaloneBlock] = []

        collectEntityMetadata(into: &blocks)
        distributeAxioms(into: &blocks, standalone: &standaloneBlocks)

        // 4. Render blocks by section order
        let sorted = blocks.values.sorted { a, b in
            if a.section != b.section { return a.section < b.section }
            return a.subject < b.subject
        }

        var currentSection: Section?
        for block in sorted {
            if block.section != currentSection {
                lines.append("")
                currentSection = block.section
            }
            renderBlock(block, to: &lines)
        }

        // 5. Standalone blocks (AllDisjointClasses, AllDifferent, etc.)
        if !standaloneBlocks.isEmpty {
            lines.append("")
            for standalone in standaloneBlocks {
                renderStandalone(standalone, to: &lines)
            }
        }

        lines.append("")
        return lines.joined(separator: "\n")
    }

    // MARK: - Prefixes

    private func writePrefixes(to lines: inout [String]) {
        let sortedPrefixes = ontology.prefixes.sorted { $0.key < $1.key }
        for (prefix, namespace) in sortedPrefixes {
            lines.append("@prefix \(prefix): <\(namespace)> .")
        }
    }

    // MARK: - Ontology Header

    private func writeOntologyHeader(to lines: inout [String]) {
        guard !ontology.iri.isEmpty else { return }
        lines.append("")
        var parts: [String] = []
        parts.append("\(formatIRI(ontology.iri)) a owl:Ontology")
        if let version = ontology.versionIRI {
            parts.append("    owl:versionIRI \(formatIRI(version))")
        }
        for imp in ontology.imports {
            parts.append("    owl:imports \(formatIRI(imp))")
        }
        lines.append(joinStatements(parts) + " .")
    }

    // MARK: - Entity Metadata

    private func collectEntityMetadata(into blocks: inout [String: SubjectBlock]) {
        for cls in ontology.classes {
            var block = getOrCreate(&blocks, subject: cls.iri, section: .owlClass)
            block.types.append("owl:Class")
            if let label = cls.label {
                block.statements.append(("rdfs:label", formatStringLiteral(label)))
            }
            if let comment = cls.comment {
                block.statements.append(("rdfs:comment", formatStringLiteral(comment)))
            }
            blocks[cls.iri] = block
        }

        for prop in ontology.objectProperties {
            var block = getOrCreate(&blocks, subject: prop.iri, section: .objectProperty)
            block.types.append("owl:ObjectProperty")
            appendPropertyCharacteristicTypes(prop.characteristics, to: &block)
            if let label = prop.label {
                block.statements.append(("rdfs:label", formatStringLiteral(label)))
            }
            if let comment = prop.comment {
                block.statements.append(("rdfs:comment", formatStringLiteral(comment)))
            }
            if let inv = prop.inverseOf {
                block.statements.append(("owl:inverseOf", formatIRI(inv)))
            }
            for domain in prop.domains {
                block.statements.append(("rdfs:domain", formatClassExpression(domain)))
            }
            for range in prop.ranges {
                block.statements.append(("rdfs:range", formatClassExpression(range)))
            }
            blocks[prop.iri] = block
        }

        for prop in ontology.dataProperties {
            var block = getOrCreate(&blocks, subject: prop.iri, section: .dataProperty)
            block.types.append("owl:DatatypeProperty")
            if prop.isFunctional {
                block.types.append("owl:FunctionalProperty")
            }
            if let label = prop.label {
                block.statements.append(("rdfs:label", formatStringLiteral(label)))
            }
            if let comment = prop.comment {
                block.statements.append(("rdfs:comment", formatStringLiteral(comment)))
            }
            for domain in prop.domains {
                block.statements.append(("rdfs:domain", formatClassExpression(domain)))
            }
            for range in prop.ranges {
                block.statements.append(("rdfs:range", formatDataRange(range)))
            }
            blocks[prop.iri] = block
        }

        for prop in ontology.annotationProperties {
            var block = getOrCreate(&blocks, subject: prop.iri, section: .annotationProperty)
            block.types.append("owl:AnnotationProperty")
            if let label = prop.label {
                block.statements.append(("rdfs:label", formatStringLiteral(label)))
            }
            blocks[prop.iri] = block
        }

        for ind in ontology.individuals {
            var block = getOrCreate(&blocks, subject: ind.iri, section: .individual)
            block.types.append("owl:NamedIndividual")
            if let label = ind.label {
                block.statements.append(("rdfs:label", formatStringLiteral(label)))
            }
            if let comment = ind.comment {
                block.statements.append(("rdfs:comment", formatStringLiteral(comment)))
            }
            blocks[ind.iri] = block
        }
    }

    // MARK: - Axiom Distribution

    private func distributeAxioms(into blocks: inout [String: SubjectBlock], standalone: inout [StandaloneBlock]) {
        for axiom in ontology.axioms {
            switch axiom {
            // TBox
            case .subClassOf(let sub, let sup):
                if case .named(let iri) = sub {
                    var block = getOrCreate(&blocks, subject: iri, section: .owlClass)
                    block.statements.append(("rdfs:subClassOf", formatClassExpression(sup)))
                    blocks[iri] = block
                }

            case .equivalentClasses(let exprs):
                if let firstNamed = exprs.first(where: { if case .named = $0 { return true }; return false }),
                   case .named(let iri) = firstNamed {
                    var block = getOrCreate(&blocks, subject: iri, section: .owlClass)
                    for expr in exprs where expr != firstNamed {
                        block.statements.append(("owl:equivalentClass", formatClassExpression(expr)))
                    }
                    blocks[iri] = block
                }

            case .disjointClasses(let exprs):
                let members = exprs.map { formatClassExpression($0) }
                standalone.append(StandaloneBlock(
                    type: "owl:AllDisjointClasses",
                    predicate: "owl:members",
                    members: members
                ))

            case .disjointUnion(let cls, let disj):
                var block = getOrCreate(&blocks, subject: cls, section: .owlClass)
                let list = disj.map { formatClassExpression($0) }.joined(separator: " ")
                block.statements.append(("owl:disjointUnionOf", "( \(list) )"))
                blocks[cls] = block

            // RBox — Object Properties
            case .subObjectPropertyOf(let sub, let sup):
                var block = getOrCreate(&blocks, subject: sub, section: .objectProperty)
                block.statements.append(("rdfs:subPropertyOf", formatIRI(sup)))
                blocks[sub] = block

            case .subPropertyChainOf(let chain, let sup):
                var block = getOrCreate(&blocks, subject: sup, section: .objectProperty)
                let list = chain.map { formatIRI($0) }.joined(separator: " ")
                block.statements.append(("owl:propertyChainAxiom", "( \(list) )"))
                blocks[sup] = block

            case .equivalentObjectProperties(let props):
                if let first = props.first {
                    var block = getOrCreate(&blocks, subject: first, section: .objectProperty)
                    for prop in props.dropFirst() {
                        block.statements.append(("owl:equivalentProperty", formatIRI(prop)))
                    }
                    blocks[first] = block
                }

            case .disjointObjectProperties(let props):
                let members = props.map { formatIRI($0) }
                standalone.append(StandaloneBlock(
                    type: "owl:AllDisjointProperties",
                    predicate: "owl:members",
                    members: members
                ))

            case .inverseObjectProperties(let first, let second):
                var block = getOrCreate(&blocks, subject: first, section: .objectProperty)
                if !block.statements.contains(where: { $0.0 == "owl:inverseOf" }) {
                    block.statements.append(("owl:inverseOf", formatIRI(second)))
                }
                blocks[first] = block

            case .objectPropertyDomain(let prop, let domain):
                var block = getOrCreate(&blocks, subject: prop, section: .objectProperty)
                block.statements.append(("rdfs:domain", formatClassExpression(domain)))
                blocks[prop] = block

            case .objectPropertyRange(let prop, let range):
                var block = getOrCreate(&blocks, subject: prop, section: .objectProperty)
                block.statements.append(("rdfs:range", formatClassExpression(range)))
                blocks[prop] = block

            case .functionalObjectProperty(let prop):
                var block = getOrCreate(&blocks, subject: prop, section: .objectProperty)
                appendTypeIfMissing("owl:FunctionalProperty", to: &block)
                blocks[prop] = block

            case .inverseFunctionalObjectProperty(let prop):
                var block = getOrCreate(&blocks, subject: prop, section: .objectProperty)
                appendTypeIfMissing("owl:InverseFunctionalProperty", to: &block)
                blocks[prop] = block

            case .transitiveObjectProperty(let prop):
                var block = getOrCreate(&blocks, subject: prop, section: .objectProperty)
                appendTypeIfMissing("owl:TransitiveProperty", to: &block)
                blocks[prop] = block

            case .symmetricObjectProperty(let prop):
                var block = getOrCreate(&blocks, subject: prop, section: .objectProperty)
                appendTypeIfMissing("owl:SymmetricProperty", to: &block)
                blocks[prop] = block

            case .asymmetricObjectProperty(let prop):
                var block = getOrCreate(&blocks, subject: prop, section: .objectProperty)
                appendTypeIfMissing("owl:AsymmetricProperty", to: &block)
                blocks[prop] = block

            case .reflexiveObjectProperty(let prop):
                var block = getOrCreate(&blocks, subject: prop, section: .objectProperty)
                appendTypeIfMissing("owl:ReflexiveProperty", to: &block)
                blocks[prop] = block

            case .irreflexiveObjectProperty(let prop):
                var block = getOrCreate(&blocks, subject: prop, section: .objectProperty)
                appendTypeIfMissing("owl:IrreflexiveProperty", to: &block)
                blocks[prop] = block

            // RBox — Data Properties
            case .subDataPropertyOf(let sub, let sup):
                var block = getOrCreate(&blocks, subject: sub, section: .dataProperty)
                block.statements.append(("rdfs:subPropertyOf", formatIRI(sup)))
                blocks[sub] = block

            case .equivalentDataProperties(let props):
                if let first = props.first {
                    var block = getOrCreate(&blocks, subject: first, section: .dataProperty)
                    for prop in props.dropFirst() {
                        block.statements.append(("owl:equivalentProperty", formatIRI(prop)))
                    }
                    blocks[first] = block
                }

            case .disjointDataProperties(let props):
                let members = props.map { formatIRI($0) }
                standalone.append(StandaloneBlock(
                    type: "owl:AllDisjointProperties",
                    predicate: "owl:members",
                    members: members
                ))

            case .dataPropertyDomain(let prop, let domain):
                var block = getOrCreate(&blocks, subject: prop, section: .dataProperty)
                block.statements.append(("rdfs:domain", formatClassExpression(domain)))
                blocks[prop] = block

            case .dataPropertyRange(let prop, let range):
                var block = getOrCreate(&blocks, subject: prop, section: .dataProperty)
                block.statements.append(("rdfs:range", formatDataRange(range)))
                blocks[prop] = block

            case .functionalDataProperty(let prop):
                var block = getOrCreate(&blocks, subject: prop, section: .dataProperty)
                appendTypeIfMissing("owl:FunctionalProperty", to: &block)
                blocks[prop] = block

            // ABox
            case .classAssertion(let ind, let cls):
                var block = getOrCreate(&blocks, subject: ind, section: .individual)
                block.types.append(formatClassExpression(cls))
                blocks[ind] = block

            case .objectPropertyAssertion(let subj, let prop, let obj):
                var block = getOrCreate(&blocks, subject: subj, section: .individual)
                block.statements.append((formatIRI(prop), formatIRI(obj)))
                blocks[subj] = block

            case .negativeObjectPropertyAssertion(let subj, let prop, let obj):
                let bnode = "[ a owl:NegativePropertyAssertion ; owl:sourceIndividual \(formatIRI(subj)) ; owl:assertionProperty \(formatIRI(prop)) ; owl:targetIndividual \(formatIRI(obj)) ]"
                standalone.append(StandaloneBlock(type: nil, predicate: nil, members: [], raw: bnode))

            case .dataPropertyAssertion(let subj, let prop, let value):
                var block = getOrCreate(&blocks, subject: subj, section: .individual)
                block.statements.append((formatIRI(prop), formatLiteral(value)))
                blocks[subj] = block

            case .negativeDataPropertyAssertion(let subj, let prop, let value):
                let bnode = "[ a owl:NegativePropertyAssertion ; owl:sourceIndividual \(formatIRI(subj)) ; owl:assertionProperty \(formatIRI(prop)) ; owl:targetValue \(formatLiteral(value)) ]"
                standalone.append(StandaloneBlock(type: nil, predicate: nil, members: [], raw: bnode))

            case .sameIndividual(let inds):
                if let first = inds.first {
                    var block = getOrCreate(&blocks, subject: first, section: .individual)
                    for ind in inds.dropFirst() {
                        block.statements.append(("owl:sameAs", formatIRI(ind)))
                    }
                    blocks[first] = block
                }

            case .differentIndividuals(let inds):
                let members = inds.map { formatIRI($0) }
                standalone.append(StandaloneBlock(
                    type: "owl:AllDifferent",
                    predicate: "owl:distinctMembers",
                    members: members
                ))

            // Declarations — only add type if block doesn't already exist with types
            case .declareClass(let iri):
                var block = getOrCreate(&blocks, subject: iri, section: .owlClass)
                appendTypeIfMissing("owl:Class", to: &block)
                blocks[iri] = block

            case .declareObjectProperty(let iri):
                var block = getOrCreate(&blocks, subject: iri, section: .objectProperty)
                appendTypeIfMissing("owl:ObjectProperty", to: &block)
                blocks[iri] = block

            case .declareDataProperty(let iri):
                var block = getOrCreate(&blocks, subject: iri, section: .dataProperty)
                appendTypeIfMissing("owl:DatatypeProperty", to: &block)
                blocks[iri] = block

            case .declareNamedIndividual(let iri):
                var block = getOrCreate(&blocks, subject: iri, section: .individual)
                appendTypeIfMissing("owl:NamedIndividual", to: &block)
                blocks[iri] = block

            case .declareDatatype(let iri):
                var block = getOrCreate(&blocks, subject: iri, section: .owlClass)
                appendTypeIfMissing("rdfs:Datatype", to: &block)
                blocks[iri] = block

            case .declareAnnotationProperty(let iri):
                var block = getOrCreate(&blocks, subject: iri, section: .annotationProperty)
                appendTypeIfMissing("owl:AnnotationProperty", to: &block)
                blocks[iri] = block
            }
        }
    }

    // MARK: - Rendering

    private func renderBlock(_ block: SubjectBlock, to lines: inout [String]) {
        let subject = formatIRI(block.subject)
        var parts: [String] = []

        // rdf:type always first
        if !block.types.isEmpty {
            let types = block.types.joined(separator: " , ")
            parts.append("\(subject) a \(types)")
        }

        // Group statements by predicate for comma-separated objects
        let grouped = groupByPredicate(block.statements)
        for (pred, objects) in grouped {
            let objStr = objects.joined(separator: " , ")
            if parts.isEmpty {
                parts.append("\(subject) \(pred) \(objStr)")
            } else {
                parts.append("    \(pred) \(objStr)")
            }
        }

        if !parts.isEmpty {
            lines.append(joinStatements(parts) + " .")
        }
    }

    private func renderStandalone(_ standalone: StandaloneBlock, to lines: inout [String]) {
        if let raw = standalone.raw {
            lines.append("\(raw) .")
            return
        }
        guard let type = standalone.type, let predicate = standalone.predicate else { return }
        let members = standalone.members.joined(separator: " ")
        lines.append("[] a \(type) ;")
        lines.append("    \(predicate) ( \(members) ) .")
    }

    // MARK: - IRI Formatting

    private func formatIRI(_ iri: String) -> String {
        // Already prefixed (contains ":" but not "://")
        if iri.contains(":") && !iri.contains("://") {
            return iri
        }
        // Try to compact full IRI
        let compacted = prefixMap.compact(iri)
        if compacted != iri {
            return compacted
        }
        // Fallback: bracket the full IRI
        return "<\(iri)>"
    }

    // MARK: - Class Expression Formatting

    private func formatClassExpression(_ expr: OWLClassExpression) -> String {
        switch expr {
        case .named(let iri):
            return formatIRI(iri)
        case .thing:
            return "owl:Thing"
        case .nothing:
            return "owl:Nothing"

        case .intersection(let exprs):
            let list = exprs.map { formatClassExpression($0) }.joined(separator: " ")
            return "[ owl:intersectionOf ( \(list) ) ]"

        case .union(let exprs):
            let list = exprs.map { formatClassExpression($0) }.joined(separator: " ")
            return "[ owl:unionOf ( \(list) ) ]"

        case .complement(let expr):
            return "[ owl:complementOf \(formatClassExpression(expr)) ]"

        case .oneOf(let inds):
            let list = inds.map { formatIRI($0) }.joined(separator: " ")
            return "[ owl:oneOf ( \(list) ) ]"

        case .someValuesFrom(let prop, let filler):
            return "[ a owl:Restriction ; owl:onProperty \(formatIRI(prop)) ; owl:someValuesFrom \(formatClassExpression(filler)) ]"

        case .allValuesFrom(let prop, let filler):
            return "[ a owl:Restriction ; owl:onProperty \(formatIRI(prop)) ; owl:allValuesFrom \(formatClassExpression(filler)) ]"

        case .hasValue(let prop, let ind):
            return "[ a owl:Restriction ; owl:onProperty \(formatIRI(prop)) ; owl:hasValue \(formatIRI(ind)) ]"

        case .hasSelf(let prop):
            return "[ a owl:Restriction ; owl:onProperty \(formatIRI(prop)) ; owl:hasSelf true ]"

        case .minCardinality(let prop, let n, let filler):
            return formatCardinality(prop: prop, n: n, filler: filler, kind: "min")

        case .maxCardinality(let prop, let n, let filler):
            return formatCardinality(prop: prop, n: n, filler: filler, kind: "max")

        case .exactCardinality(let prop, let n, let filler):
            return formatCardinality(prop: prop, n: n, filler: filler, kind: "exact")

        case .dataSomeValuesFrom(let prop, let range):
            return "[ a owl:Restriction ; owl:onProperty \(formatIRI(prop)) ; owl:someValuesFrom \(formatDataRange(range)) ]"

        case .dataAllValuesFrom(let prop, let range):
            return "[ a owl:Restriction ; owl:onProperty \(formatIRI(prop)) ; owl:allValuesFrom \(formatDataRange(range)) ]"

        case .dataHasValue(let prop, let literal):
            return "[ a owl:Restriction ; owl:onProperty \(formatIRI(prop)) ; owl:hasValue \(formatLiteral(literal)) ]"

        case .dataMinCardinality(let prop, let n, let range):
            return formatDataCardinality(prop: prop, n: n, range: range, kind: "min")

        case .dataMaxCardinality(let prop, let n, let range):
            return formatDataCardinality(prop: prop, n: n, range: range, kind: "max")

        case .dataExactCardinality(let prop, let n, let range):
            return formatDataCardinality(prop: prop, n: n, range: range, kind: "exact")
        }
    }

    // MARK: - Cardinality Helpers

    private func formatCardinality(prop: String, n: Int, filler: OWLClassExpression?, kind: String) -> String {
        let propStr = formatIRI(prop)
        if let filler = filler {
            let cardPred: String
            switch kind {
            case "min": cardPred = "owl:minQualifiedCardinality"
            case "max": cardPred = "owl:maxQualifiedCardinality"
            default: cardPred = "owl:qualifiedCardinality"
            }
            return "[ a owl:Restriction ; owl:onProperty \(propStr) ; \(cardPred) \(n) ; owl:onClass \(formatClassExpression(filler)) ]"
        } else {
            let cardPred: String
            switch kind {
            case "min": cardPred = "owl:minCardinality"
            case "max": cardPred = "owl:maxCardinality"
            default: cardPred = "owl:cardinality"
            }
            return "[ a owl:Restriction ; owl:onProperty \(propStr) ; \(cardPred) \(n) ]"
        }
    }

    private func formatDataCardinality(prop: String, n: Int, range: OWLDataRange?, kind: String) -> String {
        let propStr = formatIRI(prop)
        if let range = range {
            let cardPred: String
            switch kind {
            case "min": cardPred = "owl:minQualifiedCardinality"
            case "max": cardPred = "owl:maxQualifiedCardinality"
            default: cardPred = "owl:qualifiedCardinality"
            }
            return "[ a owl:Restriction ; owl:onProperty \(propStr) ; \(cardPred) \(n) ; owl:onDataRange \(formatDataRange(range)) ]"
        } else {
            let cardPred: String
            switch kind {
            case "min": cardPred = "owl:minCardinality"
            case "max": cardPred = "owl:maxCardinality"
            default: cardPred = "owl:cardinality"
            }
            return "[ a owl:Restriction ; owl:onProperty \(propStr) ; \(cardPred) \(n) ]"
        }
    }

    // MARK: - Data Range Formatting

    private func formatDataRange(_ range: OWLDataRange) -> String {
        switch range {
        case .datatype(let iri):
            return formatIRI(iri)
        case .dataIntersectionOf(let ranges):
            let list = ranges.map { formatDataRange($0) }.joined(separator: " ")
            return "[ owl:intersectionOf ( \(list) ) ]"
        case .dataUnionOf(let ranges):
            let list = ranges.map { formatDataRange($0) }.joined(separator: " ")
            return "[ owl:unionOf ( \(list) ) ]"
        case .dataComplementOf(let range):
            return "[ owl:datatypeComplementOf \(formatDataRange(range)) ]"
        case .dataOneOf(let literals):
            let list = literals.map { formatLiteral($0) }.joined(separator: " ")
            return "[ owl:oneOf ( \(list) ) ]"
        case .datatypeRestriction(let datatype, let facets):
            let facetStr = facets.map { "[ \(formatIRI($0.facet.rawValue)) \(formatLiteral($0.value)) ]" }.joined(separator: " ")
            return "[ a rdfs:Datatype ; owl:onDatatype \(formatIRI(datatype)) ; owl:withRestrictions ( \(facetStr) ) ]"
        }
    }

    // MARK: - Literal Formatting

    private func formatLiteral(_ literal: OWLLiteral) -> String {
        if let lang = literal.language {
            return "\"\(escapeTurtleString(literal.lexicalForm))\"@\(lang)"
        }

        switch literal.datatype {
        case "xsd:string", "http://www.w3.org/2001/XMLSchema#string":
            return "\"\(escapeTurtleString(literal.lexicalForm))\""
        case "xsd:integer", "http://www.w3.org/2001/XMLSchema#integer":
            return literal.lexicalForm
        case "xsd:decimal", "http://www.w3.org/2001/XMLSchema#decimal":
            return literal.lexicalForm
        case "xsd:double", "http://www.w3.org/2001/XMLSchema#double":
            return literal.lexicalForm
        case "xsd:boolean", "http://www.w3.org/2001/XMLSchema#boolean":
            return literal.lexicalForm
        default:
            return "\"\(escapeTurtleString(literal.lexicalForm))\"^^\(formatIRI(literal.datatype))"
        }
    }

    private func formatStringLiteral(_ value: String) -> String {
        return "\"\(escapeTurtleString(value))\""
    }

    private func escapeTurtleString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }

    // MARK: - Property Characteristics

    private func appendPropertyCharacteristicTypes(_ chars: Set<PropertyCharacteristic>, to block: inout SubjectBlock) {
        for char in chars.sorted(by: { $0.rawValue < $1.rawValue }) {
            switch char {
            case .functional: appendTypeIfMissing("owl:FunctionalProperty", to: &block)
            case .inverseFunctional: appendTypeIfMissing("owl:InverseFunctionalProperty", to: &block)
            case .symmetric: appendTypeIfMissing("owl:SymmetricProperty", to: &block)
            case .asymmetric: appendTypeIfMissing("owl:AsymmetricProperty", to: &block)
            case .transitive: appendTypeIfMissing("owl:TransitiveProperty", to: &block)
            case .reflexive: appendTypeIfMissing("owl:ReflexiveProperty", to: &block)
            case .irreflexive: appendTypeIfMissing("owl:IrreflexiveProperty", to: &block)
            }
        }
    }

    // MARK: - Helpers

    private func getOrCreate(_ blocks: inout [String: SubjectBlock], subject: String, section: Section) -> SubjectBlock {
        if let existing = blocks[subject] {
            return existing
        }
        return SubjectBlock(subject: subject, section: section, types: [], statements: [])
    }

    private func appendTypeIfMissing(_ type: String, to block: inout SubjectBlock) {
        if !block.types.contains(type) {
            block.types.append(type)
        }
    }

    private func groupByPredicate(_ statements: [(String, String)]) -> [(String, [String])] {
        var groups: [(String, [String])] = []
        var seen: [String: Int] = [:]
        for (pred, obj) in statements {
            if let idx = seen[pred] {
                groups[idx].1.append(obj)
            } else {
                seen[pred] = groups.count
                groups.append((pred, [obj]))
            }
        }
        return groups
    }

    private func joinStatements(_ parts: [String]) -> String {
        if parts.count <= 1 {
            return parts.first ?? ""
        }
        return parts.dropLast().map { $0 + " ;" }.joined(separator: "\n") + "\n" + parts.last!
    }
}

// MARK: - Internal Types

private struct SubjectBlock {
    let subject: String
    let section: Section
    var types: [String]
    var statements: [(String, String)]
}

private struct StandaloneBlock {
    let type: String?
    let predicate: String?
    let members: [String]
    var raw: String? = nil
}

private enum Section: Int, Comparable {
    case ontologyHeader = 0
    case owlClass = 1
    case objectProperty = 2
    case dataProperty = 3
    case annotationProperty = 4
    case standalone = 5
    case individual = 6

    static func < (lhs: Section, rhs: Section) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
