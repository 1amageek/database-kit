import DatabaseTypes

/// Internal storage for validated, owner-retaining result collections.
struct RetainedResultElements<Element: Sendable>: Sendable {
    typealias EncodeElement = (
        Element,
        inout DatabaseWireWriter
    ) throws(DatabaseWireError) -> Void
    typealias DecodeElement = @Sendable (
        inout DatabaseWireReader
    ) throws(DatabaseWireError) -> Element
    typealias ValidateElement = (
        inout DatabaseWireReader
    ) throws(DatabaseWireError) -> Void

    private enum Storage: Sendable {
        case materialized([Element])
        case encoded(ByteString)
    }

    let count: Int
    private let storage: Storage
    private let limits: DatabaseWireLimits

    init(_ elements: [Element]) {
        self.count = elements.count
        self.storage = .materialized(elements)
        self.limits = .default
    }

    init(
        from reader: inout DatabaseWireReader,
        validateElement: ValidateElement
    ) throws(DatabaseWireError) {
        let count = try reader.readCount()
        let start = reader.consumedByteCount
        for _ in 0..<count {
            try validateElement(&reader)
        }
        let end = reader.consumedByteCount

        self.count = count
        self.storage = .encoded(
            try reader.bytes(inConsumedRange: start..<end)
        )
        self.limits = reader.limits
    }

    func makeIterator(
        decodeElement: @escaping DecodeElement
    ) -> ResultIterator<Element> {
        switch storage {
        case .materialized(let elements):
            return ResultIterator(elements: elements)
        case .encoded(let bytes):
            return ResultIterator(
                encodedElements: bytes,
                count: count,
                limits: limits,
                decodeElement: decodeElement
            )
        }
    }

    func materialized(
        maximumCount: Int,
        decodeElement: @escaping DecodeElement
    ) throws(DatabaseWireError) -> [Element] {
        guard maximumCount >= 0 else {
            throw .byteCountOverflow
        }
        guard count <= maximumCount else {
            throw .collectionTooLarge(actual: count, maximum: maximumCount)
        }

        var elements: [Element] = []
        elements.reserveCapacity(count)
        var iterator = makeIterator(decodeElement: decodeElement)
        while let element = try iterator.next() {
            elements.append(element)
        }
        return elements
    }

    func encode(
        into writer: inout DatabaseWireWriter,
        encodeElement: EncodeElement,
        validateElement: ValidateElement
    ) throws(DatabaseWireError) {
        try writer.writeCount(count)
        switch storage {
        case .materialized(let elements):
            for element in elements {
                try encodeElement(element, &writer)
            }

        case .encoded(let bytes):
            let initialObjectCount = writer.registeredObjectCount
            var validator = DatabaseWireReader(bytes, limits: writer.limits)
            try validator.beginSubtreeValidation(
                nestingDepth: writer.currentNestingDepth,
                registeredObjectCount: initialObjectCount
            )
            for _ in 0..<count {
                try validateElement(&validator)
            }
            try validator.ensureFullyRead()
            try writer.registerObjects(
                validator.registeredObjectCount - initialObjectCount
            )
            writer.writeUnframedBytes(bytes)
        }
    }

    var retainedBytes: ByteString? {
        guard case .encoded(let bytes) = storage else {
            return nil
        }
        return bytes
    }
}
