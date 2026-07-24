/// Validates identifier declarations and values with bounded, iterative walks.
public enum PersistableIdentifierValidator {
    public static func validate(
        _ type: PersistableIdentifierType,
        limits: PersistableIdentifierLimits = .default
    ) throws(PersistableIdentifierValidationError) {
        var pending: [(type: PersistableIdentifierType, depth: Int)] = [(type, 0)]
        var componentCount = 0

        while let node = pending.popLast() {
            componentCount = try checkedComponentCount(
                after: componentCount,
                limits: limits
            )
            guard case .composite(let components) = node.type else {
                continue
            }
            guard !components.isEmpty else {
                throw .emptyComposite
            }
            guard node.depth < limits.maximumCompositeDepth else {
                throw .compositeDepthExceeded(
                    actual: node.depth + 1,
                    maximum: limits.maximumCompositeDepth
                )
            }
            try validateScheduledComponentCount(
                components.count,
                currentCount: componentCount,
                limits: limits
            )
            for component in components.reversed() {
                pending.append((component, node.depth + 1))
            }
        }
    }

    public static func validate(
        _ value: PersistableIdentifierValue,
        as expectedType: PersistableIdentifierType,
        limits: PersistableIdentifierLimits = .default
    ) throws(PersistableIdentifierValidationError) {
        try validate(expectedType, limits: limits)

        var pending: [(
            value: PersistableIdentifierValue,
            expectedType: PersistableIdentifierType,
            depth: Int
        )] = [(value, expectedType, 0)]
        var componentCount = 0

        while let node = pending.popLast() {
            componentCount = try checkedComponentCount(
                after: componentCount,
                limits: limits
            )

            switch (node.value, node.expectedType) {
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

            case (.composite(let values), .composite(let types)):
                guard !values.isEmpty else {
                    throw .emptyComposite
                }
                guard node.depth < limits.maximumCompositeDepth else {
                    throw .compositeDepthExceeded(
                        actual: node.depth + 1,
                        maximum: limits.maximumCompositeDepth
                    )
                }
                guard values.count == types.count else {
                    throw .typeMismatch(expected: node.expectedType)
                }
                try validateScheduledComponentCount(
                    values.count,
                    currentCount: componentCount,
                    limits: limits
                )
                for index in values.indices.reversed() {
                    pending.append(
                        (values[index], types[index], node.depth + 1)
                    )
                }

            default:
                throw .typeMismatch(expected: node.expectedType)
            }
        }
    }

    public static func validateStructure(
        _ value: PersistableIdentifierValue,
        limits: PersistableIdentifierLimits = .default
    ) throws(PersistableIdentifierValidationError) {
        var pending: [(value: PersistableIdentifierValue, depth: Int)] = [(value, 0)]
        var componentCount = 0

        while let node = pending.popLast() {
            componentCount = try checkedComponentCount(
                after: componentCount,
                limits: limits
            )
            guard case .composite(let components) = node.value else {
                continue
            }
            guard !components.isEmpty else {
                throw .emptyComposite
            }
            guard node.depth < limits.maximumCompositeDepth else {
                throw .compositeDepthExceeded(
                    actual: node.depth + 1,
                    maximum: limits.maximumCompositeDepth
                )
            }
            try validateScheduledComponentCount(
                components.count,
                currentCount: componentCount,
                limits: limits
            )
            for component in components.reversed() {
                pending.append((component, node.depth + 1))
            }
        }
    }

    private static func checkedComponentCount(
        after componentCount: Int,
        limits: PersistableIdentifierLimits
    ) throws(PersistableIdentifierValidationError) -> Int {
        let (nextCount, overflow) = componentCount.addingReportingOverflow(1)
        guard !overflow, nextCount <= limits.maximumComponentCount else {
            throw .componentCountExceeded(
                actual: overflow ? Int.max : nextCount,
                maximum: limits.maximumComponentCount
            )
        }
        return nextCount
    }

    private static func validateScheduledComponentCount(
        _ scheduledCount: Int,
        currentCount: Int,
        limits: PersistableIdentifierLimits
    ) throws(PersistableIdentifierValidationError) {
        let (total, overflow) = currentCount.addingReportingOverflow(
            scheduledCount
        )
        guard !overflow, total <= limits.maximumComponentCount else {
            throw .componentCountExceeded(
                actual: overflow ? Int.max : total,
                maximum: limits.maximumComponentCount
            )
        }
    }
}
