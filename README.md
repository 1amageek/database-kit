# database-kit

Database semantic models, declarations, QueryIR, and the canonical binary
protocol for the database ecosystem.

The normative package ownership and product contract is documented in
[the database-kit package design](DESIGN.md), under the workspace authority in
[`../SPEC.md`](../SPEC.md).

The package implements the target-free DatabaseWire v3 contract by default.
The non-default `MultiBase` trait adds Base, Composition, persisted Grant,
target, provenance, and federated-consistency semantics as DatabaseWire v5.
Completion is verified through Native behavior tests, standard and Embedded
WASM release builds, the Embedded macro-compilation fixture, and byte-owner
identity tests in both trait configurations.

## Overview

database-kit is the semantic contract consumed by both
[database-framework](https://github.com/1amageek/database-framework) and
[database-client](https://github.com/1amageek/database-client). Primitive
representations are owned by
[database-types](https://github.com/1amageek/database-types); database-kit adds
model, schema, query, graph, and protocol meaning.

It provides:

- `@Persistable` macro for defining data models
- `@Polymorphable` macro for protocol-oriented polymorphic storage metadata
- `@OWLClass` macro for OWL ontology class mapping
- `@OWLDataProperty` / `@OWLObjectProperty` macros for OWL property annotations
- one stable `#Index` macro surface backed by typed `IndexDeclaration` values
- Foundation-independent identity, schema fingerprints, execution budgets,
  RDF, and `QueryIR` semantic models
- bounded RDF term-role and structural validation without binary materialization
- canonical binary `DatabaseWire` operations, envelopes, limits, and errors
- canonical schema manifests, SHA-256 fingerprints, and typed schema
  plan/apply requests through `schema.execute`
- strict, lossless JSON adaptation for schema manifests in the optional
  native `DatabaseSchemaJSON` product
- one Foundation-independent semantic module
- one canonical bounded binary protocol module
- one optional native Foundation model-integration module

With the non-default `MultiBase` trait it additionally provides:

- `Base`, `Base.Composition`, and persisted `Security.Grant` semantics;
- `CompositionSelection` and `CompositionResolution` for named or derived
  read-only Composition targets without synthetic identity;
- database, Base, or Composition operation targets;
- Base-qualified identity, placement, lifecycle, provenance, and federated
  read consistency;
- the `base.execute`, `composition.execute`, and `grant.execute` operations.

```
database-client ────────┐
                       ▼
                database-kit ───────▶ database-types
                       ▲
                       │
                database-framework ─▶ storage-kit
```

## Installation

```swift
dependencies: [
    .package(
        url: "https://github.com/1amageek/database-kit.git",
        from: "26.0818.0"
    )
]
```

## Modules

| Module | Description |
|--------|-------------|
| `DatabaseKit` | Foundation-independent model, identity, schema fingerprint, execution budget, query, mutation, relationship, index, graph, ontology, SHACL, and shared streaming digest support |
| `DatabaseWire` | Canonical binary envelopes, typed operations, bounded encoding and decoding, results, errors, and protocol-specific digest values |
| `DatabaseSchemaJSON` | Native strict JSON adapter for `SchemaManifest`; rejects duplicate or unknown keys and preserves every `FieldValue` case without numeric inference |
| `DatabaseKitFoundation` | Native-only participation of Foundation scalar types in `Persistable` field adaptation |

Relationship, vector, full-text, geographic, rank, graph,
ontology, and SHACL are source classifications within `DatabaseKit`, not
separate products.

`DatabaseKit` and `DatabaseWire` build with the matching Swift 6.4 standard and
Embedded WASM SDKs. `DatabaseSchemaJSON` and `DatabaseKitFoundation` are native
adapter products and are excluded from that dependency graph.

There is no umbrella value module in database-kit. `FieldValue` and every
primitive alternative are defined only by `DatabaseTypes`; the database-kit
modules above add model, RDF, SHACL, query, and protocol semantics without
redeclaring that algebra.

Query pagination uses `UInt64`, so negative `LIMIT` and `OFFSET` values are not
representable. DatabaseWire encoding measures the exact frame and writes
directly into one final `ByteString` allocation; there is no public
mutable-array writer path.

The default graph has no Base declarations, target field, persisted Grant
operations, provenance table, topology, or federated consistency payload. It
represents one database and one execution root directly.

When `MultiBase` is enabled, `Base.ID`, `Base.Placement.ID`, and
`Base.Composition.ID` are validated ASCII slugs. A Composition stores a
nonempty, unique, canonically ordered Base set. Requests then carry an explicit
database, Base, or Composition selection. A named selection resolves a catalog
generation; a derived selection carries only its canonical Base set.
Composition result pages encode their
Base table once and attach ordinal provenance to each row or quad, together
with the transactional or federated read points that fixed the result.

```swift
.package(
    url: "https://github.com/1amageek/database-kit.git",
    from: "26.0818.0",
    traits: [.trait(name: "MultiBase")]
)
```

See [the package design](DESIGN.md) for the package boundary and dependency
rules.
See
[Zero-Copy and Embedded rationale](Docs/ZERO_COPY_EMBEDDED_DESIGN.md) for
the copy budget, static model-adaptation design, lazy result pages, and WASM
host transport contract.

## Verification

| Contract | Verification |
|---|---|
| Apple platform behavior | `TOOLCHAINS=org.swift.64202607231a scripts/xcode-test-harness`; the package-owned harness enforces the reviewed exact test count with zero skips, expected failures, runtime warnings, or internal tool errors |
| Standard WASM contract | Release builds of `DatabaseKit` and `DatabaseWire` with the matching Swift 6.4 WASM SDK and `-debug-info-format none` |
| Embedded semantic and Wire graph | Release builds of `DatabaseKit` and `DatabaseWire` with the matching Swift 6.4 Embedded WASM SDK and `-debug-info-format none` |
| Embedded macro use | Embedded release build of `DatabaseKitDeclarationContract` with `-debug-info-format none`, which expands model, field, directory, index, and relationship declarations |
| Binary ownership | Tests assert that payload pages borrow ranges from the single final frame allocation |
| Decoder safety | Tests cover truncation, limits, malformed values, non-canonical input, and cyclic RDF lists |

The current baseline is
`swift-6.4.x-DEVELOPMENT-SNAPSHOT-2026-07-23-a` with the exactly matching
standard and Embedded WASM SDKs. The macro dependency requires `swift-syntax`
as a release range (`from: "603.0.2"`) so downstream graphs that also
constrain swift-syntax (e.g. through JavaScriptKit) stay resolvable;
reproducibility comes from the committed `Package.resolved`, which CI enforces
with `-onlyUsePackageVersionsFromResolvedFile`. The full verification matrix
(host test harness plus the standard and Embedded WASM release builds below)
passes on this toolchain with swift-syntax `603.0.2`.
Release/WASM verification disables debug information because it is not shipped
in the reactor and avoids running host-side `dsymutil` over macro dependency
objects. Compiler diagnostics remain enabled.

```bash
TOOLCHAINS=org.swift.64202607231a scripts/xcode-test-harness
TOOLCHAINS=org.swift.64202607231a \
  DATABASE_KIT_TEST_TRAITS=MultiBase \
  scripts/xcode-test-harness

swift build --disable-default-traits --product DatabaseWire
swift build --disable-default-traits --traits MultiBase --product DatabaseWire

swift build --swift-sdk swift-6.4.x-DEVELOPMENT-SNAPSHOT-2026-07-23-a_wasm --product DatabaseKit -c release -debug-info-format none
swift build --swift-sdk swift-6.4.x-DEVELOPMENT-SNAPSHOT-2026-07-23-a_wasm --product DatabaseWire -c release -debug-info-format none
swift build --swift-sdk swift-6.4.x-DEVELOPMENT-SNAPSHOT-2026-07-23-a_wasm-embedded --product DatabaseKit -c release -debug-info-format none
swift build --swift-sdk swift-6.4.x-DEVELOPMENT-SNAPSHOT-2026-07-23-a_wasm-embedded --product DatabaseWire -c release -debug-info-format none
swift build --swift-sdk swift-6.4.x-DEVELOPMENT-SNAPSHOT-2026-07-23-a_wasm-embedded --target DatabaseKitDeclarationContract -c release -debug-info-format none
```

## Quick Start

### Define a Model

```swift
import DatabaseKit

@Persistable
struct User {
    #Directory<User>("app", "users")
    #Index(.ordered(
        name: "users_by_email",
        keys: [.ascending(\User.email)],
        unique: true
    ))
    #Index(.ordered(
        name: "users_by_creation",
        keys: [.ascending(\User.createdAt)]
    ))

    var id: String
    var email: String
    var name: String
    var createdAt: Timestamp
}
```

### Schema

```swift
let schema = try Schema(
    entities: [
        try User.schemaEntity,
        try Product.schemaEntity,
    ],
    version: Schema.Version(1, 0, 0)
)
```

## @Persistable Macro

The `@Persistable` macro generates all required protocol conformances:

```swift
@Persistable
struct Product {
    #Index(.ordered(
        name: "products_by_category_and_price",
        keys: [
            .ascending(\Product.category),
            .ascending(\Product.price),
        ]
    ))
    #Index(.ordered(
        name: "products_by_name",
        keys: [.ascending(\Product.name)],
        unique: true
    ))

    var id: String
    var name: String
    var category: String
    var price: Double

    @Transient
    var cachedDescription: String?  // Excluded from persistence
}
```

**Generated code**: `persistableType`, `allFields`, `fieldSchemas`, typed
`fields`, `indexDescriptors`, `fieldAccessRules`, concrete
`PersistedFieldOutput` traversal, canonical decoding, and `Sendable`
conformance. The model declares `id` and owns its generation policy.

The production encoder does not inspect a model through `Mirror`, `Any`, or a
runtime metatype. It writes each concrete property directly to the selected
output. `PersistableFieldEncoder.encode(_:)` is the explicit owned
materializer for callers that require `[PersistableField]`; Wire and storage
outputs can consume the generated traversal without that intermediate array.
When an execution path needs one field after typed access has been erased,
`persistedFieldValue(for:)` selects it by `FieldIdentity` through the same
generated traversal. It materializes only that field as `FieldValue`; the model
contract has no `Any`, `any Sendable`, dynamic-member, or reflection fallback.

`PersistedEntityValue` is the common read boundary for compiled values and
`PersistedModel`. Once a concrete model becomes an owned `PersistedModel`,
heterogeneous execution can read its canonical fields without reconstructing a
synthetic or concrete `Persistable` value. Its complete-field accessor preserves
the owned `PersistedModel` backing and materializes compiled values only at the
explicit type-erasure boundary.

Ontology bindings retain the complete field-to-property descriptor mapping in
`Schema.Entity`. A schema manifest therefore preserves the same RDF projection
contract as a compiled `@OWLClass` or `@OWLObjectProperty` model.
`OWLCanonicalDataPropertyProjection` and the canonical
`OWLIndividualIRIBuilder` overloads apply that contract directly to
`FieldValue`, so schema-driven runtimes do not reconstruct concrete Swift
models or pass through JSON before materializing RDF terms.

## Polymorphic Persistence

Polymorphic persistence lets multiple concrete `@Persistable` models share a
logical protocol group for storage and querying.

The intended API is:

```swift
@Polymorphable
@PolymorphicDirectory("memory", "entities")
@PolymorphicIndex(.vector(
    name: "Entity_embedding",
    embedding: "embedding",
    dimensions: 256,
    metric: .cosine
))
public protocol Entity: Polymorphable<EntityPolymorphicGroup> {
    var label: String { get }
    var embedding: Vector { get set }
}

@Persistable
public struct Person: Entity {
    public var id: String
    public var name: String
    public var embedding: Vector

    public var label: String { name }
}
```

`@Persistable` owns `Persistable` conformance for concrete structs.
`Polymorphable<Group>` owns only static group membership. The domain protocol
requires the fields shared by its concrete models, while
`EntityPolymorphicGroup` is the generated metadata declaration.

`@Polymorphable` is a metadata and validation macro. Swift 6.4 does not allow an
attached macro on a protocol to add protocol inheritance, so the protocol must
explicitly bind the generated declaration with
`: Polymorphable<EntityPolymorphicGroup>`.

Schema versions may use different Swift protocol names while preserving one
logical storage identity. Declare that stable identity explicitly:

```swift
@Polymorphable(identifier: "Document")
protocol DocumentV2: Polymorphable<DocumentV2PolymorphicGroup> {
    var id: String { get }
}
```

The identifier is part of persisted polymorphic membership and directory
identity. It must remain unchanged across schema versions that represent the
same logical group.

Swift 6.4 cannot form a `KeyPath<Self, Value>` while the protocol containing
the declaration is still being defined. Protocol-level indexes therefore use
logical property names with the `@PolymorphicIndex` attribute.
`@Polymorphable` validates every name against a declared protocol property at
compile time. `Schema` then resolves the logical property to each concrete
member's generated `FieldIdentity` and validates its canonical field type.

This string boundary is limited to protocol source declarations. Concrete
models continue to use KeyPath syntax with `#Index`, and runtime index
maintenance receives only concrete field identities. It performs neither
KeyPath retention nor string-to-field discovery.

See [Polymorphic Persistence guide](Docs/POLYMORPHIC_DESIGN.md) for
implementation rationale and migration notes; `DESIGN.md` remains the package
and module authority.

## #Directory Macro

### Static Path

```swift
#Directory<User>("app", "users")
```

### Entity Partition

```swift
@Persistable
struct Order {
    #Directory<Order>("accounts", \Order.accountID, "orders", layer: .partition)

    var orderID: Int64
    var accountID: String  // Entity partition key
}
```

### Multi-level Partitioning

```swift
@Persistable
struct Message {
    #Directory<Message>(
        "accounts", \Message.accountID,
        "channels", \Message.channelID,
        "messages",
        layer: .partition
    )

    var messageID: String
    var accountID: String
    var channelID: String
    var content: String
}
```

### Dynamic component rules

A dynamic component resolves one path element from one stored value, so every
key path used in `#Directory` must reference an existing persisted field, be
required rather than optional, carry a scalar rather than an array or nested
value, and occur at most once in the declaration. Each rule is a typed
`SchemaEntityError` raised at entity construction.

`layer:` names the layer tag of the resolved leaf. On `#Directory`,
`.partition` requires at least one dynamic component. `@PolymorphicDirectory`
retains `layer:` for the node its members share, and members disagreeing on
that tag raise `SchemaError.inconsistentPolymorphicDirectoryLayer`.

### Placement is schema identity

The static component values and their order, the dynamic field identity and its
order, and the leaf layer tag together select where an entity's rows live.
`compatibilityReport(from:)` reports a change to any of them as
`changedDirectoryComponents`, `changedDirectoryLayer`, or
`changedPolymorphicGroup`, and a change to the declared kind of a dynamic
component's field as `changedFieldEncoding`. None of these is lightweight
evolution: each one relocates existing data and requires an explicit move.

## Index declarations

See [Index Declaration rationale](Docs/INDEX_DECLARATION_DESIGN.md) for
declaration rationale, validation, evolution, and runtime-boundary notes;
`DESIGN.md` remains the package and module authority.

Built-in indexes have one declaration surface: `IndexDefinition` through
`#Index`. The macro always accepts one `IndexDeclaration`; changing index
semantics does not change the macro signature.

```swift
@Persistable
struct Event {
    #Index(.ordered(
        name: "events_by_calendar_and_start",
        keys: [
            .ascending(\Event.calendarID),
            .ascending(\Event.startsAt),
        ]
    ))
    #Index(.aggregate(
        name: "event_count_by_calendar",
        function: .count,
        groupBy: [.ascending(\Event.calendarID)]
    ))
    #Index(.aggregate(
        name: "event_attendees_by_calendar",
        function: .sum,
        groupBy: [.ascending(\Event.calendarID)],
        value: \Event.attendeeCount
    ))
    #Index(.history(
        name: "event_history",
        version: \Event.id,
        retention: .keepAll
    ))
    #Index(.vector(
        name: "event_embedding",
        embedding: \Event.embedding,
        dimensions: 384,
        metric: .cosine
    ))
    #Index(.text(
        name: "event_text",
        fields: [\Event.title, \Event.description],
        mode: .fullText(tokenizer: .simple)
    ))
    #Index(.text(
        name: "event_autocomplete",
        fields: [\Event.title, \Event.searchTerms],
        mode: .autocomplete(
            minimumPrefixLength: 2,
            maximumPrefixLength: 12
        )
    ))
    #Index(.spatial(
        name: "event_location",
        location: \Event.location
    ))
    #Index(.rank(
        name: "event_attendee_rank",
        score: \Event.attendeeCount
    ))
    #Index(.graph(
        name: "event_relationships",
        definition: .property(
            source: \Event.sourceID,
            label: .field(\Event.relationship),
            target: \Event.targetID,
            graph: nil,
            strategy: .adjacency
        )
    ))

    var id: String
    var calendarID: String
    var startsAt: Timestamp
    var attendeeCount: Int64
    var embedding: Vector
    var title: String
    var description: String
    var searchTerms: [String]
    var location: GeographicPoint
    var sourceID: String
    var relationship: String
    var targetID: String
}
```

The enclosing macro consumes each KeyPath and emits the corresponding
generated field identity. Protocol-level polymorphic declarations use
logical property names, which `@Polymorphable` verifies against protocol
properties.
Neither runtime path retains a KeyPath.

Property graphs and RDF datasets have separate declarations because their
identity contracts are different. A property graph uses `String` source,
label, target, and optional namespace fields. An RDF dataset uses `RDFTerm`
subject, predicate, object, and optional graph fields:

```swift
@Persistable
struct Statement {
    #Index(.graph(
        name: "statements_by_quad",
        definition: .rdf(
            subject: \Statement.subject,
            predicate: \Statement.predicate,
            object: \Statement.object,
            graph: \Statement.graph
        )
    ))

    var id: String
    var subject: RDFTerm
    var predicate: RDFTerm
    var object: RDFTerm
    var graph: RDFTerm?
}
```

Their semantic types are `graph(.property)` and `graph(.rdf)`. Schema
validation never infers one graph model from the other.

## Custom indexes

Third-party semantics use `IndexDeclaration.custom`. DatabaseKit preserves a
stable identifier, ordered keys, included fields, and canonical parameters;
the runtime provider owns their execution meaning.

```swift
import DatabaseKit

@Persistable
struct TimeSeriesEvent {
    #Index(.custom(
        name: "events_by_start_time",
        definition: CustomIndexDefinition(
            identifier: "com.mycompany.timeseries",
            keys: [.ascending(\TimeSeriesEvent.startsAt)],
            parameters: ["resolution": .string("minute")]
        )
    ))

    var id: String
    var startsAt: Timestamp
}
```

Index maintenance execution is implemented and registered by
[database-framework](https://github.com/1amageek/database-framework). Custom
declarations expose only canonical `CustomIndexDefinition` values; runtime
behavior remains outside this package. `IndexDescriptor` validates concrete
generated fields before `Schema` exposes the catalog.

## @Persistable enums

```swift
@Persistable
enum Status: String {
    case active, inactive, pending
}

@Persistable
struct Task {
    var id: String
    var title: String
    var status: Status = .pending
}
```

Applying `@Persistable` to a raw-value enum generates its `PersistableEnum`
conformance and case enumeration. String- and Int-backed enums receive
canonical field encoding and case metadata. Availability-qualified cases are
rejected so the persisted schema cannot vary by platform. `@Persistable(type:)`
remains specific to model structs.

## @Relationship Macro

```swift
@Persistable
struct Order {
    var total: Double

    @Relationship(Customer.self, indexFields: [\.name])
    var customerID: String?
}
```

## Ontology Integration

Ontology features are in the **Graph** module. Three usage levels can be combined incrementally.

| Level | Components | Use Case |
|-------|-----------|----------|
| **1. OntologyStore** | `OWLOntology`, `context.ontology` API | OWL reasoning, class hierarchy, property chain evaluation |
| **2. Macros + OntologyStore** | Level 1 + `@OWLClass`, `@OWLObjectProperty`, `@OWLDataProperty` | Bind Persistable types to OWL concepts, IRI validation, SPARQL over tables |
| **3. Macros + OntologyStore + Triples** | Level 2 + graph and RDF index declarations | SPARQL federation across Persistable tables and RDF triples |

### Level 1: OntologyStore

Define and load OWL ontologies for reasoning and hierarchy queries. No macros required.

```swift
var ontology = OWLOntology(iri: "http://example.org/onto")
ontology.classes = [OWLClass(iri: "ex:Person"), OWLClass(iri: "ex:Employee")]
ontology.axioms = [.subClassOf(sub: .named("ex:Employee"), sup: .named("ex:Person"))]

// Load and query through database-framework execution
try await context.ontology.load(ontology)
let reasoner = try await context.ontology.reasoner(for: "http://example.org/onto")
let superClasses = reasoner.superClasses(of: "ex:Employee")
```

### Level 2: Macros + OntologyStore

Bind Persistable types to OntologyStore concepts. **Macros are bindings, not definitions** — class hierarchies, property characteristics, and axioms live in the OntologyStore. Each row is interpreted as virtual RDF triples, enabling SPARQL queries over Persistable tables.

```swift
@Persistable
@OWLClass("ex:Employee")
struct Employee {
    @OWLDataProperty("ex:name")
    var name: String

    @OWLDataProperty("ex:worksFor", to: \Department.id, functional: true)
    var departmentID: String?
}

@Persistable
@OWLObjectProperty("ex:employs", from: "employeeID", to: "projectID")
struct Assignment {
    var id: String = UUID().uuidString
    var employeeID: String = ""
    var projectID: String = ""

    @OWLDataProperty("ex:since")
    var startDate: Timestamp
}
```

IRI validation checks that macro bindings reference valid OntologyStore entries:

```swift
try await context.ontology.validateSchema(schema, ontologyIRI: "http://example.org/onto")
```

SPARQL queries Persistable tables directly:

```swift
let results = try await context.sparql()
    .from(Employee.self)
    .where("?e", "rdf:type", "ex:Employee")
    .where("?e", "ex:name", "?name")
    .select("?e", "?name")
    .execute()
```

### Level 3: Macros + OntologyStore + Triples

Add a GraphIndex triple store alongside Persistable tables. SPARQL federation resolves each triple pattern to the optimal source — structured data in tables, unstructured knowledge in triples:

```swift
let results = try await context.sparql()
    .from(RDFTriple.self)        // Triple store
    .from(Employee.self)          // Persistable table
    .where("?e", "rdf:type", "ex:Employee")     // → Employee table
    .where("?e", "ex:worksFor", "?dept")         // → Employee table
    .where("?dept", "ex:locatedIn", "?city")     // → Triple store
    .select("?e", "?city")
    .execute()
```

### Macro Reference

**`@OWLClass(_ iri: String)`** — Maps a Persistable type to an OWL class. Generates `OWLClassEntity` conformance, `ontologyClassIRI`, and `ontologyPropertyDescriptors`.

**`@OWLObjectProperty(_ iri: String, from: String, to: String)`** — Maps a Persistable type to an OWL ObjectProperty with endpoint fields. Generates `OWLObjectPropertyEntity` conformance and an adjacency graph index declaration with an implicit label.

**`@OWLDataProperty(_ iri: String, ...)`** — Annotates a field with an OWL datatype property IRI.

Bare names (without `:`, `#`, or `/`) default to the namespace extracted from the parent `@OWLClass` or `@OWLObjectProperty` IRI.

## Platform Support

| Platform | Minimum Version |
|----------|-----------------|
| iOS | 26.0+ |
| macOS | 26.0+ |
| tvOS | 26.0+ |
| watchOS | 26.0+ |
| visionOS | 26.0+ |
| Linux | Swift 6.4+ |
| WASI Embedded | Swift 6.4+ for `DatabaseKit` and `DatabaseWire` |
| WASI (standard runtime) | Swift 6.4+ for the same semantic and wire products |

## Related Packages

| Package | Role | Platform |
|---------|------|----------|
| **[database-types](https://github.com/1amageek/database-types)** | Primitive field-value algebra and immutable byte ownership | Embedded, Apple, Linux |
| **[database-framework](https://github.com/1amageek/database-framework)** | Database execution, transactions, indexes, graph, ontology, and validation | WASI, macOS, Linux |
| **[database-client](https://github.com/1amageek/database-client)** | Typed invocation and WASM host, HTTP, and WebSocket transports | Embedded, Apple, Linux |
| **[storage-kit](https://github.com/1amageek/storage-kit)** | Storage transactions and backend adapters | WASI, macOS, Linux |

## License

Licensed under the [MIT License](LICENSE).
