import DatabaseValue

/// Resolves canonical wire parameters into an immutable QueryIR statement.
public struct QueryParameterBinder: Sendable {
    private let positions: [UInt32: DatabaseValue]
    private let names: [String: DatabaseValue]
    private let structuralLimits: QueryStructuralLimits

    public init(
        parameters: [DatabaseObjectField],
        structuralLimits: QueryStructuralLimits = .default
    ) throws {
        try QueryStructuralValidator.validate(
            parameters: parameters,
            limits: structuralLimits
        )
        var positions: [UInt32: DatabaseValue] = [:]
        var names: [String: DatabaseValue] = [:]

        for parameter in parameters {
            guard parameter.number > 0 else {
                throw QueryParameterBindingError.invalidPosition(
                    parameter.number
                )
            }
            guard positions.updateValue(parameter.value, forKey: parameter.number) == nil else {
                throw QueryParameterBindingError.duplicatePosition(
                    parameter.number
                )
            }
            if !parameter.name.isEmpty {
                guard names.updateValue(parameter.value, forKey: parameter.name) == nil else {
                    throw QueryParameterBindingError.duplicateName(
                        parameter.name
                    )
                }
            }
        }

        self.positions = positions
        self.names = names
        self.structuralLimits = structuralLimits
    }

    public func bind(
        _ statement: QueryStatement
    ) throws -> QueryStatement {
        try QueryStructuralValidator.validateBoundStructure(
            statement,
            positionalParameters: positions,
            namedParameters: names,
            limits: structuralLimits
        )
        var traversal = QueryParameterBindingTraversal(
            positions: positions,
            names: names
        )
        return try traversal.bind(statement)
    }
}
