import DatabaseTypes
import DatabaseValue
import Testing
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import GraphMacros

@Suite("@OWL Macro IRI Diagnostic Tests")
struct OWLMacroIRIDiagnosticTests {
    @Test("@OWLClass rejects relative and bare class IRIs")
    func rejectsRelativeAndBareClassIRIs() {
        assertInvalidClassIRI("Person")
        assertInvalidClassIRI("ontology/Person")
    }

    @Test("@OWLDataProperty rejects relative property IRIs")
    func rejectsRelativePropertyIRI() {
        assertMacroExpansion(
            """
            @OWLDataProperty("properties/name")
            var name: String
            """,
            expandedSource: """
            var name: String
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@OWLDataProperty IRI must be absolute",
                    line: 1,
                    column: 18
                )
            ],
            macros: owlMacros
        )
    }

    @Test("@OWLClass rejects a relative individual IRI base")
    func rejectsRelativeIndividualIRIBase() {
        assertMacroExpansion(
            """
            @OWLClass(
                "https://example.org/ontology/Person",
                individualIRIBase: "individuals/"
            )
            struct Person {
                var id: String
            }
            """,
            expandedSource: """
            struct Person {
                var id: String
            }

            extension Person: OWLClassEntity {
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@OWLClass 'individualIRIBase:' must be an absolute IRI",
                    line: 1,
                    column: 1
                )
            ],
            macros: owlMacros
        )
    }

    @Test("@OWLClass rejects a relative graph IRI")
    func rejectsRelativeGraphIRI() {
        assertMacroExpansion(
            """
            @OWLClass(
                "https://example.org/ontology/Person",
                individualIRIBase: "https://example.org/individuals/",
                graph: "graphs/people"
            )
            struct Person {
                var id: String
            }
            """,
            expandedSource: """
            struct Person {
                var id: String
            }

            extension Person: OWLClassEntity {
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@OWLClass 'graph:' must be an absolute IRI",
                    line: 1,
                    column: 1
                )
            ],
            macros: owlMacros
        )
    }

    @Test("OWL IRI arguments reject string interpolation")
    func rejectsInterpolatedIRIs() {
        assertMacroExpansion(
            """
            @OWLClass(
                "https://example.org/ontology/\\(className)",
                individualIRIBase: "https://example.org/individuals/"
            )
            struct Person {
                var id: String
            }
            """,
            expandedSource: """
            struct Person {
                var id: String
            }

            extension Person: OWLClassEntity {
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@OWLClass class IRI must be a plain string literal",
                    line: 2,
                    column: 5
                )
            ],
            macros: owlMacros
        )

        assertMacroExpansion(
            """
            @OWLDataProperty("https://example.org/properties/\\(propertyName)")
            var name: String
            """,
            expandedSource: """
            var name: String
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@OWLDataProperty first argument must be a plain string literal",
                    line: 1,
                    column: 18
                )
            ],
            macros: owlMacros
        )
    }

    @Test("OWL object properties must reference the target id")
    func rejectsObjectPropertyTargetOtherThanID() {
        assertMacroExpansion(
            """
            @OWLClass(
                "https://example.org/ontology/Employee",
                individualIRIBase: "https://example.org/individuals/"
            )
            struct Employee {
                @OWLDataProperty("https://example.org/ontology/worksFor", to: \\Department.slug)
                var departmentID: String
                var id: String
            }
            """,
            expandedSource: """
            struct Employee {
                var departmentID: String
                var id: String
            }

            extension Employee: OWLClassEntity {
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "OWL object properties must reference the target id field",
                    line: 6,
                    column: 5
                )
            ],
            macros: owlMacros
        )
    }

    private func assertInvalidClassIRI(_ iri: String) {
        assertMacroExpansion(
            """
            @OWLClass(
                "\(iri)",
                individualIRIBase: "https://example.org/individuals/"
            )
            struct Person {
                var id: String
            }
            """,
            expandedSource: """
            struct Person {
                var id: String
            }

            extension Person: OWLClassEntity {
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@OWLClass class IRI must be absolute",
                    line: 2,
                    column: 5
                )
            ],
            macros: owlMacros
        )
    }

    private var owlMacros: [String: Macro.Type] {
        [
            "OWLClass": OWLClassMacro.self,
            "OWLDataProperty": OWLDataPropertyMacro.self,
        ]
    }
}
