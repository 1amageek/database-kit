import DatabaseTypes

/// Resolves canonical wire parameters into an immutable QueryIR statement.
public struct QueryParameterBinder: Sendable {
    private let positions: [UInt32: QueryParameter]
    private let names: [String: QueryParameter]
    private let structuralLimits: QueryStructuralLimits

    public init(
        parameters: [QueryParameter],
        structuralLimits: QueryStructuralLimits = .default
    ) throws(QueryParameterBindingError) {
        do {
            try QueryStructuralValidator.validate(
                parameters: parameters,
                limits: structuralLimits
            )
        } catch {
            throw .invalidStructure(error)
        }
        var positions: [UInt32: QueryParameter] = [:]
        var names: [String: QueryParameter] = [:]

        for parameter in parameters {
            guard parameter.position > 0 else {
                throw QueryParameterBindingError.invalidPosition(
                    parameter.position
                )
            }
            guard positions.updateValue(
                parameter,
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
                guard names.updateValue(parameter, forKey: name) == nil else {
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

    /// Admits every parameter occurrence without substituting the semantic tree.
    public func validate(
        _ statement: QueryStatement
    ) throws(QueryParameterBindingError) {
        let missing: QueryParameterReference?
        do {
            missing = try QueryStructuralValidator.validateBoundStructure(
                statement,
                positionalParameters: positions,
                namedParameters: names,
                limits: structuralLimits
            )
        } catch {
            throw .invalidStructure(error)
        }
        if let missing {
            switch missing {
            case .position(let position): throw .missingPosition(position)
            case .name(let name): throw .missingName(name)
            }
        }
    }

    public func bind(
        _ statement: QueryStatement
    ) throws(QueryParameterBindingError) -> QueryStatement {
        try validate(statement)
        var traversal = QueryParameterBindingTraversal(
            positions: positions,
            names: names
        )
        return try traversal.bind(statement)
    }
}
