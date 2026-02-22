// OntologyIndex.swift
// Graph - O(1) axiom lookup index for OWL ontologies
//
// Provides pre-computed index structures for efficient axiom access.
// OWLOntology is a Sendable/Codable/Hashable struct, so this index
// is built separately and cached by the caller.
//
// Reference: Baader, F., et al. (2003).
// "The Description Logic Handbook: Theory, Implementation, and Applications."

import Foundation

/// Pre-computed index for O(1) axiom lookup
///
/// Built from an `OWLOntology` in a single O(|axioms|) pass.
/// Replaces repeated O(n) linear scans with dictionary lookups.
///
/// **Usage**:
/// ```swift
/// let index = OntologyIndex(ontology: ontology)
/// let superAxioms = index.subClassAxiomsBySubClass["ex:Employee"] ?? []
/// let types = index.classAssertionsByIndividual["ex:Alice"] ?? []
/// ```
public struct OntologyIndex: Sendable {

    // MARK: - TBox Indices

    /// SubClassOf axioms indexed by sub-class IRI
    /// Key: sub-class IRI, Value: array of (sub, sup) pairs
    public let subClassAxiomsBySubClass: [String: [(sub: OWLClassExpression, sup: OWLClassExpression)]]

    /// SubClassOf axioms indexed by super-class IRI (for named super-classes)
    public let subClassAxiomsBySupClass: [String: [(sub: OWLClassExpression, sup: OWLClassExpression)]]

    /// EquivalentClasses axioms indexed by each participating named class
    public let equivalentClassAxiomsByClass: [String: [[OWLClassExpression]]]

    /// DisjointClasses axioms indexed by each participating named class
    public let disjointClassAxiomsByClass: [String: [[OWLClassExpression]]]

    /// DisjointUnion axioms indexed by the union class
    public let disjointUnionByClass: [String: [[OWLClassExpression]]]

    // MARK: - ABox Indices

    /// Class assertions indexed by individual IRI
    public let classAssertionsByIndividual: [String: [OWLClassExpression]]

    /// Object property assertions indexed by subject IRI
    public let objectPropertyAssertionsBySubject: [String: [(property: String, object: String)]]

    /// Object property assertions indexed by object IRI
    public let objectPropertyAssertionsByObject: [String: [(property: String, subject: String)]]

    /// Data property assertions indexed by subject IRI
    public let dataPropertyAssertionsBySubject: [String: [(property: String, value: OWLLiteral)]]

    /// SameIndividual assertions indexed by each individual
    public let sameIndividualsByIndividual: [String: [[String]]]

    /// DifferentIndividuals assertions indexed by each individual
    public let differentIndividualsByIndividual: [String: [[String]]]

    /// Negative object property assertions indexed by subject IRI
    public let negativeObjectPropertyAssertionsBySubject: [String: [(property: String, object: String)]]

    /// Negative data property assertions indexed by subject IRI
    public let negativeDataPropertyAssertionsBySubject: [String: [(property: String, value: OWLLiteral)]]

    // MARK: - RBox Indices

    /// SubObjectPropertyOf axioms indexed by sub-property
    public let subPropertyAxiomsBySub: [String: [String]]

    /// SubObjectPropertyOf axioms indexed by super-property
    public let subPropertyAxiomsBySup: [String: [String]]

    /// PropertyChain axioms indexed by super-property
    public let propertyChainAxiomsBySup: [String: [[String]]]

    /// InverseObjectProperties indexed by each property
    public let inverseProperties: [String: String]

    // MARK: - Signature Caches

    /// All class IRIs in the ontology signature
    public let classSignature: Set<String>

    /// All object property IRIs in the ontology signature
    public let objectPropertySignature: Set<String>

    /// All data property IRIs in the ontology signature
    public let dataPropertySignature: Set<String>

    /// All individual IRIs in the ontology signature
    public let individualSignature: Set<String>

    // MARK: - Pre-split Axiom Arrays

    /// TBox axioms only
    public let tboxAxioms: [OWLAxiom]

    /// RBox axioms only
    public let rboxAxioms: [OWLAxiom]

    /// ABox axioms only
    public let aboxAxioms: [OWLAxiom]

    // MARK: - Object Property Assertions (flat)

    /// All object property assertions as flat array for property-based lookup
    public let allObjectPropertyAssertions: [(subject: String, property: String, object: String)]

    // MARK: - Initialization

    /// Build all indices in a single O(|axioms|) pass
    ///
    /// - Parameter ontology: The ontology to index
    public init(ontology: OWLOntology) {
        // Temporary mutable builders
        var subClassBySub: [String: [(sub: OWLClassExpression, sup: OWLClassExpression)]] = [:]
        var subClassBySup: [String: [(sub: OWLClassExpression, sup: OWLClassExpression)]] = [:]
        var equivByClass: [String: [[OWLClassExpression]]] = [:]
        var disjointByClass: [String: [[OWLClassExpression]]] = [:]
        var disjointUnion: [String: [[OWLClassExpression]]] = [:]

        var classAssertions: [String: [OWLClassExpression]] = [:]
        var objPropBySubject: [String: [(property: String, object: String)]] = [:]
        var objPropByObject: [String: [(property: String, subject: String)]] = [:]
        var dataPropBySubject: [String: [(property: String, value: OWLLiteral)]] = [:]
        var sameIndividuals: [String: [[String]]] = [:]
        var diffIndividuals: [String: [[String]]] = [:]
        var negObjPropBySubject: [String: [(property: String, object: String)]] = [:]
        var negDataPropBySubject: [String: [(property: String, value: OWLLiteral)]] = [:]

        var subPropBySub: [String: [String]] = [:]
        var subPropBySup: [String: [String]] = [:]
        var propChainBySup: [String: [[String]]] = [:]
        var inverseProps: [String: String] = [:]

        var classSig = Set<String>(ontology.classes.map { $0.iri })
        var objPropSig = Set<String>(ontology.objectProperties.map { $0.iri })
        var dataPropSig = Set<String>(ontology.dataProperties.map { $0.iri })
        var indSig = Set<String>(ontology.individuals.map { $0.iri })

        var tbox: [OWLAxiom] = []
        var rbox: [OWLAxiom] = []
        var abox: [OWLAxiom] = []
        var allObjPropAssertions: [(subject: String, property: String, object: String)] = []

        for axiom in ontology.axioms {
            // Classify axiom
            if axiom.isTBoxAxiom { tbox.append(axiom) }
            if axiom.isRBoxAxiom { rbox.append(axiom) }
            if axiom.isABoxAxiom { abox.append(axiom) }

            // Collect signature
            classSig.formUnion(axiom.referencedClasses)
            objPropSig.formUnion(axiom.referencedObjectProperties)
            dataPropSig.formUnion(axiom.referencedDataProperties)
            indSig.formUnion(axiom.referencedIndividuals)

            // Index by case
            switch axiom {
            case .subClassOf(let sub, let sup):
                let pair = (sub: sub, sup: sup)
                if case .named(let subIRI) = sub {
                    subClassBySub[subIRI, default: []].append(pair)
                }
                if case .named(let supIRI) = sup {
                    subClassBySup[supIRI, default: []].append(pair)
                }

            case .equivalentClasses(let exprs):
                for expr in exprs {
                    if case .named(let iri) = expr {
                        equivByClass[iri, default: []].append(exprs)
                    }
                }

            case .disjointClasses(let exprs):
                for expr in exprs {
                    if case .named(let iri) = expr {
                        disjointByClass[iri, default: []].append(exprs)
                    }
                }

            case .disjointUnion(let cls, let disjuncts):
                disjointUnion[cls, default: []].append(disjuncts)

            case .classAssertion(let individual, let classExpr):
                classAssertions[individual, default: []].append(classExpr)

            case .objectPropertyAssertion(let subject, let property, let object):
                objPropBySubject[subject, default: []].append((property: property, object: object))
                objPropByObject[object, default: []].append((property: property, subject: subject))
                allObjPropAssertions.append((subject: subject, property: property, object: object))

            case .dataPropertyAssertion(let subject, let property, let value):
                dataPropBySubject[subject, default: []].append((property: property, value: value))

            case .sameIndividual(let individuals):
                for ind in individuals {
                    sameIndividuals[ind, default: []].append(individuals)
                }

            case .differentIndividuals(let individuals):
                for ind in individuals {
                    diffIndividuals[ind, default: []].append(individuals)
                }

            case .subObjectPropertyOf(let sub, let sup):
                subPropBySub[sub, default: []].append(sup)
                subPropBySup[sup, default: []].append(sub)

            case .subPropertyChainOf(let chain, let sup):
                propChainBySup[sup, default: []].append(chain)

            case .inverseObjectProperties(let first, let second):
                inverseProps[first] = second
                inverseProps[second] = first

            case .negativeObjectPropertyAssertion(let subject, let property, let object):
                negObjPropBySubject[subject, default: []].append((property: property, object: object))

            case .negativeDataPropertyAssertion(let subject, let property, let value):
                negDataPropBySubject[subject, default: []].append((property: property, value: value))

            default:
                break
            }
        }

        // Also collect inverse from property declarations
        for prop in ontology.objectProperties {
            if let inv = prop.inverseOf {
                inverseProps[prop.iri] = inv
                inverseProps[inv] = prop.iri
            }
        }

        // Assign to stored properties
        self.subClassAxiomsBySubClass = subClassBySub
        self.subClassAxiomsBySupClass = subClassBySup
        self.equivalentClassAxiomsByClass = equivByClass
        self.disjointClassAxiomsByClass = disjointByClass
        self.disjointUnionByClass = disjointUnion

        self.classAssertionsByIndividual = classAssertions
        self.objectPropertyAssertionsBySubject = objPropBySubject
        self.objectPropertyAssertionsByObject = objPropByObject
        self.dataPropertyAssertionsBySubject = dataPropBySubject
        self.sameIndividualsByIndividual = sameIndividuals
        self.differentIndividualsByIndividual = diffIndividuals

        self.subPropertyAxiomsBySub = subPropBySub
        self.subPropertyAxiomsBySup = subPropBySup
        self.propertyChainAxiomsBySup = propChainBySup
        self.inverseProperties = inverseProps

        self.negativeObjectPropertyAssertionsBySubject = negObjPropBySubject
        self.negativeDataPropertyAssertionsBySubject = negDataPropBySubject

        self.classSignature = classSig
        self.objectPropertySignature = objPropSig
        self.dataPropertySignature = dataPropSig
        self.individualSignature = indSig

        self.tboxAxioms = tbox
        self.rboxAxioms = rbox
        self.aboxAxioms = abox
        self.allObjectPropertyAssertions = allObjPropAssertions
    }
}

// MARK: - OWLOntology Convenience

extension OWLOntology {
    /// Build a pre-computed index for O(1) axiom lookup
    ///
    /// - Returns: An `OntologyIndex` with all axioms indexed by relevant keys
    public func buildIndex() -> OntologyIndex {
        OntologyIndex(ontology: self)
    }
}
