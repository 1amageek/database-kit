// OWLClass.swift
// Graph - OWL DL class and class expression definitions
//
// Provides class types for OWL DL ontologies (SHOIN(D)).
//
// Reference: W3C OWL 2 Web Ontology Language
// https://www.w3.org/TR/owl2-syntax/#Class_Expressions

import Foundation

/// OWL Named Class
///
/// Represents a named class (concept) in an OWL ontology.
///
/// **Example**:
/// ```swift
/// let person = OWLClass(iri: "ex:Person", label: "Person")
/// let employee = OWLClass(iri: "ex:Employee", label: "Employee")
/// ```
public struct OWLClass: Sendable, Codable, Hashable {
    /// Class IRI (identifier)
    public let iri: String

    /// Human-readable label
    public var label: String?

    /// Human-readable comment/description
    public var comment: String?

    /// Additional annotations
    public var annotations: [String: String]

    public init(
        iri: String,
        label: String? = nil,
        comment: String? = nil,
        annotations: [String: String] = [:]
    ) {
        self.iri = iri
        self.label = label
        self.comment = comment
        self.annotations = annotations
    }
}

// MARK: - OWLClassExpression

/// OWL Class Expression (SHOIN(D) complete)
///
/// Represents complex class expressions in OWL DL.
///
/// **DL Notation Mapping**:
/// - `⊤` = Thing, `⊥` = Nothing
/// - `C ⊓ D` = intersection, `C ⊔ D` = union, `¬C` = complement
/// - `{a, b}` = oneOf (Nominals - O)
/// - `∃R.C` = someValuesFrom, `∀R.C` = allValuesFrom
/// - `∃R.{a}` = hasValue
/// - `∃R.Self` = hasSelf
/// - `≥n R.C` = minCardinality, `≤n R.C` = maxCardinality, `=n R.C` = exactCardinality (N)
/// - Data property constraints (D)
///
/// **Example**:
/// ```swift
/// // Person who has at least 1 child
/// let parent = OWLClassExpression.intersection([
///     .named("ex:Person"),
///     .minCardinality(property: "ex:hasChild", n: 1, filler: nil)
/// ])
///
/// // Employee with salary > 50000
/// let highPaid = OWLClassExpression.intersection([
///     .named("ex:Employee"),
///     .dataSomeValuesFrom(
///         property: "ex:salary",
///         range: .datatypeRestriction(
///             datatype: "xsd:integer",
///             facets: [.minExclusive(50000)]
///         )
///     )
/// ])
/// ```
public indirect enum OWLClassExpression: Sendable, Codable, Hashable {

    // MARK: - Basic Class Expressions

    /// Named class reference
    case named(String)

    /// Top concept (owl:Thing) - ⊤
    case thing

    /// Bottom concept (owl:Nothing) - ⊥
    case nothing

    // MARK: - Boolean Constructors

    /// Intersection of class expressions (C ⊓ D)
    case intersection([OWLClassExpression])

    /// Union of class expressions (C ⊔ D)
    case union([OWLClassExpression])

    /// Complement of a class expression (¬C)
    case complement(OWLClassExpression)

    // MARK: - Nominals (O)

    /// Enumeration of individuals ({a, b, c})
    case oneOf([String])

    // MARK: - Object Property Restrictions

    /// Existential quantification (∃R.C)
    case someValuesFrom(property: String, filler: OWLClassExpression)

    /// Universal quantification (∀R.C)
    case allValuesFrom(property: String, filler: OWLClassExpression)

    /// Has value restriction (∃R.{a})
    case hasValue(property: String, individual: String)

    /// Self restriction (∃R.Self)
    case hasSelf(property: String)

    // MARK: - Cardinality Restrictions (N)

    /// Minimum cardinality (≥n R.C)
    case minCardinality(property: String, n: Int, filler: OWLClassExpression?)

    /// Maximum cardinality (≤n R.C)
    case maxCardinality(property: String, n: Int, filler: OWLClassExpression?)

    /// Exact cardinality (=n R.C)
    case exactCardinality(property: String, n: Int, filler: OWLClassExpression?)

    // MARK: - Data Property Restrictions (D)

    /// Data existential quantification (∃T.D)
    case dataSomeValuesFrom(property: String, range: OWLDataRange)

    /// Data universal quantification (∀T.D)
    case dataAllValuesFrom(property: String, range: OWLDataRange)

    /// Data has value restriction (∃T.{v})
    case dataHasValue(property: String, literal: OWLLiteral)

    /// Data minimum cardinality (≥n T.D)
    case dataMinCardinality(property: String, n: Int, range: OWLDataRange?)

    /// Data maximum cardinality (≤n T.D)
    case dataMaxCardinality(property: String, n: Int, range: OWLDataRange?)

    /// Data exact cardinality (=n T.D)
    case dataExactCardinality(property: String, n: Int, range: OWLDataRange?)
}

// MARK: - Negation Normal Form (NNF)

extension OWLClassExpression {
    /// Convert to Negation Normal Form (NNF)
    ///
    /// In NNF, negation only appears directly in front of named classes.
    /// This is required for the Tableaux algorithm.
    ///
    /// **Transformation rules**:
    /// - ¬(C ⊓ D) → ¬C ⊔ ¬D
    /// - ¬(C ⊔ D) → ¬C ⊓ ¬D
    /// - ¬¬C → C
    /// - ¬(∃R.C) → ∀R.¬C
    /// - ¬(∀R.C) → ∃R.¬C
    /// - ¬(≥n R.C) → ≤(n-1) R.C
    /// - ¬(≤n R.C) → ≥(n+1) R.C
    public func toNNF() -> OWLClassExpression {
        switch self {
        case .named, .thing, .nothing, .oneOf, .hasValue, .hasSelf,
             .dataHasValue:
            return self

        case .intersection(let exprs):
            return .intersection(exprs.map { $0.toNNF() })

        case .union(let exprs):
            return .union(exprs.map { $0.toNNF() })

        case .complement(let expr):
            return expr.negateToNNF()

        case .someValuesFrom(let prop, let filler):
            return .someValuesFrom(property: prop, filler: filler.toNNF())

        case .allValuesFrom(let prop, let filler):
            return .allValuesFrom(property: prop, filler: filler.toNNF())

        case .minCardinality(let prop, let n, let filler):
            return .minCardinality(property: prop, n: n, filler: filler?.toNNF())

        case .maxCardinality(let prop, let n, let filler):
            return .maxCardinality(property: prop, n: n, filler: filler?.toNNF())

        case .exactCardinality(let prop, let n, let filler):
            // =n R.C ≡ ≥n R.C ⊓ ≤n R.C
            return .intersection([
                .minCardinality(property: prop, n: n, filler: filler?.toNNF()),
                .maxCardinality(property: prop, n: n, filler: filler?.toNNF())
            ])

        case .dataSomeValuesFrom, .dataAllValuesFrom,
             .dataMinCardinality, .dataMaxCardinality:
            return self

        case .dataExactCardinality(let prop, let n, let range):
            // =n T.D ≡ ≥n T.D ⊓ ≤n T.D (consistent with exactCardinality)
            return .intersection([
                .dataMinCardinality(property: prop, n: n, range: range),
                .dataMaxCardinality(property: prop, n: n, range: range)
            ])
        }
    }

    /// Negate and convert to NNF (helper for complement)
    private func negateToNNF() -> OWLClassExpression {
        switch self {
        case .named:
            return .complement(self)

        case .thing:
            return .nothing

        case .nothing:
            return .thing

        case .intersection(let exprs):
            // ¬(C ⊓ D) → ¬C ⊔ ¬D
            return .union(exprs.map { $0.negateToNNF() })

        case .union(let exprs):
            // ¬(C ⊔ D) → ¬C ⊓ ¬D
            return .intersection(exprs.map { $0.negateToNNF() })

        case .complement(let expr):
            // ¬¬C → C
            return expr.toNNF()

        case .oneOf:
            return .complement(self)

        case .someValuesFrom(let prop, let filler):
            // ¬(∃R.C) → ∀R.¬C
            return .allValuesFrom(property: prop, filler: filler.negateToNNF())

        case .allValuesFrom(let prop, let filler):
            // ¬(∀R.C) → ∃R.¬C
            return .someValuesFrom(property: prop, filler: filler.negateToNNF())

        case .hasValue(let prop, let ind):
            // ¬(∃R.{a}) → ∀R.¬{a}
            return .allValuesFrom(property: prop, filler: .complement(.oneOf([ind])))

        case .hasSelf(let prop):
            return .complement(.hasSelf(property: prop))

        case .minCardinality(let prop, let n, let filler):
            // ¬(≥n R.C) → ≤(n-1) R.C
            return .maxCardinality(property: prop, n: max(0, n - 1), filler: filler?.toNNF())

        case .maxCardinality(let prop, let n, let filler):
            // ¬(≤n R.C) → ≥(n+1) R.C
            return .minCardinality(property: prop, n: n + 1, filler: filler?.toNNF())

        case .exactCardinality(let prop, let n, let filler):
            // ¬(=n R.C) → (≤(n-1) R.C) ⊔ (≥(n+1) R.C)
            return .union([
                .maxCardinality(property: prop, n: max(0, n - 1), filler: filler?.toNNF()),
                .minCardinality(property: prop, n: n + 1, filler: filler?.toNNF())
            ])

        case .dataSomeValuesFrom(let prop, let range):
            return .dataAllValuesFrom(property: prop, range: .dataComplementOf(range))

        case .dataAllValuesFrom(let prop, let range):
            return .dataSomeValuesFrom(property: prop, range: .dataComplementOf(range))

        case .dataHasValue:
            return .complement(self)

        case .dataMinCardinality(let prop, let n, let range):
            return .dataMaxCardinality(property: prop, n: max(0, n - 1), range: range)

        case .dataMaxCardinality(let prop, let n, let range):
            return .dataMinCardinality(property: prop, n: n + 1, range: range)

        case .dataExactCardinality(let prop, let n, let range):
            return .union([
                .dataMaxCardinality(property: prop, n: max(0, n - 1), range: range),
                .dataMinCardinality(property: prop, n: n + 1, range: range)
            ])
        }
    }
}

// MARK: - Analysis

extension OWLClassExpression {
    /// Get all named classes used in this expression
    public var usedClasses: Set<String> {
        switch self {
        case .named(let iri):
            return [iri]

        case .thing, .nothing:
            return []

        case .intersection(let exprs), .union(let exprs):
            return exprs.reduce(into: Set<String>()) { $0.formUnion($1.usedClasses) }

        case .complement(let expr):
            return expr.usedClasses

        case .oneOf:
            return []

        case .someValuesFrom(_, let filler), .allValuesFrom(_, let filler):
            return filler.usedClasses

        case .hasValue, .hasSelf:
            return []

        case .minCardinality(_, _, let filler),
             .maxCardinality(_, _, let filler),
             .exactCardinality(_, _, let filler):
            return filler?.usedClasses ?? []

        case .dataSomeValuesFrom, .dataAllValuesFrom, .dataHasValue,
             .dataMinCardinality, .dataMaxCardinality, .dataExactCardinality:
            return []
        }
    }

    /// Get all object properties used in this expression
    public var usedObjectProperties: Set<String> {
        switch self {
        case .named, .thing, .nothing, .oneOf:
            return []

        case .intersection(let exprs), .union(let exprs):
            return exprs.reduce(into: Set<String>()) { $0.formUnion($1.usedObjectProperties) }

        case .complement(let expr):
            return expr.usedObjectProperties

        case .someValuesFrom(let prop, let filler), .allValuesFrom(let prop, let filler):
            return Set([prop]).union(filler.usedObjectProperties)

        case .hasValue(let prop, _), .hasSelf(let prop):
            return [prop]

        case .minCardinality(let prop, _, let filler),
             .maxCardinality(let prop, _, let filler),
             .exactCardinality(let prop, _, let filler):
            return Set([prop]).union(filler?.usedObjectProperties ?? [])

        case .dataSomeValuesFrom, .dataAllValuesFrom, .dataHasValue,
             .dataMinCardinality, .dataMaxCardinality, .dataExactCardinality:
            return []
        }
    }

    /// Get all data properties used in this expression
    public var usedDataProperties: Set<String> {
        switch self {
        case .named, .thing, .nothing, .oneOf,
             .someValuesFrom, .allValuesFrom, .hasValue, .hasSelf,
             .minCardinality, .maxCardinality, .exactCardinality:
            return []

        case .intersection(let exprs), .union(let exprs):
            return exprs.reduce(into: Set<String>()) { $0.formUnion($1.usedDataProperties) }

        case .complement(let expr):
            return expr.usedDataProperties

        case .dataSomeValuesFrom(let prop, _), .dataAllValuesFrom(let prop, _),
             .dataHasValue(let prop, _):
            return [prop]

        case .dataMinCardinality(let prop, _, _),
             .dataMaxCardinality(let prop, _, _),
             .dataExactCardinality(let prop, _, _):
            return [prop]
        }
    }

    /// Get all individuals referenced in this expression
    public var usedIndividuals: Set<String> {
        switch self {
        case .named, .thing, .nothing:
            return []

        case .intersection(let exprs), .union(let exprs):
            return exprs.reduce(into: Set<String>()) { $0.formUnion($1.usedIndividuals) }

        case .complement(let expr):
            return expr.usedIndividuals

        case .oneOf(let inds):
            return Set(inds)

        case .someValuesFrom(_, let filler), .allValuesFrom(_, let filler):
            return filler.usedIndividuals

        case .hasValue(_, let ind):
            return [ind]

        case .hasSelf:
            return []

        case .minCardinality(_, _, let filler),
             .maxCardinality(_, _, let filler),
             .exactCardinality(_, _, let filler):
            return filler?.usedIndividuals ?? []

        case .dataSomeValuesFrom, .dataAllValuesFrom, .dataHasValue,
             .dataMinCardinality, .dataMaxCardinality, .dataExactCardinality:
            return []
        }
    }

    /// Check if this is an atomic (non-compound) expression
    public var isAtomic: Bool {
        switch self {
        case .named, .thing, .nothing:
            return true
        default:
            return false
        }
    }

    /// Check if this expression contains cardinality restrictions
    public var hasCardinalityRestriction: Bool {
        switch self {
        case .named, .thing, .nothing, .oneOf, .hasValue, .hasSelf, .dataHasValue:
            return false

        case .intersection(let exprs), .union(let exprs):
            return exprs.contains { $0.hasCardinalityRestriction }

        case .complement(let expr):
            return expr.hasCardinalityRestriction

        case .someValuesFrom(_, let filler), .allValuesFrom(_, let filler):
            return filler.hasCardinalityRestriction

        case .minCardinality, .maxCardinality, .exactCardinality,
             .dataMinCardinality, .dataMaxCardinality, .dataExactCardinality:
            return true

        case .dataSomeValuesFrom, .dataAllValuesFrom:
            return false
        }
    }
}

// MARK: - CustomStringConvertible

extension OWLClassExpression: CustomStringConvertible {
    public var description: String {
        switch self {
        case .named(let iri):
            return iri

        case .thing:
            return "owl:Thing"

        case .nothing:
            return "owl:Nothing"

        case .intersection(let exprs):
            let strs = exprs.map { $0.description }
            return "(\(strs.joined(separator: " ⊓ ")))"

        case .union(let exprs):
            let strs = exprs.map { $0.description }
            return "(\(strs.joined(separator: " ⊔ ")))"

        case .complement(let expr):
            return "¬\(expr.description)"

        case .oneOf(let inds):
            return "{\(inds.joined(separator: ", "))}"

        case .someValuesFrom(let prop, let filler):
            return "∃\(prop).\(filler.description)"

        case .allValuesFrom(let prop, let filler):
            return "∀\(prop).\(filler.description)"

        case .hasValue(let prop, let ind):
            return "∃\(prop).{\(ind)}"

        case .hasSelf(let prop):
            return "∃\(prop).Self"

        case .minCardinality(let prop, let n, let filler):
            let fillerStr = filler.map { ".\($0.description)" } ?? ""
            return "≥\(n) \(prop)\(fillerStr)"

        case .maxCardinality(let prop, let n, let filler):
            let fillerStr = filler.map { ".\($0.description)" } ?? ""
            return "≤\(n) \(prop)\(fillerStr)"

        case .exactCardinality(let prop, let n, let filler):
            let fillerStr = filler.map { ".\($0.description)" } ?? ""
            return "=\(n) \(prop)\(fillerStr)"

        case .dataSomeValuesFrom(let prop, let range):
            return "∃\(prop).\(range.description)"

        case .dataAllValuesFrom(let prop, let range):
            return "∀\(prop).\(range.description)"

        case .dataHasValue(let prop, let literal):
            return "∃\(prop).{\(literal.description)}"

        case .dataMinCardinality(let prop, let n, let range):
            let rangeStr = range.map { ".\($0.description)" } ?? ""
            return "≥\(n) \(prop)\(rangeStr)"

        case .dataMaxCardinality(let prop, let n, let range):
            let rangeStr = range.map { ".\($0.description)" } ?? ""
            return "≤\(n) \(prop)\(rangeStr)"

        case .dataExactCardinality(let prop, let n, let range):
            let rangeStr = range.map { ".\($0.description)" } ?? ""
            return "=\(n) \(prop)\(rangeStr)"
        }
    }
}

// MARK: - Canonicalization

extension OWLClassExpression {
    /// Canonical form for stable hashing and cache key identity
    ///
    /// Normalizes intersection/union operands by sorting them, ensuring that
    /// `intersection([B, A])` and `intersection([A, B])` produce the same
    /// canonical form. Applied recursively to all sub-expressions.
    ///
    /// Reference: Baader et al., "The Description Logic Handbook", Section 2.2.3
    public func canonicalized() -> OWLClassExpression {
        switch self {
        case .named, .thing, .nothing, .oneOf, .hasValue, .hasSelf,
             .dataHasValue:
            return self

        case .intersection(let exprs):
            let sorted = exprs.map { $0.canonicalized() }.sorted(by: stableOrder)
            return .intersection(sorted)

        case .union(let exprs):
            let sorted = exprs.map { $0.canonicalized() }.sorted(by: stableOrder)
            return .union(sorted)

        case .complement(let expr):
            return .complement(expr.canonicalized())

        case .someValuesFrom(let prop, let filler):
            return .someValuesFrom(property: prop, filler: filler.canonicalized())

        case .allValuesFrom(let prop, let filler):
            return .allValuesFrom(property: prop, filler: filler.canonicalized())

        case .minCardinality(let prop, let n, let filler):
            return .minCardinality(property: prop, n: n, filler: filler?.canonicalized())

        case .maxCardinality(let prop, let n, let filler):
            return .maxCardinality(property: prop, n: n, filler: filler?.canonicalized())

        case .exactCardinality(let prop, let n, let filler):
            return .exactCardinality(property: prop, n: n, filler: filler?.canonicalized())

        case .dataSomeValuesFrom, .dataAllValuesFrom,
             .dataMinCardinality, .dataMaxCardinality, .dataExactCardinality:
            return self
        }
    }
}

/// Stable ordering for OWLClassExpression using structural comparison
///
/// Uses a tag + description approach for deterministic ordering
/// without requiring Comparable conformance on the enum.
private func stableOrder(_ lhs: OWLClassExpression, _ rhs: OWLClassExpression) -> Bool {
    let lhsTag = expressionTag(lhs)
    let rhsTag = expressionTag(rhs)
    if lhsTag != rhsTag { return lhsTag < rhsTag }
    return lhs.description < rhs.description
}

/// Assign a numeric tag to each expression variant for fast ordering
private func expressionTag(_ expr: OWLClassExpression) -> Int {
    switch expr {
    case .nothing: return 0
    case .thing: return 1
    case .named: return 2
    case .complement: return 3
    case .intersection: return 4
    case .union: return 5
    case .oneOf: return 6
    case .someValuesFrom: return 7
    case .allValuesFrom: return 8
    case .hasValue: return 9
    case .hasSelf: return 10
    case .minCardinality: return 11
    case .maxCardinality: return 12
    case .exactCardinality: return 13
    case .dataSomeValuesFrom: return 14
    case .dataAllValuesFrom: return 15
    case .dataHasValue: return 16
    case .dataMinCardinality: return 17
    case .dataMaxCardinality: return 18
    case .dataExactCardinality: return 19
    }
}

// MARK: - CustomStringConvertible for OWLClass

extension OWLClass: CustomStringConvertible {
    public var description: String {
        if let label = label {
            return "\(label) (\(iri))"
        }
        return iri
    }
}
