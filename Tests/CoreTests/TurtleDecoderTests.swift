import Testing
import Foundation
@testable import Graph

@Suite("TurtleDecoder")
struct TurtleDecoderTests {

    private let standardPrefixes = """
    @prefix owl: <http://www.w3.org/2002/07/owl#> .
    @prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .
    @prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .
    @prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
    @prefix ex: <http://example.org/> .

    """

    // MARK: - Prefix Resolution

    @Test("Prefix is resolved correctly")
    func prefixResolution() throws {
        let turtle = standardPrefixes + """
        ex:Person a owl:Class .
        """
        let ont = try TurtleDecoder().decode(from: turtle)
        #expect(ont.classes.contains { $0.iri == "ex:Person" })
    }

    @Test("SPARQL-style PREFIX is resolved")
    func sparqlStylePrefix() throws {
        let turtle = """
        PREFIX owl: <http://www.w3.org/2002/07/owl#>
        PREFIX ex: <http://example.org/>

        ex:Person a owl:Class .
        """
        let ont = try TurtleDecoder().decode(from: turtle)
        #expect(ont.classes.contains { $0.iri == "ex:Person" })
    }

    // MARK: - Classes

    @Test("Class declaration is decoded")
    func classDeclaration() throws {
        let turtle = standardPrefixes + """
        ex:Person a owl:Class .
        """
        let ont = try TurtleDecoder().decode(from: turtle)
        #expect(ont.classes.count == 1)
        #expect(ont.classes.first?.iri == "ex:Person")
    }

    @Test("Class with label is decoded")
    func classWithLabel() throws {
        let turtle = standardPrefixes + """
        ex:Person a owl:Class ;
            rdfs:label "Person" .
        """
        let ont = try TurtleDecoder().decode(from: turtle)
        #expect(ont.classes.first?.label == "Person")
    }

    @Test("SubClassOf axiom is decoded")
    func subClassOf() throws {
        let turtle = standardPrefixes + """
        ex:Parent a owl:Class ;
            rdfs:subClassOf ex:Person .
        ex:Person a owl:Class .
        """
        let ont = try TurtleDecoder().decode(from: turtle)
        let subClassAxioms = ont.axioms.filter {
            if case .subClassOf = $0 { return true }
            return false
        }
        #expect(subClassAxioms.count == 1)
    }

    @Test("EquivalentClass axiom is decoded")
    func equivalentClass() throws {
        let turtle = standardPrefixes + """
        ex:A a owl:Class ;
            owl:equivalentClass ex:B .
        ex:B a owl:Class .
        """
        let ont = try TurtleDecoder().decode(from: turtle)
        let eqAxioms = ont.axioms.filter {
            if case .equivalentClasses = $0 { return true }
            return false
        }
        #expect(eqAxioms.count == 1)
    }

    @Test("AllDisjointClasses is decoded as disjointClasses axiom")
    func disjointClassesViaAllDisjoint() throws {
        let turtle = standardPrefixes + """
        ex:Person a owl:Class .
        ex:Organization a owl:Class .
        [] a owl:AllDisjointClasses ;
            owl:members ( ex:Person ex:Organization ) .
        """
        let ont = try TurtleDecoder().decode(from: turtle)
        let disjointAxioms = ont.axioms.filter {
            if case .disjointClasses = $0 { return true }
            return false
        }
        #expect(disjointAxioms.count == 1)
    }

    // MARK: - Object Properties

    @Test("Object property is decoded")
    func objectProperty() throws {
        let turtle = standardPrefixes + """
        ex:knows a owl:ObjectProperty .
        """
        let ont = try TurtleDecoder().decode(from: turtle)
        #expect(ont.objectProperties.count == 1)
        #expect(ont.objectProperties.first?.iri == "ex:knows")
    }

    @Test("Property characteristics are decoded")
    func propertyCharacteristics() throws {
        let turtle = standardPrefixes + """
        ex:partOf a owl:ObjectProperty , owl:TransitiveProperty .
        """
        let ont = try TurtleDecoder().decode(from: turtle)
        #expect(ont.objectProperties.first?.characteristics.contains(.transitive) == true)
        let transitiveAxioms = ont.axioms.filter {
            if case .transitiveObjectProperty = $0 { return true }
            return false
        }
        #expect(transitiveAxioms.count == 1)
    }

    @Test("Property domain and range are decoded")
    func propertyDomainRange() throws {
        let turtle = standardPrefixes + """
        ex:knows a owl:ObjectProperty ;
            rdfs:domain ex:Person ;
            rdfs:range ex:Person .
        ex:Person a owl:Class .
        """
        let ont = try TurtleDecoder().decode(from: turtle)
        #expect(ont.objectProperties.first?.domains.count == 1)
        #expect(ont.objectProperties.first?.ranges.count == 1)
    }

    @Test("Property inverse is decoded")
    func propertyInverse() throws {
        let turtle = standardPrefixes + """
        ex:hasPart a owl:ObjectProperty ;
            owl:inverseOf ex:partOf .
        """
        let ont = try TurtleDecoder().decode(from: turtle)
        #expect(ont.objectProperties.first?.inverseOf == "ex:partOf")
    }

    // MARK: - Data Properties

    @Test("Data property with range is decoded")
    func dataProperty() throws {
        let turtle = standardPrefixes + """
        ex:age a owl:DatatypeProperty ;
            rdfs:range xsd:integer .
        """
        let ont = try TurtleDecoder().decode(from: turtle)
        #expect(ont.dataProperties.count == 1)
        #expect(ont.dataProperties.first?.iri == "ex:age")
    }

    // MARK: - Restrictions

    @Test("someValuesFrom restriction is decoded")
    func restrictionSomeValues() throws {
        let turtle = standardPrefixes + """
        ex:Parent a owl:Class ;
            rdfs:subClassOf [ a owl:Restriction ;
                owl:onProperty ex:hasChild ;
                owl:someValuesFrom ex:Person ] .
        ex:Person a owl:Class .
        """
        let ont = try TurtleDecoder().decode(from: turtle)
        let subClassAxioms = ont.axioms.compactMap { axiom -> OWLClassExpression? in
            if case .subClassOf(_, let sup) = axiom { return sup }
            return nil
        }
        let hasSomeValues = subClassAxioms.contains {
            if case .someValuesFrom = $0 { return true }
            return false
        }
        #expect(hasSomeValues)
    }

    @Test("Cardinality restriction is decoded")
    func restrictionCardinality() throws {
        let turtle = standardPrefixes + """
        ex:Parent a owl:Class ;
            rdfs:subClassOf [ a owl:Restriction ;
                owl:onProperty ex:hasChild ;
                owl:minCardinality 1 ] .
        """
        let ont = try TurtleDecoder().decode(from: turtle)
        let subClassAxioms = ont.axioms.compactMap { axiom -> OWLClassExpression? in
            if case .subClassOf(_, let sup) = axiom { return sup }
            return nil
        }
        let hasMinCard = subClassAxioms.contains {
            if case .minCardinality(_, let n, _) = $0 { return n == 1 }
            return false
        }
        #expect(hasMinCard)
    }

    // MARK: - Collections

    @Test("RDF collection is parsed correctly")
    func rdfCollection() throws {
        let turtle = standardPrefixes + """
        ex:Person a owl:Class .
        ex:Organization a owl:Class .
        ex:Place a owl:Class .
        [] a owl:AllDisjointClasses ;
            owl:members ( ex:Person ex:Organization ex:Place ) .
        """
        let ont = try TurtleDecoder().decode(from: turtle)
        let disjointAxiom = ont.axioms.first {
            if case .disjointClasses = $0 { return true }
            return false
        }
        if case .disjointClasses(let members) = disjointAxiom {
            #expect(members.count == 3)
        } else {
            Issue.record("Expected disjointClasses axiom")
        }
    }

    // MARK: - Blank Node Property Lists

    @Test("Blank node property list is parsed")
    func blankNodePropertyList() throws {
        let turtle = standardPrefixes + """
        ex:A a owl:Class ;
            rdfs:subClassOf [ a owl:Restriction ;
                owl:onProperty ex:p ;
                owl:allValuesFrom ex:B ] .
        """
        let ont = try TurtleDecoder().decode(from: turtle)
        let subClassAxioms = ont.axioms.compactMap { axiom -> OWLClassExpression? in
            if case .subClassOf(_, let sup) = axiom { return sup }
            return nil
        }
        let hasAllValues = subClassAxioms.contains {
            if case .allValuesFrom = $0 { return true }
            return false
        }
        #expect(hasAllValues)
    }

    // MARK: - Literals

    @Test("Plain string literal is decoded")
    func literalPlain() throws {
        let turtle = standardPrefixes + """
        ex:Alice a owl:NamedIndividual ;
            ex:name "Alice" .
        """
        let ont = try TurtleDecoder().decode(from: turtle)
        let assertions = ont.axioms.compactMap { axiom -> OWLLiteral? in
            if case .dataPropertyAssertion(_, _, let value) = axiom { return value }
            return nil
        }
        #expect(assertions.first?.lexicalForm == "Alice")
    }

    @Test("Typed literal is decoded")
    func literalTyped() throws {
        let turtle = standardPrefixes + """
        ex:Alice a owl:NamedIndividual ;
            ex:birthDate "1990-01-01"^^xsd:date .
        """
        let ont = try TurtleDecoder().decode(from: turtle)
        let assertions = ont.axioms.compactMap { axiom -> OWLLiteral? in
            if case .dataPropertyAssertion(_, _, let value) = axiom { return value }
            return nil
        }
        #expect(assertions.first?.datatype == "xsd:date")
    }

    @Test("Language-tagged literal is decoded")
    func literalLanguageTagged() throws {
        let turtle = standardPrefixes + """
        ex:Alice a owl:NamedIndividual ;
            ex:greeting "hello"@en .
        """
        let ont = try TurtleDecoder().decode(from: turtle)
        let assertions = ont.axioms.compactMap { axiom -> OWLLiteral? in
            if case .dataPropertyAssertion(_, _, let value) = axiom { return value }
            return nil
        }
        #expect(assertions.first?.language == "en")
        #expect(assertions.first?.lexicalForm == "hello")
    }

    @Test("Bare numeric literal is decoded")
    func literalBareNumeric() throws {
        let turtle = standardPrefixes + """
        ex:Alice a owl:NamedIndividual ;
            ex:age 30 .
        """
        let ont = try TurtleDecoder().decode(from: turtle)
        let assertions = ont.axioms.compactMap { axiom -> OWLLiteral? in
            if case .dataPropertyAssertion(_, _, let value) = axiom { return value }
            return nil
        }
        #expect(assertions.first?.intValue == 30)
    }

    // MARK: - Individuals

    @Test("Individual declaration is decoded")
    func individualDeclaration() throws {
        let turtle = standardPrefixes + """
        ex:Alice a owl:NamedIndividual , ex:Person .
        ex:Person a owl:Class .
        """
        let ont = try TurtleDecoder().decode(from: turtle)
        #expect(ont.individuals.count == 1)
        #expect(ont.individuals.first?.iri == "ex:Alice")
        let classAssertions = ont.axioms.filter {
            if case .classAssertion = $0 { return true }
            return false
        }
        #expect(classAssertions.count == 1)
    }

    @Test("Object property assertion is decoded")
    func objectPropertyAssertion() throws {
        let turtle = standardPrefixes + """
        ex:Alice a owl:NamedIndividual ;
            ex:knows ex:Bob .
        """
        let ont = try TurtleDecoder().decode(from: turtle)
        let assertions = ont.axioms.filter {
            if case .objectPropertyAssertion = $0 { return true }
            return false
        }
        #expect(assertions.count == 1)
    }

    @Test("Data property assertion is decoded")
    func dataPropertyAssertion() throws {
        let turtle = standardPrefixes + """
        ex:Alice a owl:NamedIndividual ;
            ex:age 30 .
        """
        let ont = try TurtleDecoder().decode(from: turtle)
        let assertions = ont.axioms.filter {
            if case .dataPropertyAssertion = $0 { return true }
            return false
        }
        #expect(assertions.count == 1)
    }

    // MARK: - Multiple Statements

    @Test("Multiple statements with semicolons are parsed")
    func multipleStatementsSemicolon() throws {
        let turtle = standardPrefixes + """
        ex:Person a owl:Class ;
            rdfs:label "Person" ;
            rdfs:subClassOf owl:Thing .
        """
        let ont = try TurtleDecoder().decode(from: turtle)
        #expect(ont.classes.first?.label == "Person")
        let subClassAxioms = ont.axioms.filter {
            if case .subClassOf = $0 { return true }
            return false
        }
        #expect(subClassAxioms.count == 1)
    }

    @Test("Multiple objects with commas are parsed")
    func multipleObjectsComma() throws {
        let turtle = standardPrefixes + """
        ex:partOf a owl:ObjectProperty , owl:TransitiveProperty .
        """
        let ont = try TurtleDecoder().decode(from: turtle)
        #expect(ont.objectProperties.count == 1)
        #expect(ont.objectProperties.first?.characteristics.contains(.transitive) == true)
    }

    // MARK: - Error Cases

    @Test("Undefined prefix throws error")
    func errorUndefinedPrefix() throws {
        let turtle = """
        @prefix owl: <http://www.w3.org/2002/07/owl#> .
        unknown:Person a owl:Class .
        """
        #expect(throws: TurtleDecodingError.self) {
            try TurtleDecoder().decode(from: turtle)
        }
    }

    @Test("Unterminated string throws error")
    func errorUnterminatedString() throws {
        let turtle = standardPrefixes + """
        ex:Person a owl:Class ;
            rdfs:label "hello .
        """
        #expect(throws: TurtleDecodingError.self) {
            try TurtleDecoder().decode(from: turtle)
        }
    }

    @Test("Unexpected token throws error")
    func errorUnexpectedToken() throws {
        let turtle = standardPrefixes + """
        ex:Person a .
        """
        #expect(throws: TurtleDecodingError.self) {
            try TurtleDecoder().decode(from: turtle)
        }
    }

    @Test("Unexpected end of input throws error")
    func errorUnexpectedEndOfInput() throws {
        let turtle = standardPrefixes + """
        ex:Person a owl:Class ;
        """
        #expect(throws: TurtleDecodingError.self) {
            try TurtleDecoder().decode(from: turtle)
        }
    }
}
