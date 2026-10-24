# Fluent Query Construction

## Purpose and Scope

Status: N00 implemented and behaviorally verified; N04 Builder migration remains planned. Parent:
[Query](../DESIGN.md). Children: none. Owns pure construction of existing query
IR from named sources and compiled model fields. Runtime references stay in SDK.

## Responsibilities and Boundaries

QuerySource supplies DataSource. SelectQuery is the canonical selection IR.
Proposed Selection<Model> is an immutable phantom-model view over one
SelectQuery, not a second AST. TableRef.select produces SelectQuery;
Persistable static select produces Selection<Model>. Neither stores a
connection, model instance, metatype, KeyPath, schema lease or policy result.
Client-only consumers can construct queries. QueryAST keeps parsing/SQL
serialization; Framework keeps evaluation and storage binding.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Query](../DESIGN.md) | parent | Existing IR/validation | Owns semantics | One canonical IR |
| [Model](../../Model/DESIGN.md) | depends on | Compiled Field identity | Supplies model metadata | No runtime type recovery |
| [QueryAST Builder](../../../../../database-framework/Sources/QueryAST/Builder/DESIGN.md) | coordinates with | Current construction/serializer | Construction migrates here | Serializer stays there |
| [SDK references](../../../../../database-client/Sources/DatabaseAccess/QueryReferences/DESIGN.md) | used by | Pure construction | Attaches DB handle externally | No SDK dependency in Kit |

## Architecture

```text
TableRef / compiled Model / QuerySource -> pure construction -> SelectQuery
Predicate<Model> ----------------------------^                + Selection<Model>
```

## Contracts and Invariants

QuerySource's source-producing member is a protocol requirement. Shared
algorithms use concrete/generic Source: QuerySource dispatch; no extension-only
existential calls are used on Embedded. SDK bound methods use the same pure
functions and keep their handle outside this component.

Fluent methods return new values and preserve source qualification, ordered
projection/duplicate labels, aliases, partitions, CTE scope and untouched clauses.
Pagination uses QueryPagination. No build/buildAST or SQL round trip is needed.
Model.persistableType and Field metadata supply names; reflected names do not.
Typed FieldComparison lowering retains the stored FieldValue's primitive width.
General QueryLiteralConvertible construction preserves that protocol's existing
canonical type choices, including its current integer mappings; this migration
does not silently change the converter contract. Coercion/type checking stays
in execution. Structural validation and typed literal failures remain bounded.

### Predicate declaration split

Current Field operators return Framework Predicate<Model>. Its declaration,
FieldComparison and evaluation are mixed in DatabaseQuery.swift. N00 moves only
pure Predicate/FieldComparison identity-value declarations and field comparison
vocabulary
and Field operators/factories to Kit. Model/string/sort evaluation, meters and
fetch execution remain Framework-owned. Canonical FieldComparison initialization preserves identity without granting
schema authority. Selection checks model field numbers and names; execution
rebinds current schema and policy. Runtime internals do not move into Kit.

Kit already owns a different ComparisonOperator for six SQL comparisons. Move
the broader model predicate enum under the semantic name FieldComparisonOperator,
migrating its explicit callers without a compatibility alias; do not merge
model contains/IN/nil behavior into SQL's quantified-comparison enum. This naming
collision is a required N00 migration/compile check, not an invitation to keep
two declarations with the same name in Kit.

Do not add competing Field operators returning a different wrapper: standalone
comparisons become ambiguous when both modules are imported. New selection
lowering consumes the same predicate vocabulary and immediately creates
Expression. Selection retains only SelectQuery, not another predicate tree.
Scalar comparisons/logical operators, nil tests and IN use canonical SQL
NULL/type semantics. Unsupported model-specific predicate/value forms fail
explicitly before invocation. Document the accepted/rejected inventory; no
unsupported form becomes false, LIKE, NULL or a missing filter.

Keep existing model evaluator behavior during the declaration move. In
particular, model negation of a false NULL comparison does not prove SQL
NOT UNKNOWN semantics. New canonical selections are tested against SQL/IR,
while existing model evaluation gets its own regression evidence.

### SQLQueryBuilder migration

N04 migrates all active pure construction callers/tests, preserving joins,
aliases, grouping, windows, pagination, CTEs and recursive/search/cycle metadata.
Remove the superseded Builder only after replacement success/failure behavior
and caller migration in the same implementation sprint. SQLSerializer stays
QueryAST-owned. Unrelated graph execution builders/model fetch capabilities
remain with their semantic owners; no compatibility alias replaces the migration.

## State, Ownership, and Lifecycle

Values retain existing immutable/COW IR storage; model parameters are phantom.
Construction does not serialize, decode, rebuild models or allocate per-row
state. It holds no connection, transaction or I/O resource.

## Failure, Concurrency, and Constraints

Literal, structural, pagination and unsupported-lowering failures are typed.
Runtime still performs full binding/security/budget validation. A compiled
field does not establish current schema validity or permission. Values and
Sendable contracts are the same across Native/WASM/Embedded.

## Verification and Change Impact

N00 tests exact IR, integer width/NULL/rich failures, root-field restrictions,
standalone operator inference with Kit plus Framework, no retained KeyPath/type
metadata and unchanged model evaluation. N04 retains existing Builder metadata
and serializer round trips. N05 executes typed/named construction versus SQL
and direct IR on real local/remote and portable paths. AST assertions alone
are not execution evidence.

### N00 implementation boundary

QuerySource is a source-producing protocol requirement adopted by TableRef and
DataSource. Source construction moves a TableRef alias into the existing aliased
source while preserving schema, exact name and partitions. Selection<Model>
stores only SelectQuery; heterogeneous typed projections use static parameter
packs and reject a stale field number/name before lowering. Predicate lowering
admits scalar comparison, null tests, IN/NOT IN, and boolean structure. Model
contains/hasPrefix/hasSuffix and array/object scalar operands fail explicitly.
NULL comparisons remain SQL expressions rather than being evaluated by the
model predicate engine. Lowering checks depth/node/collection limits and the
complete resulting IR is validated before a typed filter is published.

| State | Native | ordinary WASM | Embedded |
|---|---|---|---|
| Source, Selection, Predicate, FieldComparison | Immutable/COW values | Same | Same |
| Lowering counters and intermediate expressions | Exclusive synchronous locals | Same | Same |
| Shared runtime state | None introduced | None introduced | None introduced |

Behavioral owner: DatabaseKitTests/FluentSelectionTests (12 cases). Framework's
existing fetch/evaluation suites verify unchanged model semantics after the
declaration move. Exact count changes live only in the executable harness.

The pinned Aug14 Embedded compiler cannot forward a heterogeneous Field pack
through a second generic selection call: it either rejects specialization or
requests unavailable archetype metadata. Both entry points expand the pack at
their own boundary, then call the same non-generic FieldIdentity projection
operation. This keeps the public API and field validation identical across
Native, standard WASM and Embedded without unsafe conversion or target branches.
The runtime fixture verifies heterogeneous projections, exact Int32 filtering,
immutable branches, unsupported operators, depth rejection, 128 conditions and
qualified/partitioned sources. Its exact marker count belongs to the harness.
