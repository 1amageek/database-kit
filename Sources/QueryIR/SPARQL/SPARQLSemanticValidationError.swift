import DatabaseTypes
import DatabaseValue

/// A violation of the canonical QueryIR semantics defined by SPARQL.
public enum SPARQLSemanticValidationError: Error, Sendable, Equatable {
    public enum BlankNodeContext: String, Sendable, Equatable {
        case deleteData
        case deleteWhere
        case deleteTemplate
        case values
        case expression
    }

    public enum GroundDataContext: String, Sendable, Equatable {
        case insertData
        case deleteData
    }

    public enum TermRole: String, Sendable, Equatable {
        case subject
        case predicate
        case object
        case graphName
        case describeResource
    }

    public enum TermKind: String, Sendable, Equatable {
        case variable
        case iri
        case literal
        case blankNode
        case tripleTerm
        case reifiedTriple
    }

    public enum AggregateContext: String, Sendable, Equatable {
        case filter
        case bind
        case groupBy
        case aggregateOperand
    }

    /// One query blank node label occurred in more than one basic graph pattern.
    case labelCrossesBasicGraphPatterns(String)

    /// One blank node label occurred in more than one WHERE clause in an Update request.
    case labelCrossesWhereClauses(String)

    /// One blank node label occurred in more than one INSERT DATA operation in an Update request.
    case labelCrossesInsertDataOperations(String)

    /// A term used the RDF-node compatibility cases embedded in `Literal`
    /// instead of its unique canonical `SPARQLTerm` representation.
    case nonCanonicalTermLiteral

    /// A non-RDF value was embedded as a graph term literal.
    case invalidTermLiteral

    /// A blank node occurred in a DELETE form where SPARQL forbids it.
    case blankNodeNotAllowed(context: BlankNodeContext, label: String)

    /// A term kind is not valid in its RDF/SPARQL syntactic role.
    case invalidTermRole(role: TermRole, kind: TermKind)

    /// A QueryIR variable is not a canonical sigil-free SPARQL VARNAME.
    case invalidVariableName(String, SPARQLVariableNameError)

    /// A QueryIR IRI is not a validated absolute RFC 3987 IRI.
    case invalidIRI(String, RDFIRIError)

    /// An RDF typed literal used an invalid or reserved datatype annotation.
    case invalidTypedLiteralDatatype(
        String,
        RDFTypedLiteralDatatypeError
    )

    /// An RDF language literal used an invalid BCP 47 language tag.
    case invalidLanguageTag(String, RDFLanguageTagError)

    /// A directional language literal used a direction other than ltr or rtl.
    case invalidBaseDirection(String)

    /// An aggregate occurred in a SPARQL expression context that forbids it.
    case aggregateNotAllowed(AggregateContext)

    /// An aggregate operand recursively contained another aggregate.
    case nestedAggregate

    /// More than one projection item exposed the same target variable.
    case duplicateProjectionTarget(String)

    /// BIND or SELECT AS attempted to replace an in-scope variable.
    case variableAlreadyInScope(String)

    /// A non-variable projection expression omitted its required alias.
    case projectionExpressionRequiresAlias

    /// A grouped projection referenced a variable outside its group scope.
    case projectionVariableNotGrouped(String)

    /// A VALUES row did not match the declared variable width.
    case valuesRowWidth(row: Int, expected: Int, actual: Int)

    /// A VALUES declaration repeated one variable name.
    case duplicateValuesVariable(String)

    /// A variable occurred in an operation that requires ground RDF data.
    case variableNotAllowed(context: GroundDataContext, name: String)

    /// Canonical QueryIR exceeded a deterministic structural resource limit.
    case structural(QueryStructuralValidationError)
}

extension SPARQLSemanticValidationError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .labelCrossesBasicGraphPatterns(let label):
            return "Blank node label '_:\(label)' crosses basic graph pattern boundaries"
        case .labelCrossesWhereClauses(let label):
            return "Blank node label '_:\(label)' occurs in more than one WHERE clause"
        case .labelCrossesInsertDataOperations(let label):
            return "Blank node label '_:\(label)' occurs in more than one INSERT DATA operation"
        case .nonCanonicalTermLiteral:
            return "SPARQLTerm.literal must contain an RDF literal, not another RDF node representation"
        case .invalidTermLiteral:
            return "SPARQLTerm.literal must contain one RDF literal value"
        case .blankNodeNotAllowed(let context, let label):
            return "Blank node '_:\(label)' is not allowed in \(context.rawValue)"
        case .invalidTermRole(let role, let kind):
            return "SPARQL term kind '\(kind.rawValue)' is invalid in \(role.rawValue) position"
        case .invalidVariableName(let variable, let reason):
            return "Invalid canonical SPARQL variable '\(variable)': \(reason)"
        case .invalidIRI(let iri, let reason):
            return "Invalid canonical SPARQL IRI '\(iri)': \(reason)"
        case .invalidTypedLiteralDatatype(let datatype, let reason):
            return "Invalid RDF typed-literal datatype '\(datatype)': \(reason)"
        case .invalidLanguageTag(let language, let reason):
            return "Invalid RDF language tag '\(language)': \(reason)"
        case .invalidBaseDirection(let direction):
            return "Invalid RDF base direction '\(direction)'"
        case .aggregateNotAllowed(let context):
            return "SPARQL aggregate is not allowed in \(context.rawValue)"
        case .nestedAggregate:
            return "SPARQL aggregate operands cannot contain another aggregate"
        case .duplicateProjectionTarget(let variable):
            return "SPARQL projection exposes variable '\(variable)' more than once"
        case .variableAlreadyInScope(let variable):
            return "SPARQL assignment target '\(variable)' is already in scope"
        case .projectionExpressionRequiresAlias:
            return "SPARQL projection expressions require an AS target"
        case .projectionVariableNotGrouped(let variable):
            return "SPARQL grouped projection references non-group variable '\(variable)'"
        case .valuesRowWidth(let row, let expected, let actual):
            return "SPARQL VALUES row \(row) has width \(actual), expected \(expected)"
        case .duplicateValuesVariable(let variable):
            return "SPARQL VALUES declares variable '\(variable)' more than once"
        case .variableNotAllowed(let context, let name):
            return "SPARQL variable '\(name)' is not allowed in \(context.rawValue)"
        case .structural(let error):
            return error.description
        }
    }
}

extension SPARQLSemanticValidationError {
    public var isResourceLimit: Bool {
        if case .structural = self {
            return true
        }
        return false
    }
}
