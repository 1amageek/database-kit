# Model

## Purpose and Scope

Model owns static application-model adaptation and persisted field identity
inside [DatabaseKit](../DESIGN.md). Children: none. This document fixes only the
current model boundary and S01 query-field adaptation changes; it does not
redesign unrelated metadata, graph or relationship capabilities.

## Responsibilities and Boundaries

Model owns Persistable conformance vocabulary, Field identity, typed field
input/output, explicit Swift-to-FieldValue conversion and model reconstruction.
Schema owns admitted field declarations; Query owns query values and SQL
metadata/envelopes; macros generate these contracts. Storage bytes, runtime
admission, catalog state and transaction lifetime remain outside Model.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [DatabaseKit](../DESIGN.md) | parent | static semantic module boundary | Composes model adaptation with its sibling declarations. | No runtime type registry or reflection. |
| [Schema](../Schema/DESIGN.md) | coordinates with | FieldSchema and queryType admission | Validates the declarations emitted for adapted fields. | Storage kind alone does not identify a rich field. |
| [Query](../Query/DESIGN.md) | depends on | QueryColumnType and query values | Provides the semantic metadata adapted fields may declare. | Primitive FieldValue algebra remains unchanged. |
| [SQL](../Query/SQL/DESIGN.md) | depends on | rich wrappers and QueryFieldStorageAdapter | Defines exact declared envelope conversion and footprint measurement. | No guessing rich meaning from object/byte contents. |
| [DatabaseKitMacros](../../DatabaseKitMacros/DESIGN.md) | used by | statically specialized field traversal | Generates concrete encode/decode and field metadata. | No metatype/key-path retention in runtime data. |

## Architecture

```text
Swift declared field type
  → generated Field and schema metadata → Schema admission
  → generic PersistedFieldOutput.write
      → explicit FieldValueEncodable conversion
          → primitive FieldValue / declared query envelope
  ← generic PersistedFieldInput + FieldValueDecodable
```

## Contracts and Invariants

Current [Field](Field.swift) stores stable number/name and schema metadata.
[PersistableField](PersistableField.swift) and
[PersistedFieldInput](PersistedFieldInput.swift) carry FieldValue;
[PersistedFieldOutput](PersistedFieldOutput.swift) retains the concrete Swift
type through generic write. [PersistableFieldEncoder](PersistableFieldEncoder.swift)
also supports selected-field and default conversion. These are current source
facts, not a passing execution claim.

S01 public contract:

- Add immutable `Field<Root, Value>.queryType: QueryColumnType?` with nil
  default. `Field.schema` propagates it exactly to Schema's FieldSchema.
- Add `static var queryType: QueryColumnType? { get }` to
  [FieldValueEncodable](FieldValueEncodable.swift), with nil default. Optional
  forwards Wrapped.queryType; ordinary Array forwards Element.queryType.
  Forwarding carries metadata only, not permission to admit an envelope array:
  Schema rejects isArray plus a rich descriptor. This one static conformance
  path prevents `[RichWrapper]` or `Optional<[RichWrapper]>` from losing their
  descriptor through the nil default. Existing primitive arrays keep nil
  metadata and their existing storage representation.
- QueryNumericValue, QueryJSONValue, QueryJSONBValue, QueryIntervalValue and
  QueryArray<Element> conform to existing FieldValueEncodable and
  FieldValueDecodable, using the SQL-owned QueryFieldStorageAdapter. Their
  queryType is the wrapper's SQL declaration, fieldSchemaType is `.object`,
  and Field/FieldSchema uses scalar storage. Schema owns admission of that
  combination. Semantic type is static, never derived from a row or instance.
- PersistableField.value, selected-field access, input/output protocols and
  ordinary primitive model reconstruction remain FieldValue-based. No broad
  migration of primitive fields into QueryValue is needed.
- Generated traversal, defaults, selected-field encoding and reconstruction
  use the same declared conversion. Missing field, explicit outer NULL and
  JSON null remain distinct; optional rich wrappers store outer NULL as
  primitive null.
- Conversion failures retain a typed QueryValueError cause through
  PersistableEncodingError/PersistableDecodingError. An unrepresentable rich
  value is not coerced into a primitive success or a default.

### Stable query defaults

Model owns `PersistableDefaultConstructionError`, a closed typed construction
failure with `queryValue(QueryValueError)` and `timeSpan(TimeSpanError)` cases.
The generated default builder evaluates admitted nested constructors in source
order using concrete typed closures, then passes the completed value through
the same field encoding adapter. Query failures keep the existing
SchemaEntityError.invalidQueryField and PersistableDecodingError.invalidQueryValue
mapping. A nested TimeSpan failure uses invalidFieldDefaultConstruction in both
owner errors and retains the exact union cause through missing-field decoding.
No dynamic error cast, existential error storage or runtime metadata is needed.

All five rich wrapper families admit finite value-stable constructor defaults.
Typed arrays retain the explicitly specialized element type. Nested constructors
are limited to the rich wrappers, QueryArrayDimension, QueryValueLimits,
ExactDecimal, ByteString and nonthrowing fixed-width/scalar constructors, plus
TimeSpan(seconds:nanoseconds:) and CalendarPeriod(months:days:). Unsupported
constructor overloads and arbitrary factory or nonstable initializers remain
uncaptured and require an explicit migration for an added required field.
Invalid admitted constructors fail schema construction; a property's forced try
cannot make schema capture trap or silently omit a default.

## Runtime Flows

Model conversion is pure. In a Framework path the caller first measures the
SQL-owned adapter representation and admits its destination footprint, then
invokes the existing generic conversion. User-owned model encoding performs
pure conversion without acquiring runtime authority. Typed model decoding
uses Schema's admitted descriptor and explicitly rejects ambiguous result
columns or incompatible rich values.

## State, Ownership, and Lifecycle

Field metadata is immutable value data. Generic traversal preserves static
specialization without storing metatypes, existential models or key paths.
Converted bytes retain primitive owners; no pointer escapes a synchronous
borrow. Runtime reservations and generation leases are not Model state.

## Failure, Concurrency, and Constraints

Same Sendable/type-adaptation contract applies on native/WASM/Embedded.
Construction and conversion use checked counts and preserve typed failures.
No runtime service, Foundation dependency, global registration, unchecked shared
state or unlimited conversion fallback is introduced by S01.

## Verification and Change Impact

[PersistableFieldEncoderTests](../../../Tests/DatabaseKitTests/Model/PersistableFieldEncoderTests.swift)
owns concrete traversal and selected identity behavior;
[PersistedModelTests](../../../Tests/DatabaseKitTests/Model/PersistedModelTests.swift)
owns reconstruction. Extend these with the
[SQL S01-C04–C09/C13 cases](../Query/SQL/DESIGN.md#s01-falsifiable-case-ids):
generated rich/default/optional fields round trip, selected conversion agrees,
malformed envelopes preserve typed failure, and primitive identity/bytes remain
unchanged. Macro tests verify generated Field/schema agreement. The workspace
progress record owns execution evidence for these implemented contracts.

[RichQueryStableDefaultTests](../../../Tests/DatabaseKitTests/Model/RichQueryStableDefaultTests.swift)
owns stable interval/typed-array schema defaults, missing-field reconstruction,
exact nested TimeSpan and query failure causes, and nonstable factory rejection.

Changing model query metadata propagates to Schema admission, macro generation,
Query adapters, Wire SchemaManifest and Framework catalog/model conversion.
