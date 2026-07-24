/// A canonical SPARQL variable name without the leading `?` or `$` sigil.
///
/// Validation follows the SPARQL 1.1 `VARNAME` production and has no
/// Foundation dependency.
public struct SPARQLVariableName: Sendable, Hashable, Comparable,
    CustomStringConvertible
{
    public let rawValue: String

    public init(
        _ rawValue: String
    ) throws(SPARQLVariableNameError) {
        var scalars = rawValue.unicodeScalars.makeIterator()
        guard let first = scalars.next() else {
            throw .empty
        }
        guard first.value != 0x3F, first.value != 0x24 else {
            throw .leadingSigil(first.value)
        }
        guard Self.isStart(first.value) else {
            throw .invalidStartScalar(first.value)
        }
        while let scalar = scalars.next() {
            guard Self.isContinuation(scalar.value) else {
                throw .invalidContinuationScalar(scalar.value)
            }
        }
        self.rawValue = rawValue
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var description: String { rawValue }

    private static func isStart(_ value: UInt32) -> Bool {
        isPNCharsBase(value) || value == 0x5F || isASCIIDigit(value)
    }

    private static func isContinuation(_ value: UInt32) -> Bool {
        isStart(value)
            || value == 0xB7
            || (0x0300...0x036F).contains(value)
            || (0x203F...0x2040).contains(value)
    }

    private static func isASCIIDigit(_ value: UInt32) -> Bool {
        (0x30...0x39).contains(value)
    }

    private static func isPNCharsBase(_ value: UInt32) -> Bool {
        (0x41...0x5A).contains(value)
            || (0x61...0x7A).contains(value)
            || (0x00C0...0x00D6).contains(value)
            || (0x00D8...0x00F6).contains(value)
            || (0x00F8...0x02FF).contains(value)
            || (0x0370...0x037D).contains(value)
            || (0x037F...0x1FFF).contains(value)
            || (0x200C...0x200D).contains(value)
            || (0x2070...0x218F).contains(value)
            || (0x2C00...0x2FEF).contains(value)
            || (0x3001...0xD7FF).contains(value)
            || (0xF900...0xFDCF).contains(value)
            || (0xFDF0...0xFFFD).contains(value)
            || (0x10000...0xEFFFF).contains(value)
    }
}

public enum SPARQLVariableNameError: Error, Sendable, Equatable {
    case empty
    case leadingSigil(UInt32)
    case invalidStartScalar(UInt32)
    case invalidContinuationScalar(UInt32)
}
