public struct DatabaseRDFLiteral: Sendable, Hashable {
    public let lexicalForm: String
    public let annotation: DatabaseRDFLiteralAnnotation

    public init(
        lexicalForm: String,
        annotation: DatabaseRDFLiteralAnnotation
    ) {
        self.lexicalForm = lexicalForm
        self.annotation = annotation
    }

    public init(
        lexicalForm: String,
        datatype: DatabaseRDFTypedLiteralDatatype
    ) {
        self.init(lexicalForm: lexicalForm, annotation: .typed(datatype))
    }

    public init(
        lexicalForm: String,
        datatype: String
    ) throws(DatabaseRDFTypedLiteralDatatypeError) {
        self.init(
            lexicalForm: lexicalForm,
            datatype: try DatabaseRDFTypedLiteralDatatype(datatype)
        )
    }

    public init(
        lexicalForm: String,
        language: DatabaseRDFLanguageTag
    ) {
        self.init(
            lexicalForm: lexicalForm,
            annotation: .languageTagged(language)
        )
    }

    public init(
        lexicalForm: String,
        language: String
    ) throws(DatabaseRDFLanguageTagError) {
        self.init(
            lexicalForm: lexicalForm,
            language: try DatabaseRDFLanguageTag(language)
        )
    }

    public init(
        lexicalForm: String,
        language: DatabaseRDFLanguageTag,
        direction: DatabaseRDFDirection
    ) {
        self.init(
            lexicalForm: lexicalForm,
            annotation: .directionalLanguageTagged(language, direction)
        )
    }

    public var datatypeIRI: DatabaseRDFIRI { annotation.datatype }
    public var datatype: String { annotation.datatype.rawValue }
    public var languageTag: DatabaseRDFLanguageTag? { annotation.language }
    public var language: String? { annotation.language?.rawValue }
    public var baseDirection: DatabaseRDFDirection? { annotation.direction }
    public var direction: String? { annotation.direction?.rawValue }

    public static func == (
        lhs: DatabaseRDFLiteral,
        rhs: DatabaseRDFLiteral
    ) -> Bool {
        DatabaseStringIdentity.equal(lhs.lexicalForm, rhs.lexicalForm)
            && lhs.annotation == rhs.annotation
    }

    public func hash(into hasher: inout Hasher) {
        DatabaseStringIdentity.hash(lexicalForm, into: &hasher)
        hasher.combine(annotation)
    }
}
