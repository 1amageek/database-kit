# SQL DDL Declarations

## Purpose and Scope

Parent: [SQL](../DESIGN.md). Children: none. This component owns the immutable,
name-based D01–D04/D09–D11 statement algebra and the D05–D08/D12 syntax that
selects existing constraint, generation and sequence semantics. The task owner froze these S15 interfaces before implementation; this contract
is not execution evidence.

## Responsibilities and Boundaries

DDL represents user intent before catalog binding. It contains names and SQL
types, expressions and SELECT bodies, never allocated catalog IDs, field
numbers, physical entities, runtime handles or authority. Framework resolves
names, assigns durable identity and performs all transactional effects. Existing
resolved SQLCatalog constraints are not unresolved syntax payloads.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [SQL](../DESIGN.md) | parent | D01–D12 profile | Owns observable SQL meaning and sprint scope. | SET CONSTRAINTS syntax remains S16. |
| [Query](../../DESIGN.md) | depends on | QueryStatement, Expression, SelectQuery and bounded traversal | DDL is one statement case. | All embedded children share the enclosing ledger. |
| [SQLCatalog](../../../Schema/SQLCatalog/DESIGN.md) | coordinates with | Resolved constraints and stable IDs | Runtime produces admitted catalog declarations. | Input names are not catalog IDs. |
| [QueryAST](../../../../../../database-framework/Sources/QueryAST/DESIGN.md) | used by | Parser and canonical serializer | Adapts SQL text to this algebra. | Parsed support does not establish executable behavior. |
| [DatabaseEngine](../../../../../../database-framework/Sources/DatabaseEngine/DESIGN.md) | used by | Transactional catalog and physical execution | Resolves and executes declarations. | Statement results publish only after authoritative close. |
| [DatabaseWire](../../../../DatabaseWire/DESIGN.md) | used by | Closed bounded statement carriage | Carries DDL through existing statement operations. | No new operation or protocol version. |

## Architecture

```text
QueryStatement.ddl(SQLDDLStatement)
    -> name-based table / constraint / index / view / sequence declarations
        -> Expression, SelectQuery, DataType, TableRef, SortKey
            -> shared iterative identity / admission / parameter traversal
                -> Framework binding -> stable SQLCatalog declarations
```

## Contracts and Invariants

Every declaration is immutable, Sendable, Equatable and Hashable on every
target. Names use exact UTF-8 identity. Constructors preserve intent; the
structural validator rejects malformed intrinsic shape before execution or
Wire publication. Runtime owns catalog-dependent validation, volatility,
authorization, dependencies, existing-data conversion and constraint checks.

| Public owner | State or alternatives |
|---|---|
| `QueryStatement` | Adds `ddl(SQLDDLStatement)`. Existing `SQLBlockStep.statement` carries it. |
| `SQLCommandKind` | Adds `createSchema`, `alterSchema`, `dropSchema`, `createTable`, `alterTable`, `dropTable`, `createIndex`, `dropIndex`, `createView`, `dropView`, `createMaterializedView`, `refreshMaterializedView`, `dropMaterializedView`; sequence cases already exist. All report no affected rows. |
| `SQLDropBehavior` | `restrict`, `cascade`. |
| `SQLDDLStatement` | `createSchema(name:ifNotExists:)`, `renameSchema(name:to:)`, `dropSchema(names:ifExists:behavior:)`; `createTable(SQLCreateTable)`, `alterTable(SQLAlterTable)`, `dropTable(names:ifExists:behavior:)`; `createIndex(SQLCreateIndex)`, `dropIndex(names:ifExists:behavior:)`; `createView(SQLCreateView)`, `dropView(names:ifExists:behavior:)`; `createMaterializedView(SQLCreateMaterializedView)`, `refreshMaterializedView(name:withData:)`, `dropMaterializedView(names:ifExists:behavior:)`; `createSequence(SQLCreateSequence)`, `alterSequence(SQLAlterSequence)`, `dropSequence(names:ifExists:behavior:)`. Qualified object names are `TableRef`. |
| `SQLCreateTable` | `name: TableRef`, `source: SQLTableDefinition`, `temporary: Bool`, `ifNotExists: Bool`; Boolean defaults false. |
| `SQLTableDefinition` | `columns([SQLColumnDefinition], constraints: [SQLTableConstraint])`, `query(SelectQuery, columns: [String]?, withData: Bool)`. Nil CTAS names means inferred output names. |
| `SQLColumnDefinition` | `name: String`, `type: DataType`, `policy: SQLColumnDefinitionPolicy`, `constraints: [SQLTableConstraint]`; default input policy and empty constraints. |
| `SQLColumnDefinitionPolicy` | `input(defaultExpression: Expression?)`, `generated(Expression, stored: Bool)`, `identity(generation: SQLIdentityGeneration, options: SQLSequenceOptions)`, `serial`. SERIAL's integral type is the column's DataType. |
| `SQLTableConstraint` | `name: String?`, `timing: SQLConstraintTiming`, `kind: SQLTableConstraintKind`; nil/immediate defaults. |
| `SQLTableConstraintKind` | `primaryKey(columns: [String])`, `unique(columns: [String], nulls: SQLNullUniqueness)`, `notNull(column: String)`, `check(Expression)`, `foreignKey(SQLForeignKeyDefinition)`. |
| `SQLForeignKeyDefinition` | `columns: [String]`, `referencedTable: TableRef`, `referencedColumns: [String]?`, `match`, `onUpdate`, `onDelete`, `onDeleteColumns: [String]?`; existing FK enums and SIMPLE/NO ACTION defaults. |
| `SQLAlterTable` | `name: TableRef`, `actions: [SQLAlterTableAction]`, `ifExists: Bool` default false. Actions preserve source order. |
| `SQLAlterTableAction` | `addColumn(SQLColumnDefinition, ifNotExists: Bool)`, `dropColumn(name: String, ifExists: Bool, behavior: SQLDropBehavior)`, `renameColumn(name: String, to: String)`, `alterColumnType(name: String, type: DataType, using: Expression?)`, `setDefault(column: String, expression: Expression)`, `dropDefault(column: String)`, `setNotNull(column: String)`, `dropNotNull(column: String)`, `addConstraint(SQLTableConstraint)`, `dropConstraint(name: String, ifExists: Bool, behavior: SQLDropBehavior)`, `renameTable(to: String)`. |
| `SQLCreateIndex` | `name: TableRef`, `table: TableRef`, `keys: [SortKey]`, `predicate: Expression?`, `unique: Bool`, `nulls: SQLNullUniqueness`, `ifNotExists: Bool`; nil/false/distinct/false defaults. Existing SortKey owns expression, direction and explicit/default null order. |
| `SQLCreateView` | `name: TableRef`, `columns: [String]?`, `query: SelectQuery`, `orReplace: Bool` default false. |
| `SQLCreateMaterializedView` | `name: TableRef`, `columns: [String]?`, `query: SelectQuery`, `withData: Bool` default true, `ifNotExists: Bool` default false. |
| `SQLSequenceOptions` | Optional `type: DataType`, `start: Int64`, `increment: Int64`, `minimum: SQLSequenceBound`, `maximum: SQLSequenceBound`, `cycle: Bool`; unspecified creation options select dialect defaults and unspecified alteration options preserve current values. |
| `SQLSequenceBound` | `value(Int64)`, `none` for explicit NO MINVALUE/NO MAXVALUE. |
| `SQLSequenceOwnership` | `none`, `column(table: TableRef, column: String)`. |
| `SQLCreateSequence` | `name: TableRef`, `options: SQLSequenceOptions`, `ownedBy: SQLSequenceOwnership?`, `ifNotExists: Bool` default false. |
| `SQLAlterSequence` | `name: TableRef`, `options: SQLSequenceOptions`, `restart: SQLSequenceRestart?`, `ownedBy: SQLSequenceOwnership?`, `renameTo: String?`, `ifExists: Bool` default false. Nil ownership preserves current ownership. |
| `SQLSequenceRestart` | `start` for bare RESTART, `value(Int64)` for RESTART WITH. |

DDL targets disallow aliases and dynamic partition values. Drop lists, ALTER
actions, index keys, key/FK column lists and explicit name lists are nonempty.
Identifier lists contain no duplicate exact-byte names. Types and expression
children retain their existing intrinsic constraints. Timing rules match the
resolved constraint owner. SERIAL accepts only the three integer types.

DDL is schema definition and is never read-only or a row mutation. Command
kinds distinguish each observable DDL action and report no affected-row count.
`SQLDDLStatement.command: SQLCommandKind` maps schema rename to alterSchema
and each remaining case to its matching command. There is no distinct rename
command or hidden successful result state.
SPARQL rejects the entire DDL statement explicitly.

## State, Ownership, and Lifecycle

Declarations own immutable Swift values. There is no platform-specific state,
registration, resource lease or shutdown. Temporary-table lifetime belongs to
Framework's one SQL block and never enters a durable catalog generation.

## Failure, Concurrency, and Constraints

All embedded expressions, types, query bodies, names and collections share the
existing iterative QueryStructuralResourceLedger. Count and retained-byte
admission precede growth. Width uses retained indexed cursors; nesting uses
explicit continuations. Parameter admission and reconstruction preserve every
child without resetting limits or recursively walking statement/query cycles.

Distinct occurrence roles identify DDL target, column definition, default,
generated expression, constraint/check, ALTER action/USING, index key/predicate
and stored SELECT body. Equal repeated children retain distinct source paths.
Shape failures are typed `invalidSQLDDL`; invalid sequence increment, bound,
start or type values are typed `invalidSQLSequenceOptions`; resource errors
retain their existing categories. No unsupported declaration becomes synthetic successful execution.

## Verification and Change Impact

Kit tests own complete metadata preservation, exact-byte equality/hash,
parameter discovery/substitution, explicit SPARQL rejection and typed invalid
shape/exact-one-past limits. Tests include CTAS/view/MV nested SELECT bodies,
default/generated/CHECK/USING/index expressions and deep mixed query paths.
Wire tests own binary round trips and malformed layouts; Framework owns real
effects, rename stability, rollback, restart, dependencies and publication.
Changes require reviewing QueryAST, Wire and Framework direct consumers.
