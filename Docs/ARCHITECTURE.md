# Architecture and Ownership

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
| `DatabaseValue` | Persisted identity, schema version, RDF role validation, canonical RDF bytes | Primitive field values, Codable, transport |
| `DatabaseValueCodable` | Opt-in Codable adaptation | Canonical binary protocol |
| `DatabaseDigest` | Deterministic digest algorithms used by semantic and protocol contracts | Authentication or transport security |
| `Core` | Persistable model adaptation, schema and index declarations, macros | Persistence execution or index maintenance |
| `QueryIR` | SQL, SQL/PGQ, and SPARQL statements and structural validation | Parsing or executing a query |
| `QueryIRFoundation` | Opt-in Foundation conversions | Query meaning |
| `DatabaseWire` | Version 1 envelopes, typed operations, bounded binary encoding and decoding | Network transport or operation execution |
| Declaration modules | Relationship, vector, text, geographic, rank, permuted, graph, ontology, and SHACL declarations | Runtime maintenance and execution |

## Primitive Boundary

`FieldValue`, `FieldObject`, `ByteString`, temporal primitives, exact decimal,
UUID, geographic values, vectors, entity references, and RDF terms are owned by
`database-types`. database-kit consumes those values without redeclaring,
wrapping, or aliasing them.

Application model conversion is owned by `Core` because it depends on persisted
model and schema meaning. Optional Foundation conversion is isolated in adapter
targets and does not enter the Embedded dependency graph.

## Schema Catalog Boundary

`Schema.Entity` is a validated catalog value. Macro-generated, manually
constructed, and decoded entities pass through the same intrinsic validation
boundary before reaching persistence codecs or runtime registration. Field-name
and field-number maps are derived once from that validated catalog; downstream
code neither resolves duplicate metadata by precedence nor traps while building
a dictionary.

## Embedded Boundary

The Embedded client and canonical protocol path is:

```text
DatabaseTypes
      │
      ├──▶ DatabaseValue ──▶ QueryIR
      │          │             │
      └──────────┴─────────────┴──▶ DatabaseWire
```

`DatabaseValue`, `DatabaseDigest`, `QueryIR`, and `DatabaseWire` must compile
with the Swift 6.4 Embedded WASM SDK. They must not import Foundation, Codable,
URLSession, JavaScriptKit, or database runtime implementations.

`DatabaseWireReader` applies frame, string, byte-string, collection, nesting,
and object budgets before allocating or constructing decoded values.
Canonical object decoding preserves the input buffer ownership path and rejects
non-canonical field order without creating a second key array.

## Version 1 Contract

There is one protocol version and one canonical representation. Version 1 does
not provide aliases, legacy JSON envelopes, compatibility DTOs, or negotiation
with an earlier protocol.

Each `DatabaseOperation` statically binds an operation identifier to its request
and response types. Protocol failures remain typed and distinguish malformed
input, resource limits, unsupported identifiers, authorization, conflicts,
retryability, and server failures.

## Runtime Boundary

database-framework interprets the declarations and operations from this package.
It owns transaction coordination, query execution, persistence, index
maintenance, graph algorithms, ontology execution, SHACL execution, jobs, and
migrations.

database-client owns request correlation, cancellation, timeout behavior,
pagination facades, and transport adapters. storage-kit owns storage
transactions and backend adapters. Neither responsibility belongs in
database-kit.
