import DatabaseTypes

extension FieldObject: @retroactive Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(
            keyedBy: FieldObjectCodingKey.self
        )
        var fields: [(key: String, value: FieldValue)] = []
        fields.reserveCapacity(container.allKeys.count)
        for key in container.allKeys {
            fields.append(
                (
                    key: key.stringValue,
                    value: try container.decode(
                        FieldValue.self,
                        forKey: key
                    )
                )
            )
        }
        do {
            try self.init(fields)
        } catch let error {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Invalid field object: \(error)"
                )
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(
            keyedBy: FieldObjectCodingKey.self
        )
        for field in fields {
            try container.encode(
                field.value,
                forKey: FieldObjectCodingKey(field.key)
            )
        }
    }
}

private struct FieldObjectCodingKey: CodingKey {
    let stringValue: String

    init(_ stringValue: String) {
        self.stringValue = stringValue
    }

    init?(stringValue: String) {
        self.init(stringValue)
    }

    let intValue: Int? = nil

    init?(intValue: Int) {
        return nil
    }
}
