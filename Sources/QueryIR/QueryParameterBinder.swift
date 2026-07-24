import DatabaseTypes
import DatabaseValue

/// Resolves canonical wire parameters into an immutable QueryIR statement.
public struct QueryParameterBinder: Sendable {
    private let positions: [UInt32: FieldValue]
    private let names: [String: FieldValue]
    private let structuralLimits: QueryStructuralLimits

    public init(
        parameters: [QueryParameter],
        structuralLimits: QueryStructuralLimits = .default
    ) throws {
        try QueryStructuralValidator.validate(
            parameters: parameters,
            limits: structuralLimits
        )
        var positions: [UInt32: FieldValue] = [:]
        var names: [String: FieldValue] = [:]

        for parameter in parameters {
            guard parameter.position > 0 else {
                throw QueryParameterBindingError.invalidPosition(
                    parameter.position
                )
            }
            guard positions.updateValue(
                parameter.value,
                forKey: parameter.position
            ) == nil else {
                throw QueryParameterBindingError.duplicatePosition(
                    parameter.position
                )
            }
            if let name = parameter.name {
                guard !name.isEmpty else {
                    throw QueryParameterBindingError.invalidName
                }
                guard names.updateValue(parameter.value, forKey: name) == nil else {
                    throw QueryParameterBindingError.duplicateName(
                        name
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
