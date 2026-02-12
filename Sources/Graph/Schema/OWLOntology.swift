// OWLOntology.swift
// Graph - OWL DL ontology container
//
// Provides the main container for OWL DL ontologies (SHOIN(D)).
//
// Reference: W3C OWL 2 Web Ontology Language
// https://www.w3.org/TR/owl2-syntax/#Ontologies

import Foundation
import Core

/// OWL DL Ontology
///
/// The main container for an OWL ontology, including:
/// - **TBox**: Terminology definitions (classes, class axioms)
/// - **RBox**: Role definitions (properties, property axioms)
/// - **ABox**: Assertional data (individuals, assertions)
///
/// **Example**:
/// ```swift
/// var ontology = OWLOntology(iri: "http://example.org/family")
///
/// // Add classes
/// ontology.classes.append(OWLClass(iri: "ex:Person", label: "Person"))
/// ontology.classes.append(OWLClass(iri: "ex:Parent", label: "Parent"))
///
/// // Add properties
/// var hasChild = OWLObjectProperty(iri: "ex:hasChild")
/// hasChild.domains = [.named("ex:Person")]
/// hasChild.ranges = [.named("ex:Person")]
/// ontology.objectProperties.append(hasChild)
///
/// // Add axioms
/// ontology.axioms.append(.subClassOf(
///     sub: .named("ex:Parent"),
///     sup: .minCardinality(property: "ex:hasChild", n: 1, filler: nil)
/// ))
///
/// // Add individuals
/// ontology.individuals.append(OWLNamedIndividual(iri: "ex:Alice"))
/// ontology.axioms.append(.classAssertion(
///     individual: "ex:Alice",
///     class_: .named("ex:Parent")
/// ))
/// ```
public struct OWLOntology: Sendable, Codable, Hashable {

    // MARK: - Metadata

    /// Ontology IRI (identifier)
    public let iri: String

    /// Version IRI (optional)
    public let versionIRI: String?

    /// Imported ontology IRIs
    public var imports: [String]

    /// Namespace prefix mappings
    public var prefixes: [String: String]

    // MARK: - TBox (Terminological Box)

    /// Named classes
    public var classes: [OWLClass]

    // MARK: - RBox (Role Box)

    /// Object properties (roles)
    public var objectProperties: [OWLObjectProperty]

    /// Data properties
    public var dataProperties: [OWLDataProperty]

    /// Annotation properties
    public var annotationProperties: [OWLAnnotationProperty]

    // MARK: - ABox (Assertional Box)

    /// Named individuals
    public var individuals: [OWLNamedIndividual]

    // MARK: - All Axioms

    /// All axioms in the ontology
    public var axioms: [OWLAxiom]

    // MARK: - Initialization

    public init(
        iri: String,
        versionIRI: String? = nil,
        imports: [String] = [],
        prefixes: [String: String] = [:],
        classes: [OWLClass] = [],
        objectProperties: [OWLObjectProperty] = [],
        dataProperties: [OWLDataProperty] = [],
        annotationProperties: [OWLAnnotationProperty] = [],
        individuals: [OWLNamedIndividual] = [],
        axioms: [OWLAxiom] = []
    ) {
        self.iri = iri
        self.versionIRI = versionIRI
        self.imports = imports
        self.classes = classes
        self.objectProperties = objectProperties
        self.dataProperties = dataProperties
        self.annotationProperties = annotationProperties
        self.individuals = individuals
        self.axioms = axioms

        // Default prefixes
        var defaultPrefixes: [String: String] = [
            "owl": "http://www.w3.org/2002/07/owl#",
            "rdf": "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
            "rdfs": "http://www.w3.org/2000/01/rdf-schema#",
            "xsd": "http://www.w3.org/2001/XMLSchema#"
        ]
        for (key, value) in prefixes {
            defaultPrefixes[key] = value
        }
        self.prefixes = defaultPrefixes
    }
}

// MARK: - Axiom Access

extension OWLOntology {
    /// TBox axioms (class relationships)
    public var tboxAxioms: [OWLAxiom] {
        axioms.filter { $0.isTBoxAxiom }
    }

    /// RBox axioms (property relationships)
    public var rboxAxioms: [OWLAxiom] {
        axioms.filter { $0.isRBoxAxiom }
    }

    /// ABox axioms (individual assertions)
    public var aboxAxioms: [OWLAxiom] {
        axioms.filter { $0.isABoxAxiom }
    }

    /// Declaration axioms
    public var declarationAxioms: [OWLAxiom] {
        axioms.filter { $0.isDeclarationAxiom }
    }
}

// MARK: - Entity Lookup

extension OWLOntology {
    /// Find a class by IRI
    public func findClass(_ iri: String) -> OWLClass? {
        classes.first { $0.iri == iri }
    }

    /// Find an object property by IRI
    public func findObjectProperty(_ iri: String) -> OWLObjectProperty? {
        objectProperties.first { $0.iri == iri }
    }

    /// Find a data property by IRI
    public func findDataProperty(_ iri: String) -> OWLDataProperty? {
        dataProperties.first { $0.iri == iri }
    }

    /// Find an individual by IRI
    public func findIndividual(_ iri: String) -> OWLNamedIndividual? {
        individuals.first { $0.iri == iri }
    }

    /// Check if a class exists
    public func containsClass(_ iri: String) -> Bool {
        classes.contains { $0.iri == iri }
    }

    /// Check if an object property exists
    public func containsObjectProperty(_ iri: String) -> Bool {
        objectProperties.contains { $0.iri == iri }
    }

    /// Check if a data property exists
    public func containsDataProperty(_ iri: String) -> Bool {
        dataProperties.contains { $0.iri == iri }
    }

    /// Check if an individual exists
    public func containsIndividual(_ iri: String) -> Bool {
        individuals.contains { $0.iri == iri }
    }
}

// MARK: - Axiom Query

extension OWLOntology {
    /// Get all subclass axioms where the given class is the subclass
    public func subClassAxioms(for classIRI: String) -> [OWLAxiom] {
        axioms.filter { axiom in
            if case .subClassOf(let sub, _) = axiom {
                if case .named(let iri) = sub {
                    return iri == classIRI
                }
            }
            return false
        }
    }

    /// Get all superclass axioms where the given class is the subclass
    public func superClassAxioms(for classIRI: String) -> [(OWLAxiom, OWLClassExpression)] {
        axioms.compactMap { axiom -> (OWLAxiom, OWLClassExpression)? in
            if case .subClassOf(let sub, let sup) = axiom {
                if case .named(let iri) = sub, iri == classIRI {
                    return (axiom, sup)
                }
            }
            return nil
        }
    }

    /// Get all equivalent class axioms containing the given class
    public func equivalentClassAxioms(for classIRI: String) -> [OWLAxiom] {
        axioms.filter { axiom in
            if case .equivalentClasses(let exprs) = axiom {
                return exprs.contains { expr in
                    if case .named(let iri) = expr {
                        return iri == classIRI
                    }
                    return false
                }
            }
            return false
        }
    }

    /// Get all class assertions for an individual
    public func classAssertions(for individualIRI: String) -> [OWLClassExpression] {
        axioms.compactMap { axiom -> OWLClassExpression? in
            if case .classAssertion(let ind, let class_) = axiom {
                if ind == individualIRI {
                    return class_
                }
            }
            return nil
        }
    }

    /// Get all object property assertions for a subject
    public func objectPropertyAssertions(forSubject subjectIRI: String) -> [(property: String, object: String)] {
        axioms.compactMap { axiom -> (property: String, object: String)? in
            if case .objectPropertyAssertion(let subj, let prop, let obj) = axiom {
                if subj == subjectIRI {
                    return (property: prop, object: obj)
                }
            }
            return nil
        }
    }

    /// Get all data property assertions for a subject
    public func dataPropertyAssertions(forSubject subjectIRI: String) -> [(property: String, value: OWLLiteral)] {
        axioms.compactMap { axiom -> (property: String, value: OWLLiteral)? in
            if case .dataPropertyAssertion(let subj, let prop, let value) = axiom {
                if subj == subjectIRI {
                    return (property: prop, value: value)
                }
            }
            return nil
        }
    }
}

// MARK: - Signature

extension OWLOntology {
    /// Get all class IRIs in the ontology signature
    public var classSignature: Set<String> {
        var result = Set(classes.map { $0.iri })
        for axiom in axioms {
            result.formUnion(axiom.referencedClasses)
        }
        return result
    }

    /// Get all object property IRIs in the ontology signature
    public var objectPropertySignature: Set<String> {
        var result = Set(objectProperties.map { $0.iri })
        for axiom in axioms {
            result.formUnion(axiom.referencedObjectProperties)
        }
        return result
    }

    /// Get all data property IRIs in the ontology signature
    public var dataPropertySignature: Set<String> {
        var result = Set(dataProperties.map { $0.iri })
        for axiom in axioms {
            result.formUnion(axiom.referencedDataProperties)
        }
        return result
    }

    /// Get all individual IRIs in the ontology signature
    public var individualSignature: Set<String> {
        var result = Set(individuals.map { $0.iri })
        for axiom in axioms {
            result.formUnion(axiom.referencedIndividuals)
        }
        return result
    }
}

// MARK: - Validation

extension OWLOntology {
    /// Basic validation errors
    public enum ValidationError: Error, Sendable, Equatable {
        case undeclaredClass(String)
        case undeclaredObjectProperty(String)
        case undeclaredDataProperty(String)
        case undeclaredIndividual(String)
        case duplicateClass(String)
        case duplicateObjectProperty(String)
        case duplicateDataProperty(String)
        case duplicateIndividual(String)
    }

    /// Validate ontology for basic structural issues
    ///
    /// Note: This does not check OWL DL regularity constraints.
    /// Use `OWLDLRegularityChecker` for full OWL DL validation.
    public func validate() -> [ValidationError] {
        var errors: [ValidationError] = []

        // Check for duplicates
        let classIRIs = classes.map { $0.iri }
        for (index, iri) in classIRIs.enumerated() {
            if classIRIs.dropFirst(index + 1).contains(iri) {
                errors.append(.duplicateClass(iri))
            }
        }

        let objPropIRIs = objectProperties.map { $0.iri }
        for (index, iri) in objPropIRIs.enumerated() {
            if objPropIRIs.dropFirst(index + 1).contains(iri) {
                errors.append(.duplicateObjectProperty(iri))
            }
        }

        let dataPropIRIs = dataProperties.map { $0.iri }
        for (index, iri) in dataPropIRIs.enumerated() {
            if dataPropIRIs.dropFirst(index + 1).contains(iri) {
                errors.append(.duplicateDataProperty(iri))
            }
        }

        let indIRIs = individuals.map { $0.iri }
        for (index, iri) in indIRIs.enumerated() {
            if indIRIs.dropFirst(index + 1).contains(iri) {
                errors.append(.duplicateIndividual(iri))
            }
        }

        return errors
    }
}

// MARK: - Statistics

extension OWLOntology {
    /// Ontology statistics
    public struct Statistics: Sendable {
        public let classCount: Int
        public let objectPropertyCount: Int
        public let dataPropertyCount: Int
        public let individualCount: Int
        public let axiomCount: Int
        public let tboxAxiomCount: Int
        public let rboxAxiomCount: Int
        public let aboxAxiomCount: Int
    }

    /// Get ontology statistics
    public var statistics: Statistics {
        Statistics(
            classCount: classes.count,
            objectPropertyCount: objectProperties.count,
            dataPropertyCount: dataProperties.count,
            individualCount: individuals.count,
            axiomCount: axioms.count,
            tboxAxiomCount: tboxAxioms.count,
            rboxAxiomCount: rboxAxioms.count,
            aboxAxiomCount: aboxAxioms.count
        )
    }
}

// MARK: - CustomStringConvertible

extension OWLOntology: CustomStringConvertible {
    public var description: String {
        let stats = statistics
        var parts: [String] = [
            "Ontology(\(iri))"
        ]

        if let version = versionIRI {
            parts.append("  version: \(version)")
        }

        parts.append("  classes: \(stats.classCount)")
        parts.append("  object properties: \(stats.objectPropertyCount)")
        parts.append("  data properties: \(stats.dataPropertyCount)")
        parts.append("  individuals: \(stats.individualCount)")
        parts.append("  axioms: \(stats.axiomCount) (TBox: \(stats.tboxAxiomCount), RBox: \(stats.rboxAxiomCount), ABox: \(stats.aboxAxiomCount))")

        return parts.joined(separator: "\n")
    }
}

// MARK: - Result Builder Initializer

extension OWLOntology {
    /// @resultBuilder DSL でオントロジーを構築する
    public init(
        iri: String,
        versionIRI: String? = nil,
        prefixes: [String: String] = [:],
        @OWLOntologyBuilder content: () -> [OWLOntologyComponent]
    ) {
        self.init(iri: iri, versionIRI: versionIRI, prefixes: prefixes)
        let components = content()
        for component in components {
            component.apply(to: &self)
        }
    }
}

// MARK: - Builder Pattern

extension OWLOntology {
    /// Add a class to the ontology
    @discardableResult
    public mutating func addClass(_ class_: OWLClass) -> Self {
        classes.append(class_)
        return self
    }

    /// Add an object property to the ontology
    @discardableResult
    public mutating func addObjectProperty(_ property: OWLObjectProperty) -> Self {
        objectProperties.append(property)
        return self
    }

    /// Add a data property to the ontology
    @discardableResult
    public mutating func addDataProperty(_ property: OWLDataProperty) -> Self {
        dataProperties.append(property)
        return self
    }

    /// Add an individual to the ontology
    @discardableResult
    public mutating func addIndividual(_ individual: OWLNamedIndividual) -> Self {
        individuals.append(individual)
        return self
    }

    /// Add an axiom to the ontology
    @discardableResult
    public mutating func addAxiom(_ axiom: OWLAxiom) -> Self {
        axioms.append(axiom)
        return self
    }

    /// Add multiple axioms to the ontology
    @discardableResult
    public mutating func addAxioms(_ newAxioms: [OWLAxiom]) -> Self {
        axioms.append(contentsOf: newAxioms)
        return self
    }
}

// MARK: - Schema.Ontology Conversion

extension OWLOntology {

    /// Convert to type-erased `Schema.Ontology` for persistence and transport.
    ///
    /// Core module stores this representation without needing to import Graph.
    /// Encoding is guaranteed to succeed because all OWLOntology fields are Codable.
    ///
    /// - Returns: `Schema.Ontology` containing JSON-encoded `OWLOntology`
    public func asSchemaOntology() -> Schema.Ontology {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // Safe: OWLOntology is composed entirely of Codable value types.
        let data = try! encoder.encode(self)
        return Schema.Ontology(
            iri: self.iri,
            typeIdentifier: "OWLOntology",
            encodedData: data
        )
    }

    /// Restore `OWLOntology` from a type-erased `Schema.Ontology`.
    ///
    /// - Parameter schemaOntology: The type-erased ontology from Core
    /// - Throws: `DecodingError` if the encoded data is not a valid `OWLOntology`
    public init(schemaOntology: Schema.Ontology) throws {
        self = try JSONDecoder().decode(OWLOntology.self, from: schemaOntology.encodedData)
    }
}
