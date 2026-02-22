import Testing
import Foundation
@testable import Core
import Graph
import DatabaseClientProtocol

// MARK: - Test Models (File Scope)

// --- Contract 1: DataProperty ---
@Persistable
@OWLClass("ex:Employee")
struct OntEmployee {
    @OWLDataProperty("name", label: "Name")
    var name: String

    @OWLDataProperty("age")
    var age: Int
}

// --- Contract 2: ObjectProperty (to:) ---
@Persistable
@OWLClass("ex:Employee")
struct OntEmployeeWithFK {
    @OWLDataProperty("name")
    var name: String

    @OWLDataProperty("worksFor", to: \OntDepartment.id)
    var departmentID: String?
}

@Persistable
@OWLClass("ex:Department")
struct OntDepartment {
    var name: String
}

// --- Contract 3: Standard feature coexistence ---
@Persistable
@OWLClass("ex:Product")
struct OntProduct {
    #Index(ScalarIndexKind<OntProduct>(fields: [\.category]))

    @OWLDataProperty("productName")
    var productName: String

    var category: String

    @Transient
    var cached: String? = nil
}

// --- Contract 7: IRI resolution ---
@Persistable
@OWLClass("ex:MixedEntity")
struct OntMixed {
    @OWLDataProperty("localProp")
    var localProp: String

    @OWLDataProperty("foaf:name")
    var foafName: String

    @OWLDataProperty("http://other.org/full#prop")
    var fullProp: String
}

// --- Contract 8: Full IRI @OWLClass ---
@Persistable
@OWLClass("http://example.org/onto#FullIRIEntity")
struct OntFullIRI {
    @OWLDataProperty("localField")
    var localField: String
}

// --- Contract 9: Full IRI @OWLClass + DataProperty + ObjectProperty ---
@Persistable
@OWLClass("http://example.org/onto#FullEmployee")
struct OntFullEmployee {
    @OWLDataProperty("name", label: "Name")
    var name: String

    @OWLDataProperty("age")
    var age: Int

    @OWLDataProperty("worksFor", to: \OntFullDepartment.id)
    var departmentID: String?
}

@Persistable
@OWLClass("http://example.org/onto#FullDepartment")
struct OntFullDepartment {
    var name: String
}

// --- Contract 10: Full IRI @OWLClass + standard feature coexistence ---
@Persistable
@OWLClass("http://example.org/onto#FullProduct")
struct OntFullProduct {
    #Index(ScalarIndexKind<OntFullProduct>(fields: [\.category]))

    @OWLDataProperty("productName")
    var productName: String

    var category: String

    @Transient
    var cached: String? = nil
}

// --- Contract 12: Full IRI @OWLClass (slash-separated) ---
@Persistable
@OWLClass("http://example.org/onto/SlashEntity")
struct OntSlashIRI {
    @OWLDataProperty("localField")
    var localField: String

    @OWLDataProperty("foaf:name")
    var foafName: String

    @OWLDataProperty("http://other.org/full#prop")
    var fullProp: String
}

// --- Contract 13: Full IRI @OWLClass (hash-separated) + CURIE/full IRI mix ---
@Persistable
@OWLClass("http://example.org/onto#HashMixed")
struct OntHashMixed {
    @OWLDataProperty("localProp")
    var localProp: String

    @OWLDataProperty("foaf:name")
    var foafName: String

    @OWLDataProperty("http://other.org/full#prop")
    var fullProp: String
}

// --- Contract 14: Bare name @OWLClass (no separator) ---
@Persistable
@OWLClass("Employee")
struct OntBareEmployee {
    @OWLDataProperty("name", label: "Name")
    var name: String

    @OWLDataProperty("age")
    var age: Int

    @OWLDataProperty("worksFor", to: \OntBareDepartment.id)
    var departmentID: String?
}

@Persistable
@OWLClass("Department")
struct OntBareDepartment {
    var name: String
}

// --- Contract 20: @OWLObjectProperty ---
@Persistable
@OWLObjectProperty("onto:employs", from: "employeeID", to: "projectID")
struct OntAssignment {
    var employeeID: String = ""
    var projectID: String = ""

    @OWLDataProperty("onto:since")
    var startDate: Date = Date()
}

// --- Contract 16: Plain model (no ontology) ---
@Persistable
struct OntPlainModel {
    var name: String = ""
}

// MARK: - Test Suite

@Suite("OWL Macro Contract Tests")
struct OntologyMacroTests {

    // -- Contract 1: OWLClassEntity conformance --

    @Test("@OWLClass generates OWLClassEntity conformance")
    func owlClassEntityConformance() {
        let _: any OWLClassEntity = OntEmployee(name: "Alice", age: 30)
    }

    @Test("ontologyClassIRI returns specified IRI")
    func ontologyClassIRI() {
        #expect(OntEmployee.ontologyClassIRI == "ex:Employee")
        #expect(OntDepartment.ontologyClassIRI == "ex:Department")
    }

    // -- Contract 2: DataProperty descriptor --

    @Test("@OWLDataProperty generates OWLDataPropertyDescriptor for data properties")
    func dataPropertyDescriptors() {
        let descs = OntEmployee.ontologyPropertyDescriptors
        #expect(descs.count == 2)

        let nameDesc = descs.first { $0.fieldName == "name" }
        #expect(nameDesc != nil)
        #expect(nameDesc?.iri == "ex:name")
        #expect(nameDesc?.label == "Name")
        #expect(nameDesc?.isObjectProperty == false)
        #expect(nameDesc?.targetTypeName == nil)

        let ageDesc = descs.first { $0.fieldName == "age" }
        #expect(ageDesc != nil)
        #expect(ageDesc?.iri == "ex:age")
        #expect(ageDesc?.label == nil)
        #expect(ageDesc?.isObjectProperty == false)
    }

    // -- Contract 3: ObjectProperty descriptor --

    @Test("@OWLDataProperty with to: generates ObjectProperty descriptor")
    func objectPropertyDescriptor() {
        let descs = OntEmployeeWithFK.ontologyPropertyDescriptors
        let worksFor = descs.first { $0.fieldName == "departmentID" }
        #expect(worksFor != nil)
        #expect(worksFor?.iri == "ex:worksFor")
        #expect(worksFor?.isObjectProperty == true)
        #expect(worksFor?.targetTypeName == "OntDepartment")
        #expect(worksFor?.targetFieldName == "id")
    }

    @Test("ObjectProperty auto-generates reverse index with @OWLDataProperty")
    func objectPropertyReverseIndex() {
        let indexes = OntEmployeeWithFK.indexDescriptors
        let reverseIdx = indexes.first { $0.name.contains("departmentID") }
        #expect(reverseIdx != nil)
    }

    // -- Contract 4: Standard feature coexistence --

    @Test("OWL features coexist with #Index and @Transient")
    func coexistenceWithStandardFeatures() {
        #expect(OntProduct.ontologyClassIRI == "ex:Product")

        let propDescs = OntProduct.ontologyPropertyDescriptors
        #expect(propDescs.count == 1)
        #expect(propDescs[0].fieldName == "productName")

        let idxDescs = OntProduct.indexDescriptors
        #expect(idxDescs.contains { $0.name.contains("category") })

        #expect(!OntProduct.allFields.contains("cached"))

        #expect(OntProduct.allFields.contains("productName"))
        #expect(OntProduct.allFields.contains("category"))
    }

    // -- Contract 6: Persistable basics maintained --

    @Test("OWL entities retain standard Persistable features")
    func persistableBasics() {
        #expect(OntEmployee.persistableType == "OntEmployee")
        #expect(OntEmployee.allFields.contains("id"))
        #expect(OntEmployee.allFields.contains("name"))
        #expect(OntEmployee.allFields.contains("age"))

        let e = OntEmployee(name: "Bob", age: 25)
        #expect(e.id.count == 26)
    }

    // -- Contract 7: IRI resolution --

    @Test("IRI resolution: local name, CURIE, full IRI")
    func iriResolution() {
        let descs = OntMixed.ontologyPropertyDescriptors
        #expect(descs.count == 3)

        let localDesc = descs.first { $0.fieldName == "localProp" }
        #expect(localDesc?.iri == "ex:localProp")

        let curieDesc = descs.first { $0.fieldName == "foafName" }
        #expect(curieDesc?.iri == "foaf:name")

        let fullDesc = descs.first { $0.fieldName == "fullProp" }
        #expect(fullDesc?.iri == "http://other.org/full#prop")
    }

    // -- Contract 8: Full IRI @OWLClass local name resolution --

    @Test("IRI resolution with full IRI @OWLClass")
    func fullIRIOntologyResolution() {
        #expect(OntFullIRI.ontologyClassIRI == "http://example.org/onto#FullIRIEntity")

        let descs = OntFullIRI.ontologyPropertyDescriptors
        let desc = descs.first { $0.fieldName == "localField" }
        #expect(desc?.iri == "http://example.org/onto#localField")
    }

    // -- Contract 9: Full IRI @OWLClass + DataProperty + ObjectProperty --

    @Test("Full IRI @OWLClass with DataProperty and ObjectProperty")
    func fullIRIDataAndObjectProperty() {
        #expect(OntFullEmployee.ontologyClassIRI == "http://example.org/onto#FullEmployee")
        #expect(OntFullDepartment.ontologyClassIRI == "http://example.org/onto#FullDepartment")

        let descs = OntFullEmployee.ontologyPropertyDescriptors
        #expect(descs.count == 3)

        let nameDesc = descs.first { $0.fieldName == "name" }
        #expect(nameDesc?.iri == "http://example.org/onto#name")
        #expect(nameDesc?.label == "Name")
        #expect(nameDesc?.isObjectProperty == false)

        let ageDesc = descs.first { $0.fieldName == "age" }
        #expect(ageDesc?.iri == "http://example.org/onto#age")
        #expect(ageDesc?.isObjectProperty == false)

        let worksFor = descs.first { $0.fieldName == "departmentID" }
        #expect(worksFor?.iri == "http://example.org/onto#worksFor")
        #expect(worksFor?.isObjectProperty == true)
        #expect(worksFor?.targetTypeName == "OntFullDepartment")
        #expect(worksFor?.targetFieldName == "id")
    }

    @Test("Full IRI @OWLClass ObjectProperty generates reverse index")
    func fullIRIObjectPropertyReverseIndex() {
        let indexes = OntFullEmployee.indexDescriptors
        let reverseIdx = indexes.first { $0.name.contains("departmentID") }
        #expect(reverseIdx != nil)
    }

    // -- Contract 10: Full IRI @OWLClass + standard feature coexistence --

    @Test("Full IRI @OWLClass coexists with #Index and @Transient")
    func fullIRICoexistence() {
        #expect(OntFullProduct.ontologyClassIRI == "http://example.org/onto#FullProduct")

        let propDescs = OntFullProduct.ontologyPropertyDescriptors
        #expect(propDescs.count == 1)
        #expect(propDescs[0].fieldName == "productName")
        #expect(propDescs[0].iri == "http://example.org/onto#productName")

        let idxDescs = OntFullProduct.indexDescriptors
        #expect(idxDescs.contains { $0.name.contains("category") })

        #expect(!OntFullProduct.allFields.contains("cached"))
        #expect(OntFullProduct.allFields.contains("productName"))
        #expect(OntFullProduct.allFields.contains("category"))
    }

    // -- Contract 12: Full IRI @OWLClass (slash-separated) --

    @Test("IRI resolution with slash-separated full IRI @OWLClass")
    func slashIRIOntologyResolution() {
        #expect(OntSlashIRI.ontologyClassIRI == "http://example.org/onto/SlashEntity")

        let descs = OntSlashIRI.ontologyPropertyDescriptors
        #expect(descs.count == 3)

        let localDesc = descs.first { $0.fieldName == "localField" }
        #expect(localDesc?.iri == "http://example.org/onto/localField")

        let curieDesc = descs.first { $0.fieldName == "foafName" }
        #expect(curieDesc?.iri == "foaf:name")

        let fullDesc = descs.first { $0.fieldName == "fullProp" }
        #expect(fullDesc?.iri == "http://other.org/full#prop")
    }

    // -- Contract 13: Full IRI @OWLClass (hash-separated) + mixed --

    @Test("IRI resolution with hash-separated full IRI @OWLClass and mixed property IRIs")
    func hashIRIMixedPropertyResolution() {
        #expect(OntHashMixed.ontologyClassIRI == "http://example.org/onto#HashMixed")

        let descs = OntHashMixed.ontologyPropertyDescriptors
        #expect(descs.count == 3)

        let localDesc = descs.first { $0.fieldName == "localProp" }
        #expect(localDesc?.iri == "http://example.org/onto#localProp")

        let curieDesc = descs.first { $0.fieldName == "foafName" }
        #expect(curieDesc?.iri == "foaf:name")

        let fullDesc = descs.first { $0.fieldName == "fullProp" }
        #expect(fullDesc?.iri == "http://other.org/full#prop")
    }

    // -- Contract 14: Bare name @OWLClass (default ex: namespace) --

    @Test("Bare name @OWLClass defaults to ex: namespace")
    func bareNameOntologyResolution() {
        #expect(OntBareEmployee.ontologyClassIRI == "ex:Employee")
        #expect(OntBareDepartment.ontologyClassIRI == "ex:Department")

        let descs = OntBareEmployee.ontologyPropertyDescriptors
        #expect(descs.count == 3)

        let nameDesc = descs.first { $0.fieldName == "name" }
        #expect(nameDesc?.iri == "ex:name")
        #expect(nameDesc?.label == "Name")
        #expect(nameDesc?.isObjectProperty == false)

        let ageDesc = descs.first { $0.fieldName == "age" }
        #expect(ageDesc?.iri == "ex:age")
        #expect(ageDesc?.isObjectProperty == false)

        let worksFor = descs.first { $0.fieldName == "departmentID" }
        #expect(worksFor?.iri == "ex:worksFor")
        #expect(worksFor?.isObjectProperty == true)
        #expect(worksFor?.targetTypeName == "OntBareDepartment")
        #expect(worksFor?.targetFieldName == "id")
    }

    // -- Contract 11: Full IRI @OWLClass Persistable basics --

    @Test("Full IRI @OWLClass retains Persistable features")
    func fullIRIPersistableBasics() {
        #expect(OntFullEmployee.persistableType == "OntFullEmployee")
        #expect(OntFullEmployee.allFields.contains("id"))
        #expect(OntFullEmployee.allFields.contains("name"))
        #expect(OntFullEmployee.allFields.contains("age"))
        #expect(OntFullEmployee.allFields.contains("departmentID"))

        let e = OntFullEmployee(name: "Charlie", age: 40, departmentID: nil)
        #expect(e.id.count == 26)
    }

    // -- Contract 15: SchemaResponse transport --

    @Test("SchemaResponse round-trips through JSON")
    func schemaResponseRoundTrip() throws {
        let entity = Schema([OntEmployee.self]).entities[0]
        let response = SchemaResponse(entities: [entity])

        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(SchemaResponse.self, from: data)

        #expect(decoded.entities.count == 1)
        #expect(decoded.entities[0].name == entity.name)
    }

    // -- Contract 20: @OWLObjectProperty --

    @Test("@OWLObjectProperty generates OWLObjectPropertyEntity conformance")
    func owlObjectPropertyEntityConformance() {
        let _: any OWLObjectPropertyEntity = OntAssignment(employeeID: "e1", projectID: "p1")
    }

    @Test("@OWLObjectProperty IRI is set correctly")
    func objectPropertyIRI() {
        #expect(OntAssignment.objectPropertyIRI == "onto:employs")
    }

    @Test("@OWLObjectProperty from/to field names are set correctly")
    func objectPropertyFromToFields() {
        #expect(OntAssignment.fromFieldName == "employeeID")
        #expect(OntAssignment.toFieldName == "projectID")
    }

    @Test("@OWLObjectProperty auto-generates graph index")
    func objectPropertyAutoGraphIndex() {
        let indexes = OntAssignment.indexDescriptors
        let graphIdx = indexes.first { $0.name.contains("graph") }
        #expect(graphIdx != nil)
        #expect(graphIdx?.name == "OntAssignment_graph_employeeID_projectID")
    }

    @Test("@OWLObjectProperty generates OWLObjectPropertyDescriptor")
    func objectPropertyDescriptorGenerated() {
        let descs = OntAssignment.owlObjectPropertyDescriptors
        #expect(descs.count == 1)
        #expect(descs[0].iri == "onto:employs")
        #expect(descs[0].fromFieldName == "employeeID")
        #expect(descs[0].toFieldName == "projectID")
    }

    @Test("@OWLObjectProperty collects @OWLDataProperty metadata")
    func objectPropertyCollectsDataProperties() {
        let propDescs = OntAssignment.ontologyPropertyDescriptors
        #expect(propDescs.count == 1)
        #expect(propDescs[0].fieldName == "startDate")
        #expect(propDescs[0].iri == "onto:since")
    }

    // -- Contract 16: Schema.Entity ontology metadata --

    @Test("Schema.Entity captures ontologyClassIRI from @OWLClass")
    func schemaEntityOntologyClassIRI() {
        let entity = Schema.Entity(from: OntEmployee.self)
        #expect(entity.ontologyClassIRI == "ex:Employee")
    }

    @Test("Schema.Entity captures objectPropertyIRI from @OWLObjectProperty")
    func schemaEntityObjectPropertyIRI() {
        let entity = Schema.Entity(from: OntAssignment.self)
        #expect(entity.objectPropertyIRI == "onto:employs")
        #expect(entity.objectPropertyFromField == "employeeID")
        #expect(entity.objectPropertyToField == "projectID")
    }

    @Test("Schema.Entity ontology metadata round-trips through JSON")
    func schemaEntityOntologyMetadataRoundTrip() throws {
        let entity = Schema.Entity(from: OntEmployee.self)
        let data = try JSONEncoder().encode(entity)
        let decoded = try JSONDecoder().decode(Schema.Entity.self, from: data)
        #expect(decoded.ontologyClassIRI == "ex:Employee")
        #expect(decoded.objectPropertyIRI == nil)
    }

    @Test("Schema.Entity without ontology has nil ontology fields")
    func schemaEntityNoOntology() {
        let entity = Schema.Entity(from: OntPlainModel.self)
        #expect(entity.ontologyClassIRI == nil)
        #expect(entity.objectPropertyIRI == nil)
    }
}
