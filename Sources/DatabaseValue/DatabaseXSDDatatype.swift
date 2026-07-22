/// XML Schema datatypes that are built into the RDF and OWL runtimes.
public enum DatabaseXSDDatatype: String, Sendable, Hashable, CaseIterable {
    case string = "http://www.w3.org/2001/XMLSchema#string"
    case boolean = "http://www.w3.org/2001/XMLSchema#boolean"
    case decimal = "http://www.w3.org/2001/XMLSchema#decimal"
    case float = "http://www.w3.org/2001/XMLSchema#float"
    case double = "http://www.w3.org/2001/XMLSchema#double"
    case duration = "http://www.w3.org/2001/XMLSchema#duration"
    case dateTime = "http://www.w3.org/2001/XMLSchema#dateTime"
    case dateTimeStamp = "http://www.w3.org/2001/XMLSchema#dateTimeStamp"
    case time = "http://www.w3.org/2001/XMLSchema#time"
    case date = "http://www.w3.org/2001/XMLSchema#date"
    case anyURI = "http://www.w3.org/2001/XMLSchema#anyURI"
    case base64Binary = "http://www.w3.org/2001/XMLSchema#base64Binary"
    case hexBinary = "http://www.w3.org/2001/XMLSchema#hexBinary"
    case normalizedString = "http://www.w3.org/2001/XMLSchema#normalizedString"
    case token = "http://www.w3.org/2001/XMLSchema#token"
    case language = "http://www.w3.org/2001/XMLSchema#language"
    case nmtoken = "http://www.w3.org/2001/XMLSchema#NMTOKEN"
    case name = "http://www.w3.org/2001/XMLSchema#Name"
    case ncname = "http://www.w3.org/2001/XMLSchema#NCName"
    case integer = "http://www.w3.org/2001/XMLSchema#integer"
    case nonPositiveInteger = "http://www.w3.org/2001/XMLSchema#nonPositiveInteger"
    case negativeInteger = "http://www.w3.org/2001/XMLSchema#negativeInteger"
    case nonNegativeInteger = "http://www.w3.org/2001/XMLSchema#nonNegativeInteger"
    case positiveInteger = "http://www.w3.org/2001/XMLSchema#positiveInteger"
    case long = "http://www.w3.org/2001/XMLSchema#long"
    case int = "http://www.w3.org/2001/XMLSchema#int"
    case short = "http://www.w3.org/2001/XMLSchema#short"
    case byte = "http://www.w3.org/2001/XMLSchema#byte"
    case unsignedLong = "http://www.w3.org/2001/XMLSchema#unsignedLong"
    case unsignedInt = "http://www.w3.org/2001/XMLSchema#unsignedInt"
    case unsignedShort = "http://www.w3.org/2001/XMLSchema#unsignedShort"
    case unsignedByte = "http://www.w3.org/2001/XMLSchema#unsignedByte"

    public var iri: String { rawValue }
    public var expandedIRI: String { rawValue }

    public var typedLiteralDatatype: DatabaseRDFTypedLiteralDatatype {
        DatabaseRDFTypedLiteralDatatype(
            validatedIRI: DatabaseRDFIRI(validatedRawValue: rawValue)
        )
    }
}
