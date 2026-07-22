public import DatabaseValue

extension DatabaseRDFLiteral {
    public func encode(into writer: inout DatabaseWireWriter) throws(DatabaseWireError) {
        try writer.writeString(lexicalForm)
        switch annotation {
        case .typed(let datatype):
            writer.writeUInt8(0)
            try writer.writeString(datatype.rawValue)
        case .languageTagged(let language):
            writer.writeUInt8(1)
            try writer.writeString(language.rawValue)
        case .directionalLanguageTagged(let language, let direction):
            writer.writeUInt8(2)
            try writer.writeString(language.rawValue)
            writer.writeUInt8(direction == .leftToRight ? 0 : 1)
        }
    }

    public init(from reader: inout DatabaseWireReader) throws(DatabaseWireError) {
        let lexicalForm = try reader.readString()
        switch try reader.readUInt8() {
        case 0:
            let rawDatatype = try reader.readString()
            let datatype: DatabaseRDFTypedLiteralDatatype
            do {
                datatype = try DatabaseRDFTypedLiteralDatatype(rawDatatype)
            } catch {
                throw .invalidRDFDatatypeIRI
            }
            self.init(lexicalForm: lexicalForm, datatype: datatype)
        case 1:
            let language = try Self.readLanguageTag(from: &reader)
            self.init(lexicalForm: lexicalForm, language: language)
        case 2:
            let language = try Self.readLanguageTag(from: &reader)
            let direction: DatabaseRDFDirection
            switch try reader.readUInt8() {
            case 0: direction = .leftToRight
            case 1: direction = .rightToLeft
            case let tag: throw .invalidRDFDirection(tag)
            }
            self.init(
                lexicalForm: lexicalForm,
                language: language,
                direction: direction
            )
        case let tag:
            throw .invalidRDFLiteralAnnotation(tag)
        }
    }

    private static func readLanguageTag(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> DatabaseRDFLanguageTag {
        let rawLanguage = try reader.readString()
        let language: DatabaseRDFLanguageTag
        do {
            language = try DatabaseRDFLanguageTag(rawLanguage)
        } catch {
            throw .invalidRDFLanguageTag
        }
        guard language.rawValue.utf8.elementsEqual(rawLanguage.utf8) else {
            throw .nonCanonicalRDFLanguageTag
        }
        return language
    }
}
