# Architecture and Ownership

The normative package and module-boundary contract is defined in
[database-kit Responsibility Specification](DATABASE_KIT_SPECIFICATION.md).
This document describes behavioral invariants within that ownership model.
The performance-sensitive ownership path is defined in
[Zero-Copy and Embedded Architecture](ZERO_COPY_EMBEDDED_DESIGN.md).

## Responsibility

`database-kit` owns the Foundation-independent database semantic model above
primitive values. Its public contracts describe persisted models, identity,
schema, relationships, indexes, graph and ontology declarations, queries,
mutations, and the canonical binary operation protocol.

It does not own primitive representation, transport, database execution,
transactions, storage backends, runtime assembly, or application schemas.

```text
database-client ────────┐
                       ▼
                database-kit ───────▶ database-types
                       ▲
                       │
                database-framework ─▶ storage-kit
```

The arrows point from a consumer to a dependency.

## Module Boundaries

| Module | Owns | Does not own |
|---|---|---|
| `DatabaseKit` | Foundation-independent model, identity, schema, query, mutation, relationship, index, graph, ontology, and SHACL declarations | Primitive values, Codable-based canonical persistence, execution, transport |
| `DatabaseWire` | Version 1 envelopes, typed operations, bounded binary encoding and decoding, and internal canonical digest support | Semantic meaning, network transport, or operation execution |
| `DatabaseKitFoundation` | Native Foundation scalar participation in `Persistable` field adaptation | Primitive conversion rules, Wire, transport, or Embedded behavior |
| Compiler plugin | Static generation for `DatabaseKit` contracts | Runtime behavior or a public library product |

## Primitive Boundary

`FieldValue`, `FieldObject`, `ByteString`, temporal primitives, exact decimal,
UUID, geographic values, vectors, entity references, and RDF terms are owned by
`database-types`. database-kit consumes those values without redeclaring,
wrapping, or aliasing them.

database-kit intentionally has no generic value or Codable-only product.
`Codable` remains valid for a Native application's own external formats; it is
not the canonical persistence dependency shared with Embedded Swift.
Foundation-independent persistence identity, model adaptation, query, and graph
meaning belong to `DatabaseKit`. Feature categories are source directories
inside that module rather than products.

Primitive Foundation conversions remain in `DatabaseTypesFoundation`.
`DatabaseKit` and `DatabaseWire` do not depend on that product.
`DatabaseKitFoundation` depends on those conversions and exposes their
participation in `Persistable` field adaptation to native applications.

## Performance Foundation

Zero-copy and Embedded suitability shape the APIs rather than being retrofitted
onto them:

```text
static model traversal
      │
      ├── measure exact frame
      └── write one final ByteString
                         │
                         ▼
               bounded borrowing decode
                         │
                         ▼
                 lazy bulk-result view
```

The target core path contains no reflection, existential storage, Foundation,
JavaScriptKit, or intermediate byte arrays. Independently owned native,
JavaScript, and network boundaries may copy once when ownership cannot be
shared; internal stages do not repeat that copy.

## Schema Catalog Boundary

`Schema.Entity` is a validated catalog value. Macro-generated, manually
constructed, and decoded entities pass through the same intrinsic validation
boundary before reaching persistence codecs or runtime registration. Field-name
and field-number maps are derived once from that validated catalog; downstream
code neither resolves duplicate metadata by precedence nor traps while building
a dictionary.

Swift 6.4 KeyPath syntax is consumed by schema macros while the concrete root
and value types are available. The macro resolves each selected property to a
generated `Field<Model, Value>` containing stable identity and
`FieldSchemaType`. `IndexDescriptor` stores those canonical field descriptions,
not `KeyPath`, `PartialKeyPath`, `AnyKeyPath`, or `Any.Type`.

Construction evaluates both `IndexKind.validateTypes` and
`validateConfiguration`, and requires the selected generated fields to match
the fields declared by the concrete kind. Invalid descriptors fail during
construction; macro-generated descriptor accessors and `Schema` preserve that
typed construction failure instead of storing an invalid descriptor. Runtime
maintainers may therefore rely on a schema containing only type-compatible,
configuration-valid declarations.

## Query Boundary

The query declarations in `DatabaseKit` represent SQL, SQL/PGQ, and SPARQL
meaning without owning parsing,
planning, or execution. Text parsers and runtime execution belong to
`database-framework`; both text and binary inputs must pass the same QueryIR
structural and semantic validators.

`LIMIT` and `OFFSET` use `UInt64`. Negative pagination is not representable,
and a runtime that needs a platform-sized collection index performs a checked
conversion only after applying its execution resource limit.

`QueryStructuralResourceLedger` reports invalid admission use and unbalanced
nesting as typed failures. Hostile input and parser lifecycle mistakes never
become process traps or successful partial queries.

## Embedded Boundary

The Embedded client and canonical protocol path is:

```text
database-client ──▶ DatabaseWire ──▶ DatabaseKit ──▶ DatabaseTypes
```

`DatabaseKit` and `DatabaseWire` must compile with the Swift 6.4 Embedded WASM
SDK. Their canonical path must not import Foundation, FoundationEssentials,
Codable, URLSession, JavaScriptKit, or database runtime implementations.

`DatabaseWireReader` applies frame, string, byte-string, collection, nesting,
and object budgets before allocating or constructing decoded values.
Canonical object decoding preserves the input buffer ownership path and rejects
non-canonical field order without creating a second key array.

`DatabaseWireWriter` has no public mutable-array accumulation mode. Canonical
encoding first measures the exact output, then writes directly into one final
`ByteString` allocation. Synchronous streaming uses borrowed spans whose
lifetime ends when the consumer call returns. Decoder state inconsistencies are
typed `DatabaseWireError` failures rather than traps.

## Version 1 Contract

There is one protocol version and one canonical representation. Version 1 does
not provide aliases, legacy JSON envelopes, compatibility DTOs, or negotiation
with an earlier protocol.

Each DatabaseWire-provided `DatabaseOperation<Request, Response>` descriptor
statically binds an operation identifier to its request and response types.
Applications cannot construct raw operation descriptors or provide binary
encoding witnesses. Protocol failures remain typed and distinguish malformed
input, resource limits, unsupported identifiers, authorization, conflicts,
retryability, and server failures.

OWL mapping follows the same rule: malformed class expressions, data ranges,
restrictions, and RDF lists are rejected. Unknown values are not replaced with
`owl:Thing` or `xsd:string`, and cyclic lists terminate with a typed error.

The version 1 operation families are fixed:

| Family | Contract |
|---|---|
| `capabilities.describe` | Runtime capability catalog |
| `schema.describe` | Validated schema catalog |
| `query.execute` | SQL, graph pattern, and SPARQL queries |
| `mutation.execute` | Typed mutation batches |
| `graph.algorithm` | Graph algorithm invocation and paging |
| `ontology.execute` | Ontology operations |
| `shacl.execute` | SHACL operations |
| `command.execute` | Application command execution |
| `maintenance.execute` | Migration and index maintenance |
| `job.start/status/result/cancel` | Durable operation lifecycle |

`command.execute` is one operation family. Each command descriptor declares
`readOnly` or `readWrite` access, and that access is encoded in both request and
response payloads. A read response carries output and continuation. A write
response additionally carries the commit version. Typed decoding rejects an
access value that does not match the statically selected command descriptor.
`CommandOperation<Command>` binds `CommandInvocation<Command>` to the
descriptor's associated result. `ReadCommandResult` has no commit-version
state; `WriteCommandResult` requires a non-optional commit version.

## Runtime Boundary

database-framework interprets the declarations and operations from this package.
It owns transaction coordination, query execution, persistence, index
maintenance, graph algorithms, ontology execution, SHACL execution, jobs, and
migrations.

database-client owns request correlation, cancellation, timeout behavior,
pagination facades, and transport adapters. storage-kit owns storage
transactions and backend adapters. Neither responsibility belongs in
database-kit.
