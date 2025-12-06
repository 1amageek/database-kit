// OWLProperty.swift
// Graph - OWL DL property definitions
//
// Provides object and data property types for OWL DL ontologies (SHOIN(D)).
//
// Reference: W3C OWL 2 Web Ontology Language
// https://www.w3.org/TR/owl2-syntax/#Object_Properties
// https://www.w3.org/TR/owl2-syntax/#Data_Properties

import Foundation

// MARK: - Property Characteristic

/// OWL Property Characteristics
///
/// Defines the logical characteristics of object properties.
///
/// **SHOIN(D) Mapping**:
/// - `transitive` → S (Transitive roles)
/// - `inverseOf` → I (Inverse roles)
/// - Other characteristics are OWL 2 additions
///
/// **Reference**: OWL 2 Property Characteristics
/// https://www.w3.org/TR/owl2-syntax/#Object_Property_Characteristics
public enum PropertyCharacteristic: String, Sendable, Codable, CaseIterable {
    // MARK: - Basic Characteristics

    /// Functional: R(x,y) ∧ R(x,z) → y=z
    /// At most one value for each individual
    case functional

    /// Inverse Functional: R(x,z) ∧ R(y,z) → x=y
    /// At most one subject for each object
    case inverseFunctional

    // MARK: - Symmetry

    /// Symmetric: R(x,y) → R(y,x)
    case symmetric

    /// Asymmetric: R(x,y) → ¬R(y,x)
    case asymmetric

    // MARK: - Transitivity (S)

    /// Transitive: R(x,y) ∧ R(y,z) → R(x,z)
    /// Part of SHOIN(D) - the "S" component
    case transitive

    // MARK: - Reflexivity

    /// Reflexive: ∀x. R(x,x)
    /// Every individual is related to itself
    case reflexive

    /// Irreflexive: ∀x. ¬R(x,x)
    /// No individual is related to itself
    case irreflexive
}

// MARK: - OWLObjectProperty

/// OWL Object Property (Role)
///
/// Represents a binary relation between individuals.
///
/// **SHOIN(D) Features**:
/// - Role characteristics (S): transitive, etc.
/// - Role hierarchy (H): subPropertyOf
/// - Inverse roles (I): inverseOf
///
/// **Example**:
/// ```swift
/// var hasParent = OWLObjectProperty(iri: "ex:hasParent", label: "has parent")
/// hasParent.inverseOf = "ex:hasChild"
/// hasParent.domains = [.named("ex:Person")]
/// hasParent.ranges = [.named("ex:Person")]
///
/// var ancestorOf = OWLObjectProperty(iri: "ex:ancestorOf")
/// ancestorOf.characteristics.insert(.transitive)
/// ```
public struct OWLObjectProperty: Sendable, Codable, Hashable {
    /// Property IRI (identifier)
    public let iri: String

    /// Human-readable label
    public var label: String?

    /// Human-readable comment/description
    public var comment: String?

    /// Additional annotations
    public var annotations: [String: String]

    // MARK: - Role Characteristics (S, I)

    /// Property characteristics (functional, transitive, etc.)
    public var characteristics: Set<PropertyCharacteristic>

    // MARK: - Inverse Role (I)

    /// IRI of the inverse property (owl:inverseOf)
    public var inverseOf: String?

    // MARK: - Domain/Range

    /// Domain class expressions (individuals that can be subjects)
    public var domains: [OWLClassExpression]

    /// Range class expressions (individuals that can be objects)
    public var ranges: [OWLClassExpression]

    // MARK: - Role Hierarchy (H)

    /// Super-properties (rdfs:subPropertyOf)
    public var superProperties: [String]

    /// Equivalent properties (owl:equivalentProperty)
    public var equivalentProperties: [String]

    /// Disjoint properties (owl:propertyDisjointWith)
    public var disjointProperties: [String]

    // MARK: - Property Chains

    /// Property chains that imply this property (R₁ ∘ R₂ ∘ ... ⊑ this)
    /// Each element is an array of property IRIs representing a chain
    public var propertyChains: [[String]]

    public init(
        iri: String,
        label: String? = nil,
        comment: String? = nil,
        annotations: [String: String] = [:],
        characteristics: Set<PropertyCharacteristic> = [],
        inverseOf: String? = nil,
        domains: [OWLClassExpression] = [],
        ranges: [OWLClassExpression] = [],
        superProperties: [String] = [],
        equivalentProperties: [String] = [],
        disjointProperties: [String] = [],
        propertyChains: [[String]] = []
    ) {
        self.iri = iri
        self.label = label
        self.comment = comment
        self.annotations = annotations
        self.characteristics = characteristics
        self.inverseOf = inverseOf
        self.domains = domains
        self.ranges = ranges
        self.superProperties = superProperties
        self.equivalentProperties = equivalentProperties
        self.disjointProperties = disjointProperties
        self.propertyChains = propertyChains
    }
}

// MARK: - Convenience Methods

extension OWLObjectProperty {
    /// Check if property is transitive
    public var isTransitive: Bool {
        characteristics.contains(.transitive)
    }

    /// Check if property is functional
    public var isFunctional: Bool {
        characteristics.contains(.functional)
    }

    /// Check if property is inverse functional
    public var isInverseFunctional: Bool {
        characteristics.contains(.inverseFunctional)
    }

    /// Check if property is symmetric
    public var isSymmetric: Bool {
        characteristics.contains(.symmetric)
    }

    /// Check if property is asymmetric
    public var isAsymmetric: Bool {
        characteristics.contains(.asymmetric)
    }

    /// Check if property is reflexive
    public var isReflexive: Bool {
        characteristics.contains(.reflexive)
    }

    /// Check if property is irreflexive
    public var isIrreflexive: Bool {
        characteristics.contains(.irreflexive)
    }

    /// Check if property has an inverse
    public var hasInverse: Bool {
        inverseOf != nil
    }

    /// Check if this is a "simple" role (OWL DL requirement)
    /// A role is simple if it is not transitive and does not have
    /// any transitive sub-properties.
    /// Note: Full simplicity check requires the role hierarchy.
    public var isPotentiallySimple: Bool {
        !isTransitive
    }
}

// MARK: - OWLDataProperty

/// OWL Data Property
///
/// Represents a relation from individuals to data values (literals).
///
/// **Example**:
/// ```swift
/// var hasAge = OWLDataProperty(iri: "ex:hasAge", label: "age")
/// hasAge.domains = [.named("ex:Person")]
/// hasAge.ranges = [.integerRange(min: 0, max: 150)]
/// hasAge.isFunctional = true
///
/// var hasEmail = OWLDataProperty(iri: "ex:hasEmail")
/// hasEmail.ranges = [.stringPattern("[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+")]
/// ```
public struct OWLDataProperty: Sendable, Codable, Hashable {
    /// Property IRI (identifier)
    public let iri: String

    /// Human-readable label
    public var label: String?

    /// Human-readable comment/description
    public var comment: String?

    /// Additional annotations
    public var annotations: [String: String]

    // MARK: - Domain/Range

    /// Domain class expressions (individuals that can have this property)
    public var domains: [OWLClassExpression]

    /// Range data ranges (allowed value types)
    public var ranges: [OWLDataRange]

    // MARK: - Characteristics

    /// Whether the property is functional (at most one value per individual)
    public var isFunctional: Bool

    // MARK: - Property Hierarchy

    /// Super-properties (rdfs:subPropertyOf)
    public var superProperties: [String]

    /// Equivalent properties (owl:equivalentProperty)
    public var equivalentProperties: [String]

    /// Disjoint properties (owl:propertyDisjointWith)
    public var disjointProperties: [String]

    public init(
        iri: String,
        label: String? = nil,
        comment: String? = nil,
        annotations: [String: String] = [:],
        domains: [OWLClassExpression] = [],
        ranges: [OWLDataRange] = [],
        isFunctional: Bool = false,
        superProperties: [String] = [],
        equivalentProperties: [String] = [],
        disjointProperties: [String] = []
    ) {
        self.iri = iri
        self.label = label
        self.comment = comment
        self.annotations = annotations
        self.domains = domains
        self.ranges = ranges
        self.isFunctional = isFunctional
        self.superProperties = superProperties
        self.equivalentProperties = equivalentProperties
        self.disjointProperties = disjointProperties
    }
}

// MARK: - Annotation Property

/// OWL Annotation Property
///
/// Represents a property for adding metadata/annotations to entities.
/// Annotation properties are not subject to logical reasoning.
///
/// **Standard Annotation Properties**:
/// - rdfs:label, rdfs:comment, rdfs:seeAlso
/// - owl:versionInfo, owl:deprecated
public struct OWLAnnotationProperty: Sendable, Codable, Hashable {
    /// Property IRI (identifier)
    public let iri: String

    /// Human-readable label
    public var label: String?

    /// Super-properties
    public var superProperties: [String]

    /// Domain constraints (IRIs, not class expressions)
    public var domains: [String]

    /// Range constraints (IRIs)
    public var ranges: [String]

    public init(
        iri: String,
        label: String? = nil,
        superProperties: [String] = [],
        domains: [String] = [],
        ranges: [String] = []
    ) {
        self.iri = iri
        self.label = label
        self.superProperties = superProperties
        self.domains = domains
        self.ranges = ranges
    }
}

// MARK: - CustomStringConvertible

extension OWLObjectProperty: CustomStringConvertible {
    public var description: String {
        var parts: [String] = []

        if let label = label {
            parts.append("\(label) (\(iri))")
        } else {
            parts.append(iri)
        }

        if !characteristics.isEmpty {
            let charStrs = characteristics.map { $0.rawValue }
            parts.append("[\(charStrs.joined(separator: ", "))]")
        }

        if let inv = inverseOf {
            parts.append("inverse: \(inv)")
        }

        return parts.joined(separator: " ")
    }
}

extension OWLDataProperty: CustomStringConvertible {
    public var description: String {
        var parts: [String] = []

        if let label = label {
            parts.append("\(label) (\(iri))")
        } else {
            parts.append(iri)
        }

        if isFunctional {
            parts.append("[functional]")
        }

        if !ranges.isEmpty {
            let rangeStrs = ranges.map { $0.description }
            parts.append("range: \(rangeStrs.joined(separator: ", "))")
        }

        return parts.joined(separator: " ")
    }
}

extension OWLAnnotationProperty: CustomStringConvertible {
    public var description: String {
        if let label = label {
            return "\(label) (\(iri))"
        }
        return iri
    }
}
