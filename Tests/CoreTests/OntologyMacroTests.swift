import Testing
import Foundation
@testable import Core
import Graph
import DatabaseClientProtocol

// MARK: - Test Models (File Scope)

// --- Contract 1: DataProperty ---
@Persistable
@Ontology("ex:Employee")
struct OntEmployee {
    @OWLProperty("name", label: "Name")
    var name: String

    @OWLProperty("age")
    var age: Int
}

// --- Contract 2: ObjectProperty (to:) ---
@Persistable
@Ontology("ex:Employee")
struct OntEmployeeWithFK {
    @OWLProperty("name")
    var name: String

    @OWLProperty("worksFor", to: \OntDepartment.id)
    var departmentID: String?
}

@Persistable
@Ontology("ex:Department")
struct OntDepartment {
    var name: String
}

// --- Contract 3: 標準機能との共存 ---
@Persistable
@Ontology("ex:Product")
struct OntProduct {
    #Index(ScalarIndexKind<OntProduct>(fields: [\.category]))

    @OWLProperty("productName")
    var productName: String

    var category: String

    @Transient
    var cached: String? = nil
}

// --- Contract 7: IRI 解決 ---
@Persistable
@Ontology("ex:MixedEntity")
struct OntMixed {
    @OWLProperty("localProp")
    var localProp: String

    @OWLProperty("foaf:name")
    var foafName: String

    @OWLProperty("http://other.org/full#prop")
    var fullProp: String
}

// --- Contract 8: フル IRI @Ontology ---
@Persistable
@Ontology("http://example.org/onto#FullIRIEntity")
struct OntFullIRI {
    @OWLProperty("localField")
    var localField: String
}

// --- Contract 9: フル IRI @Ontology + DataProperty + ObjectProperty ---
@Persistable
@Ontology("http://example.org/onto#FullEmployee")
struct OntFullEmployee {
    @OWLProperty("name", label: "Name")
    var name: String

    @OWLProperty("age")
    var age: Int

    @OWLProperty("worksFor", to: \OntFullDepartment.id)
    var departmentID: String?
}

@Persistable
@Ontology("http://example.org/onto#FullDepartment")
struct OntFullDepartment {
    var name: String
}

// --- Contract 10: フル IRI @Ontology + 標準機能との共存 ---
@Persistable
@Ontology("http://example.org/onto#FullProduct")
struct OntFullProduct {
    #Index(ScalarIndexKind<OntFullProduct>(fields: [\.category]))

    @OWLProperty("productName")
    var productName: String

    var category: String

    @Transient
    var cached: String? = nil
}

// --- Contract 12: フル IRI @Ontology (/ 区切り) ---
@Persistable
@Ontology("http://example.org/onto/SlashEntity")
struct OntSlashIRI {
    @OWLProperty("localField")
    var localField: String

    @OWLProperty("foaf:name")
    var foafName: String

    @OWLProperty("http://other.org/full#prop")
    var fullProp: String
}

// --- Contract 13: フル IRI @Ontology (# 区切り) + CURIE/フルIRI 混在 ---
@Persistable
@Ontology("http://example.org/onto#HashMixed")
struct OntHashMixed {
    @OWLProperty("localProp")
    var localProp: String

    @OWLProperty("foaf:name")
    var foafName: String

    @OWLProperty("http://other.org/full#prop")
    var fullProp: String
}

// --- Contract 14: ベア名 @Ontology (区切り文字なし) ---
@Persistable
@Ontology("Employee")
struct OntBareEmployee {
    @OWLProperty("name", label: "Name")
    var name: String

    @OWLProperty("age")
    var age: Int

    @OWLProperty("worksFor", to: \OntBareDepartment.id)
    var departmentID: String?
}

@Persistable
@Ontology("Department")
struct OntBareDepartment {
    var name: String
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
        #expect(OntEmployee.ontologyClassIRI == "ex:Employee")
        #expect(OntDepartment.ontologyClassIRI == "ex:Department")
    }

    // ── Contract 2: DataProperty descriptor ──

    @Test("@OWLProperty generates OntologyPropertyDescriptor for data properties")
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

    // ── Contract 3: ObjectProperty descriptor ──

    @Test("@OWLProperty with to: generates ObjectProperty descriptor")
    func objectPropertyDescriptor() {
        let descs = OntEmployeeWithFK.ontologyPropertyDescriptors
        let worksFor = descs.first { $0.fieldName == "departmentID" }
        #expect(worksFor != nil)
        #expect(worksFor?.iri == "ex:worksFor")
        #expect(worksFor?.isObjectProperty == true)
        #expect(worksFor?.targetTypeName == "OntDepartment")
        #expect(worksFor?.targetFieldName == "id")
    }

    @Test("ObjectProperty auto-generates reverse index with @OWLProperty")
    func objectPropertyReverseIndex() {
        let indexes = OntEmployeeWithFK.indexDescriptors
        let reverseIdx = indexes.first { $0.name.contains("departmentID") }
        #expect(reverseIdx != nil)
    }

    // ── Contract 4: 標準機能との共存 ──

    @Test("Ontology features coexist with #Index and @Transient")
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

    // ── Contract 5: Schema.ontology ──

    @Test("Schema accepts ontology parameter")
    func schemaOntology() {
        let ontology = OWLOntology(iri: "http://example.org/onto")
        let schema = Schema([OntEmployee.self], ontology: ontology.asSchemaOntology())
        #expect(schema.ontology != nil)
        #expect(schema.ontology?.iri == "http://example.org/onto")
        #expect(schema.ontology?.typeIdentifier == "OWLOntology")
    }

    @Test("Schema without ontology defaults to nil")
    func schemaNoOntology() {
        let schema = Schema([OntEmployee.self])
        #expect(schema.ontology == nil)
    }

    @Test("Schema.Ontology round-trips through JSON")
    func schemaOntologyRoundTrip() throws {
        var original = OWLOntology(iri: "http://example.org/onto")
        original.classes.append(OWLClass(iri: "ex:Person", label: "Person"))
        let schemaOntology = original.asSchemaOntology()

        // Round-trip through JSON
        let data = try JSONEncoder().encode(schemaOntology)
        let decoded = try JSONDecoder().decode(Schema.Ontology.self, from: data)
        #expect(decoded.iri == "http://example.org/onto")
        #expect(decoded.typeIdentifier == "OWLOntology")

        // Restore to OWLOntology
        let restored = try OWLOntology(schemaOntology: decoded)
        #expect(restored.iri == "http://example.org/onto")
        #expect(restored.classes.count == 1)
        #expect(restored.classes.first?.iri == "ex:Person")
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

    // ── Contract 7: IRI 解決 ──

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

    // ── Contract 8: フル IRI @Ontology でのローカル名解決 ──

    @Test("IRI resolution with full IRI @Ontology")
    func fullIRIOntologyResolution() {
        #expect(OntFullIRI.ontologyClassIRI == "http://example.org/onto#FullIRIEntity")

        let descs = OntFullIRI.ontologyPropertyDescriptors
        let desc = descs.first { $0.fieldName == "localField" }
        #expect(desc?.iri == "http://example.org/onto#localField")
    }

    // ── Contract 9: フル IRI @Ontology + DataProperty + ObjectProperty ──

    @Test("Full IRI @Ontology with DataProperty and ObjectProperty")
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

    @Test("Full IRI @Ontology ObjectProperty generates reverse index")
    func fullIRIObjectPropertyReverseIndex() {
        let indexes = OntFullEmployee.indexDescriptors
        let reverseIdx = indexes.first { $0.name.contains("departmentID") }
        #expect(reverseIdx != nil)
    }

    // ── Contract 10: フル IRI @Ontology + 標準機能との共存 ──

    @Test("Full IRI @Ontology coexists with #Index and @Transient")
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

    // ── Contract 12: フル IRI @Ontology (/ 区切り) でのローカル名解決 ──

    @Test("IRI resolution with slash-separated full IRI @Ontology")
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

    // ── Contract 13: フル IRI @Ontology (# 区切り) + CURIE/フルIRI 混在 ──

    @Test("IRI resolution with hash-separated full IRI @Ontology and mixed property IRIs")
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

    // ── Contract 14: ベア名 @Ontology (デフォルト ex: 名前空間) ──

    @Test("Bare name @Ontology defaults to ex: namespace")
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

    // ── Contract 11: フル IRI @Ontology の Persistable 基本機能 ──

    @Test("Full IRI @Ontology retains Persistable features")
    func fullIRIPersistableBasics() {
        #expect(OntFullEmployee.persistableType == "OntFullEmployee")
        #expect(OntFullEmployee.allFields.contains("id"))
        #expect(OntFullEmployee.allFields.contains("name"))
        #expect(OntFullEmployee.allFields.contains("age"))
        #expect(OntFullEmployee.allFields.contains("departmentID"))

        let e = OntFullEmployee(name: "Charlie", age: 40, departmentID: nil)
        #expect(e.id.count == 26)
    }

    // ── Contract 15: Complex OWLOntology type-erasure round-trip ──

    @Test("Complex OWLOntology with axioms, properties, individuals round-trips through Schema.Ontology")
    func complexOntologyRoundTrip() throws {
        var original = OWLOntology(iri: "http://example.org/complex")
        original.classes = [
            OWLClass(iri: "ex:Organization"),
            OWLClass(iri: "ex:Company"),
            OWLClass(iri: "ex:TechCompany"),
        ]
        original.objectProperties = [
            OWLObjectProperty(
                iri: "ex:worksFor",
                domains: [.named("ex:Person")],
                ranges: [.named("ex:Company")]
            ),
        ]
        original.dataProperties = [
            OWLDataProperty(iri: "ex:name", domains: [.named("ex:Person")]),
        ]
        original.axioms = [
            .subClassOf(sub: .named("ex:Company"), sup: .named("ex:Organization")),
            .subClassOf(sub: .named("ex:TechCompany"), sup: .named("ex:Company")),
            .equivalentClasses([
                .named("ex:TechCompany"),
                .intersection([
                    .named("ex:Company"),
                    .dataHasValue(property: "ex:industry", literal: .string("Tech")),
                ]),
            ]),
            .disjointClasses([.named("ex:Organization"), .named("ex:TechCompany")]),
        ]
        original.individuals = [
            OWLNamedIndividual(iri: "ex:Google"),
        ]

        // OWLOntology → Schema.Ontology → JSON → Schema.Ontology → OWLOntology
        let schemaOntology = original.asSchemaOntology()
        let json = try JSONEncoder().encode(schemaOntology)
        let decoded = try JSONDecoder().decode(Schema.Ontology.self, from: json)
        let restored = try OWLOntology(schemaOntology: decoded)

        #expect(restored.iri == "http://example.org/complex")
        #expect(restored.classes.count == 3)
        #expect(restored.objectProperties.count == 1)
        #expect(restored.objectProperties[0].iri == "ex:worksFor")
        #expect(restored.dataProperties.count == 1)
        #expect(restored.dataProperties[0].iri == "ex:name")
        #expect(restored.axioms.count == 4)
        #expect(restored.individuals.count == 1)
        #expect(restored.individuals[0].iri == "ex:Google")
    }

    @Test("Schema.Ontology preserves Hashable equality")
    func schemaOntologyHashable() {
        let ontology = OWLOntology(iri: "http://example.org/test")
        let a = ontology.asSchemaOntology()
        let b = ontology.asSchemaOntology()
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
    }

    // ── Contract 16: SchemaResponse transport ──

    @Test("SchemaResponse with ontology round-trips through JSON")
    func schemaResponseWithOntology() throws {
        let ontology = OWLOntology(iri: "http://example.org/onto")
        let entity = Schema([OntEmployee.self]).entities[0]
        let response = SchemaResponse(
            entities: [entity],
            ontology: ontology.asSchemaOntology()
        )

        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(SchemaResponse.self, from: data)

        #expect(decoded.entities.count == 1)
        #expect(decoded.entities[0].name == entity.name)
        #expect(decoded.ontology != nil)
        #expect(decoded.ontology?.iri == "http://example.org/onto")
        #expect(decoded.ontology?.typeIdentifier == "OWLOntology")
    }

    @Test("SchemaResponse without ontology round-trips through JSON")
    func schemaResponseWithoutOntology() throws {
        let entity = Schema([OntEmployee.self]).entities[0]
        let response = SchemaResponse(entities: [entity])

        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(SchemaResponse.self, from: data)

        #expect(decoded.entities.count == 1)
        #expect(decoded.ontology == nil)
    }

    @Test("SchemaResponse backward-compatible: missing ontology key decodes as nil")
    func schemaResponseBackwardCompatibility() throws {
        // Simulate old server response without ontology field
        let entity = Schema([OntEmployee.self]).entities[0]
        let entityJSON = try JSONEncoder().encode([entity])
        let json = """
        {"entities":\(String(data: entityJSON, encoding: .utf8)!)}
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(SchemaResponse.self, from: json)
        #expect(decoded.entities.count == 1)
        #expect(decoded.ontology == nil)
    }
}
