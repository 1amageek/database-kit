#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import DatabaseValue

public protocol OWLDataPropertyScalar: OWLDataPropertyValue {
    func owlDataPropertyTerm() throws -> DatabaseRDFTerm
}

extension OWLDataPropertyScalar {
    public func owlDataPropertyTerms() throws -> [DatabaseRDFTerm] {
        [try owlDataPropertyTerm()]
    }
}

extension DatabaseRDFTerm: OWLDataPropertyScalar {
    public func owlDataPropertyTerm() throws -> DatabaseRDFTerm {
        guard case .literal = self else {
            throw OWLProjectionError.dataPropertyRequiresLiteral
        }
        return self
    }
}

extension String: OWLDataPropertyScalar {
    public func owlDataPropertyTerm() throws -> DatabaseRDFTerm {
        OWLRDFVocabulary.literal(self, datatype: .string)
    }
}

extension Int: OWLDataPropertyScalar {
    public func owlDataPropertyTerm() throws -> DatabaseRDFTerm {
        OWLRDFVocabulary.literal(String(self), datatype: .integer)
    }
}

extension Int8: OWLDataPropertyScalar {
    public func owlDataPropertyTerm() throws -> DatabaseRDFTerm {
        OWLRDFVocabulary.literal(String(self), datatype: .integer)
    }
}

extension Int16: OWLDataPropertyScalar {
    public func owlDataPropertyTerm() throws -> DatabaseRDFTerm {
        OWLRDFVocabulary.literal(String(self), datatype: .integer)
    }
}

extension Int32: OWLDataPropertyScalar {
    public func owlDataPropertyTerm() throws -> DatabaseRDFTerm {
        OWLRDFVocabulary.literal(String(self), datatype: .integer)
    }
}

extension Int64: OWLDataPropertyScalar {
    public func owlDataPropertyTerm() throws -> DatabaseRDFTerm {
        OWLRDFVocabulary.literal(String(self), datatype: .integer)
    }
}

extension UInt: OWLDataPropertyScalar {
    public func owlDataPropertyTerm() throws -> DatabaseRDFTerm {
        OWLRDFVocabulary.literal(String(self), datatype: .nonNegativeInteger)
    }
}

extension UInt8: OWLDataPropertyScalar {
    public func owlDataPropertyTerm() throws -> DatabaseRDFTerm {
        OWLRDFVocabulary.literal(String(self), datatype: .nonNegativeInteger)
    }
}

extension UInt16: OWLDataPropertyScalar {
    public func owlDataPropertyTerm() throws -> DatabaseRDFTerm {
        OWLRDFVocabulary.literal(String(self), datatype: .nonNegativeInteger)
    }
}

extension UInt32: OWLDataPropertyScalar {
    public func owlDataPropertyTerm() throws -> DatabaseRDFTerm {
        OWLRDFVocabulary.literal(String(self), datatype: .nonNegativeInteger)
    }
}

extension UInt64: OWLDataPropertyScalar {
    public func owlDataPropertyTerm() throws -> DatabaseRDFTerm {
        OWLRDFVocabulary.literal(String(self), datatype: .nonNegativeInteger)
    }
}

extension Double: OWLDataPropertyScalar {
    public func owlDataPropertyTerm() throws -> DatabaseRDFTerm {
        OWLRDFVocabulary.literal(
            OWLRDFLexicalForm.floatingPoint(self),
            datatype: .double
        )
    }
}

extension Float: OWLDataPropertyScalar {
    public func owlDataPropertyTerm() throws -> DatabaseRDFTerm {
        OWLRDFVocabulary.literal(
            OWLRDFLexicalForm.floatingPoint(Double(self)),
            datatype: .float
        )
    }
}

extension Bool: OWLDataPropertyScalar {
    public func owlDataPropertyTerm() throws -> DatabaseRDFTerm {
        OWLRDFVocabulary.literal(self ? "true" : "false", datatype: .boolean)
    }
}

extension DatabaseDate: OWLDataPropertyScalar {
    public func owlDataPropertyTerm() throws -> DatabaseRDFTerm {
        OWLRDFVocabulary.literal(
            try OWLRDFLexicalForm.date(self),
            datatype: .date
        )
    }
}

extension DatabaseTimestamp: OWLDataPropertyScalar {
    public func owlDataPropertyTerm() throws -> DatabaseRDFTerm {
        return OWLRDFVocabulary.literal(
            try OWLRDFLexicalForm.dateTime(self),
            datatype: .dateTime
        )
    }
}

extension UUID: OWLDataPropertyScalar {
    public func owlDataPropertyTerm() throws -> DatabaseRDFTerm {
        OWLRDFVocabulary.literal(uuidString.lowercased(), datatype: .string)
    }
}

extension DatabaseUUID: OWLDataPropertyScalar {
    public func owlDataPropertyTerm() throws -> DatabaseRDFTerm {
        OWLRDFVocabulary.literal(description, datatype: .string)
    }
}

extension Data: OWLDataPropertyScalar {
    public func owlDataPropertyTerm() throws -> DatabaseRDFTerm {
        OWLRDFVocabulary.literal(base64EncodedString(), datatype: .base64Binary)
    }
}
