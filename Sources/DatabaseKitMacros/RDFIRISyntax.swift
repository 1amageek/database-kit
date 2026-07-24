import DatabaseTypes

enum RDFIRISyntax {
    static func isValid(_ value: String) -> Bool {
        do {
            _ = try RDFIRI(value)
            return true
        } catch {
            return false
        }
    }
}
