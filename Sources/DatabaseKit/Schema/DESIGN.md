# Schema

## Purpose and Scope

Schema owns validated database declaration catalogs and their identity/evolution
contracts inside [DatabaseKit](../DESIGN.md). Children: none. This document
fixes S01 field query-metadata admission only; existing unrelated catalog
features retain their contracts.

## Responsibilities and Boundaries

Schema owns FieldSchema's declaration, Schema.Entity validation, canonical
fingerprint meaning and schema evolution classification. Model owns concrete
Swift conversion, Query owns query types/values and rich envelopes, Wire owns
canonical binary representation, Framework owns runtime schema execution.
Schema does not infer SQL meaning from persisted object or byte payloads.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [DatabaseKit](../DESIGN.md) | parent | declaration-only module | Composes Schema with its sibling semantic owners. | No mutable runtime catalog. |
| [Model](../Model/DESIGN.md) | coordinates with | declared Field.queryType and static adaptation | Supplies field declarations from statically known model types. | Instance contents do not choose the schema. |
| [Query](../Query/DESIGN.md) | depends on | QueryColumnType | Supplies query type descriptors. | Preserve SPARQL/primitive type meaning. |
| [SQL](../Query/SQL/DESIGN.md) | depends on | declared rich envelope validation | Validates query-specific defaults and field types. | A matching primitive storage kind is insufficient. |
| [DatabaseWire](../../DatabaseWire/DESIGN.md) | used by | SchemaManifest and canonical schema bytes | Carries complete schema metadata and fingerprint input. | Do not add optional old-layout decode fallback. |
| [DatabaseKitMacros](../../DatabaseKitMacros/DESIGN.md) | used by | generated field declaration metadata | Emits declarations consumed by the same manual validation path. | Generated and manual schemas must agree. |

## Architecture

```text
generated or manual FieldSchema
  → Schema.Entity validation
      → immutable field lookup/catalog
          → canonical SchemaManifest bytes → SchemaFingerprint
          → SchemaEvolution comparison
          → Framework admitted runtime schema
```

## Contracts and Invariants

Current [FieldSchema](FieldSchema.swift) records primitive type, optional/array
shape and FieldValue default. [Schema.Entity](Schema.swift) validates defaults
and dynamic Directory components. [SchemaEvolution](SchemaEvolution.swift)'s
storage-shape comparison currently checks type/optional/array;
[SchemaFingerprint](SchemaFingerprint.swift) hashes supplied canonical schema
bytes. These facts describe the current implementation, not new test evidence.

S01 contract:

- Add immutable `FieldSchema.queryType: QueryColumnType?` with nil initializer
  default. Nil preserves the existing primitive field interpretation; explicit
  metadata selects declared query adaptation. Include it in equality/hash.
- Schema.Entity validates queryType together with primitive storage kind,
  optional/array shape and default. Rich wrappers require the SQL-owned
  declared envelope shape. Matching `.object` alone cannot admit a malformed
  payload or a mismatched descriptor.
- Explicit rich SQL wrappers have scalar `.object` storage and `isArray ==
  false`, including the statically typed SQL array wrapper. Ordinary Swift
  primitive arrays retain their primitive representation. Reject an ordinary
  isArray field carrying a rich scalar wrapper descriptor; use the typed SQL
  array declaration rather than expose envelope arrays.
- Optional rich fields accept outer primitive NULL as their missing/default
  representation. Nonoptional NULL and malformed rich defaults fail at schema
  construction; literal JSON null is validated as a JSON value.
- queryType is part of the complete canonical schema declaration and therefore
  SchemaManifest encoding and fingerprint input. Two identical primitive
  storage kinds with different queryType produce different schema identity.
- SchemaEvolution's storage-shape comparison includes queryType; adding,
  removing or replacing a descriptor is changedFieldEncoding, requiring an
  explicit migration. It is never an append-only or read-time inference.
- Dynamic Directory components reject rich query descriptors even where an
  underlying scalar could have been accepted. Ordinary primitive indexes also
  reject rich descriptors until their owning SQL index contract is implemented.
  Existing unwrapped ExactDecimal primitive behavior remains unchanged.

## Runtime Flows

Manual and macro-generated declarations use the same intrinsic admission.
Framework validates the stored manifest and compiled field declaration before
choosing query adaptation. DDL, schema generation publication and backfill are
runtime-owned; S01 adds no schema-changing SQL capability.

## State, Ownership, and Lifecycle

Schema instances own immutable validated collections and lookup maps. They hold
no engine, transaction, generation lease, runtime model registry or credentials.
Fingerprint bytes follow primitive retained-owner semantics.

## Failure, Concurrency, and Constraints

Invalid descriptor/storage/default combinations are SchemaEntityError failures
with the field identity and typed query adaptation cause. Unknown descriptors
or corrupt manifests are explicit failures at the relevant codec boundary.
Stable query defaults consume Model's
[closed construction failure](../Model/DESIGN.md#stable-query-defaults).
QueryValueError retains invalidQueryField; nested TimeSpanError is carried by
invalidFieldDefaultConstruction(fieldName:cause:). Model reconstruction retains
the same exact cause rather than converting it into a missing/default success.
Schema validation applies checked structural limits and has the same immutable
Sendable contract across targets.

## Verification and Change Impact

[SchemaValidationTests](../../../Tests/DatabaseKitTests/Model/SchemaValidationTests.swift),
[SchemaEvolutionTests](../../../Tests/DatabaseKitTests/Model/SchemaEvolutionTests.swift)
and [Directory field tests](../../../Tests/DatabaseKitTests/Model/FieldSchemaTypeDirectoryComponentTests.swift)
own schema success/failure and migration classification. Expand them for
[S01-C09/C13](../Query/SQL/DESIGN.md#s01-falsifiable-case-ids): metadata in manual
and generated schemas, rich defaults/NULL, mismatched envelope rejection,
descriptor fingerprint/evolution change, Directory/index rejection and
unchanged primitive interpretation. Wire tests own exact SchemaManifest
round-trip/malformed bytes. The workspace progress record owns runtime evidence.

Changes propagate to Model Field metadata/conformances, macro generation,
canonical Wire schema bytes/fingerprint tests and Framework catalog adaptation;
they do not change primitive FieldValue representation.
