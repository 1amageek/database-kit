import DatabaseTypes

extension RDFLiteral: @retroactive Codable {
    private enum CodingKeys: String, CodingKey {
        case lexicalForm
        case annotation
        case datatype
        case language
        case direction
    }

    private enum AnnotationKind: String, Codable {
        case typed
        case languageTagged
        case directionalLanguageTagged
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let lexicalForm = try container.decode(
            String.self,
            forKey: .lexicalForm
        )
        let annotation = try container.decode(
            AnnotationKind.self,
            forKey: .annotation
        )
        switch annotation {
        case .typed:
            try Self.reject(
                [.language, .direction],
                in: container
            )
            let rawDatatype = try container.decode(
                String.self,
                forKey: .datatype
            )
            let datatype: RDFTypedLiteralDatatype
            do {
                datatype = try RDFTypedLiteralDatatype(rawDatatype)
            } catch {
                throw DecodingError.dataCorruptedError(
                    forKey: .datatype,
                    in: container,
                    debugDescription: "Invalid RDF typed-literal datatype IRI"
                )
            }
            self.init(lexicalForm: lexicalForm, datatype: datatype)
        case .languageTagged:
            try Self.reject(
                [.datatype, .direction],
                in: container
            )
            self.init(
                lexicalForm: lexicalForm,
                language: try Self.decodeLanguage(from: container)
            )
        case .directionalLanguageTagged:
            try Self.reject([.datatype], in: container)
            let rawDirection = try container.decode(
                String.self,
                forKey: .direction
            )
            guard let direction = RDFDirection(rawValue: rawDirection) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .direction,
                    in: container,
                    debugDescription: "Invalid RDF base direction"
                )
            }
            self.init(
                lexicalForm: lexicalForm,
                language: try Self.decodeLanguage(from: container),
                direction: direction
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(lexicalForm, forKey: .lexicalForm)
        switch annotation {
        case .typed(let datatype):
            try container.encode(AnnotationKind.typed, forKey: .annotation)
            try container.encode(datatype.rawValue, forKey: .datatype)
        case .languageTagged(let language):
            try container.encode(
                AnnotationKind.languageTagged,
                forKey: .annotation
            )
            try container.encode(language.rawValue, forKey: .language)
        case .directionalLanguageTagged(let language, let direction):
            try container.encode(
                AnnotationKind.directionalLanguageTagged,
                forKey: .annotation
            )
            try container.encode(language.rawValue, forKey: .language)
            try container.encode(direction.rawValue, forKey: .direction)
        }
    }

    private static func decodeLanguage(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> RDFLanguageTag {
        let rawLanguage = try container.decode(String.self, forKey: .language)
        do {
            return try RDFLanguageTag(rawLanguage)
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .language,
                in: container,
                debugDescription: "Invalid BCP 47 RDF language tag"
            )
        }
    }

    private static func reject(
        _ keys: [CodingKeys],
        in container: KeyedDecodingContainer<CodingKeys>
    ) throws {
        for key in keys where container.contains(key) {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "Field is invalid for this RDF literal annotation"
            )
        }
    }
}
