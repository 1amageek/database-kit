import DatabaseTypes

/// Validates a reference identifier against a compiled model identifier type.
public enum PersistableIdentifierValidator {
    public static func validate(
        _ identifier: ReferenceIdentifier,
        as expectedType: PersistableIdentifierType
    ) throws(PersistableIdentifierValidationError) {
        do {
            try identifier.validate()
        } catch let error {
            throw .invalidValue(error)
        }

        var pending: [(ReferenceIdentifier, PersistableIdentifierType)] = [
            (identifier, expectedType)
        ]
        while let (value, expected) = pending.popLast() {
            switch (value, expected) {
            case (.bool, .bool),
                 (.int8, .int8),
                 (.int16, .int16),
                 (.int32, .int32),
                 (.int64, .int64),
                 (.uint8, .uint8),
                 (.uint16, .uint16),
                 (.uint32, .uint32),
                 (.uint64, .uint64),
                 (.string, .string),
                 (.bytes, .bytes),
                 (.uuid, .uuid):
                continue
            case (
                .composite(let values),
                .composite(let expectedComponents)
            ):
                guard values.count == expectedComponents.count else {
                    throw .componentCountMismatch(
                        expected: expectedComponents.count,
                        actual: values.count
                    )
                }
                for index in values.indices.reversed() {
                    pending.append(
                        (values[index], expectedComponents[index])
                    )
                }
            default:
                throw .typeMismatch(
                    expected: expected,
                    actual: type(of: value)
                )
            }
        }
    }

    private static func type(
        of value: ReferenceIdentifier
    ) -> PersistableIdentifierType {
        switch value {
        case .bool: .bool
        case .int8: .int8
        case .int16: .int16
        case .int32: .int32
        case .int64: .int64
        case .uint8: .uint8
        case .uint16: .uint16
        case .uint32: .uint32
        case .uint64: .uint64
        case .string: .string
        case .bytes: .bytes
        case .uuid: .uuid
        case .composite(let components):
            .composite(components.map(type(of:)))
        }
    }
}
