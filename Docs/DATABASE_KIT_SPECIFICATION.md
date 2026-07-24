# database-kit Version 1 Specification

## Status

This document is the normative responsibility, public-contract, naming,
ownership, and module-boundary specification for `database-kit`.

The implementation, package manifest, tests, and public documentation must
conform to this document. Existing source placement and existing product names
are not evidence of correct ownership.

This is the first protocol release. Backward compatibility, compatibility
aliases, deprecated duplicate paths, and versioned replacement names are not
part of the design.

## Package Responsibility

`database-kit` owns the Foundation-independent database semantic contract above
the primitive values provided by `database-types`.

It defines:

- persisted model and document metadata;
- logical identity;
- schema and migration declarations;
- relationship declarations;
- index declarations;
- graph, RDF, ontology, and SHACL declarations;
- query and mutation language models;
- operation request and response models;
- the canonical bounded binary representation of those operations;
- compiler macros that generate static conformance to these contracts.

It does not execute those declarations.

The package does not own:

- primitive field-value representation;
- client invocation, transport, retry, timeout, or correlation;
- transaction coordination, query execution, or index maintenance;
- storage transactions or storage backends;
- runtime composition;
- application-specific schemas;
- Foundation scalar representation or implicit platform conversion policy.

## Responsibility Decomposition

The package contains two public responsibilities. They are separate products
because semantic declarations and their transfer representation have different
reasons to change.

| Product | Owns | Changes when |
|---|---|---|
| `DatabaseKit` | Persisted model and document meaning, identity, schema, query, mutation, relationship, index, graph, ontology, and SHACL declarations | Database semantics or their static declaration contracts change |
| `DatabaseWire` | The canonical version 1 binary representation of database operations | The version 1 frame, operation, bound, or protocol-error contract changes |

The package name is not a semantic namespace. A declaration belongs here only
when its represented concept belongs to one of the responsibilities above.
Sharing a declaration between a client and runtime does not create a third
"shared" responsibility.

## Ownership Model

Ownership is determined by what a declaration represents and why it changes.
The number of consumers, portability, or passage across a process boundary does
not determine ownership.

```text
database-client ───────▶ DatabaseWire ───────▶ DatabaseKit ───────▶ DatabaseTypes
                               ▲                    ▲
                               │                    │
database-framework ────────────┴────────────────────┘
```

Arrows point from a consumer to the contract it depends on.

### Primitive ownership

`DatabaseTypes` owns only primitive value representation and intrinsic
invariants.

This includes:

- `FieldValue`;
- `FieldObject`;
- `ByteString` and bounded byte views;
- exact numeric, temporal, UUID, vector, geographic, reference, and RDF term
  primitives that are alternatives of `FieldValue`.

`database-kit` must not redeclare, wrap, alias, or rename those primitive
values. In particular, there is no `DatabaseValue` type or product.

### Semantic ownership

`DatabaseKit` owns declarations that describe database meaning without
executing it.

This includes:

| Semantic area | Owned declarations |
|---|---|
| Model and document | persistence contracts, field metadata, model adaptation contracts |
| Identity | persisted identifiers, logical references, identity validation |
| Schema | schema catalog, versions, constraints, migration declarations |
| Query | SQL, SQL/PGQ, graph-pattern, and SPARQL intermediate representations |
| Mutation | mutation statements, preconditions, and transaction intent |
| Relationship | cardinality, relationship descriptors, and delete rules |
| Index | scalar, aggregate, text, vector, geographic, rank, permutation, graph, and RDF index declarations |
| Graph | RDF dataset meaning, graph names, ontology declarations, and SHACL shapes |
| Validation | intrinsic structural and semantic validation of declarations |

### Model and document adaptation

`Persistable` is the single application-model contract. It applies equally to
structured entities and document-shaped models; the API does not use `Record`
as the universal database noun.

Model adaptation has three distinct values:

```text
application model
      │ generated static field adaptation
      ▼
PersistableField + FieldValue
      │ DatabaseWire representation
      ▼
operation frame
```

| Value | Owner | Meaning |
|---|---|---|
| application model | Application | The user's Swift type and chosen Swift property types |
| `PersistableField` | `DatabaseKit` | Stable field identity plus one canonical primitive value |
| `FieldValue` / `FieldObject` | `DatabaseTypes` | Closed primitive value algebra |

The adaptation contract is:

- `@Persistable` generates concrete, statically typed field adaptation.
- Encoding preserves the declared primitive width and semantic case.
- Decoding validates field number, field name, requiredness, declared type, and
  nested structure before constructing the model.
- Unknown, duplicate, missing, or mismatched fields produce a typed failure.
- Nested application models become `FieldObject`; there is no parallel
  object-field DTO.
- Application identity becomes the canonical `ReferenceIdentifier` and
  `EntityReference` primitives through the `PersistableIdentifier` and
  `PersistableReference` contracts.
- The application declares identifiers and owns identifier generation policy.
  A macro does not read a clock or generate randomness implicitly.
- Canonical adaptation does not require `Codable` or JSON. Native-only
  applications may conform the same model to `Codable` for their own external
  formats, but that conformance is independent of database persistence.
- Canonical adaptation does not use reflection, string-based runtime type
  recovery, or a mutable global registry.

The public adaptation vocabulary is based on persistence and field
representation: `Persistable`, `PersistableField`, `PersistableIdentifier`,
`PersistableReference`, and field-value conversion requirements. Generic names
such as `DatabaseModel` and `DatabaseCodable` are not part of the API.
`Codable` previously formed a workable persistence boundary while the
supported runtime was native-only. It is no longer the canonical dependency
because the version 1 product must expose the same persistence contract to
Swift Embedded.

`Encoder` and `Decoder` are used only for a directional transformation with a
defined input, output, and typed failure. A public catch-all `Codec` abstraction
is not part of the model-adaptation API.

Relationship, vector, full-text, geographic, rank, permutation, graph,
ontology, and SHACL are capabilities within the same semantic responsibility.
They are source-directory classifications, not public module boundaries.

### Wire ownership

`DatabaseWire` owns the canonical representation used to transfer operations
across process, WASM, and network boundaries.

It owns:

- protocol version 1 framing;
- operation identifiers;
- request and response envelopes;
- request identifiers, trace metadata, and idempotency metadata;
- bounded binary readers and writers;
- operation-to-request-and-response type binding;
- protocol error representation;
- canonical operation golden vectors;
- digest implementation used only to establish canonical protocol values.

It does not own:

- query, schema, graph, relationship, or mutation meaning;
- operation execution;
- transport;
- authentication policy;
- storage encoding;
- JSON or Codable serialization.

Wire-specific encoding of a semantic value is owned by `DatabaseWire`.
Validation or normalization intrinsic to the semantic value remains owned by
`DatabaseKit`.

The public Wire vocabulary follows the operation contract already exposed to
the client and runtime:

```swift
public protocol DatabaseOperation {
    associatedtype Request
    associatedtype Response

    static var identifier: DatabaseOperationIdentifier { get }
    static func encode(
        _ request: Request,
        into encoder: inout DatabaseWireEncoder
    ) throws(DatabaseWireError)
    static func decode(
        from decoder: inout DatabaseWireDecoder
    ) throws(DatabaseWireError) -> Response
}
```

The exact signatures may use operation-bound request and response protocols,
but they must preserve all four static bindings: identifier, request, response,
and canonical binary representation. A generic public `Codec` that permits an
unbound request/response combination is not allowed.

### Macro ownership

Compiler macros are an implementation boundary, not a user-facing capability
module.

One compiler-plugin target owns generation for model, schema, identity,
relationship, index, ontology, and SHACL declarations. Macro declarations are
published by `DatabaseKit`; the compiler-plugin target is not a library
product.

Generated code must depend on public semantic contracts. It must not introduce
a second DTO, implicit string-based schema, global registry, or runtime
execution behavior.

## Public Product Surface

`database-kit` publishes two library products:

| Product | Responsibility |
|---|---|
| `DatabaseKit` | Foundation-independent database semantic declarations |
| `DatabaseWire` | Canonical bounded binary operation representation |

The compiler-plugin target is an implementation dependency of `DatabaseKit`
and is not a public library product.

No primitive, feature, Codable-only, digest, Foundation, compatibility, or
re-export product is published. In particular:

- there is no `DatabaseValue`; the canonical type is
  `DatabaseTypes.FieldValue`;
- there is no `DatabaseObjectField`; an object is
  `DatabaseTypes.FieldObject`;
- there is no `DatabaseModel` or `DatabaseCodable`; application models conform
  to `Persistable`;
- relationship, vector, full-text, geographic, rank, permutation, graph,
  ontology, and SHACL declarations remain in `DatabaseKit`;
- digest implementation used by canonical Wire values is internal to
  `DatabaseWire`.

## Source Organization

Source directories express navigation and code ownership within a module. They
do not create feature modules.

```text
Sources/
├── DatabaseKit/
│   ├── Model/
│   ├── Identity/
│   ├── Schema/
│   ├── Query/
│   ├── Relationship/
│   ├── Security/
│   ├── Index/
│   │   ├── Scalar/
│   │   ├── Aggregate/
│   │   ├── FullText/
│   │   ├── Vector/
│   │   ├── Geospatial/
│   │   ├── Rank/
│   │   └── Permuted/
│   ├── Graph/
│       ├── RDF/
│       ├── SPARQL/
│       ├── Ontology/
│       └── SHACL/
│   └── Support/
│       └── package-internal platform-neutral utilities
├── DatabaseWire/
│   ├── Operation/
│   ├── Encoding/
│   ├── Decoding/
│   └── Digest/
└── DatabaseKitMacros/
```

## Foundation Boundary

`DatabaseKit` and `DatabaseWire` must not import Foundation,
FoundationEssentials, `DatabaseTypesFoundation`, URLSession, JavaScriptKit, or
platform runtime APIs.

Foundation scalar conversion is owned by the
`DatabaseTypesFoundation` product in `database-types`:

| User-facing type | Canonical primitive |
|---|---|
| `Date` | `Timestamp` |
| `Data` | `ByteString` |
| Foundation `UUID` | `DatabaseTypes.UUID` |
| Foundation `Decimal` | `ExactDecimal` |
| `DateComponents` representing a date amount | `CalendarPeriod` |

`DatabaseTypesFoundation` is not a database model adapter and does not know
about `Persistable`, schemas, fields, or DatabaseWire. It only defines explicit
scalar conversion in both directions.

There is no object named `FoundationAdapter` and no `database-kit` Foundation
product. A native application that declares Foundation property types imports
`DatabaseTypesFoundation`. `@Persistable`-generated concrete adaptation invokes
those visible scalar conversions at the application compilation boundary:

```text
native application target
  ├── Foundation property type
  ├── DatabaseTypesFoundation scalar conversion
  └── generated Persistable field adaptation
              │
              ▼
      canonical DatabaseTypes primitive
```

This does not add Foundation to `DatabaseKit`, `DatabaseWire`, or an Embedded
client dependency graph.

The persistence boundary is selected from the deployment requirement:

| Use | Contract |
|---|---|
| Persistence shared by Native and Embedded | Static `Persistable` field adaptation through `FieldValue` |
| Canonical DatabaseWire transfer | Bounded binary DatabaseWire representation |
| Application-owned JSON or property-list input/output | Optional `Codable` conformance outside the canonical database path |

`Codable` is therefore not treated as defective or forbidden in an
application. It is not a prerequisite of the canonical database contract
because that would make the Embedded product depend on a capability that is
unavailable there.

The conversions are deterministic:

- `Date` maps only to `Timestamp`, using the nearest representable nanosecond
  with ties rounded to even.
- `Data` maps to `ByteString` and retains immutable storage when the source API
  permits retained borrowing.
- Foundation `UUID` maps exactly to the canonical 16-byte UUID.
- Foundation `Decimal` maps exactly to `ExactDecimal` or fails.
- `DateComponents` maps to `CalendarPeriod` only when it represents a supported
  calendar amount without discarded components.

`Date` never implicitly becomes `CivilDate`, `CivilTime`, or
`CivilDateTime`. Those types remain first-class primitives for SQL
`DATE`, `TIME`, and local date-time semantics and are selected explicitly by
the application.

## Embedded Contract

The complete runtime dependency path used by an Embedded client is:

```text
database-client ──▶ DatabaseWire ──▶ DatabaseKit ──▶ DatabaseTypes
```

`DatabaseKit` and `DatabaseWire` must build with Swift 6.4 Embedded WASM.

This Embedded requirement is the reason the canonical path does not depend on
`Codable`. A Native-only product could validly choose `Codable`; this product
cannot make it the shared persistence or protocol requirement while exposing
the same contract on Embedded WASM.

The Embedded path must not contain:

- Foundation or FoundationEssentials;
- Codable-based model reconstruction;
- protocol existential storage;
- URLSession or JavaScriptKit;
- database execution or storage backends;
- mutable global registration.

All failures reachable on the Embedded path use typed throws. Public APIs on
that path must not store protocol existential values. Heterogeneous semantic
declarations use a closed, validated representation or compile-time generic
composition; an existential array is not an acceptable registry.

## Wire Version 1

There is exactly one protocol version and one canonical representation.
Version negotiation and legacy envelopes do not exist.

Every operation statically binds:

1. an operation identifier;
2. a request type;
3. a response type;
4. an encoder;
5. a decoder.

`DatabaseWireEncoder` and `DatabaseWireDecoder` are directional protocol
boundaries. A type named `Codec` must not be used as a public umbrella for both
directions.

The operation families are:

1. `capabilities.describe`
2. `schema.describe`
3. `query.execute`
4. `mutation.execute`
5. `graph.algorithm`
6. `ontology.execute`
7. `shacl.execute`
8. `command.execute`
9. `maintenance.execute`
10. `job.start`
11. `job.status`
12. `job.result`
13. `job.cancel`

Decoding must deterministically reject:

- truncated frames;
- unknown versions;
- unknown operations;
- invalid tags;
- invalid semantic values;
- trailing bytes;
- excessive frame size;
- excessive string or byte length;
- excessive collection count;
- excessive object count;
- excessive nesting depth.

## Data and Ownership Contract

Large binary paths use one owned `ByteString` and bounded borrowed views.

- Readers borrow ranges from the input frame.
- Writers measure exact output and allocate the final frame once.
- A borrowed pointer never escapes its closure.
- A borrowed view does not outlive its owner.
- `Array`, `Data`, and `String` materialization occurs only at an explicit
  ownership or external API boundary.
- Required copies are documented at the implementation site.
- Zero-copy claims require allocation, copy-count, or benchmark evidence.

The ownership path for an encoded request or response is:

```text
measure exact size
      │
      ▼
one owned ByteString allocation
      │
      ├── writer fills final storage
      └── readers and payload pages borrow bounded ranges
```

An encoder must not build an intermediate `[UInt8]` and then copy it into a
`ByteString`. A decoder must not detach a frame or payload merely to advance a
cursor. A copy is permitted only when ownership must cross an API boundary that
cannot retain the original owner, and that site documents the reason.

## Error Contract

Malformed or unsupported input never becomes a default value, empty result,
partial success, trap, or silent fallback.

Errors distinguish:

- transport;
- malformed or non-canonical input;
- resource limits;
- unsupported operation;
- authorization;
- precondition and conflict;
- retryable server failure;
- non-retryable server failure.

Errors crossing DatabaseWire carry a stable category, code, retryability, and
bounded details.

Every public throwing API reachable from `DatabaseKit` or `DatabaseWire`
declares its concrete error type. Macro-generated code preserves that error
type. It does not widen a field, schema, query, or Wire failure to untyped
`any Error`.

## Naming Contract

Names describe database responsibility, observable behavior, ownership, or
lifetime. They do not describe the implementation language, ABI, calling
convention, module identity, binary layout, or toolchain.

The `Database` prefix is not automatically valid merely because this is a
database package. It is retained only when removing it would change the
semantic noun:

| Contract | Canonical naming decision |
|---|---|
| Primitive field value | `FieldValue`, not `DatabaseValue` |
| Primitive object | `FieldObject`, not `DatabaseObjectField` |
| Application persistence | `Persistable`, not `DatabaseModel` or `DatabaseCodable` |
| Model reference | `PersistableReference`, not a module-prefixed generic reference |
| Database operation binding | `DatabaseOperation`; “database operation” is the represented protocol concept |
| Canonical protocol encoder/decoder | `DatabaseWireEncoder` / `DatabaseWireDecoder`; DatabaseWire is the selected external protocol |

Callbacks are named for the event or state transition they handle. Fixed
external spellings stay in attributes, imports, exports, or protocol constants
and are wrapped immediately by semantic Swift declarations.

## Runtime Separation

`database-framework` consumes `DatabaseKit` declarations and executes them. It
owns:

- transaction coordination;
- query planning and execution;
- model and document persistence;
- relationship enforcement;
- index maintenance;
- graph and SPARQL execution;
- ontology and SHACL execution;
- migrations, maintenance, algorithms, and jobs.

`database-client` consumes `DatabaseKit` and `DatabaseWire`. It owns typed
invocation, correlation, cancellation, timeout, pagination facades, and
transport adapters.

Neither execution nor transport behavior is implemented in this package.

## Acceptance Conditions

The responsibility migration is complete only when all of the following hold:

1. `Package.swift` publishes only `DatabaseKit` and `DatabaseWire`.
2. No source or test imports a removed feature module.
3. `DatabaseKit` and `DatabaseWire` contain no Foundation, Codable-based
   canonical adaptation, transport, runtime, or storage dependency.
4. `DatabaseWire` contains no duplicate query, schema, graph, or primitive
   semantic model.
5. Feature names remain only as source organization or domain declaration
   names, not public module boundaries.
6. The compiler macros are provided by one non-library compiler-plugin target.
7. All existing callers are migrated in the same change.
8. Obsolete products, targets, source paths, tests, aliases, and re-export
   shims are removed.
9. No public source declaration uses `DatabaseValue`, `DatabaseObjectField`,
   `DatabaseModel`, `DatabaseCodable`, or a catch-all `Codec` API.
10. All public throwing APIs reachable from the Embedded graph use typed
    throws, and the graph stores no protocol existential values.
11. Native model adaptation tests cover Foundation `Date`, `Data`, `UUID`, and
    `Decimal` through the explicit `DatabaseTypesFoundation` conversion
    boundary.
12. macOS tests validate actual success and failure behavior.
13. Swift 6.4 Embedded builds validate the complete client dependency graph.
14. DatabaseWire golden vectors cover every operation family and are consumed
    unchanged by client and runtime tests.
