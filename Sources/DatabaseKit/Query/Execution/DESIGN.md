# Query Execution Contracts

## Purpose and Scope

This component owns Foundation-independent execution input and final result
contracts above QueryStatement, SQLBlock, QueryColumn and QueryValue. Parent:
[Query](../DESIGN.md). Children: none. Runtime implementations belong to Framework
and Client; framing belongs to [DatabaseWire](../../../DatabaseWire/DESIGN.md).

## Responsibilities and Boundaries

QueryInput preserves text/language or the existing IR/block without conversion.
SQL is text plus canonical bound parameters, not another statement IR. Its
string interpolation appends numbered placeholders and retains values through
Kit's existing total FieldValueRepresentable adaptation or an explicit
QueryValue/type. Fallible model serialization is not implicit SQL conversion.
Dynamic SQL source uses an explicit text/parameters initializer; the public
connection does not overload execute(String), which could already contain
unsafe ordinary String interpolation.
QueryRow owns positional canonical values, annotations and an opaque version.
QueryResult is the closed outcome algebra parameterized by retained row, graph
and boolean carriers. QueryRows/QueryGraph are independently implemented result
consumption contracts; this component creates no connection, cursor, transaction,
transport, meter, executable closure, runtime registry or authority handle.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Query](../DESIGN.md) | parent | QueryStatement, schema and typed values | Semantic input/output vocabulary | No second statement algebra or SQL-to-IR coercion policy |
| [SQL](../SQL/DESIGN.md) | depends on | SQLBlock and SQL command kinds | Ordered transactional block meaning | First failure rolls back the entire request |
| [Wire](../../../DatabaseWire/DESIGN.md) | used by | Bounded codecs and retained pages | Closed canonical operation projection | Bulk decoding stays lazy; no runtime state moves into declarations |
| [Framework Database](../../../../../database-framework/Sources/Database/DESIGN.md) | used by | Common execution facade | Local runtime implementation | Original authorization, one meter and authoritative data closure |
| [Client](../../../../../database-client/DESIGN.md) | used by | Typed remote invocation | Remote runtime implementation | No SQL parsing or automatic mutation replay |

## Architecture

```text
SQL text -> execution-side parser --+
QueryStatement --------------------+-> admission -> execution -> QueryResult
SQLBlock --------------------------+                           -> QueryRow
Kit owns declarations; Framework owns execution; Client owns remote invocation.
```

## Contracts and Invariants

- Text and equivalent IR use the same QueryStatement/SQLBlock meaning.
- Final rows use one QueryRow, QueryColumn and QueryValue vocabulary. Column
  order, duplicate labels, zero-row schemas, exact values and SQL-specific
  metadata survive local adaptation and Wire round trips.
- Rows, commands, COPY, booleans and RDF graphs are distinct outcomes. Blocks
  preserve statement order rather than flattening unrelated row schemas.
- Row/graph carrier types differ only in ownership and retrieval mechanism;
  the result algebra and observable value/failure contracts are common.
- No result declaration proves transaction closure. Framework's concrete
  collecting/ready owners remain the only authority for publication.
- QueryResult.rows, columns, command and affectedRows expose the accepted
  single-statement consumption surface. Non-row outcomes have an empty row
  sequence, while their distinct outcome and count remain available. A block
  has no combined row schema; results preserves each statement separately.

## Failure, Concurrency, and Constraints

AsyncSequence carriers preserve failure and cancellation. Runtime owners enforce
active-call cancellation, bounded retention and resource release; complete
immutable values are caller-owned after transfer and need no result.close().
A paged reader requires its connection only for subsequent retrieval. Declaration values
contain no mutable synchronization or target-specific ownership branch. Intrinsic
structural limits and Wire limits reject invalid input rather than synthesizing
empty success. IR input retains full validation and authorization.

## Verification and Change Impact

Kit tests cover input carriage and canonical row/result value contracts. Wire
tests cover rich values, duplicate columns, zero rows, bounded decoding and
retained-frame lifetime. Framework and Server own SQL/IR/local/remote behavioral
parity and failures; Client owns correlation, cancellation, close and no replay.
Changing this contract requires all four owners and affected consumers to migrate.

### Result Carrier Composition

`QueryResult<Rows, Graph, Boolean>` is one closed outcome algebra. Its generic
parameters are result carriers, not root, authority or operation-lifecycle
parameters. `QueryRows` and `QueryGraph` describe retained AsyncSequence values;
`QueryBoolean` preserves the value while allowing the MultiBase provenance
carrier. Wire specializes the algebra with its immutable frame-retaining pages.
Client and Framework specialize it with connection-owned retrieval sequences.
No transport, meter, cursor or executor implementation enters this component.
The final QueryRow stores QueryValue, FieldObject annotations and opaque version
bytes. Wire supplies only codec extensions, not a second final row declaration.
