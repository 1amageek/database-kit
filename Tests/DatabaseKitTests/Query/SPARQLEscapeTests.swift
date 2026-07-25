import DatabaseKit
import Testing

@Suite("SPARQL escaping")
struct SPARQLEscapeTests {
    @Test("NCName accepts the complete XML character classes")
    func ncNameCharacterClasses() throws {
        #expect(try SPARQLEscape.ncName("日本語") == "日本語")
        #expect(try SPARQLEscape.ncName("éclair") == "éclair")
        #expect(try SPARQLEscape.ncName("_value.1") == "_value.1")
        #expect(SPARQLEscape.ncNameOrNil("1value") == nil)
        #expect(SPARQLEscape.ncNameOrNil("name:value") == nil)
    }

    @Test("SPARQL prefixes follow PN_PREFIX")
    func prefixGrammar() {
        #expect(SPARQLEscape.prefixOrNil("") == "")
        #expect(SPARQLEscape.prefixOrNil("schema") == "schema")
        #expect(SPARQLEscape.prefixOrNil("名前.空間") == "名前.空間")
        #expect(SPARQLEscape.prefixOrNil("_schema") == nil)
        #expect(SPARQLEscape.prefixOrNil("schema.") == nil)
    }

    @Test("SPARQL local names accept escapes and reject trailing periods")
    func localNameGrammar() {
        #expect(SPARQLEscape.localNameOrNil("") == "")
        #expect(SPARQLEscape.localNameOrNil("1:item") == "1:item")
        #expect(SPARQLEscape.localNameOrNil("item%20name") == "item%20name")
        #expect(SPARQLEscape.localNameOrNil(#"item\~name"#) == #"item\~name"#)
        #expect(SPARQLEscape.localNameOrNil("item.") == nil)
        #expect(SPARQLEscape.localNameOrNil("item%2") == nil)
        #expect(SPARQLEscape.localNameOrNil(#"item\x"#) == nil)
    }

    @Test("Blank-node fallback is deterministic and injective")
    func blankNodeFallback() {
        #expect(SPARQLEscape.blankNodeLabel("1node") == "1node")
        #expect(SPARQLEscape.blankNodeLabel("node.") == "z6e6f64652e")
        #expect(SPARQLEscape.blankNodeLabel("") == "z")
        #expect(SPARQLEscape.blankNodeLabel("z") == "z7a")
        #expect(
            SPARQLEscape.blankNodeLabel("z6e6f64652e")
                != SPARQLEscape.blankNodeLabel("node.")
        )
        #expect(
            SPARQLTerm.blankNode("node.").toSPARQL()
                == "_:z6e6f64652e"
        )
    }

    @Test("IRI references escape every forbidden scalar")
    func iriReferenceEscaping() {
        #expect(
            SPARQLEscape.iri("https://example.invalid/a b\u{0001}")
                == "<https://example.invalid/a%20b%01>"
        )
        #expect(
            SPARQLEscape.iri(#"https://example.invalid/<>{}|\^`""#)
                == "<https://example.invalid/%3C%3E%7B%7D%7C%5C%5E%60%22>"
        )
    }

    @Test("String literals escape controls without losing Unicode")
    func stringEscaping() {
        #expect(
            SPARQLEscape.string("日本語\u{0000}\u{0008}\u{000C}")
                == #""日本語\u0000\b\f""#
        )
    }

    @Test("IRI abbreviation selects the longest base deterministically")
    func deterministicPrefixSelection() {
        let term = SPARQLTerm.iri("https://example.invalid/ns/item")
        let prefixes = [
            "root": "https://example.invalid/",
            "z": "https://example.invalid/ns/",
            "a": "https://example.invalid/ns/",
        ]

        #expect(term.toSPARQL(prefixes: prefixes) == "a:item")
    }
}
