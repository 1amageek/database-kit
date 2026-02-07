/// Literal+Codable.swift
/// Codable conformance for Literal using tag-based encoding
///
/// Encoding format:
/// ```json
/// {"tag": "int", "value": 42}
/// {"tag": "typedLiteral", "value": "42", "datatype": "xsd:integer"}
/// ```

import Foundation

extension Literal: Codable {
    private enum CodingKeys: String, CodingKey {
        case tag
        case value
        case datatype
        case language
        case elements
    }

    private enum Tag: String, Codable {
        case null
        case bool
        case int
        case double
        case string
        case date
        case timestamp
        case binary
        case array
        case iri
        case blankNode
        case typedLiteral
        case langLiteral
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .null:
            try container.encode(Tag.null, forKey: .tag)
        case .bool(let v):
            try container.encode(Tag.bool, forKey: .tag)
            try container.encode(v, forKey: .value)
        case .int(let v):
            try container.encode(Tag.int, forKey: .tag)
            try container.encode(v, forKey: .value)
        case .double(let v):
            try container.encode(Tag.double, forKey: .tag)
            try container.encode(v, forKey: .value)
        case .string(let v):
            try container.encode(Tag.string, forKey: .tag)
            try container.encode(v, forKey: .value)
        case .date(let v):
            try container.encode(Tag.date, forKey: .tag)
            try container.encode(v, forKey: .value)
        case .timestamp(let v):
            try container.encode(Tag.timestamp, forKey: .tag)
            try container.encode(v, forKey: .value)
        case .binary(let v):
            try container.encode(Tag.binary, forKey: .tag)
            try container.encode(v, forKey: .value)
        case .array(let elements):
            try container.encode(Tag.array, forKey: .tag)
            try container.encode(elements, forKey: .elements)
        case .iri(let v):
            try container.encode(Tag.iri, forKey: .tag)
            try container.encode(v, forKey: .value)
        case .blankNode(let v):
            try container.encode(Tag.blankNode, forKey: .tag)
            try container.encode(v, forKey: .value)
        case .typedLiteral(let value, let datatype):
            try container.encode(Tag.typedLiteral, forKey: .tag)
            try container.encode(value, forKey: .value)
            try container.encode(datatype, forKey: .datatype)
        case .langLiteral(let value, let language):
            try container.encode(Tag.langLiteral, forKey: .tag)
            try container.encode(value, forKey: .value)
            try container.encode(language, forKey: .language)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let tag = try container.decode(Tag.self, forKey: .tag)
        switch tag {
        case .null:
            self = .null
        case .bool:
            self = .bool(try container.decode(Bool.self, forKey: .value))
        case .int:
            self = .int(try container.decode(Int64.self, forKey: .value))
        case .double:
            self = .double(try container.decode(Double.self, forKey: .value))
        case .string:
            self = .string(try container.decode(String.self, forKey: .value))
        case .date:
            self = .date(try container.decode(Date.self, forKey: .value))
        case .timestamp:
            self = .timestamp(try container.decode(Date.self, forKey: .value))
        case .binary:
            self = .binary(try container.decode(Data.self, forKey: .value))
        case .array:
            self = .array(try container.decode([Literal].self, forKey: .elements))
        case .iri:
            self = .iri(try container.decode(String.self, forKey: .value))
        case .blankNode:
            self = .blankNode(try container.decode(String.self, forKey: .value))
        case .typedLiteral:
            let value = try container.decode(String.self, forKey: .value)
            let datatype = try container.decode(String.self, forKey: .datatype)
            self = .typedLiteral(value: value, datatype: datatype)
        case .langLiteral:
            let value = try container.decode(String.self, forKey: .value)
            let language = try container.decode(String.self, forKey: .language)
            self = .langLiteral(value: value, language: language)
        }
    }
}
