# Index Declaration Design

## Purpose and ownership

`DatabaseKit` owns the complete logical meaning of an index. It does not own
storage layout, online build state, query planning, runtime algorithm choice,
or maintainer construction. Those execution concerns belong to
`database-framework`.

The public declaration surface has one stable macro argument:

```swift
#Index(.ordered(
    name: "events_by_calendar_and_start",
    keys: [
        .ascending(\Event.calendarID),
        .ascending(\Event.startsAt),
    ]
))
```

`#Index` always receives one `IndexDeclaration<AnyKeyPath>`. New index
semantics are added to `IndexDefinition`; they do not add macro parameters or
new index macros. The macro does not keep an allowlist of factory names;
declaration typing and schema validation own that extensibility boundary.

## Value model

```text
#Index
  -> IndexDeclaration<AnyKeyPath>
      -> explicit logical name
      -> IndexDefinition<AnyKeyPath>
  -> macro field resolution
  -> IndexDeclaration<FieldIdentity>
  -> IndexDescriptor
  -> Schema.Entity
```

An `IndexDeclaration` contains the explicit persisted name and the complete
definition. An `IndexDescriptor` adds the owning entity and validated field
schemas. It retains no key paths, metatypes, runtime providers, or physical
subspaces.

Index identity and index definition are separate:

| Concept | Meaning |
|---|---|
| `IndexIdentity(entityName:name:)` | Stable logical identity used for schema comparison |
| `IndexDefinition` | Complete logical behavior of that identity |
| definition fingerprint | Physical-generation identity derived from the complete validated declaration |

Keeping the same name while changing any definition field is a replacement,
not an unchanged index.

## Definition algebra

| Factory | Logical meaning | Selected fields |
|---|---|---|
| `.ordered` | Ordered or unique lookup | ordered keys plus optional included fields |
| `.aggregate` | Count, sum, minimum, maximum, average, non-null count, approximate distinct, or percentile | grouping keys and optional value |
| `.updateCount` | Per-value update frequency | one field |
| `.history` | Version history with retention | version field |
| `.bitmap` | Equality bitmap | one field |
| `.leaderboard` | Time-window leaderboard | grouping keys and descending score |
| `.vector` | Vector similarity semantics | embedding, dimensions, metric |
| `.text` | Full-text or autocomplete semantics | one or more text fields |
| `.spatial` | Geographic lookup | location, encoding, level |
| `.rank` | Numeric rank | descending score |
| `.graph` | Property graph, RDF dataset, or ontology projection | graph-specific identities and optional included fields |
| `.custom` | Third-party semantic family | explicit identifier, keys, included fields, canonical parameters |

`IndexType` is the typed runtime dispatch key derived from the definition. It
is not a second metadata model and cannot carry parameters that belong to the
definition.

There is no separate Permuted index. A different compound-key order is an
ordinary `.ordered` declaration whose `keys` are written in that order.

## Macro contract

Concrete model declarations use key paths. The macro resolves every key path
to the model's generated `FieldIdentity` and rejects nested or unknown
properties. The explicit index name must be a nonempty string literal.

Protocol declarations use the same declaration algebra:

```swift
@PolymorphicIndex(.vector(
    name: "Entity_embedding",
    embedding: "embedding",
    dimensions: 384,
    metric: .cosine
))
```

Swift cannot form `KeyPath<Self, Value>` inside the protocol declaration, so
this one source boundary uses property names. The macro preserves the typed
declaration without inspecting factory-specific argument labels. `Schema`
resolves the fields independently for every concrete member and rejects
missing or incompatible fields. Runtime execution receives only concrete
`FieldIdentity` values.

## Validation invariants

- `#Index` and `@PolymorphicIndex` names are explicit, nonempty, and globally
  unambiguous in one schema. Macro-owned ontology support uses its documented
  model-scoped projection identity rather than inferring a user declaration.
- Every field identity must exactly match the containing entity's field name
  and number.
- Key fields and included fields contain no duplicates or overlap.
- Each definition validates field count, canonical field type, ordering
  capability, and all numeric configuration bounds.
- Only ordered indexes can declare uniqueness.
- Ontology projections contain no key or included fields; their runtime
  projection is derived from ontology metadata.
- Polymorphic members must materialize the same logical declaration and each
  member must satisfy its field-type contract.
- Decoders reject unknown cases and unsupported manifest versions. They do not
  map malformed input to a default index.

## Evolution and serialization

`Schema.indexChanges(from:)` compares stable identity and the full
`IndexDescriptor`. `Schema.polymorphicIndexChanges(from:)` performs the same
comparison for group identity and logical declaration. The result is
`added`, `removed`, or `replaced`.

DatabaseWire and DatabaseSchemaJSON encode the complete algebra. Their format
versions are strict. A definition added to the algebra must be added to both
encoders, both decoders, schema comparison, validation, and round-trip tests
in the same change.

Schema description responses also carry `IndexType` with fixed wire tags.
Diagnostic strings are presentation values only; clients do not recover type
semantics by parsing a name or a diagnostic label.

The canonical format used for an index definition fingerprint has its own
version. It does not inherit the complete schema-manifest format version;
otherwise an unrelated manifest change would replace every physical index
generation.

## Runtime boundary

```text
DatabaseKit declaration
    -> database-framework validates available IndexType provider
        -> ResolvedIndex binds root expression and item types
            -> lifecycle resolves definition fingerprint
                -> maintainer and reader use one physical generation
```

Deployment choices such as Flat versus HNSW, memory budgets, batch sizes, and
backend-specific storage remain runtime configuration. They must not change
the logical declaration unless they change observable database semantics.
