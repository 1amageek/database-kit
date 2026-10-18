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

    /// Admits a complete request while retaining independent PREPARE definitions.
    public func validate(_ block: SQLBlock) throws(QueryParameterBindingError) {
        let missing: QueryParameterReference?
        do {
            missing = try QueryStructuralValidator.validateBoundStructure(block,
                positionalParameters: positions, namedParameters: names, limits: structuralLimits)
        } catch { throw .invalidStructure(error) }
        if let missing {
            switch missing {
            case .position(let position): throw .missingPosition(position)
            case .name(let name): throw .missingName(name)
            }
        }
    }

    /// Substitutes only request-scope parameters, then admits their cumulative footprint.
    public func bind(_ block: SQLBlock) throws(QueryParameterBindingError) -> SQLBlock {
        try validate(block)
        var steps: [SQLBlockStep] = []
        steps.reserveCapacity(block.steps.count)
        for step in block.steps {
            switch step {
            case .statement(let statement): steps.append(.statement(try bind(statement)))
            case .explain(let command):
                steps.append(.explain(SQLExplain(statement: try bind(command.statement), options: command.options)))
            case .setting(.set(let name, let value, let scope)):
                steps.append(.setting(.set(name: name, value: try bindRequestExpression(value), scope: scope)))
            case .execute(let command):
                var arguments: [Expression] = []
                arguments.reserveCapacity(command.arguments.count)
                for argument in command.arguments { arguments.append(try bindRequestExpression(argument)) }
                steps.append(.execute(SQLExecute(name: command.name, arguments: arguments)))
            case .copy(let command):
                if case .query(let query) = command.target {
                    guard case .select(let bound) = try bind(.select(query)) else { throw .invalidTraversalState }
                    steps.append(.copy(SQLCopyCommand(target: .query(bound), direction: command.direction,
                        options: command.options, data: command.data)))
                } else { steps.append(step) }
            case .prepare, .transaction, .setting, .deallocate, .setConstraints, .sequence,
                 .savepoint, .rollbackTo, .release:
                steps.append(step)
            }
        }
        do { return try SQLBlock(steps: steps, limits: structuralLimits) }
        catch { throw .invalidStructure(error) }
    }

    private func bindRequestExpression(_ expression: Expression) throws(QueryParameterBindingError) -> Expression {
        var traversal = QueryParameterBindingTraversal(positions: positions, names: names)
        return try traversal.bindExpression(expression).value
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
