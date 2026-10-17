# SQL Catalog Declarations

## Purpose and Scope

SQLCatalog is a child of [Schema](../DESIGN.md) and owns immutable logical SQL
namespace, relation, column, key and search-path declarations. It has no child
components. S11 introduces these values without changing `Schema`,
`SchemaManifest`, wire bytes, JSON schema layout or primitive field values.

## Responsibilities and Boundaries

This component owns intrinsic declaration validation and exact identifier
identity. Framework owns persisted catalog generations, transactional storage,
physical-schema validation, name resolution, authorization, metadata budgets,
static-model protection and restart admission. A key declaration does not
enforce uniqueness; S13 owns constraint execution. S14 owns SQL writes and S15
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
| `SQLColumn` | `id: String`, `name: String`, `fieldNumber: Int`; throwing `init(id:name:fieldNumber:)` |
| `SQLRelation` | `id: String`, `namespaceID: String`, `name: String`, `entityName: String`, `columns: [SQLColumn]`, `primaryKeyColumnIDs: [String]?`; throwing initializer with nil primary-key default |
| `SQLCatalog` | `namespaces: [SQLNamespace]`, `relations: [SQLRelation]`; throwing `init(namespaces:relations:)` |
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
that the exact physical entity and field number exist and derives SQL types
and nullability from the physical `FieldSchema`; these checks do not belong
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
