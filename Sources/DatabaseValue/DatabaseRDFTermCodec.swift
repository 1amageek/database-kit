import DatabaseTypes

/// Canonical, bounded, zero-byte-free encoding for RDF terms stored in database keys.
///
/// The returned `ByteString` owns exactly one final payload allocation.
/// Decoding borrows slices from that owner until an RDF string must be owned.
/// The zero-byte-free representation lets tuple decoders retain RDF key
/// components as views instead of allocating an unescaped buffer.
public enum RDFTermCodec {
    /// Validates a semantic RDF term without allocating an encoded payload.
    public static func validate(
        _ term: RDFTerm,
        role: RDFTermRole = .term,
        limits: RDFTermCodecLimits = .default
    ) throws(RDFTermCodecError) {
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
        _ bytes: ByteString,
        role: RDFTermRole = .term,
        limits: RDFTermCodecLimits = .default
    ) throws(RDFTermCodecError) -> RDFTermKind {
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
        _ bytes: ByteString,
        role: RDFTermRole = .term,
        limits: RDFTermCodecLimits = .default,
        _ body: (
            UnsafeRawBufferPointer,
            RDFTermEncodingValidation
        ) -> BodyResult
    ) throws(RDFTermCodecError) -> BodyResult {
        guard bytes.count <= limits.maximumBytes else {
            throw .maximumBytesExceeded(
                actual: bytes.count,
                maximum: limits.maximumBytes
            )
        }
        let result: Result<BodyResult, RDFTermCodecError>
            = bytes.withUnsafeBytes { buffer in
                do {
                    let metrics = try validate(
                        buffer,
                        role: role,
                        limits: limits
                    )
                    let validation = RDFTermEncodingValidation(
                        kind: metrics.kind,
                        fingerprint: RDFTermEncodingFingerprint(buffer),
                        objectCount: metrics.objectCount,
                        maximumDepth: metrics.maximumDepth
                    )
                    return .success(body(buffer, validation))
                } catch let error as RDFTermCodecError {
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
        _ term: RDFTerm,
        role: RDFTermRole = .term,
        limits: RDFTermCodecLimits = .default
    ) throws(RDFTermCodecError) -> ByteString {
        let plan = try encodingPlan(term, role: role, limits: limits)

        do {
            return try ByteString.copying(count: plan.byteCount) { output in
                try encode(plan, into: output)
            }
        } catch let error as RDFTermCodecError {
            throw error
        } catch {
            preconditionFailure("Unexpected RDF term encoding error")
        }
    }

    /// Returns the exact canonical byte count without allocating a payload.
    public static func encodedByteCount(
        _ term: RDFTerm,
        role: RDFTermRole = .term,
        limits: RDFTermCodecLimits = .default
    ) throws(RDFTermCodecError) -> Int {
        try encodingPlan(term, role: role, limits: limits).byteCount
    }

    /// Measures and validates a term once for direct initialization of final storage.
    public static func encodingPlan(
        _ term: RDFTerm,
        role: RDFTermRole = .term,
        limits: RDFTermCodecLimits = .default
    ) throws(RDFTermCodecError) -> RDFTermEncodingPlan {
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
        return RDFTermEncodingPlan(
            term: term,
            limits: limits,
            byteCount: byteCount,
            objectCount: measurement.objectCount,
            maximumDepth: measurement.maximumDepth
        )
    }

    /// Initializes exactly the storage measured by `encodingPlan`.
    package static func encode(
        _ plan: RDFTermEncodingPlan,
        into output: UnsafeMutableRawBufferPointer
    ) throws(RDFTermCodecError) {
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
    public static func encode<Sink: RDFTermEncodingSink>(
        _ plan: RDFTermEncodingPlan,
        into sink: inout Sink
    ) throws(RDFTermCodecError) {
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
        _ bytes: ByteString,
        role: RDFTermRole = .term,
        limits: RDFTermCodecLimits = .default
    ) throws(RDFTermCodecError) -> RDFTerm {
        try decodeWithMetrics(
            bytes,
            role: role,
            limits: limits
        ).term
    }

    public static func decodeWithMetrics(
        _ bytes: ByteString,
        role: RDFTermRole = .term,
        limits: RDFTermCodecLimits = .default
    ) throws(RDFTermCodecError) -> RDFTermDecodingResult {
        guard bytes.count <= limits.maximumBytes else {
            throw .maximumBytesExceeded(
                actual: bytes.count,
                maximum: limits.maximumBytes
            )
        }
        let result: Result<RDFTermDecodingResult, RDFTermCodecError>
            = bytes.withUnsafeBytes { buffer in
                do {
                    var reader = TermReader(bytes: buffer, limits: limits)
                    let term = try reader.readTerm(depth: 0)
                    guard reader.isAtEnd else {
                        return .failure(.trailingBytes)
                    }
                    try validate(term.rdfTermKind, for: role)
                    return .success(RDFTermDecodingResult(
                        term: term,
                        objectCount: reader.objectCount,
                        maximumDepth: reader.maximumDepth
                    ))
                } catch let error as RDFTermCodecError {
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
        _ kind: RDFTermKind,
        for role: RDFTermRole
    ) throws(RDFTermCodecError) {
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
        role: RDFTermRole,
        limits: RDFTermCodecLimits
    ) throws(RDFTermCodecError) -> (
        kind: RDFTermKind,
        objectCount: Int,
        maximumDepth: Int
    ) {
        var validator = RDFTermEncodingValidator(
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
        case term(RDFTerm, depth: Int)
        case string(String)
        case byte(UInt8)
    }

    private struct MeasurementSink: RDFTermEncodingSink {
        mutating func write(_ byte: UInt8) {}

        mutating func write(_ bytes: UnsafeRawBufferPointer) {}
    }

    private struct DestinationSink: RDFTermEncodingSink {
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

    private struct TermEncoder<Sink: RDFTermEncodingSink> {
        var sink: Sink
        let emitsBytes: Bool
        let limits: RDFTermCodecLimits
        var offset = 0
        var objectCount = 0
        var maximumDepth = 0

        mutating func encode(
            _ root: RDFTerm
        ) throws(RDFTermCodecError) {
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
                        try append(1)
                        encodingSteps.append(.string(identifier.rawValue))
                    case .iri(let iri):
                        try append(2)
                        encodingSteps.append(.string(iri.rawValue))
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
                        try append(4)
                        let nestedDepth = depth + 1
                        encodingSteps.append(.term(object, depth: nestedDepth))
                        encodingSteps.append(
                            .term(predicate.term, depth: nestedDepth)
                        )
                        encodingSteps.append(
                            .term(subject.term, depth: nestedDepth)
                        )
                    }
                }
            }
        }

        private mutating func registerTerm(
            at depth: Int
        ) throws(RDFTermCodecError) {
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
        ) throws(RDFTermCodecError) {
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
        ) throws(RDFTermCodecError) {
            var remaining = value
            while remaining >= 0x80 {
                try append(UInt8(remaining & 0x7F) | 0x80)
                remaining >>= 7
            }
            try append(UInt8(remaining))
        }

        private mutating func append(
            _ byte: UInt8
        ) throws(RDFTermCodecError) {
            try reserve(1)
            if emitsBytes {
                sink.write(byte)
            }
        }

        private mutating func reserve(
            _ count: Int
        ) throws(RDFTermCodecError) {
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
        let limits: RDFTermCodecLimits
        var offset = 0
        var objectCount = 0
        var maximumDepth = 0

        var isAtEnd: Bool { offset == bytes.count }

        mutating func readTerm(
            depth: Int
        ) throws(RDFTermCodecError) -> RDFTerm {
            try registerTerm(at: depth)
            switch try readByte() {
            case 1:
                do {
                    return .blankNode(
                        try RDFBlankNodeIdentifier(readString())
                    )
                } catch {
                    throw .invalidBlankNodeIdentifier
                }
            case 2:
                let rawIRI = try readString()
                do {
                    return .iri(try RDFIRI(rawIRI))
                } catch let error {
                    throw .invalidIRI(error)
                }
            case 3:
                return .literal(try readLiteral())
            case 4:
                let nestedDepth = depth + 1
                let subject: RDFSubject
                switch try readTerm(depth: nestedDepth) {
                case .iri(let iri):
                    subject = .iri(iri)
                case .blankNode(let identifier):
                    subject = .blankNode(identifier)
                case .literal, .tripleTerm:
                    throw .invalidTripleSubject
                }
                let predicate: RDFPredicateIRI
                switch try readTerm(depth: nestedDepth) {
                case .iri(let iri):
                    predicate = RDFPredicateIRI(iri)
                case .blankNode, .literal, .tripleTerm:
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
        ) throws(RDFTermCodecError) -> RDFLiteral {
            let lexicalForm = try readString()
            switch try readByte() {
            case 1:
                let rawDatatype = try readString()
                let datatype: RDFTypedLiteralDatatype
                do {
                    datatype = try RDFTypedLiteralDatatype(
                        rawDatatype
                    )
                } catch {
                    throw .invalidDatatypeIRI
                }
                return RDFLiteral(
                    lexicalForm: lexicalForm,
                    datatype: datatype
                )
            case 2:
                return RDFLiteral(
                    lexicalForm: lexicalForm,
                    language: try readLanguageTag()
                )
            case 3:
                let language = try readLanguageTag()
                let direction: RDFDirection
                switch try readByte() {
                case 1: direction = .leftToRight
                case 2: direction = .rightToLeft
                case let tag: throw .invalidDirection(tag)
                }
                return RDFLiteral(
                    lexicalForm: lexicalForm,
                    language: language,
                    direction: direction
                )
            case let tag:
                throw .invalidLiteralAnnotation(tag)
            }
        }

        private mutating func readLanguageTag(
        ) throws(RDFTermCodecError) -> RDFLanguageTag {
            let rawLanguage = try readString()
            let language: RDFLanguageTag
            do {
                language = try RDFLanguageTag(rawLanguage)
            } catch {
                throw .invalidLanguageTag
            }
            guard language.rawValue.utf8.elementsEqual(rawLanguage.utf8) else {
                throw .nonCanonicalLanguageTag
            }
            return language
        }

        private mutating func readString(
        ) throws(RDFTermCodecError) -> String {
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
                guard let value = UTF8Decoder.decode(encoded) else {
                    throw .invalidUTF8
                }
                return value
            }

            // A semantic String must own valid UTF-8. Only the uncommon escaped-NUL
            // path needs a temporary canonical UTF-8 buffer before that boundary.
            let decodedByteCount = encoded.count - escapedZeroCount
            let decoded = ByteString.copying(count: decodedByteCount) { output in
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
            guard let value = UTF8Decoder.decode(decoded) else {
                throw .invalidUTF8
            }
            return value
        }

        private mutating func readCount(
        ) throws(RDFTermCodecError) -> Int {
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
        ) throws(RDFTermCodecError) -> UInt8 {
            guard offset < bytes.count else { throw .truncated }
            let byte = bytes[offset]
            offset += 1
            return byte
        }

        private mutating func registerTerm(
            at depth: Int
        ) throws(RDFTermCodecError) {
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

private extension RDFTerm {
    var rdfTermKind: RDFTermKind {
        switch self {
        case .blankNode: .blankNode
        case .iri: .iri
        case .literal: .literal
        case .tripleTerm: .tripleTerm
        }
    }

}
