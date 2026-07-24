import DatabaseTypes
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

public protocol OWLIndividualIdentifier: Sendable {
    var owlIndividualIdentifierLexicalForm: String { get }
}

extension String: OWLIndividualIdentifier {
    public var owlIndividualIdentifierLexicalForm: String { self }
}

extension Int: OWLIndividualIdentifier {
    public var owlIndividualIdentifierLexicalForm: String { String(self) }
}

extension Int8: OWLIndividualIdentifier {
    public var owlIndividualIdentifierLexicalForm: String { String(self) }
}

extension Int16: OWLIndividualIdentifier {
    public var owlIndividualIdentifierLexicalForm: String { String(self) }
}

extension Int32: OWLIndividualIdentifier {
    public var owlIndividualIdentifierLexicalForm: String { String(self) }
}

extension Int64: OWLIndividualIdentifier {
    public var owlIndividualIdentifierLexicalForm: String { String(self) }
}

extension UInt: OWLIndividualIdentifier {
    public var owlIndividualIdentifierLexicalForm: String { String(self) }
}

extension UInt8: OWLIndividualIdentifier {
    public var owlIndividualIdentifierLexicalForm: String { String(self) }
}

extension UInt16: OWLIndividualIdentifier {
    public var owlIndividualIdentifierLexicalForm: String { String(self) }
}

extension UInt32: OWLIndividualIdentifier {
    public var owlIndividualIdentifierLexicalForm: String { String(self) }
}

extension UInt64: OWLIndividualIdentifier {
    public var owlIndividualIdentifierLexicalForm: String { String(self) }
}

extension Bool: OWLIndividualIdentifier {
    public var owlIndividualIdentifierLexicalForm: String {
        self ? "true" : "false"
    }
}

extension Double: OWLIndividualIdentifier {
    public var owlIndividualIdentifierLexicalForm: String {
        OWLRDFLexicalForm.floatingPoint(self)
    }
}

extension Float: OWLIndividualIdentifier {
    public var owlIndividualIdentifierLexicalForm: String {
        OWLRDFLexicalForm.floatingPoint(Double(self))
    }
}

extension FoundationUUID: OWLIndividualIdentifier {
    public var owlIndividualIdentifierLexicalForm: String {
        uuidString.lowercased()
    }
}

extension DatabaseTypes.UUID: OWLIndividualIdentifier {
    public var owlIndividualIdentifierLexicalForm: String { description }
}

extension Data: OWLIndividualIdentifier {
    public var owlIndividualIdentifierLexicalForm: String {
        let base64 = base64EncodedString()
        var result = ""
        result.reserveCapacity(base64.utf8.count)
        for byte in base64.utf8 {
            switch byte {
            case 43:
                result.append("-")
            case 47:
                result.append("_")
            case 61:
                continue
            default:
                result.unicodeScalars.append(Unicode.Scalar(byte))
            }
        }
        return result
    }
}
