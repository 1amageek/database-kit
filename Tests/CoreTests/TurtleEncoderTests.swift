import Testing
import Foundation
@testable import Graph

@Suite("TurtleEncoder")
struct TurtleEncoderTests {

    private func makeOntology(
        @OWLOntologyBuilder content: () -> [OWLOntologyComponent]
    ) -> OWLOntology {
        OWLOntology(
            iri: "http://test.org/",
            prefixes: ["ex": "http://example.org/"]
        ) {
            content()
        }
    }

    @Test("Empty ontology produces prefix declarations only")
    func emptyOntology() {
        let ont = OWLOntology(
            iri: "http://test.org/",
            prefixes: ["ex": "http://example.org/"]
        )
        let turtle = TurtleEncoder().encode(ont)
        #expect(turtle.contains("@prefix"))
        #expect(turtle.contains("owl:Ontology"))
    }

    @Test("Prefix declarations are rendered correctly")
    func prefixDeclarations() {
        let ont = OWLOntology(
            iri: "http://test.org/",
            prefixes: ["ex": "http://example.org/", "foaf": "http://xmlns.com/foaf/0.1/"]
        )
        let turtle = TurtleEncoder().encode(ont)
        #expect(turtle.contains("@prefix ex: <http://example.org/> ."))
        #expect(turtle.contains("@prefix foaf: <http://xmlns.com/foaf/0.1/> ."))
    }

    @Test("Single class is encoded")
    func singleClass() {
        let ont = makeOntology {
            OWLClass(iri: "ex:Person", label: "Person")
        }
        let turtle = TurtleEncoder().encode(ont)
        #expect(turtle.contains("ex:Person"))
        #expect(turtle.contains("owl:Class"))
        #expect(turtle.contains("\"Person\""))
    }

    @Test("SubClassOf axiom is encoded")
    func subClassOf() {
        let ont = makeOntology {
            OWLClass(iri: "ex:Parent")
            OWLClass(iri: "ex:Person")
            OWLAxiom.subClassOf(sub: .named("ex:Parent"), sup: .named("ex:Person"))
        }
        let turtle = TurtleEncoder().encode(ont)
        #expect(turtle.contains("rdfs:subClassOf"))
        #expect(turtle.contains("ex:Person"))
    }

    @Test("EquivalentClasses axiom is encoded")
    func equivalentClasses() {
        let ont = makeOntology {
            OWLClass(iri: "ex:A")
            OWLClass(iri: "ex:B")
            OWLAxiom.equivalentClasses([.named("ex:A"), .named("ex:B")])
        }
        let turtle = TurtleEncoder().encode(ont)
        #expect(turtle.contains("owl:equivalentClass"))
    }

    @Test("DisjointClasses axiom uses AllDisjointClasses")
    func disjointClasses() {
        let ont = makeOntology {
            OWLClass(iri: "ex:Person")
            OWLClass(iri: "ex:Organization")
            OWLAxiom.disjointClasses([.named("ex:Person"), .named("ex:Organization")])
        }
        let turtle = TurtleEncoder().encode(ont)
        #expect(turtle.contains("owl:AllDisjointClasses"))
        #expect(turtle.contains("owl:members"))
        #expect(turtle.contains("ex:Person"))
        #expect(turtle.contains("ex:Organization"))
    }

    @Test("Object property characteristics are encoded as types")
    func objectPropertyCharacteristics() {
        let ont = makeOntology {
            OWLObjectProperty(iri: "ex:partOf", label: "part of", characteristics: [.transitive])
        }
        let turtle = TurtleEncoder().encode(ont)
        #expect(turtle.contains("owl:ObjectProperty"))
        #expect(turtle.contains("owl:TransitiveProperty"))
    }

    @Test("Object property domain and range are encoded")
    func objectPropertyDomainRange() {
        let ont = makeOntology {
            OWLObjectProperty(iri: "ex:knows", domains: [.named("ex:Person")], ranges: [.named("ex:Person")])
        }
        let turtle = TurtleEncoder().encode(ont)
        #expect(turtle.contains("rdfs:domain"))
        #expect(turtle.contains("rdfs:range"))
        #expect(turtle.contains("ex:Person"))
    }

    @Test("Object property inverseOf is encoded")
    func objectPropertyInverse() {
        let ont = makeOntology {
            OWLObjectProperty(iri: "ex:hasPart", inverseOf: "ex:partOf")
        }
        let turtle = TurtleEncoder().encode(ont)
        #expect(turtle.contains("owl:inverseOf"))
        #expect(turtle.contains("ex:partOf"))
    }

    @Test("Data property is encoded")
    func dataProperty() {
        let ont = makeOntology {
            OWLDataProperty(iri: "ex:age", domains: [.named("ex:Person")], ranges: [.datatype("xsd:integer")])
        }
        let turtle = TurtleEncoder().encode(ont)
        #expect(turtle.contains("owl:DatatypeProperty"))
        #expect(turtle.contains("rdfs:domain"))
        #expect(turtle.contains("xsd:integer"))
    }

    @Test("Class expression restriction (someValuesFrom) is encoded")
    func classExpressionRestriction() {
        let ont = makeOntology {
            OWLAxiom.subClassOf(
                sub: .named("ex:Parent"),
                sup: .someValuesFrom(property: "ex:hasChild", filler: .named("ex:Person"))
            )
        }
        let turtle = TurtleEncoder().encode(ont)
        #expect(turtle.contains("owl:Restriction"))
        #expect(turtle.contains("owl:onProperty"))
        #expect(turtle.contains("owl:someValuesFrom"))
    }

    @Test("Class expression boolean (intersection, union, complement) is encoded")
    func classExpressionBoolean() {
        let ont = makeOntology {
            OWLAxiom.equivalentClasses([
                .named("ex:WorkingParent"),
                .intersection([.named("ex:Parent"), .named("ex:Employee")])
            ])
        }
        let turtle = TurtleEncoder().encode(ont)
        #expect(turtle.contains("owl:intersectionOf"))
    }

    @Test("Class expression cardinality is encoded")
    func classExpressionCardinality() {
        let ont = makeOntology {
            OWLAxiom.subClassOf(
                sub: .named("ex:Parent"),
                sup: .minCardinality(property: "ex:hasChild", n: 1, filler: nil)
            )
        }
        let turtle = TurtleEncoder().encode(ont)
        #expect(turtle.contains("owl:minCardinality"))
        #expect(turtle.contains("1"))
    }

    @Test("Individual class assertion is encoded")
    func individualClassAssertion() {
        let ont = makeOntology {
            OWLNamedIndividual(iri: "ex:Alice")
            OWLAxiom.classAssertion(individual: "ex:Alice", class_: .named("ex:Person"))
        }
        let turtle = TurtleEncoder().encode(ont)
        #expect(turtle.contains("ex:Alice"))
        #expect(turtle.contains("ex:Person"))
    }

    @Test("Individual property assertions are encoded")
    func individualPropertyAssertion() {
        let ont = makeOntology {
            OWLNamedIndividual(iri: "ex:Alice")
            OWLAxiom.objectPropertyAssertion(subject: "ex:Alice", property: "ex:knows", object: "ex:Bob")
            OWLAxiom.dataPropertyAssertion(subject: "ex:Alice", property: "ex:age", value: .integer(30))
        }
        let turtle = TurtleEncoder().encode(ont)
        #expect(turtle.contains("ex:knows"))
        #expect(turtle.contains("ex:Bob"))
        #expect(turtle.contains("ex:age"))
        #expect(turtle.contains("30"))
    }

    @Test("Literal types are correctly formatted")
    func literalTypes() {
        let ont = makeOntology {
            OWLNamedIndividual(iri: "ex:Alice")
            OWLAxiom.dataPropertyAssertion(subject: "ex:Alice", property: "ex:name", value: .string("Alice"))
            OWLAxiom.dataPropertyAssertion(subject: "ex:Alice", property: "ex:age", value: .integer(30))
            OWLAxiom.dataPropertyAssertion(subject: "ex:Alice", property: "ex:active", value: .boolean(true))
        }
        let turtle = TurtleEncoder().encode(ont)
        #expect(turtle.contains("\"Alice\""))
        #expect(turtle.contains("30"))
        #expect(turtle.contains("true"))
    }

    @Test("Deterministic output: same input always produces same output")
    func deterministicOutput() {
        let ont = makeOntology {
            OWLClass(iri: "ex:B", label: "B")
            OWLClass(iri: "ex:A", label: "A")
            OWLAxiom.subClassOf(sub: .named("ex:B"), sup: .named("ex:A"))
        }
        let turtle1 = TurtleEncoder().encode(ont)
        let turtle2 = TurtleEncoder().encode(ont)
        #expect(turtle1 == turtle2)
    }

    @Test("Prefixed IRI is passed through without double compaction")
    func prefixedIRIPassthrough() {
        let ont = makeOntology {
            OWLClass(iri: "ex:Person")
        }
        let turtle = TurtleEncoder().encode(ont)
        #expect(turtle.contains("ex:Person"))
        // Should not contain <ex:Person>
        #expect(!turtle.contains("<ex:Person>"))
    }

    @Test("Full IRI is bracketed when no prefix matches")
    func fullIRIBracketing() {
        let ont = OWLOntology(iri: "http://test.org/") {
            OWLClass(iri: "http://unknown.org/Thing")
        }
        let turtle = TurtleEncoder().encode(ont)
        #expect(turtle.contains("<http://unknown.org/Thing>"))
    }
}
