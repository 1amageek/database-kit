/// A single SPARQL basic graph pattern and therefore one blank-node scope.
public struct BasicGraphPattern: Sendable, Equatable, Hashable {
    public let elements: [BasicGraphPatternElement]

    public init(elements: consuming [BasicGraphPatternElement]) {
        self.elements = consume elements
    }

    public init(triples: consuming [TriplePattern]) {
        self.elements = triples.map(BasicGraphPatternElement.triple)
    }

    public var count: Int { elements.count }
    public var isEmpty: Bool { elements.isEmpty }

    public func appending(
        _ element: consuming BasicGraphPatternElement
    ) -> BasicGraphPattern {
        var result = elements
        result.append(element)
        return BasicGraphPattern(elements: result)
    }

    public func joined(
        with other: borrowing BasicGraphPattern
    ) -> BasicGraphPattern {
        var result = elements
        result.append(contentsOf: other.elements)
        return BasicGraphPattern(elements: result)
    }

    /// Materializes the triple-only view required by SPARQL grammar
    /// positions that reject property paths, such as update templates.
    public func triplePatterns(
    ) throws(BasicGraphPatternError) -> [TriplePattern] {
        var result: [TriplePattern] = []
        result.reserveCapacity(elements.count)
        for (index, element) in elements.enumerated() {
            guard case .triple(let triple) = element else {
                throw .propertyPathAtIndex(index)
            }
            result.append(triple)
        }
        return result
    }
}

extension BasicGraphPattern: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: TriplePattern...) {
        self.init(triples: elements)
    }
}
