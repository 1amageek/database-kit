# database-kit Responsibility Specification

## Status

This document is the normative ownership and module-boundary specification for
`database-kit`.

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

The following historical products are removed:

| Historical product | Disposition |
|---|---|
| `DatabaseValue` | Removed; primitives are owned by `DatabaseTypes` |
| `DatabaseValueCodable` | Removed; Codable is not a canonical database contract |
| `Core` | Folded into `DatabaseKit` |
| `QueryIR` | Folded into `DatabaseKit` |
| `QueryIRFoundation` | Removed |
| `Relationship` | Folded into `DatabaseKit` |
| `Vector` | Folded into `DatabaseKit` |
| `FullText` | Folded into `DatabaseKit` |
| `Geospatial` | Folded into `DatabaseKit` |
| `Rank` | Folded into `DatabaseKit` |
| `Permuted` | Folded into `DatabaseKit` |
| `Graph` | Folded into `DatabaseKit` |
| `DatabaseDigest` | Folded into the internal implementation of `DatabaseWire` |
| feature-specific macro products | Folded into one compiler-plugin target |

No compatibility re-export modules remain.

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
│   ├── Mutation/
│   ├── Relationship/
│   ├── Index/
│   │   ├── Scalar/
│   │   ├── Aggregate/
│   │   ├── FullText/
│   │   ├── Vector/
│   │   ├── Geospatial/
│   │   ├── Rank/
│   │   └── Permuted/
│   └── Graph/
│       ├── RDF/
│       ├── SPARQL/
│       ├── Ontology/
│       └── SHACL/
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

Foundation scalar conversion is owned by the existing
`DatabaseTypesFoundation` product in `database-types`:

| User-facing type | Canonical primitive |
|---|---|
| `Date` | `Timestamp` |
| `Data` | `ByteString` |
| Foundation `UUID` | `DatabaseTypes.UUID` |
| Foundation `Decimal` | `ExactDecimal` |
| `DateComponents` representing a date amount | `CalendarPeriod` |

These conversions are explicit. `database-kit` does not define a Foundation
adapter product and does not use Codable or JSON as an implicit persistence or
wire path.

Macro-generated adaptation for a platform type may use an explicit conversion
that is visible in the consuming application target. Such generated code must
not cause `DatabaseTypesFoundation` to enter the dependency graph of
`DatabaseKit` or `DatabaseWire`.

## Embedded Contract

The complete runtime dependency path used by an Embedded client is:

```text
database-client ──▶ DatabaseWire ──▶ DatabaseKit ──▶ DatabaseTypes
```

`DatabaseKit` and `DatabaseWire` must build with Swift 6.4 Embedded WASM.

The Embedded path must not contain:

- Foundation or FoundationEssentials;
- Codable-based model reconstruction;
- protocol existential storage;
- URLSession or JavaScriptKit;
- database execution or storage backends;
- mutable global registration.

## Wire Version 1

There is exactly one protocol version and one canonical representation.
Version negotiation and legacy envelopes do not exist.

Every operation statically binds:

1. an operation identifier;
2. a request type;
3. a response type;
4. an encoder;
5. a decoder.

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
3. `DatabaseKit` and `DatabaseWire` contain no Foundation, Codable, transport,
   runtime, or storage dependency.
4. `DatabaseWire` contains no duplicate query, schema, graph, or primitive
   semantic model.
5. Feature names remain only as source organization or domain declaration
   names, not public module boundaries.
6. The compiler macros are provided by one non-library compiler-plugin target.
7. All existing callers are migrated in the same change.
8. Obsolete products, targets, source paths, tests, aliases, and re-export
   shims are removed.
9. macOS tests validate actual success and failure behavior.
10. Swift 6.4 Embedded builds validate the complete client dependency graph.
