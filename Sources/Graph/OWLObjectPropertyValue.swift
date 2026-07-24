import DatabaseTypes
import DatabaseValue

#if canImport(FoundationEssentials)
import FoundationEssentials
#elseif canImport(Foundation)
import Foundation
#endif

public protocol OWLObjectPropertyValue: Sendable {
    var owlObjectPropertyIdentifierLexicalForms: [String] { get }
}

extension OWLIndividualIdentifier {
    public var owlObjectPropertyIdentifierLexicalForms: [String] {
        [owlIndividualIdentifierLexicalForm]
    }
}

extension String: OWLObjectPropertyValue {}
extension Int: OWLObjectPropertyValue {}
extension Int8: OWLObjectPropertyValue {}
extension Int16: OWLObjectPropertyValue {}
extension Int32: OWLObjectPropertyValue {}
extension Int64: OWLObjectPropertyValue {}
extension UInt: OWLObjectPropertyValue {}
extension UInt8: OWLObjectPropertyValue {}
extension UInt16: OWLObjectPropertyValue {}
extension UInt32: OWLObjectPropertyValue {}
extension UInt64: OWLObjectPropertyValue {}
extension Bool: OWLObjectPropertyValue {}
extension Double: OWLObjectPropertyValue {}
extension Float: OWLObjectPropertyValue {}

#if canImport(FoundationEssentials) || canImport(Foundation)
extension Foundation.UUID: OWLObjectPropertyValue {}
extension DatabaseTypes.UUID: OWLObjectPropertyValue {}
extension Data: OWLObjectPropertyValue {}
#endif

extension Optional: OWLObjectPropertyValue where Wrapped: OWLIndividualIdentifier {
    public var owlObjectPropertyIdentifierLexicalForms: [String] {
        switch self {
        case .none: return []
        case .some(let value): return [value.owlIndividualIdentifierLexicalForm]
        }
    }
}

extension Array: OWLObjectPropertyValue where Element: OWLIndividualIdentifier {
    public var owlObjectPropertyIdentifierLexicalForms: [String] {
        map(\.owlIndividualIdentifierLexicalForm)
    }
}
