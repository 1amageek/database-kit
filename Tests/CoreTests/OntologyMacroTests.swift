import Testing
import Foundation
@testable import Core
import Graph

// MARK: - Test Models (File Scope)

// --- Contract 1: DataProperty ---
@Persistable
@Ontology("http://example.org/onto#Employee")
struct OntEmployee {
    @Property("http://example.org/onto#name", label: "Name")
    var name: String

    @Property("http://example.org/onto#age")
    var age: Int
}

// --- Contract 2: ObjectProperty (to:) ---
@Persistable
@Ontology("http://example.org/onto#Employee")
struct OntEmployeeWithFK {
    @Property("http://example.org/onto#name")
    var name: String

    @Property("http://example.org/onto#worksFor", to: \OntDepartment.id)
    var departmentID: String?
}

@Persistable
@Ontology("http://example.org/onto#Department")
struct OntDepartment {
    var name: String
}

// --- Contract 3: 標準機能との共存 ---
@Persistable
@Ontology("http://example.org/onto#Product")
struct OntProduct {
    #Index(ScalarIndexKind<OntProduct>(fields: [\.category]))

    @Property("http://example.org/onto#productName")
    var productName: String

    var category: String

    @Transient
    var cached: String? = nil
}

// MARK: - Test Suite

@Suite("Ontology Macro Contract Tests")
struct OntologyMacroTests {

    // ── Contract 1: OntologyEntity 準拠 ──

    @Test("ontologyClass generates OntologyEntity conformance")
    func ontologyEntityConformance() {
        let _: any OntologyEntity = OntEmployee(name: "Alice", age: 30)
    }

    @Test("ontologyClassIRI returns specified IRI")
    func ontologyClassIRI() {
        #expect(OntEmployee.ontologyClassIRI == "http://example.org/onto#Employee")
        #expect(OntDepartment.ontologyClassIRI == "http://example.org/onto#Department")
    }

    // ── Contract 2: DataProperty descriptor ──

    @Test("@Property generates OntologyPropertyDescriptor for data properties")
    func dataPropertyDescriptors() {
        let descs = OntEmployee.ontologyPropertyDescriptors
        #expect(descs.count == 2)

        let nameDesc = descs.first { $0.fieldName == "name" }
        #expect(nameDesc != nil)
        #expect(nameDesc?.iri == "http://example.org/onto#name")
        #expect(nameDesc?.label == "Name")
        #expect(nameDesc?.isObjectProperty == false)
        #expect(nameDesc?.targetTypeName == nil)

        let ageDesc = descs.first { $0.fieldName == "age" }
        #expect(ageDesc != nil)
        #expect(ageDesc?.iri == "http://example.org/onto#age")
        #expect(ageDesc?.label == nil)
        #expect(ageDesc?.isObjectProperty == false)
    }

    // ── Contract 3: ObjectProperty descriptor ──

    @Test("@Property with to: generates ObjectProperty descriptor")
    func objectPropertyDescriptor() {
        let descs = OntEmployeeWithFK.ontologyPropertyDescriptors
        let worksFor = descs.first { $0.fieldName == "departmentID" }
        #expect(worksFor != nil)
        #expect(worksFor?.iri == "http://example.org/onto#worksFor")
        #expect(worksFor?.isObjectProperty == true)
        #expect(worksFor?.targetTypeName == "OntDepartment")
        #expect(worksFor?.targetFieldName == "id")
    }

    @Test("ObjectProperty auto-generates reverse index")
    func objectPropertyReverseIndex() {
        let indexes = OntEmployeeWithFK.indexDescriptors
        let reverseIdx = indexes.first { $0.name.contains("departmentID") }
        #expect(reverseIdx != nil)
    }

    // ── Contract 4: 標準機能との共存 ──

    @Test("Ontology features coexist with #Index and @Transient")
    func coexistenceWithStandardFeatures() {
        #expect(OntProduct.ontologyClassIRI == "http://example.org/onto#Product")

        let propDescs = OntProduct.ontologyPropertyDescriptors
        #expect(propDescs.count == 1)
        #expect(propDescs[0].fieldName == "productName")

        let idxDescs = OntProduct.indexDescriptors
        #expect(idxDescs.contains { $0.name.contains("category") })

        #expect(!OntProduct.allFields.contains("cached"))

        #expect(OntProduct.allFields.contains("productName"))
        #expect(OntProduct.allFields.contains("category"))
    }

    // ── Contract 5: Schema.ontology ──

    @Test("Schema accepts ontology parameter")
    func schemaOntology() {
        let ontology = OWLOntology(iri: "http://example.org/onto")
        let schema = Schema([OntEmployee.self], ontology: ontology)
        #expect(schema.ontology != nil)
        #expect(schema.ontology?.iri == "http://example.org/onto")
    }

    @Test("Schema without ontology defaults to nil")
    func schemaNoOntology() {
        let schema = Schema([OntEmployee.self])
        #expect(schema.ontology == nil)
    }

    // ── Contract 6: Persistable 基本機能の維持 ──

    @Test("Ontology entities retain standard Persistable features")
    func persistableBasics() {
        #expect(OntEmployee.persistableType == "OntEmployee")
        #expect(OntEmployee.allFields.contains("id"))
        #expect(OntEmployee.allFields.contains("name"))
        #expect(OntEmployee.allFields.contains("age"))

        let e = OntEmployee(name: "Bob", age: 25)
        #expect(e.id.count == 26)
    }
}
