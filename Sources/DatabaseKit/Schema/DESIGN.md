# Schema

## Purpose and Scope

Schema owns validated database declaration catalogs and their identity/evolution
contracts inside [DatabaseKit](../DESIGN.md). Children: none. This document
fixes S01/S06 field query-metadata admission; existing unrelated catalog
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

### S06 declared temporal storage

The [Query authority](../Query/DESIGN.md) owns temporal value identity and pure
declared-value validation; [Model](../Model/DESIGN.md#s06-temporal-model-adaptation)
fixes the exact temporal persistence productions. Schema owns
which FieldSchema combinations admit those productions. The explicit
queryType is authoritative; an object shape without that declaration never
acquires temporal meaning.

| Declared SQL family | Admitted scalar FieldSchemaType | Payload admission |
|---|---|---|
| DATE | `.date` | Existing finite primitive date or the Query-owned date-infinity production |
| TIME WITHOUT TIME ZONE | `.time` | Existing primitive time or the distinct full-range SQL TIME production |
| TIMESTAMP WITHOUT TIME ZONE | `.dateTime` | Existing finite primitive dateTime or the matching timestamp-infinity production |
| TIMESTAMP WITH TIME ZONE | `.timestamp` | Existing finite primitive timestamp or the matching timestamp-infinity production |
| TIME WITH TIME ZONE | `.object` | The Query-owned offset-preserving SQL TIMETZ production |
| INTERVAL, including admitted modifiers | `.object` | Existing finite interval production or interval infinity |

All rows require `isArray == false`. The existing SQL array wrapper uses scalar
object storage with its explicit element type; ordinary primitive arrays keep
their existing shape and do not become temporal envelope arrays.

For a declared field, Schema validates the descriptor/storage combination and
then validates a non-NULL default through QueryFieldStorageAdapter. That
successful declared validation is the physical payload authority: a later
primitive-case-only check must not reject an admitted temporal extension.
Fields with nil queryType continue to use the existing primitive-only gate.
Nonoptional NULL, unknown or extra envelope members, invalid sign/offset/time,
wrong temporal family and invalid precision fail schema construction. There
is no permissive shape inference or fallback decode.

This union preserves all existing finite primitive payloads, field kinds and
unmodified descriptor bytes. New SQL TIME values retain their envelope for the
whole carrier range, including values below 24:00, so encoding does not erase
their structural distinction from primitive TIME. No all-finite object layout
migration is performed. Descriptor modifiers remain schema identity and an
actual descriptor change retains changedFieldEncoding migration semantics.

Temporal storage recognition is distinct from index/Directory capability.
Existing DATE/TIME/TIMESTAMP declarations retain their prior admitted
capabilities. Framework owns total, injective, descriptor-aware Directory
encoding/decoding and ordered index keys for their newly admitted extension
values, while preserving existing finite key bytes. It must not pass extension
objects through a generic object tuple ordering or reject an admitted Directory
value only at runtime. Index key projection never rewrites the original stored
or included/covering payload. The newly admitted object-backed TIMETZ family
may retain rich-descriptor index/Directory rejection until its owning index
contract admits it; this removes no existing capability. Existing interval and
other rich-family capability gates remain unchanged.

SQL temporal range and precision checks belong to Query's declared admission;
rounding, timezone/calendar evaluation and operation clocks belong to
Framework. Schema admits completed, representable values and never invokes
those runtime services during declaration validation.

## Runtime Flows

S08 consumes the [SQL result-only composite contract](../Query/SQL/DESIGN.md#s08-frozen-composite-values-and-ownership).
Schema field/default admission rejects direct or nested composite descriptors
before schema publication, preserving invalidPersistenceDescriptor through
the existing typed field error. Descriptive result metadata and Wire/JSON
carriage are not permission to persist the type. The schema validation tests
own explicit direct/array/nested rejection and unchanged finite scalar/rich
field admission.

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

S06 adds manual/generated temporal descriptor and default cases covering every
union alternative, both infinity signs and timestamp zone declarations; wrong
physical kind, malformed extensions and nonoptional NULL must fail. Compare
existing finite manifests/fingerprints and capability declarations without
changes; explicit interval modifiers must differ in identity and evolution.
Framework-owned golden and behavioral tests prove unchanged finite keys,
extension ordering, total Directory round trips, and original covering payload
retention. Codec and ordinary/Embedded runtime tests separately prove bounded
lossless carriage. These are required proof subjects, not executed results.

Changes propagate to Model Field metadata/conformances, macro generation,
canonical Wire schema bytes/fingerprint tests and Framework catalog adaptation;
they do not change primitive FieldValue representation.
