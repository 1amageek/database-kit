import DatabaseTypes

/// An iterator that materializes one validated result element at a time.
public struct ResultIterator<Element: Sendable>: Sendable {
    typealias DecodeElement = @Sendable (
        inout DatabaseWireReader
    ) throws(DatabaseWireError) -> Element

    private enum Storage: Sendable {
        case materialized(elements: [Element], nextIndex: Int)
        case encoded(
            reader: DatabaseWireReader,
            remainingCount: Int,
            decodeElement: DecodeElement
        )
    }

    private var storage: Storage

    init(elements: [Element]) {
        self.storage = .materialized(elements: elements, nextIndex: 0)
    }

    init(
        encodedElements: ByteString,
        count: Int,
        limits: DatabaseWireLimits,
        decodeElement: @escaping DecodeElement
    ) {
        self.storage = .encoded(
            reader: DatabaseWireReader(encodedElements, limits: limits),
            remainingCount: count,
            decodeElement: decodeElement
        )
    }

    public mutating func next() throws(DatabaseWireError) -> Element? {
        switch storage {
        case .materialized(let elements, let nextIndex):
            guard nextIndex < elements.count else {
                return nil
            }
            storage = .materialized(
                elements: elements,
                nextIndex: nextIndex + 1
            )
            return elements[nextIndex]

        case .encoded(
            var reader,
            let remainingCount,
            let decodeElement
        ):
            guard remainingCount > 0 else {
                try reader.ensureFullyRead()
                return nil
            }
            let element = try decodeElement(&reader)
            storage = .encoded(
                reader: reader,
                remainingCount: remainingCount - 1,
                decodeElement: decodeElement
            )
            return element
        }
    }
}
