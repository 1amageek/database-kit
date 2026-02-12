import Testing
import Foundation
@testable import Graph

@Suite("Turtle Round-trip")
struct TurtleRoundTripTests {

    @Test("Simple class round-trips")
    func encodeDecodeSimple() throws {
        let original = OWLOntology(
            iri: "http://test.org/",
            prefixes: ["ex": "http://example.org/"]
        ) {
            OWLClass(iri: "ex:Person", label: "Person")
        }

        let turtle = TurtleEncoder().encode(original)
        let decoded = try TurtleDecoder().decode(from: turtle)

        #expect(decoded.classes.count == original.classes.count)
        #expect(decoded.classes.first?.iri == "ex:Person")
        #expect(decoded.classes.first?.label == "Person")
    }

    @Test("Class hierarchy round-trips")
    func encodeDecodeClassHierarchy() throws {
        let original = OWLOntology(
            iri: "http://test.org/",
            prefixes: ["ex": "http://example.org/"]
        ) {
            OWLClass(iri: "ex:Animal", label: "Animal")
            OWLClass(iri: "ex:Dog", label: "Dog")
            OWLClass(iri: "ex:Cat", label: "Cat")
            OWLAxiom.subClassOf(sub: .named("ex:Dog"), sup: .named("ex:Animal"))
            OWLAxiom.subClassOf(sub: .named("ex:Cat"), sup: .named("ex:Animal"))
        }

        let turtle = TurtleEncoder().encode(original)
        let decoded = try TurtleDecoder().decode(from: turtle)

        #expect(decoded.classes.count == 3)
        let subClassAxioms = decoded.axioms.filter {
            if case .subClassOf = $0 { return true }
            return false
        }
        #expect(subClassAxioms.count == 2)
    }

    @Test("Properties with characteristics round-trip")
    func encodeDecodeProperties() throws {
        let original = OWLOntology(
            iri: "http://test.org/",
            prefixes: ["ex": "http://example.org/"]
        ) {
            OWLObjectProperty(
                iri: "ex:partOf",
                label: "part of",
                characteristics: [.transitive],
                inverseOf: "ex:hasPart",
                domains: [.named("ex:Thing")]
            )
            OWLDataProperty(
                iri: "ex:name",
                domains: [.named("ex:Thing")],
                ranges: [.datatype("xsd:string")]
            )
        }

        let turtle = TurtleEncoder().encode(original)
        let decoded = try TurtleDecoder().decode(from: turtle)

        #expect(decoded.objectProperties.count == 1)
        #expect(decoded.objectProperties.first?.characteristics.contains(.transitive) == true)
        #expect(decoded.objectProperties.first?.inverseOf == "ex:hasPart")
        #expect(decoded.dataProperties.count == 1)
    }

    @Test("Disjoint classes round-trip")
    func encodeDecodeDisjoint() throws {
        let original = OWLOntology(
            iri: "http://test.org/",
            prefixes: ["ex": "http://example.org/"]
        ) {
            OWLClass(iri: "ex:Person")
            OWLClass(iri: "ex:Organization")
            OWLClass(iri: "ex:Place")
            OWLAxiom.disjointClasses([.named("ex:Person"), .named("ex:Organization")])
            OWLAxiom.disjointClasses([.named("ex:Person"), .named("ex:Place")])
        }

        let turtle = TurtleEncoder().encode(original)
        let decoded = try TurtleDecoder().decode(from: turtle)

        let disjointAxioms = decoded.axioms.filter {
            if case .disjointClasses = $0 { return true }
            return false
        }
        #expect(disjointAxioms.count == 2)
    }

    @Test("Restriction expressions round-trip")
    func encodeDecodeRestrictions() throws {
        let original = OWLOntology(
            iri: "http://test.org/",
            prefixes: ["ex": "http://example.org/"]
        ) {
            OWLClass(iri: "ex:Parent")
            OWLAxiom.subClassOf(
                sub: .named("ex:Parent"),
                sup: .someValuesFrom(property: "ex:hasChild", filler: .named("ex:Person"))
            )
            OWLAxiom.subClassOf(
                sub: .named("ex:Parent"),
                sup: .minCardinality(property: "ex:hasChild", n: 1, filler: nil)
            )
        }

        let turtle = TurtleEncoder().encode(original)
        let decoded = try TurtleDecoder().decode(from: turtle)

        let subClassAxioms = decoded.axioms.compactMap { axiom -> OWLClassExpression? in
            if case .subClassOf(_, let sup) = axiom { return sup }
            return nil
        }

        let hasSome = subClassAxioms.contains {
            if case .someValuesFrom = $0 { return true }
            return false
        }
        let hasMinCard = subClassAxioms.contains {
            if case .minCardinality = $0 { return true }
            return false
        }

        #expect(hasSome)
        #expect(hasMinCard)
    }

    @Test("Individuals with assertions round-trip")
    func encodeDecodeIndividuals() throws {
        let original = OWLOntology(
            iri: "http://test.org/",
            prefixes: ["ex": "http://example.org/"]
        ) {
            OWLNamedIndividual(iri: "ex:Alice", label: "Alice")
            OWLAxiom.classAssertion(individual: "ex:Alice", class_: .named("ex:Person"))
            OWLAxiom.objectPropertyAssertion(subject: "ex:Alice", property: "ex:knows", object: "ex:Bob")
            OWLAxiom.dataPropertyAssertion(subject: "ex:Alice", property: "ex:age", value: .integer(30))
        }

        let turtle = TurtleEncoder().encode(original)
        let decoded = try TurtleDecoder().decode(from: turtle)

        #expect(decoded.individuals.count == 1)
        #expect(decoded.individuals.first?.label == "Alice")

        let classAssertions = decoded.axioms.filter {
            if case .classAssertion = $0 { return true }
            return false
        }
        let objAssertions = decoded.axioms.filter {
            if case .objectPropertyAssertion = $0 { return true }
            return false
        }
        let dataAssertions = decoded.axioms.filter {
            if case .dataPropertyAssertion = $0 { return true }
            return false
        }
        #expect(classAssertions.count == 1)
        #expect(objAssertions.count == 1)
        #expect(dataAssertions.count == 1)
    }

    @Test("Literals preserve type information through round-trip")
    func encodeDecodeLiterals() throws {
        let original = OWLOntology(
            iri: "http://test.org/",
            prefixes: ["ex": "http://example.org/"]
        ) {
            OWLNamedIndividual(iri: "ex:X")
            OWLAxiom.dataPropertyAssertion(subject: "ex:X", property: "ex:name", value: .string("test"))
            OWLAxiom.dataPropertyAssertion(subject: "ex:X", property: "ex:count", value: .integer(42))
            OWLAxiom.dataPropertyAssertion(subject: "ex:X", property: "ex:active", value: .boolean(true))
        }

        let turtle = TurtleEncoder().encode(original)
        let decoded = try TurtleDecoder().decode(from: turtle)

        let literals = decoded.axioms.compactMap { axiom -> OWLLiteral? in
            if case .dataPropertyAssertion(_, _, let value) = axiom { return value }
            return nil
        }
        #expect(literals.count == 3)
        #expect(literals.contains { $0.lexicalForm == "test" })
        #expect(literals.contains { $0.intValue == 42 })
        #expect(literals.contains { $0.boolValue == true })
    }

    @Test("Full ontology with all element types round-trips")
    func encodeDecodeFullOntology() throws {
        let original = OWLOntology(
            iri: "http://test.org/",
            prefixes: ["ex": "http://example.org/"]
        ) {
            // Classes
            OWLClass(iri: "ex:Person", label: "Person")
            OWLClass(iri: "ex:Organization", label: "Organization")
            OWLClass(iri: "ex:Event", label: "Event")

            // Class axioms
            OWLAxiom.subClassOf(sub: .named("ex:Person"), sup: .thing)
            OWLAxiom.disjointClasses([.named("ex:Person"), .named("ex:Organization")])

            // Object properties
            OWLObjectProperty(
                iri: "ex:knows",
                label: "knows",
                characteristics: [.symmetric],
                domains: [.named("ex:Person")],
                ranges: [.named("ex:Person")]
            )

            // Data properties
            OWLDataProperty(
                iri: "ex:name",
                label: "name",
                domains: [.named("ex:Person")],
                ranges: [.datatype("xsd:string")]
            )

            // Individuals
            OWLNamedIndividual(iri: "ex:Alice", label: "Alice")
            OWLAxiom.classAssertion(individual: "ex:Alice", class_: .named("ex:Person"))
            OWLAxiom.dataPropertyAssertion(subject: "ex:Alice", property: "ex:name", value: .string("Alice"))
        }

        let turtle = TurtleEncoder().encode(original)
        let decoded = try TurtleDecoder().decode(from: turtle)

        #expect(decoded.classes.count == original.classes.count)
        #expect(decoded.objectProperties.count == original.objectProperties.count)
        #expect(decoded.dataProperties.count == original.dataProperties.count)
        #expect(decoded.individuals.count == original.individuals.count)

        // Verify class names preserved
        let classIRIs = Set(decoded.classes.map { $0.iri })
        #expect(classIRIs.contains("ex:Person"))
        #expect(classIRIs.contains("ex:Organization"))
        #expect(classIRIs.contains("ex:Event"))

        // Verify labels preserved
        #expect(decoded.classes.first { $0.iri == "ex:Person" }?.label == "Person")
        #expect(decoded.objectProperties.first?.label == "knows")
    }
}
