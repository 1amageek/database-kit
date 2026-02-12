import Testing
import Graph

@Suite("OWLOntologyBuilder Tests")
struct OWLOntologyBuilderTests {

    // MARK: - Basic Component Types

    @Test("Builder adds OWLClass")
    func builderAddsClass() {
        let ontology = OWLOntology(iri: "test:") {
            OWLClass(iri: "ex:Person", label: "Person")
            OWLClass(iri: "ex:Organization", label: "Organization")
        }
        #expect(ontology.classes.count == 2)
        #expect(ontology.classes[0].iri == "ex:Person")
        #expect(ontology.classes[1].iri == "ex:Organization")
    }

    @Test("Builder adds OWLObjectProperty")
    func builderAddsObjectProperty() {
        let ontology = OWLOntology(iri: "test:") {
            OWLObjectProperty(
                iri: "ex:hasParticipant",
                label: "has participant",
                inverseOf: "ex:participatesIn",
                domains: [.named("ex:Event")]
            )
        }
        #expect(ontology.objectProperties.count == 1)
        #expect(ontology.objectProperties[0].iri == "ex:hasParticipant")
        #expect(ontology.objectProperties[0].inverseOf == "ex:participatesIn")
    }

    @Test("Builder adds OWLDataProperty")
    func builderAddsDataProperty() {
        let ontology = OWLOntology(iri: "test:") {
            OWLDataProperty(
                iri: "ex:occurredOnDate",
                label: "occurred on date",
                domains: [.named("ex:Event")],
                ranges: [.datatype(XSDDatatype.date.iri)]
            )
        }
        #expect(ontology.dataProperties.count == 1)
        #expect(ontology.dataProperties[0].iri == "ex:occurredOnDate")
    }

    @Test("Builder adds OWLAnnotationProperty")
    func builderAddsAnnotationProperty() {
        let ontology = OWLOntology(iri: "test:") {
            OWLAnnotationProperty(iri: "rdfs:comment", label: "comment")
        }
        #expect(ontology.annotationProperties.count == 1)
        #expect(ontology.annotationProperties[0].iri == "rdfs:comment")
    }

    @Test("Builder adds OWLNamedIndividual")
    func builderAddsIndividual() {
        let ontology = OWLOntology(iri: "test:") {
            OWLNamedIndividual(iri: "ex:Alice", label: "Alice")
        }
        #expect(ontology.individuals.count == 1)
        #expect(ontology.individuals[0].iri == "ex:Alice")
    }

    @Test("Builder adds OWLAxiom")
    func builderAddsAxiom() {
        let ontology = OWLOntology(iri: "test:") {
            OWLAxiom.subClassOf(sub: .named("ex:Company"), sup: .named("ex:Organization"))
        }
        #expect(ontology.axioms.count == 1)
    }

    // MARK: - Mixed Types

    @Test("Builder handles mixed component types")
    func mixedTypes() {
        let ontology = OWLOntology(iri: "test:") {
            OWLClass(iri: "ex:Event", label: "Event")
            OWLObjectProperty(iri: "ex:causes", domains: [.named("ex:Event")])
            OWLDataProperty(iri: "ex:startDate")
            OWLAxiom.subClassOf(sub: .named("ex:Event"), sup: .thing)
            OWLNamedIndividual(iri: "ex:event1")
        }
        #expect(ontology.classes.count == 1)
        #expect(ontology.objectProperties.count == 1)
        #expect(ontology.dataProperties.count == 1)
        #expect(ontology.axioms.count == 1)
        #expect(ontology.individuals.count == 1)
    }

    // MARK: - for Loop (buildArray)

    @Test("Builder supports for loop")
    func forLoop() {
        let items: [(iri: String, label: String)] = [
            ("ex:Person", "Person"),
            ("ex:Place", "Place"),
            ("ex:Event", "Event"),
        ]
        let ontology = OWLOntology(iri: "test:") {
            for (iri, label) in items {
                OWLClass(iri: iri, label: label)
                OWLAxiom.subClassOf(sub: .named(iri), sup: .thing)
            }
        }
        #expect(ontology.classes.count == 3)
        #expect(ontology.axioms.count == 3)
        #expect(ontology.classes[0].iri == "ex:Person")
        #expect(ontology.classes[2].iri == "ex:Event")
    }

    // MARK: - if (buildOptional)

    @Test("Builder supports if condition")
    func ifCondition() {
        let includePlace = true
        let ontology = OWLOntology(iri: "test:") {
            OWLClass(iri: "ex:Person", label: "Person")
            if includePlace {
                OWLClass(iri: "ex:Place", label: "Place")
            }
        }
        #expect(ontology.classes.count == 2)

        let excludePlace = false
        let ontology2 = OWLOntology(iri: "test:") {
            OWLClass(iri: "ex:Person", label: "Person")
            if excludePlace {
                OWLClass(iri: "ex:Place", label: "Place")
            }
        }
        #expect(ontology2.classes.count == 1)
    }

    // MARK: - if-else (buildEither)

    @Test("Builder supports if-else")
    func ifElse() {
        let useTransitive = true
        let ontology = OWLOntology(iri: "test:") {
            if useTransitive {
                OWLObjectProperty(iri: "ex:partOf", characteristics: [.transitive])
            } else {
                OWLObjectProperty(iri: "ex:partOf")
            }
        }
        #expect(ontology.objectProperties.count == 1)
        #expect(ontology.objectProperties[0].isTransitive == true)
    }

    // MARK: - Empty Builder

    @Test("Builder handles empty content")
    func emptyBuilder() {
        let ontology = OWLOntology(iri: "test:") {
        }
        #expect(ontology.classes.isEmpty)
        #expect(ontology.objectProperties.isEmpty)
        #expect(ontology.dataProperties.isEmpty)
        #expect(ontology.axioms.isEmpty)
        #expect(ontology.individuals.isEmpty)
        #expect(ontology.iri == "test:")
    }

    // MARK: - Metadata Preservation

    @Test("Builder preserves IRI and prefixes")
    func metadataPreservation() {
        let ontology = OWLOntology(
            iri: "aurora:",
            versionIRI: "aurora:v1",
            prefixes: ["ex": "http://example.org/"]
        ) {
            OWLClass(iri: "ex:Person")
        }
        #expect(ontology.iri == "aurora:")
        #expect(ontology.versionIRI == "aurora:v1")
        #expect(ontology.prefixes["ex"] == "http://example.org/")
        // Default prefixes are also present
        #expect(ontology.prefixes["owl"] != nil)
    }

    // MARK: - Complex Scenario

    @Test("Builder constructs realistic ontology")
    func realisticOntology() {
        let primitiveClasses = [
            ("ex:Person", "Person"),
            ("ex:Organization", "Organization"),
            ("ex:Event", "Event"),
        ]
        let subClasses = [
            ("ex:Company", "Company", "ex:Organization"),
            ("ex:Acquisition", "Acquisition", "ex:Event"),
        ]

        let ontology = OWLOntology(iri: "aurora:", prefixes: ["ex": "http://example.org/"]) {
            for (iri, label) in primitiveClasses {
                OWLClass(iri: iri, label: label)
                OWLAxiom.subClassOf(sub: .named(iri), sup: .thing)
            }
            for (iri, label, superClass) in subClasses {
                OWLClass(iri: iri, label: label)
                OWLAxiom.subClassOf(sub: .named(iri), sup: .named(superClass))
            }
            OWLObjectProperty(
                iri: "ex:hasParticipant",
                label: "has participant",
                inverseOf: "ex:participatesIn",
                domains: [.named("ex:Event")]
            )
            OWLObjectProperty(
                iri: "ex:participatesIn",
                label: "participates in",
                inverseOf: "ex:hasParticipant",
                ranges: [.named("ex:Event")]
            )
            OWLDataProperty(
                iri: "ex:occurredOnDate",
                label: "occurred on date",
                domains: [.named("ex:Event")],
                ranges: [.datatype(XSDDatatype.date.iri)]
            )
        }

        #expect(ontology.classes.count == 5)
        #expect(ontology.axioms.count == 5)
        #expect(ontology.objectProperties.count == 2)
        #expect(ontology.dataProperties.count == 1)

        // Verify class order preserved
        #expect(ontology.classes[0].iri == "ex:Person")
        #expect(ontology.classes[3].iri == "ex:Company")

        // Verify inverse pair
        #expect(ontology.objectProperties[0].inverseOf == "ex:participatesIn")
        #expect(ontology.objectProperties[1].inverseOf == "ex:hasParticipant")
    }
}
