import Testing
@testable import DatabaseKit

@Suite("SPARQL Variable")
struct VariableTests {
    @Test("Initializer canonicalizes supported SPARQL sigils")
    func canonicalizesSigils() {
        #expect(Variable("value").name == "value")
        #expect(Variable("?value").name == "value")
        #expect(Variable("$value").name == "value")
        #expect(Variable("?value").description == "?value")
        #expect(Variable("$value").description == "?value")
    }

    @Test("Initializer removes only one leading sigil")
    func removesOnlyOneSigil() {
        #expect(Variable("??value").name == "?value")
        #expect(Variable("$$value").name == "$value")
    }
}
