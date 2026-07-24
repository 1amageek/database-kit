import DatabaseTypes
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import DatabaseValue

public protocol OWLDataPropertyScalar: OWLDataPropertyValue {
    func owlDataPropertyTerm() throws -> RDFTerm
}

extension OWLDataPropertyScalar {
    public func owlDataPropertyTerms() throws -> [RDFTerm] {
        [try owlDataPropertyTerm()]
    }
}

extension RDFTerm: OWLDataPropertyScalar {
    public func owlDataPropertyTerm() throws -> RDFTerm {
        guard case .literal = self else {
            throw OWLProjectionError.dataPropertyRequiresLiteral
        }
        return self
    }
}

extension String: OWLDataPropertyScalar {
    public func owlDataPropertyTerm() throws -> RDFTerm {
        OWLRDFVocabulary.literal(self, datatype: .string)
    }
}

extension Int: OWLDataPropertyScalar {
    public func owlDataPropertyTerm() throws -> RDFTerm {
        OWLRDFVocabulary.literal(String(self), datatype: .integer)
    }
}

extension Int8: OWLDataPropertyScalar {
    public func owlDataPropertyTerm() throws -> RDFTerm {
        OWLRDFVocabulary.literal(String(self), datatype: .integer)
    }
}

extension Int16: OWLDataPropertyScalar {
    public func owlDataPropertyTerm() throws -> RDFTerm {
        OWLRDFVocabulary.literal(String(self), datatype: .integer)
    }
}

extension Int32: OWLDataPropertyScalar {
    public func owlDataPropertyTerm() throws -> RDFTerm {
        OWLRDFVocabulary.literal(String(self), datatype: .integer)
    }
}

extension Int64: OWLDataPropertyScalar {
    public func owlDataPropertyTerm() throws -> RDFTerm {
        OWLRDFVocabulary.literal(String(self), datatype: .integer)
    }
}

extension UInt: OWLDataPropertyScalar {
    public func owlDataPropertyTerm() throws -> RDFTerm {
        OWLRDFVocabulary.literal(String(self), datatype: .nonNegativeInteger)
    }
}

extension UInt8: OWLDataPropertyScalar {
    public func owlDataPropertyTerm() throws -> RDFTerm {
        OWLRDFVocabulary.literal(String(self), datatype: .nonNegativeInteger)
    }
}

extension UInt16: OWLDataPropertyScalar {
    public func owlDataPropertyTerm() throws -> RDFTerm {
        OWLRDFVocabulary.literal(String(self), datatype: .nonNegativeInteger)
    }
}

extension UInt32: OWLDataPropertyScalar {
    public func owlDataPropertyTerm() throws -> RDFTerm {
        OWLRDFVocabulary.literal(String(self), datatype: .nonNegativeInteger)
    }
}

extension UInt64: OWLDataPropertyScalar {
    public func owlDataPropertyTerm() throws -> RDFTerm {
        OWLRDFVocabulary.literal(String(self), datatype: .nonNegativeInteger)
    }
}

extension Double: OWLDataPropertyScalar {
    public func owlDataPropertyTerm() throws -> RDFTerm {
        OWLRDFVocabulary.literal(
            OWLRDFLexicalForm.floatingPoint(self),
            datatype: .double
        )
    }
}

extension Float: OWLDataPropertyScalar {
    public func owlDataPropertyTerm() throws -> RDFTerm {
        OWLRDFVocabulary.literal(
            OWLRDFLexicalForm.floatingPoint(Double(self)),
            datatype: .float
        )
    }
}

extension Bool: OWLDataPropertyScalar {
    public func owlDataPropertyTerm() throws -> RDFTerm {
        OWLRDFVocabulary.literal(self ? "true" : "false", datatype: .boolean)
    }
}

extension CivilDate: OWLDataPropertyScalar {
    public func owlDataPropertyTerm() throws -> RDFTerm {
        OWLRDFVocabulary.literal(
            OWLRDFLexicalForm.date(self),
            datatype: .date
        )
    }
}

extension Timestamp: OWLDataPropertyScalar {
    public func owlDataPropertyTerm() throws -> RDFTerm {
        return OWLRDFVocabulary.literal(
            try OWLRDFLexicalForm.dateTime(self),
            datatype: .dateTime
        )
    }
}

extension Foundation.UUID: OWLDataPropertyScalar {
    public func owlDataPropertyTerm() throws -> RDFTerm {
        OWLRDFVocabulary.literal(uuidString.lowercased(), datatype: .string)
    }
}

extension DatabaseTypes.UUID: OWLDataPropertyScalar {
    public func owlDataPropertyTerm() throws -> RDFTerm {
        OWLRDFVocabulary.literal(description, datatype: .string)
    }
}

extension Data: OWLDataPropertyScalar {
    public func owlDataPropertyTerm() throws -> RDFTerm {
        OWLRDFVocabulary.literal(base64EncodedString(), datatype: .base64Binary)
    }
}
