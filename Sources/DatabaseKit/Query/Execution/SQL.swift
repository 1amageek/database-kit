import DatabaseTypes

/// SQL source and bound values; interpolation never inserts a value into source.
public struct SQL: Sendable, Hashable, ExpressibleByStringInterpolation {
    public let text: String
    public let parameters: [QueryParameter]

    public init(text: String, parameters: [QueryParameter] = []) {
        self.text = text
        self.parameters = parameters
    }

    public init(stringLiteral value: String) {
        self.init(text: value)
    }

    public init(stringInterpolation: StringInterpolation) {
        self.init(text: stringInterpolation.text, parameters: stringInterpolation.parameters)
    }

    public struct StringInterpolation: StringInterpolationProtocol {
        fileprivate var text = ""
        fileprivate var parameters: [QueryParameter] = []

        public init(literalCapacity: Int, interpolationCount: Int) {
            if literalCapacity > 0 { text.reserveCapacity(literalCapacity) }
            if interpolationCount > 0 { parameters.reserveCapacity(interpolationCount) }
        }

        public mutating func appendLiteral(_ literal: String) {
            text.append(contentsOf: literal)
        }

        public mutating func appendInterpolation<Value: FieldValueRepresentable>(
            _ value: Value
        ) throws(SQLInterpolationError) {
            try appendInterpolation(QueryValue.primitive(value.fieldValue))
        }

        public mutating func appendInterpolation(
            _ value: QueryValue, type: QueryColumnType? = nil
        ) throws(SQLInterpolationError) {
            let next = parameters.count.addingReportingOverflow(1)
            guard !next.overflow, let position = UInt32(exactly: next.partialValue) else {
                throw .tooManyParameters
            }
            text.append(contentsOf: "$\(position)")
            parameters.append(QueryParameter(position: position, value: value, type: type))
        }
    }
}
