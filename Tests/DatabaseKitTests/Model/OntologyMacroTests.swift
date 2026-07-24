import DatabaseTypes
import Testing
import Foundation
@testable import DatabaseKit
import DatabaseKit

// MARK: - Test Models (File Scope)

// --- Contract 1: DataProperty ---
@Persistable
@OWLClass(
    "https://example.org/onto#Employee",
    individualIRIBase: "https://example.org/individual/"
)
struct OntEmployee {
    var id: String = "fixture-id"
    @OWLDataProperty("https://example.org/onto#name", label: "Name")
    var name: String

    @OWLDataProperty("https://example.org/onto#age")
    var age: Int32
}

// --- Contract 2: ObjectProperty (to:) ---
@Persistable
@OWLClass(
    "https://example.org/onto#Employee",
    individualIRIBase: "https://example.org/individual/"
)
struct OntEmployeeWithFK {
    var id: String = "fixture-id"
    @OWLDataProperty("https://example.org/onto#name")
    var name: String

    @OWLDataProperty("https://example.org/onto#worksFor", to: \OntDepartment.id)
    var departmentID: String?
}

@Persistable
@OWLClass(
    "https://example.org/onto#Department",
    individualIRIBase: "https://example.org/individual/"
)
struct OntDepartment {
    var id: String = "fixture-id"
    var name: String
}

// --- Contract 3: Record feature coexistence ---
@Persistable
@OWLClass(
    "https://example.org/onto#Product",
    individualIRIBase: "https://example.org/individual/"
)
struct OntProduct {
    var id: String = "fixture-id"
    #Index(ScalarIndexKind<OntProduct>(fields: [\.category]))

    @OWLDataProperty("https://example.org/onto#productName")
    var productName: String

    var category: String

    @Transient
    var cached: String? = nil
}

// --- Contract 7: Absolute IRI preservation ---
@Persistable
@OWLClass(
    "https://example.org/onto#MixedEntity",
    individualIRIBase: "https://example.org/individual/"
)
struct OntMixed {
    var id: String = "fixture-id"
    @OWLDataProperty("https://example.org/onto#localProp")
    var localProp: String

    @OWLDataProperty("http://xmlns.com/foaf/0.1/name")
    var foafName: String

    @OWLDataProperty("http://other.org/full#prop")
    var fullProp: String
}

// --- Contract 8: Full IRI @OWLClass ---
@Persistable
@OWLClass(
    "http://example.org/onto#FullIRIEntity",
    individualIRIBase: "http://example.org/individual/"
)
struct OntFullIRI {
    var id: String = "fixture-id"
    @OWLDataProperty("http://example.org/onto#localField")
    var localField: String
}

// --- Contract 9: Full IRI @OWLClass + DataProperty + ObjectProperty ---
@Persistable
@OWLClass(
    "http://example.org/onto#FullEmployee",
    individualIRIBase: "http://example.org/individual/"
)
struct OntFullEmployee {
    var id: String = "fixture-id"
    @OWLDataProperty("http://example.org/onto#name", label: "Name")
    var name: String

    @OWLDataProperty("http://example.org/onto#age")
    var age: Int32

    @OWLDataProperty("http://example.org/onto#worksFor", to: \OntFullDepartment.id)
    var departmentID: String?
}

@Persistable
@OWLClass(
    "http://example.org/onto#FullDepartment",
    individualIRIBase: "http://example.org/individual/"
)
struct OntFullDepartment {
    var id: String = "fixture-id"
    var name: String
}

// --- Contract 10: Full IRI @OWLClass + record feature coexistence ---
@Persistable
@OWLClass(
    "http://example.org/onto#FullProduct",
    individualIRIBase: "http://example.org/individual/"
)
struct OntFullProduct {
    var id: String = "fixture-id"
    #Index(ScalarIndexKind<OntFullProduct>(fields: [\.category]))

    @OWLDataProperty("http://example.org/onto#productName")
    var productName: String

    var category: String

    @Transient
    var cached: String? = nil
}

// --- Contract 12: Full IRI @OWLClass (slash-separated) ---
@Persistable
@OWLClass(
    "http://example.org/onto/SlashEntity",
    individualIRIBase: "http://example.org/individual/"
)
struct OntSlashIRI {
    var id: String = "fixture-id"
    @OWLDataProperty("http://example.org/onto/localField")
    var localField: String

    @OWLDataProperty("http://xmlns.com/foaf/0.1/name")
    var foafName: String

    @OWLDataProperty("http://other.org/full#prop")
    var fullProp: String
}

// --- Contract 13: Hash-separated absolute IRI ---
@Persistable
@OWLClass(
    "http://example.org/onto#HashMixed",
    individualIRIBase: "http://example.org/individual/"
)
struct OntHashMixed {
    var id: String = "fixture-id"
    @OWLDataProperty("http://example.org/onto#localProp")
    var localProp: String

    @OWLDataProperty("http://xmlns.com/foaf/0.1/name")
    var foafName: String

    @OWLDataProperty("http://other.org/full#prop")
    var fullProp: String
}

// --- Contract 20: @OWLObjectProperty ---
@Persistable
@OWLObjectProperty(
    "https://example.org/onto#employs",
    from: "employeeID",
    to: "projectID"
)
struct OntAssignment {
    var id: String = "fixture-id"
    var employeeID: String = ""
    var projectID: String = ""

    @OWLDataProperty("https://example.org/onto#since")
    var startDate: Timestamp? = nil
}

// --- Contract 16: Plain model (no ontology) ---
@Persistable
struct OntPlainModel {
    var id: String = "fixture-id"
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
        #expect(OntEmployee.ontologyClassIRI == "https://example.org/onto#Employee")
        #expect(OntDepartment.ontologyClassIRI == "https://example.org/onto#Department")
    }

    // -- Contract 2: DataProperty descriptor --

    @Test("@OWLDataProperty generates OWLDataPropertyDescriptor for data properties")
    func dataPropertyDescriptors() {
        let descs = OntEmployee.ontologyPropertyDescriptors
        #expect(descs.count == 2)

        let nameDesc = descs.first { $0.fieldName == "name" }
        #expect(nameDesc != nil)
        #expect(nameDesc?.iri == "https://example.org/onto#name")
        #expect(nameDesc?.label == "Name")
        #expect(nameDesc?.isObjectProperty == false)
        #expect(nameDesc?.targetTypeName == nil)

        let ageDesc = descs.first { $0.fieldName == "age" }
        #expect(ageDesc != nil)
        #expect(ageDesc?.iri == "https://example.org/onto#age")
        #expect(ageDesc?.label == nil)
        #expect(ageDesc?.isObjectProperty == false)
    }

    // -- Contract 3: ObjectProperty descriptor --

    @Test("@OWLDataProperty with to: generates ObjectProperty descriptor")
    func objectPropertyDescriptor() {
        let descs = OntEmployeeWithFK.ontologyPropertyDescriptors
        let worksFor = descs.first { $0.fieldName == "departmentID" }
        #expect(worksFor != nil)
        #expect(worksFor?.iri == "https://example.org/onto#worksFor")
        #expect(worksFor?.isObjectProperty == true)
        #expect(worksFor?.targetTypeName == "OntDepartment")
        #expect(worksFor?.targetFieldName == "id")
    }

    @Test("ObjectProperty auto-generates reverse index with @OWLDataProperty")
    func objectPropertyReverseIndex() throws {
        let indexes = try OntEmployeeWithFK.indexDescriptors
        let reverseIdx = indexes.first { $0.name.contains("departmentID") }
        #expect(reverseIdx != nil)
    }

    // -- Contract 4: Record feature coexistence --

    @Test("OWL features coexist with #Index and @Transient")
    func coexistenceWithRecordFeatures() throws {
        #expect(OntProduct.ontologyClassIRI == "https://example.org/onto#Product")

        let propDescs = OntProduct.ontologyPropertyDescriptors
        #expect(propDescs.count == 1)
        #expect(propDescs[0].fieldName == "productName")

        let idxDescs = try OntProduct.indexDescriptors
        #expect(idxDescs.contains { $0.name.contains("category") })

        #expect(!OntProduct.allFields.contains("cached"))

        #expect(OntProduct.allFields.contains("productName"))
        #expect(OntProduct.allFields.contains("category"))
    }

    // -- Contract 6: Persistable basics maintained --

    @Test("OWL entities retain Persistable record features")
    func persistableBasics() {
        #expect(OntEmployee.persistableType == "OntEmployee")
        #expect(OntEmployee.allFields.contains("id"))
        #expect(OntEmployee.allFields.contains("name"))
        #expect(OntEmployee.allFields.contains("age"))

        let e = OntEmployee(name: "Bob", age: 25)
        #expect(e.id == "fixture-id")
    }

    // -- Contract 7: Absolute IRI preservation --

    @Test("Absolute property IRIs are preserved")
    func absoluteIRIValues() {
        let descs = OntMixed.ontologyPropertyDescriptors
        #expect(descs.count == 3)

        let localDesc = descs.first { $0.fieldName == "localProp" }
        #expect(localDesc?.iri == "https://example.org/onto#localProp")

        let curieDesc = descs.first { $0.fieldName == "foafName" }
        #expect(curieDesc?.iri == "http://xmlns.com/foaf/0.1/name")

        let fullDesc = descs.first { $0.fieldName == "fullProp" }
        #expect(fullDesc?.iri == "http://other.org/full#prop")
    }

    // -- Contract 8: Full IRI @OWLClass --

    @Test("Full class and property IRIs are preserved")
    func fullIRIOntologyValues() {
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
    func fullIRIObjectPropertyReverseIndex() throws {
        let indexes = try OntFullEmployee.indexDescriptors
        let reverseIdx = indexes.first { $0.name.contains("departmentID") }
        #expect(reverseIdx != nil)
    }

    // -- Contract 10: Full IRI @OWLClass + standard feature coexistence --

    @Test("Full IRI @OWLClass coexists with #Index and @Transient")
    func fullIRICoexistence() throws {
        #expect(OntFullProduct.ontologyClassIRI == "http://example.org/onto#FullProduct")

        let propDescs = OntFullProduct.ontologyPropertyDescriptors
        #expect(propDescs.count == 1)
        #expect(propDescs[0].fieldName == "productName")
        #expect(propDescs[0].iri == "http://example.org/onto#productName")

        let idxDescs = try OntFullProduct.indexDescriptors
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
        #expect(curieDesc?.iri == "http://xmlns.com/foaf/0.1/name")

        let fullDesc = descs.first { $0.fieldName == "fullProp" }
        #expect(fullDesc?.iri == "http://other.org/full#prop")
    }

    // -- Contract 13: Full IRI @OWLClass (hash-separated) --

    @Test("Hash-separated absolute IRIs are preserved")
    func hashIRIValues() {
        #expect(OntHashMixed.ontologyClassIRI == "http://example.org/onto#HashMixed")

        let descs = OntHashMixed.ontologyPropertyDescriptors
        #expect(descs.count == 3)

        let localDesc = descs.first { $0.fieldName == "localProp" }
        #expect(localDesc?.iri == "http://example.org/onto#localProp")

        let curieDesc = descs.first { $0.fieldName == "foafName" }
        #expect(curieDesc?.iri == "http://xmlns.com/foaf/0.1/name")

        let fullDesc = descs.first { $0.fieldName == "fullProp" }
        #expect(fullDesc?.iri == "http://other.org/full#prop")
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
        #expect(e.id == "fixture-id")
    }

    // -- Contract 20: @OWLObjectProperty --

    @Test("@OWLObjectProperty generates OWLObjectPropertyEntity conformance")
    func owlObjectPropertyEntityConformance() {
        let _: any OWLObjectPropertyEntity = OntAssignment(employeeID: "e1", projectID: "p1")
    }

    @Test("@OWLObjectProperty IRI is set correctly")
    func objectPropertyIRI() {
        #expect(OntAssignment.objectPropertyIRI == "https://example.org/onto#employs")
    }

    @Test("@OWLObjectProperty from/to field names are set correctly")
    func objectPropertyFromToFields() {
        #expect(OntAssignment.fromFieldName == "employeeID")
        #expect(OntAssignment.toFieldName == "projectID")
    }

    @Test("@OWLObjectProperty auto-generates graph index")
    func objectPropertyAutoGraphIndex() throws {
        let indexes = try OntAssignment.indexDescriptors
        let graphIdx = indexes.first { $0.name.contains("graph") }
        #expect(graphIdx != nil)
        #expect(graphIdx?.name == "OntAssignment_graph_employeeID_projectID")
    }

    @Test("@OWLObjectProperty generates OWLObjectPropertyDescriptor")
    func objectPropertyDescriptorGenerated() throws {
        let descs = try OntAssignment.owlObjectPropertyDescriptors
        #expect(descs.count == 1)
        #expect(descs[0].iri == "https://example.org/onto#employs")
        #expect(descs[0].fromFieldName == "employeeID")
        #expect(descs[0].toFieldName == "projectID")
    }

    @Test("@OWLObjectProperty collects @OWLDataProperty metadata")
    func objectPropertyCollectsDataProperties() {
        let propDescs = OntAssignment.ontologyPropertyDescriptors
        #expect(propDescs.count == 1)
        #expect(propDescs[0].fieldName == "startDate")
        #expect(propDescs[0].iri == "https://example.org/onto#since")
    }

    // -- Contract 16: Schema.Entity ontology metadata --

    @Test("Schema.Entity captures ontologyClassIRI from @OWLClass")
    func schemaEntityOntologyClassIRI() throws {
        let entity = try Schema.Entity(from: OntEmployee.self)
        #expect(entity.ontologyClassIRI == "https://example.org/onto#Employee")
    }

    @Test("Schema.Entity captures objectPropertyIRI from @OWLObjectProperty")
    func schemaEntityObjectPropertyIRI() throws {
        let entity = try Schema.Entity(from: OntAssignment.self)
        #expect(entity.objectPropertyIRI == "https://example.org/onto#employs")
        #expect(entity.objectPropertyFromField == "employeeID")
        #expect(entity.objectPropertyToField == "projectID")
    }

    @Test("Schema.Entity ontology metadata round-trips through JSON")
    func schemaEntityOntologyMetadataRoundTrip() throws {
        let entity = try Schema.Entity(from: OntEmployee.self)
        let data = try JSONEncoder().encode(entity)
        let decoded = try JSONDecoder().decode(Schema.Entity.self, from: data)
        #expect(decoded.ontologyClassIRI == "https://example.org/onto#Employee")
        #expect(decoded.objectPropertyIRI == nil)
    }

    @Test("Schema.Entity without ontology has nil ontology fields")
    func schemaEntityNoOntology() throws {
        let entity = try Schema.Entity(from: OntPlainModel.self)
        #expect(entity.ontologyClassIRI == nil)
        #expect(entity.objectPropertyIRI == nil)
    }
}

// MARK: - Descriptor Ownership Tests

@Suite("Descriptor Ownership Tests")
struct DescriptorOwnershipTests {

    // -- _persistableDescriptors --

    @Test("@Persistable generates _persistableDescriptors")
    func persistableDescriptorsGenerated() throws {
        // OntPlainModel has no #Index → empty
        #expect(try OntPlainModel._persistableDescriptors.isEmpty)
    }

    @Test("_persistableDescriptors contains #Index descriptors")
    func persistableDescriptorsContainsIndex() throws {
        // OntProduct has #Index(ScalarIndexKind<...>(fields: [\.category]))
        let descs = try OntProduct._persistableDescriptors
        let indexDescs = descs.compactMap { $0 as? IndexDescriptor }
        #expect(indexDescs.contains { $0.name.contains("category") })
    }

    // -- _owlRDFDescriptors --

    @Test("@OWLClass generates its canonical RDF index descriptor")
    func owlRDFDescriptorsGenerated() throws {
        let descs = try OntEmployee._owlRDFDescriptors
        #expect(descs.count == 1)

        let indexDesc = descs[0] as? IndexDescriptor
        #expect(indexDesc != nil)
        #expect(indexDesc?.name == "OntEmployee_owl_rdf")
        #expect(indexDesc?.kindIdentifier == "owl_class_rdf")
    }

    @Test("Non-OWL type has no OWL RDF index descriptor")
    func plainTypeNoOwlDescriptors() throws {
        // OntPlainModel is @Persistable but NOT @OWLClass
        // The protocol requirement is unavailable without @OWLClass conformance.
        let indexDescs = try OntPlainModel.indexDescriptors
        let owlRDF = indexDescs.first { $0.kindIdentifier == "owl_class_rdf" }
        #expect(owlRDF == nil)
    }

    // -- Descriptor merging --

    @Test("OWLClassEntity.descriptors merges record and RDF descriptors")
    func descriptorsMerge() throws {
        // OntProduct has @OWLClass + #Index(ScalarIndexKind) + @Transient
        let all = try OntProduct.descriptors
        let indexDescs = all.compactMap { $0 as? IndexDescriptor }

        // The record index and RDF projection are both registered.
        let scalar = indexDescs.first { $0.kindIdentifier == "scalar" }
        let owlRDF = indexDescs.first { $0.kindIdentifier == "owl_class_rdf" }

        #expect(scalar != nil, "Should contain scalar index from #Index")
        #expect(owlRDF != nil, "Should contain RDF projection from @OWLClass")
    }

    @Test("Plain type descriptors == _persistableDescriptors (no merge)")
    func plainTypeDescriptorsDefault() throws {
        // No @OWLClass → descriptors defaults to _persistableDescriptors
        let descs = try OntPlainModel.descriptors
        let persistable = try OntPlainModel._persistableDescriptors
        #expect(descs.count == persistable.count)
    }

    // -- OWLClassRDFIndexKind --

    @Test("OWLClassRDFIndexKind has canonical metadata")
    func owlRDFIndexKindProperties() {
        let kind = OWLClassRDFIndexKind<OntEmployee>(
            individualIRIBase: "https://example.org/individual/"
        )
        #expect(OWLClassRDFIndexKind<OntEmployee>.identifier == "owl_class_rdf")
        #expect(OWLClassRDFIndexKind<OntEmployee>.subspaceStructure == .hierarchical)
        #expect(kind.indexName == "OntEmployee_owl_rdf")
        #expect(kind.graph == nil)
        #expect(kind.individualIRIBase == "https://example.org/individual/")
    }

    @Test("OWLClassRDFIndexKind supports a fixed named graph")
    func owlRDFIndexKindNamedGraph() throws {
        let graph = try RDFGraphName(iri: "https://example.org/graph/people")
        let kind = OWLClassRDFIndexKind<OntEmployee>(
            individualIRIBase: "https://example.org/individual/",
            graph: graph
        )
        #expect(kind.graph == graph)
    }

    @Test("OWLClassRDFIndexKind Codable round-trip")
    func owlRDFIndexKindCodable() throws {
        let kind = OWLClassRDFIndexKind<OntEmployee>(
            individualIRIBase: "https://example.org/individual/",
            graph: try RDFGraphName(iri: "https://example.org/graph/test")
        )
        let data = try JSONEncoder().encode(kind)
        let decoded = try JSONDecoder().decode(OWLClassRDFIndexKind<OntEmployee>.self, from: data)
        #expect(decoded == kind)
    }

    @Test("OWLClassRDFIndexKind Hashable")
    func owlRDFIndexKindHashable() {
        let a = OWLClassRDFIndexKind<OntEmployee>(individualIRIBase: "https://example.org/a/")
        let b = OWLClassRDFIndexKind<OntEmployee>(individualIRIBase: "https://example.org/a/")
        let c = OWLClassRDFIndexKind<OntEmployee>(individualIRIBase: "https://example.org/b/")
        #expect(a == b)
        #expect(a != c)
        #expect(a.hashValue == b.hashValue)
    }
}
