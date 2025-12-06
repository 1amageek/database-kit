// OWLAxiom.swift
// Graph - OWL DL axiom definitions
//
// Provides axiom types for OWL DL ontologies (SHOIN(D)).
// Covers TBox (terminology), RBox (roles), and ABox (assertions).
//
// Reference: W3C OWL 2 Web Ontology Language
// https://www.w3.org/TR/owl2-syntax/#Axioms

import Foundation

/// OWL Axiom
///
/// Represents statements (facts) in an OWL ontology.
/// Divided into three categories:
/// - **TBox**: Terminological axioms about classes
/// - **RBox**: Role axioms about properties
/// - **ABox**: Assertional axioms about individuals
///
/// **Example**:
/// ```swift
/// // TBox: Employee ⊑ Person
/// let subClassAxiom = OWLAxiom.subClassOf(
///     sub: .named("ex:Employee"),
///     sup: .named("ex:Person")
/// )
///
/// // RBox: hasChild⁻ ≡ hasParent
/// let inverseAxiom = OWLAxiom.inverseObjectProperties(
///     first: "ex:hasChild",
///     second: "ex:hasParent"
/// )
///
/// // ABox: Alice : Person
/// let classAssertion = OWLAxiom.classAssertion(
///     individual: "ex:Alice",
///     class_: .named("ex:Person")
/// )
/// ```
public enum OWLAxiom: Sendable, Codable, Hashable {

    // ========================================
    // MARK: - TBox Axioms (Class Relations)
    // ========================================

    /// Subclass axiom: C ⊑ D
    ///
    /// States that every instance of `sub` is also an instance of `sup`.
    case subClassOf(sub: OWLClassExpression, sup: OWLClassExpression)

    /// Equivalent classes: C ≡ D
    ///
    /// States that all listed classes have exactly the same instances.
    case equivalentClasses([OWLClassExpression])

    /// Disjoint classes: disjoint(C, D, ...)
    ///
    /// States that the listed classes have no common instances.
    case disjointClasses([OWLClassExpression])

    /// Disjoint union: C ≡ D₁ ⊔ D₂ ⊔ ... and disjoint(D₁, D₂, ...)
    ///
    /// States that `class_` is equivalent to the union of disjuncts,
    /// and the disjuncts are pairwise disjoint.
    case disjointUnion(class_: String, disjuncts: [OWLClassExpression])

    // ========================================
    // MARK: - RBox Axioms (Property Relations)
    // ========================================

    // --- Object Property Axioms ---

    /// Sub-property: R ⊑ S
    ///
    /// States that every pair related by `sub` is also related by `sup`.
    case subObjectPropertyOf(sub: String, sup: String)

    /// Property chain: R₁ ∘ R₂ ∘ ... ∘ Rₙ ⊑ S
    ///
    /// States that the composition of properties in `chain` implies `sup`.
    /// Example: hasParent ∘ hasBrother ⊑ hasUncle
    case subPropertyChainOf(chain: [String], sup: String)

    /// Equivalent properties: R ≡ S
    case equivalentObjectProperties([String])

    /// Disjoint properties: disjoint(R, S, ...)
    case disjointObjectProperties([String])

    /// Inverse properties: R⁻ ≡ S
    case inverseObjectProperties(first: String, second: String)

    /// Property domain: domain(R) = C
    ///
    /// States that individuals with property R are instances of class C.
    case objectPropertyDomain(property: String, domain: OWLClassExpression)

    /// Property range: range(R) = C
    ///
    /// States that values of property R are instances of class C.
    case objectPropertyRange(property: String, range: OWLClassExpression)

    // --- Object Property Characteristics ---

    /// Functional property: R(x,y) ∧ R(x,z) → y=z
    case functionalObjectProperty(String)

    /// Inverse functional: R(x,z) ∧ R(y,z) → x=y
    case inverseFunctionalObjectProperty(String)

    /// Transitive: R(x,y) ∧ R(y,z) → R(x,z)
    case transitiveObjectProperty(String)

    /// Symmetric: R(x,y) → R(y,x)
    case symmetricObjectProperty(String)

    /// Asymmetric: R(x,y) → ¬R(y,x)
    case asymmetricObjectProperty(String)

    /// Reflexive: ∀x. R(x,x)
    case reflexiveObjectProperty(String)

    /// Irreflexive: ∀x. ¬R(x,x)
    case irreflexiveObjectProperty(String)

    // --- Data Property Axioms ---

    /// Sub-property for data properties
    case subDataPropertyOf(sub: String, sup: String)

    /// Equivalent data properties
    case equivalentDataProperties([String])

    /// Disjoint data properties
    case disjointDataProperties([String])

    /// Data property domain
    case dataPropertyDomain(property: String, domain: OWLClassExpression)

    /// Data property range
    case dataPropertyRange(property: String, range: OWLDataRange)

    /// Functional data property
    case functionalDataProperty(String)

    // ========================================
    // MARK: - ABox Axioms (Individual Assertions)
    // ========================================

    /// Class assertion: a : C
    ///
    /// States that individual `individual` is an instance of class `class_`.
    case classAssertion(individual: String, class_: OWLClassExpression)

    /// Object property assertion: R(a, b)
    ///
    /// States that `subject` is related to `object` by property `property`.
    case objectPropertyAssertion(subject: String, property: String, object: String)

    /// Negative object property assertion: ¬R(a, b)
    ///
    /// States that `subject` is NOT related to `object` by property `property`.
    case negativeObjectPropertyAssertion(subject: String, property: String, object: String)

    /// Data property assertion: T(a, v)
    ///
    /// States that `subject` has data value `value` for property `property`.
    case dataPropertyAssertion(subject: String, property: String, value: OWLLiteral)

    /// Negative data property assertion: ¬T(a, v)
    ///
    /// States that `subject` does NOT have data value `value` for property `property`.
    case negativeDataPropertyAssertion(subject: String, property: String, value: OWLLiteral)

    /// Same individual assertion: a = b = ...
    ///
    /// States that all listed individuals refer to the same entity.
    case sameIndividual([String])

    /// Different individuals assertion: a ≠ b ≠ ...
    ///
    /// States that all listed individuals are pairwise distinct.
    case differentIndividuals([String])

    // ========================================
    // MARK: - Declaration Axioms
    // ========================================

    /// Class declaration
    case declareClass(String)

    /// Object property declaration
    case declareObjectProperty(String)

    /// Data property declaration
    case declareDataProperty(String)

    /// Named individual declaration
    case declareNamedIndividual(String)

    /// Datatype declaration
    case declareDatatype(String)

    /// Annotation property declaration
    case declareAnnotationProperty(String)
}

// MARK: - Axiom Classification

extension OWLAxiom {
    /// Check if this is a TBox (terminological) axiom
    public var isTBoxAxiom: Bool {
        switch self {
        case .subClassOf, .equivalentClasses, .disjointClasses, .disjointUnion:
            return true
        default:
            return false
        }
    }

    /// Check if this is an RBox (role) axiom
    public var isRBoxAxiom: Bool {
        switch self {
        case .subObjectPropertyOf, .subPropertyChainOf, .equivalentObjectProperties,
             .disjointObjectProperties, .inverseObjectProperties,
             .objectPropertyDomain, .objectPropertyRange,
             .functionalObjectProperty, .inverseFunctionalObjectProperty,
             .transitiveObjectProperty, .symmetricObjectProperty,
             .asymmetricObjectProperty, .reflexiveObjectProperty, .irreflexiveObjectProperty,
             .subDataPropertyOf, .equivalentDataProperties, .disjointDataProperties,
             .dataPropertyDomain, .dataPropertyRange, .functionalDataProperty:
            return true
        default:
            return false
        }
    }

    /// Check if this is an ABox (assertional) axiom
    public var isABoxAxiom: Bool {
        switch self {
        case .classAssertion, .objectPropertyAssertion, .negativeObjectPropertyAssertion,
             .dataPropertyAssertion, .negativeDataPropertyAssertion,
             .sameIndividual, .differentIndividuals:
            return true
        default:
            return false
        }
    }

    /// Check if this is a declaration axiom
    public var isDeclarationAxiom: Bool {
        switch self {
        case .declareClass, .declareObjectProperty, .declareDataProperty,
             .declareNamedIndividual, .declareDatatype, .declareAnnotationProperty:
            return true
        default:
            return false
        }
    }
}

// MARK: - Entity Extraction

extension OWLAxiom {
    /// Get all class IRIs referenced in this axiom
    public var referencedClasses: Set<String> {
        switch self {
        case .subClassOf(let sub, let sup):
            return sub.usedClasses.union(sup.usedClasses)

        case .equivalentClasses(let exprs), .disjointClasses(let exprs):
            return exprs.reduce(into: Set<String>()) { $0.formUnion($1.usedClasses) }

        case .disjointUnion(let cls, let disjuncts):
            var result: Set<String> = [cls]
            for d in disjuncts {
                result.formUnion(d.usedClasses)
            }
            return result

        case .objectPropertyDomain(_, let domain):
            return domain.usedClasses

        case .objectPropertyRange(_, let range):
            return range.usedClasses

        case .dataPropertyDomain(_, let domain):
            return domain.usedClasses

        case .classAssertion(_, let class_):
            return class_.usedClasses

        case .declareClass(let iri):
            return [iri]

        default:
            return []
        }
    }

    /// Get all object property IRIs referenced in this axiom
    public var referencedObjectProperties: Set<String> {
        switch self {
        case .subClassOf(let sub, let sup):
            return sub.usedObjectProperties.union(sup.usedObjectProperties)

        case .equivalentClasses(let exprs), .disjointClasses(let exprs):
            return exprs.reduce(into: Set<String>()) { $0.formUnion($1.usedObjectProperties) }

        case .disjointUnion(_, let disjuncts):
            return disjuncts.reduce(into: Set<String>()) { $0.formUnion($1.usedObjectProperties) }

        case .subObjectPropertyOf(let sub, let sup):
            return [sub, sup]

        case .subPropertyChainOf(let chain, let sup):
            return Set(chain).union([sup])

        case .equivalentObjectProperties(let props), .disjointObjectProperties(let props):
            return Set(props)

        case .inverseObjectProperties(let first, let second):
            return [first, second]

        case .objectPropertyDomain(let prop, let domain):
            return Set([prop]).union(domain.usedObjectProperties)

        case .objectPropertyRange(let prop, let range):
            return Set([prop]).union(range.usedObjectProperties)

        case .functionalObjectProperty(let prop),
             .inverseFunctionalObjectProperty(let prop),
             .transitiveObjectProperty(let prop),
             .symmetricObjectProperty(let prop),
             .asymmetricObjectProperty(let prop),
             .reflexiveObjectProperty(let prop),
             .irreflexiveObjectProperty(let prop):
            return [prop]

        case .objectPropertyAssertion(_, let prop, _),
             .negativeObjectPropertyAssertion(_, let prop, _):
            return [prop]

        case .classAssertion(_, let class_):
            return class_.usedObjectProperties

        case .declareObjectProperty(let iri):
            return [iri]

        default:
            return []
        }
    }

    /// Get all data property IRIs referenced in this axiom
    public var referencedDataProperties: Set<String> {
        switch self {
        case .subClassOf(let sub, let sup):
            return sub.usedDataProperties.union(sup.usedDataProperties)

        case .equivalentClasses(let exprs), .disjointClasses(let exprs):
            return exprs.reduce(into: Set<String>()) { $0.formUnion($1.usedDataProperties) }

        case .disjointUnion(_, let disjuncts):
            return disjuncts.reduce(into: Set<String>()) { $0.formUnion($1.usedDataProperties) }

        case .subDataPropertyOf(let sub, let sup):
            return [sub, sup]

        case .equivalentDataProperties(let props), .disjointDataProperties(let props):
            return Set(props)

        case .dataPropertyDomain(let prop, _), .dataPropertyRange(let prop, _),
             .functionalDataProperty(let prop):
            return [prop]

        case .dataPropertyAssertion(_, let prop, _),
             .negativeDataPropertyAssertion(_, let prop, _):
            return [prop]

        case .classAssertion(_, let class_):
            return class_.usedDataProperties

        case .declareDataProperty(let iri):
            return [iri]

        default:
            return []
        }
    }

    /// Get all individual IRIs referenced in this axiom
    public var referencedIndividuals: Set<String> {
        switch self {
        case .subClassOf(let sub, let sup):
            return sub.usedIndividuals.union(sup.usedIndividuals)

        case .equivalentClasses(let exprs), .disjointClasses(let exprs):
            return exprs.reduce(into: Set<String>()) { $0.formUnion($1.usedIndividuals) }

        case .disjointUnion(_, let disjuncts):
            return disjuncts.reduce(into: Set<String>()) { $0.formUnion($1.usedIndividuals) }

        case .classAssertion(let ind, let class_):
            return Set([ind]).union(class_.usedIndividuals)

        case .objectPropertyAssertion(let subj, _, let obj),
             .negativeObjectPropertyAssertion(let subj, _, let obj):
            return [subj, obj]

        case .dataPropertyAssertion(let subj, _, _),
             .negativeDataPropertyAssertion(let subj, _, _):
            return [subj]

        case .sameIndividual(let inds), .differentIndividuals(let inds):
            return Set(inds)

        case .declareNamedIndividual(let iri):
            return [iri]

        default:
            return []
        }
    }
}

// MARK: - CustomStringConvertible

extension OWLAxiom: CustomStringConvertible {
    public var description: String {
        switch self {
        // TBox
        case .subClassOf(let sub, let sup):
            return "SubClassOf(\(sub.description) \(sup.description))"

        case .equivalentClasses(let exprs):
            let strs = exprs.map { $0.description }
            return "EquivalentClasses(\(strs.joined(separator: " ")))"

        case .disjointClasses(let exprs):
            let strs = exprs.map { $0.description }
            return "DisjointClasses(\(strs.joined(separator: " ")))"

        case .disjointUnion(let cls, let disjuncts):
            let strs = disjuncts.map { $0.description }
            return "DisjointUnion(\(cls) \(strs.joined(separator: " ")))"

        // RBox - Object Properties
        case .subObjectPropertyOf(let sub, let sup):
            return "SubObjectPropertyOf(\(sub) \(sup))"

        case .subPropertyChainOf(let chain, let sup):
            return "SubPropertyChainOf(\(chain.joined(separator: " ∘ ")) \(sup))"

        case .equivalentObjectProperties(let props):
            return "EquivalentObjectProperties(\(props.joined(separator: " ")))"

        case .disjointObjectProperties(let props):
            return "DisjointObjectProperties(\(props.joined(separator: " ")))"

        case .inverseObjectProperties(let first, let second):
            return "InverseObjectProperties(\(first) \(second))"

        case .objectPropertyDomain(let prop, let domain):
            return "ObjectPropertyDomain(\(prop) \(domain.description))"

        case .objectPropertyRange(let prop, let range):
            return "ObjectPropertyRange(\(prop) \(range.description))"

        case .functionalObjectProperty(let prop):
            return "FunctionalObjectProperty(\(prop))"

        case .inverseFunctionalObjectProperty(let prop):
            return "InverseFunctionalObjectProperty(\(prop))"

        case .transitiveObjectProperty(let prop):
            return "TransitiveObjectProperty(\(prop))"

        case .symmetricObjectProperty(let prop):
            return "SymmetricObjectProperty(\(prop))"

        case .asymmetricObjectProperty(let prop):
            return "AsymmetricObjectProperty(\(prop))"

        case .reflexiveObjectProperty(let prop):
            return "ReflexiveObjectProperty(\(prop))"

        case .irreflexiveObjectProperty(let prop):
            return "IrreflexiveObjectProperty(\(prop))"

        // RBox - Data Properties
        case .subDataPropertyOf(let sub, let sup):
            return "SubDataPropertyOf(\(sub) \(sup))"

        case .equivalentDataProperties(let props):
            return "EquivalentDataProperties(\(props.joined(separator: " ")))"

        case .disjointDataProperties(let props):
            return "DisjointDataProperties(\(props.joined(separator: " ")))"

        case .dataPropertyDomain(let prop, let domain):
            return "DataPropertyDomain(\(prop) \(domain.description))"

        case .dataPropertyRange(let prop, let range):
            return "DataPropertyRange(\(prop) \(range.description))"

        case .functionalDataProperty(let prop):
            return "FunctionalDataProperty(\(prop))"

        // ABox
        case .classAssertion(let ind, let class_):
            return "ClassAssertion(\(class_.description) \(ind))"

        case .objectPropertyAssertion(let subj, let prop, let obj):
            return "ObjectPropertyAssertion(\(prop) \(subj) \(obj))"

        case .negativeObjectPropertyAssertion(let subj, let prop, let obj):
            return "NegativeObjectPropertyAssertion(\(prop) \(subj) \(obj))"

        case .dataPropertyAssertion(let subj, let prop, let value):
            return "DataPropertyAssertion(\(prop) \(subj) \(value.description))"

        case .negativeDataPropertyAssertion(let subj, let prop, let value):
            return "NegativeDataPropertyAssertion(\(prop) \(subj) \(value.description))"

        case .sameIndividual(let inds):
            return "SameIndividual(\(inds.joined(separator: " ")))"

        case .differentIndividuals(let inds):
            return "DifferentIndividuals(\(inds.joined(separator: " ")))"

        // Declarations
        case .declareClass(let iri):
            return "Declaration(Class(\(iri)))"

        case .declareObjectProperty(let iri):
            return "Declaration(ObjectProperty(\(iri)))"

        case .declareDataProperty(let iri):
            return "Declaration(DataProperty(\(iri)))"

        case .declareNamedIndividual(let iri):
            return "Declaration(NamedIndividual(\(iri)))"

        case .declareDatatype(let iri):
            return "Declaration(Datatype(\(iri)))"

        case .declareAnnotationProperty(let iri):
            return "Declaration(AnnotationProperty(\(iri)))"
        }
    }
}

// MARK: - Convenience Constructors

extension OWLAxiom {
    /// Create a simple subclass axiom between named classes
    public static func simpleSubClassOf(sub: String, sup: String) -> OWLAxiom {
        .subClassOf(sub: .named(sub), sup: .named(sup))
    }

    /// Create an equivalence between named classes
    public static func simpleEquivalent(_ classes: String...) -> OWLAxiom {
        .equivalentClasses(classes.map { .named($0) })
    }

    /// Create a disjoint axiom between named classes
    public static func simpleDisjoint(_ classes: String...) -> OWLAxiom {
        .disjointClasses(classes.map { .named($0) })
    }

    /// Create a type assertion (individual is instance of named class)
    public static func typeAssertion(individual: String, type: String) -> OWLAxiom {
        .classAssertion(individual: individual, class_: .named(type))
    }
}
