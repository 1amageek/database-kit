// SHACLConstraint.swift
// Graph - SHACL constraint components
//
// Reference: W3C SHACL §4-§7 (Core Constraint Components)
// https://www.w3.org/TR/shacl/#core-components

import Foundation

/// SHACL Constraint Component
///
/// Defines a single constraint that value nodes must satisfy.
/// Covers all W3C SHACL Core constraint components (§4.1–§4.8).
///
/// **Example**:
/// ```swift
/// // Value must be of type xsd:string with min length 1
/// let constraints: [SHACLConstraint] = [
///     .datatype("xsd:string"),
///     .minLength(1),
///     .maxCount(1)
/// ]
/// ```
public indirect enum SHACLConstraint: Sendable, Codable, Hashable {

    // MARK: - §4.1 Value Type Constraints

    /// sh:class — each value node is a SHACL instance of the given class
    case class_(String)

    /// sh:datatype — each value node is a literal with the given datatype
    case datatype(String)

    /// sh:nodeKind — each value node matches the given node kind
    case nodeKind(SHACLNodeKind)

    // MARK: - §4.2 Cardinality Constraints

    /// sh:minCount — minimum number of value nodes
    case minCount(Int)

    /// sh:maxCount — maximum number of value nodes
    case maxCount(Int)

    // MARK: - §4.3 Value Range Constraints

    /// sh:minExclusive — each value node > the given value
    case minExclusive(RDFTerm)

    /// sh:maxExclusive — each value node < the given value
    case maxExclusive(RDFTerm)

    /// sh:minInclusive — each value node >= the given value
    case minInclusive(RDFTerm)

    /// sh:maxInclusive — each value node <= the given value
    case maxInclusive(RDFTerm)

    // MARK: - §4.4 String-based Constraints

    /// sh:minLength — string length >= the given value
    case minLength(Int)

    /// sh:maxLength — string length <= the given value
    case maxLength(Int)

    /// sh:pattern + sh:flags — string matches the given regex pattern
    case pattern(String, flags: String?)

    /// sh:languageIn — language tag is one of the given values
    case languageIn([String])

    /// sh:uniqueLang — no two values share the same language tag
    case uniqueLang

    // MARK: - §4.5 Property Pair Constraints

    /// sh:equals — value nodes equal those reachable via the given path
    case equals(SHACLPath)

    /// sh:disjoint — value nodes are disjoint from those reachable via the given path
    case disjoint(SHACLPath)

    /// sh:lessThan — each value node < corresponding values via the given path
    case lessThan(SHACLPath)

    /// sh:lessThanOrEquals — each value node <= corresponding values via the given path
    case lessThanOrEquals(SHACLPath)

    // MARK: - §4.6 Logical Constraints

    /// sh:not — value node does NOT conform to the given shape
    case not(SHACLShape)

    /// sh:and — value node conforms to ALL given shapes
    case and([SHACLShape])

    /// sh:or — value node conforms to at least one given shape
    case or([SHACLShape])

    /// sh:xone — value node conforms to exactly one given shape
    case xone([SHACLShape])

    // MARK: - §4.7 Shape-based Constraints

    /// sh:node — value node conforms to the given node shape
    case node(NodeShape)

    /// sh:qualifiedValueShape — qualified cardinality constraint
    case qualifiedValueShape(
        shape: SHACLShape,
        min: Int?,
        max: Int?
    )

    // MARK: - §4.8 Other Constraints

    /// sh:closed — only declared properties are allowed
    case closed(ignoredProperties: [String])

    /// sh:hasValue — the set of value nodes includes the given value
    case hasValue(RDFTerm)

    /// sh:in — each value node is a member of the given list
    case in_([RDFTerm])
}

// MARK: - SHACLNodeKind

/// SHACL Node Kind — categorizes RDF nodes
///
/// Reference: W3C SHACL §4.1.3
public enum SHACLNodeKind: String, Sendable, Codable, Hashable {
    case blankNode          = "sh:BlankNode"
    case iri                = "sh:IRI"
    case literal            = "sh:Literal"
    case blankNodeOrIRI     = "sh:BlankNodeOrIRI"
    case blankNodeOrLiteral = "sh:BlankNodeOrLiteral"
    case iriOrLiteral       = "sh:IRIOrLiteral"
}

// MARK: - SHACLSeverity

/// SHACL Severity — severity level of a validation result
///
/// Reference: W3C SHACL §2.1.5
public enum SHACLSeverity: String, Sendable, Codable, Hashable {
    /// Constraint violation (default severity)
    case violation = "sh:Violation"

    /// Warning (less severe than violation)
    case warning = "sh:Warning"

    /// Informational (least severe)
    case info = "sh:Info"
}


extension SHACLNodeKind: CustomStringConvertible {
    public var description: String { rawValue }
}

extension SHACLSeverity: CustomStringConvertible {
    public var description: String { rawValue }
}

// MARK: - Constraint Component IRI

extension SHACLConstraint {
    /// The W3C SHACL constraint component IRI
    ///
    /// Used in validation results as `sh:sourceConstraintComponent`.
    public var componentIRI: String {
        switch self {
        case .class_: return "sh:ClassConstraintComponent"
        case .datatype: return "sh:DatatypeConstraintComponent"
        case .nodeKind: return "sh:NodeKindConstraintComponent"
        case .minCount: return "sh:MinCountConstraintComponent"
        case .maxCount: return "sh:MaxCountConstraintComponent"
        case .minExclusive: return "sh:MinExclusiveConstraintComponent"
        case .maxExclusive: return "sh:MaxExclusiveConstraintComponent"
        case .minInclusive: return "sh:MinInclusiveConstraintComponent"
        case .maxInclusive: return "sh:MaxInclusiveConstraintComponent"
        case .minLength: return "sh:MinLengthConstraintComponent"
        case .maxLength: return "sh:MaxLengthConstraintComponent"
        case .pattern: return "sh:PatternConstraintComponent"
        case .languageIn: return "sh:LanguageInConstraintComponent"
        case .uniqueLang: return "sh:UniqueLangConstraintComponent"
        case .equals: return "sh:EqualsConstraintComponent"
        case .disjoint: return "sh:DisjointConstraintComponent"
        case .lessThan: return "sh:LessThanConstraintComponent"
        case .lessThanOrEquals: return "sh:LessThanOrEqualsConstraintComponent"
        case .not: return "sh:NotConstraintComponent"
        case .and: return "sh:AndConstraintComponent"
        case .or: return "sh:OrConstraintComponent"
        case .xone: return "sh:XoneConstraintComponent"
        case .node: return "sh:NodeConstraintComponent"
        case .qualifiedValueShape: return "sh:QualifiedValueShapeConstraintComponent"
        case .closed: return "sh:ClosedConstraintComponent"
        case .hasValue: return "sh:HasValueConstraintComponent"
        case .in_: return "sh:InConstraintComponent"
        }
    }
}
