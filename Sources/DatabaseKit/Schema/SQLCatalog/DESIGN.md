# SQL Catalog Declarations

## Purpose and Scope

SQLCatalog is a child of [Schema](../DESIGN.md) and owns immutable logical SQL
namespace, relation, column, key and search-path declarations. It has no child
components. S11 introduced the initial values; S13 extends them with constraint, column-policy and sequence declarations without changing `Schema`,
`SchemaManifest`, wire bytes, JSON schema layout or primitive field values.

## Responsibilities and Boundaries

This component owns intrinsic declaration validation and exact identifier
identity. Framework owns persisted catalog generations, transactional storage,
physical-schema validation, name resolution, authorization, metadata budgets,
static-model protection and restart admission. A key declaration does not
enforce uniqueness; Framework owns constraint execution. S14 owns SQL writes and S15
owns DDL syntax and execution.

SQL namespaces do not represent Directory, Partition, tenant, Base, placement
or authority boundaries. Renaming a logical name does not change a stable ID,
physical field number or physical entity binding.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Schema](../DESIGN.md) | parent | immutable database declarations | Composes the logical catalog with physical model declarations. | Neither `Schema` nor its manifest acquires SQL runtime state. |
| [SQL profile](../../Query/SQL/DESIGN.md) | coordinates with | exact SQL names, logical keys, runtime ownership | Defines accepted SQL meaning and sprint boundaries. | A declared primary key is not constraint enforcement. |
| [Parser](../../../../../database-framework/Sources/QueryAST/Parser/DESIGN.md#s02-strict-lexical-and-grammar-contract) | used by | folded unquoted and exact quoted names | Supplies already normalized logical identifiers. | Do not fold again, truncate, normalize Unicode or split dotted names. |
| [DatabaseEngine](../../../../../database-framework/Sources/DatabaseEngine/DESIGN.md) | used by | validated immutable catalog input | Owns physical binding and persisted generations. | Runtime limits, principal expansion and storage remain Framework-owned. |

## Architecture

```text
SQLNamespace ──────────────┐
SQLColumn → SQLRelation ──┼→ SQLCatalog → Framework physical binding / persistence
                         │                 → binding / restart / protection
SQLSearchPathEntry → SQLSearchPath ─────────→ Framework name resolution
```

## Contracts and Invariants

The public values below are immutable `Sendable` and `Hashable`. Their
initializers validate pure intrinsic meaning with typed `SQLCatalogError`.
They contain no engine, application metatype, mutable registration, credentials
or runtime service. Array order is preserved and participates in identity;
column order is observable SQL ordinal order and primary-key order is key order.

| Value | Public state and construction |
|---|---|
| `SQLNamespace` | `id: String`, `name: String`; throwing `init(id:name:)` |
| `SQLColumn` | Logical column identity and backing; the S13 table below owns its complete current shape. |
| `SQLRelation` | Logical relation identity, physical entity binding and ordered columns/key; S13 below owns its extended constraint shape. |
| `SQLCatalog` | Immutable namespaces, relations and sequences; S13 below owns the complete initializer contract. |
| `SQLSearchPathEntry` | `.schema(String)` or `.currentUser`; payload validation occurs in `SQLSearchPath` construction |
| `SQLSearchPath` | `entries: [SQLSearchPathEntry]`; throwing `init(entries:)`; nonthrowing `.default` with ordered `[.currentUser, .schema("public")]` |

Every ID, name, namespace reference, entity binding and key-column reference
must be nonempty and contain no U+0000. No inferred 63-byte SQL name limit or
new collection cap is introduced. Framework admits total UTF-8 bytes and
collection cardinality under its persisted-frame and request metadata budget
before runtime allocation or decoding.

Equality and hashing compare every String by its exact UTF-8 bytes, following
[NamedWindow](../../Query/NamedWindow.swift). Swift String's canonical Unicode
equivalence must not collapse distinct quoted SQL names. Unquoted ASCII folding
belongs to the lexer, and an exact quoted dot remains part of one identifier.
Validation uniqueness and reference checks use that same byte identity.

| Scope | Required validation |
|---|---|
| Catalog namespaces | Unique namespace IDs and unique namespace names. |
| Catalog relations | Unique relation IDs; unique relation name within its namespace; namespace ID exists. |
| Physical binding | At most one SQL relation binds an exact `entityName` in one catalog. Views are a separate later contract. |
| Relation columns | Unique column IDs, names and physical field numbers within the relation. A column's field number is strictly positive. Empty public columns are permitted. |
| Primary key | Nil means no declared primary key. A present key is nonempty, contains unique column IDs and references only columns of the same relation. |
| Search path | Explicit schema names are valid identifiers. Empty paths and repeated entries preserve the caller's ordered declaration. |

Namespace and relation IDs are catalog-wide identities. A column's stable
identity is `(relationID, columnID)`; different relations may reuse a column ID.
SQL column identity is independent of physical field number. Framework checks
that each physical entity/field binding exists and derives physical SQL types
and nullability from `FieldSchema`; virtual backing declares its own type and generated policy; these checks do not belong
to intrinsic Kit construction.

`.currentUser` is a deferred search-path entry. Framework expands it from the
existing authenticated principal identifier and skips it for an anonymous
principal. This component introduces no SQL roles, authentication identity or
mutable session state.

## State, Ownership, and Lifecycle

Each value owns its immutable String and Array values through Swift value
semantics. There is no shutdown, resource lease or target-specific storage.
Native, WASM and Embedded share the same representation, validation and
Sendable contract. A persisted generation's lifetime belongs to Framework.

## Failure, Concurrency, and Constraints

`SQLCatalogError` distinguishes empty/NUL identifiers, nonpositive field
numbers, duplicate namespace/relation/column IDs or names, duplicate physical
bindings/field numbers, unknown namespace references and empty/duplicate/unknown
primary-key references. Malformed declarations never become empty catalog,
renamed names or an inferred primary key. Typed errors contain the invalid
value or conflicting identity needed to identify the failed declaration.

This is pure declaration validation. Successful construction proves neither
physical schema compatibility, namespace existence in storage, metadata budget
admission, authorization, persistence nor constraint enforcement.

## Verification and Change Impact

[S11SQLCatalogTests](../../../../Tests/DatabaseKitTests/Schema/S11SQLCatalogTests.swift)
owns direct success/failure construction, exact UTF-8 identity and hashing,
namespace/relation/column collision scopes, missing references, physical field
number separation, no-PK/composite-PK declarations, empty columns and ordered
default/explicit search paths. Canonically equivalent but byte-distinct names
must coexist, compare unequal and remain distinct through Set hashing.

Framework tests own catalog physical admission, transaction rollback, static
protection, search-path resolution and real storage restart. Native and exact
WASM/Embedded compilation and runtime verification follow their package/task
harness contracts. Test declarations are proof subjects; executed evidence is
recorded only in the workspace `PROGRESS.md` and retained harness artifacts.

Changes to this declaration contract require reviewing Framework's persisted
codec and physical admission plus SQL binding. SchemaManifest and wire formats
remain unchanged unless a separate approved change explicitly owns them.


## S13 Constraint, Column Policy and Sequence Contract

This section freezes the semantic declarations consumed by Framework. Runtime
binding, evaluation, persistence, statement/commit checks and sequence reservation
are Framework-owned. The declarations introduce no Foundation, service, metatype,
storage handle or mutable session state.

```text
SQLColumn(backing, policy) ──┐
SQLConstraint ──────────────┼→ SQLRelation → SQLCatalog → Framework admission
SQLSequence(ownedBy?) ──────┘                  ↓
                                 constraint / sequence execution
```

| Public declaration | Exact semantic shape |
|---|---|
| `SQLColumnBacking` | `.field(number: Int)`, `.virtual(type: QueryColumnType)` |
| `SQLColumnPolicy` | `.input(defaultExpression: Expression?)`, `.generated(Expression)`, `.identity(SQLIdentityColumn)` |
| `SQLColumn` | `id`, `name`, `backing`, `policy`; `fieldNumber: Int?` computed from backing; throwing `init(id:name:backing:policy:)` with `.input(defaultExpression: nil)` default; existing `fieldNumber` initializer forwards to `.field` |
| `SQLIdentityGeneration` | `.always`, `.byDefault` |
| `SQLIdentityColumn` | `sequenceID: String`, `generation: SQLIdentityGeneration`; throwing initializer |
| `SQLConstraintTiming` | `.immediate`, `.deferrable(initiallyDeferred: Bool)` |
| `SQLNullUniqueness` | `.distinct`, `.notDistinct` |
| `SQLForeignKeyMatch` | `.simple`, `.full` |
| `SQLReferentialAction` | `.noAction`, `.restrict`, `.cascade`, `.setNull`, `.setDefault` |
| `SQLForeignKey` | `columnIDs: [String]`, `referencedRelationID: String`, `referencedColumnIDs: [String]?`, `match`, `onUpdate`, `onDelete`, `onDeleteColumnIDs: [String]?`; throwing initializer, nil target means target PK, SIMPLE/NO ACTION/nil defaults |
| `SQLConstraintKind` | `.unique(columnIDs: [String], nulls: SQLNullUniqueness)`, `.notNull(columnID: String)`, `.check(Expression)`, `.foreignKey(SQLForeignKey)` |
| `SQLConstraintAttributes` | `id: String`, `name: String`, `timing: SQLConstraintTiming`; throwing initializer with immediate default |
| `SQLConstraint` | `attributes: SQLConstraintAttributes`, `kind: SQLConstraintKind`; throwing initializer; computed `id`, `name`, `timing` |
| `SQLRelation` | Retains canonical `primaryKeyColumnIDs`; adds `primaryKeyConstraint: SQLConstraintAttributes?` and `constraints: [SQLConstraint]`, both initializer arguments default nil/empty. With PK and nil attributes, derive ID `id + ":primary-key"` and name `name + "_pkey"`; attributes without PK fail. No second primary-key column declaration. |
| `SQLSequenceOwner` | `relationID: String`, `columnID: String`; throwing initializer |
| `SQLSequence` | `id`, `namespaceID`, `name`: String; `start`, `increment`, `minimum`, `maximum`: Int64; `cycle: Bool`; `ownedBy: SQLSequenceOwner?`; `declaredType: DataType`; throwing initializer with explicit numeric bounds/start/increment, false/nil defaults and final `declaredType: DataType = .bigint` argument |
| `SQLCatalog` | Adds immutable `sequences: [SQLSequence]`, default empty |

Physical generated columns are STORED; virtual backing is allowed only with a
generated policy and has no physical field number. No sentinel or synthetic
FieldSchema is introduced. SQL defaults are expression policies independent of
existing `FieldSchema.defaultValue`, whose application-model meaning is unchanged.
The runtime derives physical column types from the actual FieldSchema, and virtual
column types from the declared QueryColumnType.

Intrinsic validation uses exact UTF-8 identity for all IDs/names/references,
equality and hashing. Constraint names and IDs are unique per relation; a named
primary key participates in that name set. Unique/key lists must be nonempty,
unique, and local. NOT NULL and CHECK are nondeferrable. FK sides have equal
nonzero arity and distinct valid IDs; relation-local construction validates the
source and catalog construction validates referenced relation/columns. Without the
[S15 standalone-index binding](#s15-ddl-catalog-metadata), it requires a primary
or immediate UNIQUE target covering the same distinct exact-byte column set,
independent of index order. FK source-to-target pairing retains declaration order. Nil FK target columns select its PK. An action subset is nonempty, unique, local, and valid only for DELETE SET NULL/SET DEFAULT. MATCH SIMPLE/FULL and action
choice are declarations; actual data checks are runtime-owned. Generated PK attributes have immediate timing; explicit attributes may declare deferral.

Catalog sequence IDs are unique; relation and sequence names share each namespace's
name scope. Sequence increments are nonzero, minimum is below maximum, start is
within bounds, and integer arithmetic never wraps. Owned-column and identity
sequence references must exist, point to physical columns, and agree when both
sides specify ownership. Full-domain bounds and Int64.min increments remain valid
when the runtime can compute the next value by checked arithmetic. Construction
never reserves or consumes a value. FK/default/generated expression binding,
volatility, type compatibility and existing-data validation remain Framework's
admission contract.

Direct tests own valid construction, each malformed boundary, composite ordered
keys/FKs, virtual-policy rejection, timing restrictions, sequence extrema and
byte-distinct identifiers. Framework owns rollback/deferred/cascade/concurrency,
restart, storage persistence and independently committed sequence consumption.

S15 sequence syntax preserves declared smallint/integer/bigint type as durable
metadata. Other types fail intrinsic construction. Minimum, maximum and start
remain within that declared type's signed range; the increment retains its
existing Int64 contract. An omitted ALTER AS preserves the previous declared
type, including when NO MINVALUE or NO MAXVALUE recomputes dialect defaults.
Renames, candidate reconstruction, block carriage and persisted codecs preserve
this field. Default bigint retains the existing S13 constructor contract.

## S15 DDL Catalog Metadata

The task owner froze this S15 declaration contract before implementation. The
[DDL](../../Query/SQL/DDL/DESIGN.md) child owns unresolved name-based input;
SQLCatalog owns the resulting resolved declarations. SQLRelation continues to
mean one physical entity binding. An ordinary view never fabricates an entity. MV backing relations use distinct internal logical names in the shared namespace; public SQL name lookup excludes their stable IDs, and population resolves them internally by stable ID.

```text
SQLView -> SQLViewDefinition -> SelectQuery + frozen output/source bindings
SQLMaterializedView -> SQLViewDefinition + backingRelationID -> SQLRelation
SQLIndex -> stable relationID + expression keys/predicate
SQLColumn -> stable sequence bindings
SQLRelation -> durable field-number high-water mark
```

| Declaration | Immutable public shape |
|---|---|
| `SQLViewColumn` | `id: String`, `name: String`, `type: QueryColumnType`, `isNullable: Bool`. |
| `SQLViewColumnBinding` | `id: String`, `name: String`, `type: QueryColumnType`; original name, admitted input type and stable source-column identity. |
| `SQLViewSourceBinding` | `schema: String?`, `table: String`, `relationID: String`, `columns: [SQLViewColumnBinding]`; original source name and the frozen referenced columns. |
| `SQLViewDefinition` | `query: SelectQuery`, `columns: [SQLViewColumn]`, `bindings: [SQLViewSourceBinding]`; original query, stable output identity and resolved dependencies. |
| `SQLView` | `id: String`, `namespaceID: String`, `name: String`, `definition: SQLViewDefinition`. |
| `SQLMaterializedView` | `id: String`, `namespaceID: String`, `name: String`, `definition: SQLViewDefinition`, `backingRelationID: String`, `isPopulated: Bool`. |
| `SQLIndex` | `id: String`, `namespaceID: String`, `name: String`, `relationID: String`, `keys: [SortKey]`, `predicate: Expression?`, `unique: Bool`, `nulls: SQLNullUniqueness`, `bindings: [SQLViewColumnBinding]`; source expressions retain original column names through stable bindings. |
| `SQLSequenceBinding` | `originalName: String`, `sequenceID: String`; a constant sequence-function target and its resolved identity. |
| `SQLColumn` | Adds `sequenceBindings: [SQLSequenceBinding]`, default empty. |
| `SQLRelation` | Adds `fieldNumberHighWaterMark: Int`; initializer accepts optional value, defaulting to the greatest existing physical field number or zero. Explicit values must be nonnegative and at least that maximum. |
| `SQLCatalog` | Adds `views: [SQLView]`, `materializedViews: [SQLMaterializedView]`, `indexes: [SQLIndex]`, all default empty. |
| `SQLForeignKey` | Adds `referencedUniqueIndexID: String?`, default nil, to preserve a selected standalone unique index dependency. Nil retains the primary/immediate-UNIQUE constraint contract. |
| `SQLIndex.directColumnIDs` | Optional ordered stable column IDs when every key is a direct column with a declared original-name binding; nil for expression or unbound keys. It does not itself assert uniqueness, absence of a predicate or FK eligibility. |

IDs and names use the existing exact UTF-8 identity and typed intrinsic
construction failures. Catalog construction validates unique IDs, namespace
references and shared namespace name scopes. View outputs and frozen source
columns have unique IDs and names. Source binding keys are exact original
schema/table pairs; repeated physical source references share one binding.
Relation dependencies may name physical relations or logical views, while an
MV backing reference must name a physical relation. Framework validates cycles,
source shape/type compatibility, physical index registration and admission
budgets before retaining a generation. A materialized view is read-only and
querying an unpopulated view fails explicitly; these are runtime guarantees.

An FK carrying referencedUniqueIndexID must reference an existing index on its
target relation. That index is unique, has no partial predicate, and has direct
column keys whose distinct stable-ID set and key count equal the FK target.
Pairing retains the FK's declared order; the index's key order may differ.
Binding selects an eligible primary/immediate-UNIQUE constraint first and uses
a standalone index only when no such constraint matches, recording that exact
index ID. Expression, partial, nonunique and wrong-relation indexes cannot prove
referential uniqueness. Runtime uses the stable dependency for DROP INDEX:
RESTRICT rejects dependents and CASCADE removes their FK constraints while
preserving referencing tables and rows. This introduces no generic dependency
graph or change to ordinary constraint enforcement.

Stored-query binding applies lexical CTE and derived-source resolution before
physical overrides. Each view definition has its own isolated original-name to
stable-ID map. Bound original column names are projected from current physical
columns by stable IDs; wildcard expansion sees the frozen creation-time column
set. Subsequent rename and restart preserve query meaning, and later ADD COLUMN
does not change an existing wildcard view's output. This contract requires no
persisted request-local QueryOccurrenceID.

Runtime preserves the high-water mark across DROP COLUMN, restart and rollback;
new physical field allocation advances it using checked arithmetic. Snapshot
replacement rejects a decreased mark. Dropped field numbers are never reused.
Sequence defaults similarly preserve their original literal-to-stable-sequence
binding across sequence/namespace renames and restart, rather than resolving a
stored literal anew against changed names. Runtime validates that each binding
corresponds to an admitted constant sequence call and known sequence.

Kit construction tests own identity, valid/malformed metadata, missing/colliding
references and high-water boundaries. Framework owns codec persistence,
transactional publication, restart, lexical binding, wildcard stability, actual
index maintenance, read-only rejection and MV population behavior.
