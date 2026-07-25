import DatabaseTypes

public protocol OWLDataPropertyScalar: OWLDataPropertyValue {
    func owlDataPropertyTerm() throws(OWLProjectionError) -> RDFTerm
}

extension OWLDataPropertyScalar {
    public func owlDataPropertyTerms()
        throws(OWLProjectionError) -> [RDFTerm] {
        [try owlDataPropertyTerm()]
    }
}

extension RDFTerm: OWLDataPropertyScalar {
    public func owlDataPropertyTerm()
        throws(OWLProjectionError) -> RDFTerm {
        guard case .literal = self else {
            throw OWLProjectionError.dataPropertyRequiresLiteral
        }
        return self
    }
}

extension String: OWLDataPropertyScalar {
    public func owlDataPropertyTerm()
        throws(OWLProjectionError) -> RDFTerm {
        OWLRDFVocabulary.literal(self, datatype: .string)
    }
}

extension Int: OWLDataPropertyScalar {
    public func owlDataPropertyTerm()
        throws(OWLProjectionError) -> RDFTerm {
        OWLRDFVocabulary.literal(String(self), datatype: .integer)
    }
}

extension Int8: OWLDataPropertyScalar {
    public func owlDataPropertyTerm()
        throws(OWLProjectionError) -> RDFTerm {
        OWLRDFVocabulary.literal(String(self), datatype: .integer)
    }
}

extension Int16: OWLDataPropertyScalar {
    public func owlDataPropertyTerm()
        throws(OWLProjectionError) -> RDFTerm {
        OWLRDFVocabulary.literal(String(self), datatype: .integer)
    }
}

extension Int32: OWLDataPropertyScalar {
    public func owlDataPropertyTerm()
        throws(OWLProjectionError) -> RDFTerm {
        OWLRDFVocabulary.literal(String(self), datatype: .integer)
    }
}

extension Int64: OWLDataPropertyScalar {
    public func owlDataPropertyTerm()
        throws(OWLProjectionError) -> RDFTerm {
        OWLRDFVocabulary.literal(String(self), datatype: .integer)
    }
}

extension UInt: OWLDataPropertyScalar {
    public func owlDataPropertyTerm()
        throws(OWLProjectionError) -> RDFTerm {
        OWLRDFVocabulary.literal(String(self), datatype: .nonNegativeInteger)
    }
}

extension UInt8: OWLDataPropertyScalar {
    public func owlDataPropertyTerm()
        throws(OWLProjectionError) -> RDFTerm {
        OWLRDFVocabulary.literal(String(self), datatype: .nonNegativeInteger)
    }
}

extension UInt16: OWLDataPropertyScalar {
    public func owlDataPropertyTerm()
        throws(OWLProjectionError) -> RDFTerm {
        OWLRDFVocabulary.literal(String(self), datatype: .nonNegativeInteger)
    }
}

extension UInt32: OWLDataPropertyScalar {
    public func owlDataPropertyTerm()
        throws(OWLProjectionError) -> RDFTerm {
        OWLRDFVocabulary.literal(String(self), datatype: .nonNegativeInteger)
    }
}

extension UInt64: OWLDataPropertyScalar {
    public func owlDataPropertyTerm()
        throws(OWLProjectionError) -> RDFTerm {
        OWLRDFVocabulary.literal(String(self), datatype: .nonNegativeInteger)
    }
}

extension Double: OWLDataPropertyScalar {
    public func owlDataPropertyTerm()
        throws(OWLProjectionError) -> RDFTerm {
        OWLRDFVocabulary.literal(
            OWLRDFLexicalForm.floatingPoint(self),
            datatype: .double
        )
    }
}

extension Float: OWLDataPropertyScalar {
    public func owlDataPropertyTerm()
        throws(OWLProjectionError) -> RDFTerm {
        OWLRDFVocabulary.literal(
            OWLRDFLexicalForm.floatingPoint(Double(self)),
            datatype: .float
        )
    }
}

extension Bool: OWLDataPropertyScalar {
    public func owlDataPropertyTerm()
        throws(OWLProjectionError) -> RDFTerm {
        OWLRDFVocabulary.literal(self ? "true" : "false", datatype: .boolean)
    }
}

extension CivilDate: OWLDataPropertyScalar {
    public func owlDataPropertyTerm()
        throws(OWLProjectionError) -> RDFTerm {
        OWLRDFVocabulary.literal(
            OWLRDFLexicalForm.date(self),
            datatype: .date
        )
    }
}

extension Timestamp: OWLDataPropertyScalar {
    public func owlDataPropertyTerm()
        throws(OWLProjectionError) -> RDFTerm {
        let lexicalForm: String
        do {
            lexicalForm = try OWLRDFLexicalForm.dateTime(self)
        } catch let error {
            throw .invalidDateTime(error)
        }
        return OWLRDFVocabulary.literal(
            lexicalForm,
            datatype: .dateTime
        )
    }
}

extension DatabaseTypes.UUID: OWLDataPropertyScalar {
    public func owlDataPropertyTerm()
        throws(OWLProjectionError) -> RDFTerm {
        OWLRDFVocabulary.literal(description, datatype: .string)
    }
}

extension ByteString: OWLDataPropertyScalar {
    public func owlDataPropertyTerm()
        throws(OWLProjectionError) -> RDFTerm {
        OWLRDFVocabulary.literal(
            QueryLiteralEncoding.base64(self),
            datatype: .base64Binary
        )
    }
}
