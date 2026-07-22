public enum DatabaseRDFIRIValidator {
    public static func isAbsolute(_ value: String) -> Bool {
        do {
            try DatabaseRDFIRIParser.validate(value)
            return true
        } catch {
            return false
        }
    }
}
