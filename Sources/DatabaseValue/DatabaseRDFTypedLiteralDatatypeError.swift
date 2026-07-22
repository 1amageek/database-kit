public enum DatabaseRDFTypedLiteralDatatypeError: Error, Sendable, Equatable {
    case invalidIRI(DatabaseRDFIRIError)
    case languageDatatypeRequiresLanguage
    case directionalLanguageDatatypeRequiresLanguageAndDirection
}
