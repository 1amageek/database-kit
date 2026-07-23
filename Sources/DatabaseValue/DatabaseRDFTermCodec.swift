/// Canonical, bounded, zero-byte-free encoding for RDF terms stored in database keys.
///
/// The returned `DatabaseBytes` owns exactly one final payload allocation.
/// Decoding borrows slices from that owner until an RDF string must be owned.
/// The zero-byte-free representation lets tuple decoders retain RDF key
/// components as views instead of allocating an unescaped buffer.
public enum DatabaseRDFTermCodec {
    /// Validates a semantic RDF term without allocating an encoded payload.
    public static func validate(
        _ term: DatabaseRDFTerm,
        role: DatabaseRDFTermRole = .term,
        limits: DatabaseRDFTermCodecLimits = .default
    ) throws(DatabaseRDFTermCodecError) {
        try validate(term.rdfTermKind, for: role)
        var measurement = TermEncoder(
            sink: MeasurementSink(),
            emitsBytes: false,
            limits: limits
        )
        try measurement.encode(term)
    }

    /// Validates canonical bytes without materializing RDF terms or strings.
    @discardableResult
    public static func validate(
        _ bytes: DatabaseBytes,
        role: DatabaseRDFTermRole = .term,
        limits: DatabaseRDFTermCodecLimits = .default
    ) throws(DatabaseRDFTermCodecError) -> DatabaseRDFTermKind {
        try withValidatedBytes(
            bytes,
            role: role,
            limits: limits
        ) { _, validation in
            validation.kind
        }
    }

    /// Validates and lends the same canonical storage in one owner borrow.
    ///
    /// `buffer` is valid only for the synchronous borrow and must not escape.
    /// The borrow closure is nonthrowing so the codec retains a precise typed-error
    /// contract; callers can return their own `Result` when needed.
    public static func withValidatedBytes<BodyResult>(
        _ bytes: DatabaseBytes,
        role: DatabaseRDFTermRole = .term,
        limits: DatabaseRDFTermCodecLimits = .default,
        _ body: (
            UnsafeRawBufferPointer,
            DatabaseRDFTermEncodingValidation
        ) -> BodyResult
    ) throws(DatabaseRDFTermCodecError) -> BodyResult {
        guard bytes.count <= limits.maximumBytes else {
            throw .maximumBytesExceeded(
                actual: bytes.count,
                maximum: limits.maximumBytes
            )
        }
        let result: Result<BodyResult, DatabaseRDFTermCodecError>
            = bytes.withUnsafeBytes { buffer in
                do {
                    let metrics = try validate(
                        buffer,
                        role: role,
                        limits: limits
                    )
                    let validation = DatabaseRDFTermEncodingValidation(
                        kind: metrics.kind,
                        fingerprint: DatabaseRDFTermEncodingFingerprint(buffer),
                        objectCount: metrics.objectCount,
                        maximumDepth: metrics.maximumDepth
                    )
                    return .success(body(buffer, validation))
                } catch let error as DatabaseRDFTermCodecError {
                    return .failure(error)
                } catch {
                    preconditionFailure(
                        "Unexpected RDF term encoding validation error"
                    )
                }
            }
        switch result {
        case .success(let value):
            return value
        case .failure(let error):
            throw error
        }
    }

    public static func encode(
        _ term: DatabaseRDFTerm,
        role: DatabaseRDFTermRole = .term,
        limits: DatabaseRDFTermCodecLimits = .default
    ) throws(DatabaseRDFTermCodecError) -> DatabaseBytes {
        let plan = try encodingPlan(term, role: role, limits: limits)

        do {
            return try DatabaseBytes.copying(count: plan.byteCount) { output in
                try encode(plan, into: output)
            }
        } catch let error as DatabaseRDFTermCodecError {
            throw error
        } catch {
            preconditionFailure("Unexpected RDF term encoding error")
        }
    }

    /// Returns the exact canonical byte count without allocating a payload.
    public static func encodedByteCount(
        _ term: DatabaseRDFTerm,
        role: DatabaseRDFTermRole = .term,
        limits: DatabaseRDFTermCodecLimits = .default
    ) throws(DatabaseRDFTermCodecError) -> Int {
        try encodingPlan(term, role: role, limits: limits).byteCount
    }

    /// Measures and validates a term once for direct initialization of final storage.
    public static func encodingPlan(
        _ term: DatabaseRDFTerm,
        role: DatabaseRDFTermRole = .term,
        limits: DatabaseRDFTermCodecLimits = .default
    ) throws(DatabaseRDFTermCodecError) -> DatabaseRDFTermEncodingPlan {
        try validate(term.rdfTermKind, for: role)
        var measurement = TermEncoder(
            sink: MeasurementSink(),
            emitsBytes: false,
            limits: limits
        )
        try measurement.encode(term)
        let byteCount = measurement.offset
        guard byteCount <= limits.maximumBytes else {
            throw .maximumBytesExceeded(
                actual: byteCount,
                maximum: limits.maximumBytes
            )
        }
        return DatabaseRDFTermEncodingPlan(
            term: term,
            limits: limits,
            byteCount: byteCount,
            objectCount: measurement.objectCount,
            maximumDepth: measurement.maximumDepth
        )
    }

    /// Initializes exactly the storage measured by `encodingPlan`.
    package static func encode(
        _ plan: DatabaseRDFTermEncodingPlan,
        into output: UnsafeMutableRawBufferPointer
    ) throws(DatabaseRDFTermCodecError) {
        guard output.count == plan.byteCount else {
            throw .byteCountOverflow
        }
        var sink = DestinationSink(output: output)
        try encode(plan, into: &sink)
        guard sink.offset == plan.byteCount else {
            throw .byteCountOverflow
        }
    }

    /// Streams a measured canonical representation directly into a synchronous
    /// destination without allocating an intermediate RDF payload.
    public static func encode<Sink: DatabaseRDFTermEncodingSink>(
        _ plan: DatabaseRDFTermEncodingPlan,
        into sink: inout Sink
    ) throws(DatabaseRDFTermCodecError) {
        var encoder = TermEncoder(
            sink: sink,
            emitsBytes: true,
            limits: plan.limits
        )
        try encoder.encode(plan.term)
        guard encoder.offset == plan.byteCount else {
            throw .byteCountOverflow
        }
        sink = encoder.sink
    }

    public static func decode(
        _ bytes: DatabaseBytes,
        role: DatabaseRDFTermRole = .term,
        limits: DatabaseRDFTermCodecLimits = .default
    ) throws(DatabaseRDFTermCodecError) -> DatabaseRDFTerm {
        try decodeWithMetrics(
            bytes,
            role: role,
            limits: limits
        ).term
    }

    public static func decodeWithMetrics(
        _ bytes: DatabaseBytes,
        role: DatabaseRDFTermRole = .term,
        limits: DatabaseRDFTermCodecLimits = .default
    ) throws(DatabaseRDFTermCodecError) -> DatabaseRDFTermDecodingResult {
        guard bytes.count <= limits.maximumBytes else {
            throw .maximumBytesExceeded(
                actual: bytes.count,
                maximum: limits.maximumBytes
            )
        }
        let result: Result<DatabaseRDFTermDecodingResult, DatabaseRDFTermCodecError>
            = bytes.withUnsafeBytes { buffer in
                do {
                    var reader = TermReader(bytes: buffer, limits: limits)
                    let term = try reader.readTerm(depth: 0)
                    guard reader.isAtEnd else {
                        return .failure(.trailingBytes)
                    }
                    try validate(term.rdfTermKind, for: role)
                    return .success(DatabaseRDFTermDecodingResult(
                        term: term,
                        objectCount: reader.objectCount,
                        maximumDepth: reader.maximumDepth
                    ))
                } catch let error as DatabaseRDFTermCodecError {
                    return .failure(error)
                } catch {
                    preconditionFailure(
                        "Unexpected RDF term decoding error"
                    )
                }
            }
        switch result {
        case .success(let result):
            return result
        case .failure(let error):
            throw error
        }
    }

    private static func validate(
        _ kind: DatabaseRDFTermKind,
        for role: DatabaseRDFTermRole
    ) throws(DatabaseRDFTermCodecError) {
        let isValid: Bool
        switch role {
        case .term:
            isValid = true
        case .subject, .graphName:
            isValid = kind == .iri || kind == .blankNode
        case .predicate:
            isValid = kind == .iri
        case .object:
            isValid = true
        }
        guard isValid else {
            throw .invalidRole(expected: role, actual: kind)
        }
    }

    private static func validate(
        _ buffer: UnsafeRawBufferPointer,
        role: DatabaseRDFTermRole,
        limits: DatabaseRDFTermCodecLimits
    ) throws(DatabaseRDFTermCodecError) -> (
        kind: DatabaseRDFTermKind,
        objectCount: Int,
        maximumDepth: Int
    ) {
        var validator = DatabaseRDFTermEncodingValidator(
            bytes: buffer,
            limits: limits
        )
        let kind = try validator.validateTerm(depth: 0)
        guard validator.isAtEnd else { throw .trailingBytes }
        try validate(kind, for: role)
        return (
            kind: kind,
            objectCount: validator.objectCount,
            maximumDepth: validator.maximumDepth
        )
    }

    private enum EncodingStep {
        case term(DatabaseRDFTerm, depth: Int)
        case string(String)
        case byte(UInt8)
    }

    private struct MeasurementSink: DatabaseRDFTermEncodingSink {
        mutating func write(_ byte: UInt8) {}

        mutating func write(_ bytes: UnsafeRawBufferPointer) {}
    }

    private struct DestinationSink: DatabaseRDFTermEncodingSink {
        let output: UnsafeMutableRawBufferPointer
        var offset = 0

        mutating func write(_ byte: UInt8) {
            output[offset] = byte
            offset += 1
        }

        mutating func write(_ bytes: UnsafeRawBufferPointer) {
            let destination = UnsafeMutableRawBufferPointer(
                rebasing: output[offset..<(offset + bytes.count)]
            )
            destination.copyMemory(from: bytes)
            offset += bytes.count
        }
    }

    private struct TermEncoder<Sink: DatabaseRDFTermEncodingSink> {
        var sink: Sink
        let emitsBytes: Bool
        let limits: DatabaseRDFTermCodecLimits
        var offset = 0
        var objectCount = 0
        var maximumDepth = 0

        mutating func encode(
            _ root: DatabaseRDFTerm
        ) throws(DatabaseRDFTermCodecError) {
            var encodingSteps: [EncodingStep] = [.term(root, depth: 0)]
            while let encodingStep = encodingSteps.popLast() {
                switch encodingStep {
                case .byte(let byte):
                    try append(byte)
                case .string(let value):
                    try appendString(value)
                case .term(let term, let depth):
                    try registerTerm(at: depth)
                    switch term {
                    case .blankNode(let identifier):
                        guard !identifier.isEmpty else {
                            throw .invalidBlankNodeIdentifier
                        }
                        try append(1)
                        encodingSteps.append(.string(identifier))
                    case .iri(let rawIRI):
                        do {
                            _ = try DatabaseRDFIRI(rawIRI)
                        } catch let error {
                            throw .invalidIRI(error)
                        }
                        try append(2)
                        encodingSteps.append(.string(rawIRI))
                    case .literal(let literal):
                        try append(3)
                        switch literal.annotation {
                        case .typed(let datatype):
                            encodingSteps.append(.string(datatype.rawValue))
                            encodingSteps.append(.byte(1))
                        case .languageTagged(let language):
                            encodingSteps.append(.string(language.rawValue))
                            encodingSteps.append(.byte(2))
                        case .directionalLanguageTagged(
                            let language,
                            let direction
                        ):
                            encodingSteps.append(.byte(
                                direction == .leftToRight ? 1 : 2
                            ))
                            encodingSteps.append(.string(language.rawValue))
                            encodingSteps.append(.byte(3))
                        }
                        encodingSteps.append(.string(literal.lexicalForm))
                    case .tripleTerm(let subject, let predicate, let object):
                        guard subject.isValidRDFSubject else {
                            throw .invalidTripleSubject
                        }
                        guard predicate.isValidRDFPredicate else {
                            throw .invalidTriplePredicate
                        }
                        try append(4)
                        let nestedDepth = depth + 1
                        encodingSteps.append(.term(object, depth: nestedDepth))
                        encodingSteps.append(.term(predicate, depth: nestedDepth))
                        encodingSteps.append(.term(subject, depth: nestedDepth))
                    }
                }
            }
        }

        private mutating func registerTerm(
            at depth: Int
        ) throws(DatabaseRDFTermCodecError) {
            guard depth <= limits.maximumDepth else {
                throw .maximumDepthExceeded(
                    actual: depth,
                    maximum: limits.maximumDepth
                )
            }
            let (nextCount, overflow) = objectCount.addingReportingOverflow(1)
            guard !overflow else { throw .byteCountOverflow }
            guard nextCount <= limits.maximumObjectCount else {
                throw .maximumObjectCountExceeded(
                    actual: nextCount,
                    maximum: limits.maximumObjectCount
                )
            }
            objectCount = nextCount
            maximumDepth = max(maximumDepth, depth)
        }

        private mutating func appendString(
            _ value: String
        ) throws(DatabaseRDFTermCodecError) {
            var encodedByteCount = 0
            var containsNUL = false
            for byte in value.utf8 {
                let increment = byte == 0 ? 2 : 1
                containsNUL = containsNUL || byte == 0
                let (nextCount, overflow) = encodedByteCount.addingReportingOverflow(
                    increment
                )
                guard !overflow else { throw .byteCountOverflow }
                encodedByteCount = nextCount
            }
            let (storedByteCount, overflow) = encodedByteCount.addingReportingOverflow(1)
            guard !overflow else { throw .byteCountOverflow }
            try appendVarint(UInt64(storedByteCount))
            try reserve(encodedByteCount)
            guard emitsBytes else { return }

            if !containsNUL {
                let usedContiguousStorage = value.utf8
                    .withContiguousStorageIfAvailable { bytes in
                        sink.write(UnsafeRawBufferPointer(bytes))
                        return true
                    } ?? false
                if usedContiguousStorage { return }
            }

            for byte in value.utf8 {
                if byte == 0 {
                    sink.write(0xC0)
                    sink.write(0x80)
                } else {
                    sink.write(byte)
                }
            }
        }

        private mutating func appendVarint(
            _ value: UInt64
        ) throws(DatabaseRDFTermCodecError) {
            var remaining = value
            while remaining >= 0x80 {
                try append(UInt8(remaining & 0x7F) | 0x80)
                remaining >>= 7
            }
            try append(UInt8(remaining))
        }

        private mutating func append(
            _ byte: UInt8
        ) throws(DatabaseRDFTermCodecError) {
            try reserve(1)
            if emitsBytes {
                sink.write(byte)
            }
        }

        private mutating func reserve(
            _ count: Int
        ) throws(DatabaseRDFTermCodecError) {
            let (nextOffset, overflow) = offset.addingReportingOverflow(count)
            guard !overflow, count >= 0 else { throw .byteCountOverflow }
            guard nextOffset <= limits.maximumBytes else {
                throw .maximumBytesExceeded(
                    actual: nextOffset,
                    maximum: limits.maximumBytes
                )
            }
            offset = nextOffset
        }
    }

    private struct TermReader {
        let bytes: UnsafeRawBufferPointer
        let limits: DatabaseRDFTermCodecLimits
        var offset = 0
        var objectCount = 0
        var maximumDepth = 0

        var isAtEnd: Bool { offset == bytes.count }

        mutating func readTerm(
            depth: Int
        ) throws(DatabaseRDFTermCodecError) -> DatabaseRDFTerm {
            try registerTerm(at: depth)
            switch try readByte() {
            case 1:
                let identifier = try readString()
                guard !identifier.isEmpty else {
                    throw .invalidBlankNodeIdentifier
                }
                return .blankNode(identifier)
            case 2:
                let rawIRI = try readString()
                do {
                    _ = try DatabaseRDFIRI(rawIRI)
                } catch let error {
                    throw .invalidIRI(error)
                }
                return .iri(rawIRI)
            case 3:
                return .literal(try readLiteral())
            case 4:
                let nestedDepth = depth + 1
                let subject = try readTerm(depth: nestedDepth)
                guard subject.isValidRDFSubject else {
                    throw .invalidTripleSubject
                }
                let predicate = try readTerm(depth: nestedDepth)
                guard predicate.isValidRDFPredicate else {
                    throw .invalidTriplePredicate
                }
                return .tripleTerm(
                    subject: subject,
                    predicate: predicate,
                    object: try readTerm(depth: nestedDepth)
                )
            case let tag:
                throw .unknownTag(tag)
            }
        }

        private mutating func readLiteral(
        ) throws(DatabaseRDFTermCodecError) -> DatabaseRDFLiteral {
            let lexicalForm = try readString()
            switch try readByte() {
            case 1:
                let rawDatatype = try readString()
                let datatype: DatabaseRDFTypedLiteralDatatype
                do {
                    datatype = try DatabaseRDFTypedLiteralDatatype(
                        rawDatatype
                    )
                } catch {
                    throw .invalidDatatypeIRI
                }
                return DatabaseRDFLiteral(
                    lexicalForm: lexicalForm,
                    datatype: datatype
                )
            case 2:
                return DatabaseRDFLiteral(
                    lexicalForm: lexicalForm,
                    language: try readLanguageTag()
                )
            case 3:
                let language = try readLanguageTag()
                let direction: DatabaseRDFDirection
                switch try readByte() {
                case 1: direction = .leftToRight
                case 2: direction = .rightToLeft
                case let tag: throw .invalidDirection(tag)
                }
                return DatabaseRDFLiteral(
                    lexicalForm: lexicalForm,
                    language: language,
                    direction: direction
                )
            case let tag:
                throw .invalidLiteralAnnotation(tag)
            }
        }

        private mutating func readLanguageTag(
        ) throws(DatabaseRDFTermCodecError) -> DatabaseRDFLanguageTag {
            let rawLanguage = try readString()
            let language: DatabaseRDFLanguageTag
            do {
                language = try DatabaseRDFLanguageTag(rawLanguage)
            } catch {
                throw .invalidLanguageTag
            }
            guard language.rawValue.utf8.elementsEqual(rawLanguage.utf8) else {
                throw .nonCanonicalLanguageTag
            }
            return language
        }

        private mutating func readString(
        ) throws(DatabaseRDFTermCodecError) -> String {
            let storedByteCount = try readCount()
            guard storedByteCount > 0 else {
                throw .nonCanonicalStringEncoding
            }
            let encodedByteCount = storedByteCount - 1
            guard encodedByteCount <= bytes.count - offset else {
                throw .truncated
            }
            let encoded = UnsafeRawBufferPointer(
                rebasing: bytes[offset..<(offset + encodedByteCount)]
            )
            offset += encodedByteCount

            var escapedZeroCount = 0
            var cursor = 0
            while cursor < encoded.count {
                switch encoded[cursor] {
                case 0:
                    throw .nonCanonicalStringEncoding
                case 0xC0:
                    guard cursor + 1 < encoded.count,
                          encoded[cursor + 1] == 0x80 else {
                        throw .invalidUTF8
                    }
                    escapedZeroCount += 1
                    cursor += 2
                default:
                    cursor += 1
                }
            }

            guard escapedZeroCount > 0 else {
                guard let value = DatabaseUTF8Decoder.decode(encoded) else {
                    throw .invalidUTF8
                }
                return value
            }

            // A semantic String must own valid UTF-8. Only the uncommon escaped-NUL
            // path needs a temporary canonical UTF-8 buffer before that boundary.
            let decodedByteCount = encoded.count - escapedZeroCount
            let decoded = DatabaseBytes.copying(count: decodedByteCount) { output in
                var source = 0
                var destination = 0
                while source < encoded.count {
                    if encoded[source] == 0xC0 {
                        output[destination] = 0
                        source += 2
                    } else {
                        output[destination] = encoded[source]
                        source += 1
                    }
                    destination += 1
                }
            }
            guard let value = DatabaseUTF8Decoder.decode(decoded) else {
                throw .invalidUTF8
            }
            return value
        }

        private mutating func readCount(
        ) throws(DatabaseRDFTermCodecError) -> Int {
            var value: UInt64 = 0
            for byteIndex in 0..<10 {
                let byte = try readByte()
                if byteIndex == 9, byte & 0xFE != 0 {
                    throw .nonCanonicalVarint
                }
                value |= UInt64(byte & 0x7F) << UInt64(byteIndex * 7)
                if byte & 0x80 == 0 {
                    if byteIndex > 0, byte == 0 {
                        throw .nonCanonicalVarint
                    }
                    guard let count = Int(exactly: value) else {
                        throw .byteCountOverflow
                    }
                    return count
                }
            }
            throw .nonCanonicalVarint
        }

        private mutating func readByte(
        ) throws(DatabaseRDFTermCodecError) -> UInt8 {
            guard offset < bytes.count else { throw .truncated }
            let byte = bytes[offset]
            offset += 1
            return byte
        }

        private mutating func registerTerm(
            at depth: Int
        ) throws(DatabaseRDFTermCodecError) {
            guard depth <= limits.maximumDepth else {
                throw .maximumDepthExceeded(
                    actual: depth,
                    maximum: limits.maximumDepth
                )
            }
            let (nextCount, overflow) = objectCount.addingReportingOverflow(1)
            guard !overflow else { throw .byteCountOverflow }
            guard nextCount <= limits.maximumObjectCount else {
                throw .maximumObjectCountExceeded(
                    actual: nextCount,
                    maximum: limits.maximumObjectCount
                )
            }
            objectCount = nextCount
            maximumDepth = max(maximumDepth, depth)
        }
    }
}

private extension DatabaseRDFTerm {
    var rdfTermKind: DatabaseRDFTermKind {
        switch self {
        case .blankNode: .blankNode
        case .iri: .iri
        case .literal: .literal
        case .tripleTerm: .tripleTerm
        }
    }

    var isValidRDFSubject: Bool {
        switch self {
        case .iri, .blankNode: true
        case .literal, .tripleTerm: false
        }
    }

    var isValidRDFPredicate: Bool {
        if case .iri = self { true } else { false }
    }
}
