# AGENTS.md

## Responsibility

- This package consumes primitive representations from `DatabaseTypes` and owns
  the Foundation-independent database semantic model above those primitives:
  model and document metadata, logical identity, schema, relationships, index
  and graph declarations, QueryIR, and the canonical DatabaseWire v3 contract.
- It does not own transport, database execution, storage, application schemas, or platform adapters.
- A declaration does not move to `DatabaseTypes` merely because multiple
  database packages consume it. Query, schema, identity, operation, and wire
  semantics remain here unless the declaration passes the workspace primitive
  admission gate.
- DatabaseWire is deterministic and bounded. Every decoder must reject truncated, oversized, invalid, unknown, or trailing input explicitly.
- `DatabaseKitFoundation` is the optional native-only integration between
  Foundation scalar values and `DatabaseKit` model adaptation. It must never
  enter the `DatabaseKit`, `DatabaseWire`, or Embedded dependency graph.

## Architectural Priorities

- Correct database semantics and explicit ownership are prerequisites.
- Zero-copy data flow and Embedded suitability are primary design inputs, not
  later optimizations.
- Performance-sensitive paths use one final owned `ByteString` plus bounded
  views. Independently owned network, JavaScript, or native API boundaries may
  copy once when ownership cannot be shared.
- The Embedded path does not use Foundation, Codable-based persistence,
  reflection, existential storage, JavaScriptKit, or mutable runtime
  registration.
- Model adaptation is generated statically. Do not add `Mirror`,
  `any Persistable`, `[any Descriptor]`, or `[any Persistable.Type]` to a
  production path.
- Swift 6.4 KeyPath syntax may select fields only at a macro expansion
  boundary. Generated runtime code, schema values, QueryIR, and Wire values
  store typed `Field<Model, Value>` identity or canonical field references,
  never `KeyPath`, `PartialKeyPath`, `AnyKeyPath`, or `Any.Type`.
- DatabaseWire operation descriptors are constructed only by DatabaseWire.
  Do not expose a public raw Wire conformance point, arbitrary operation
  initializer, or application-supplied binary encoding witness.
- Bulk Wire results retain their frame and materialize rows or values on
  demand. Do not eagerly decode an entire result page merely for API
  convenience.
- `ByteString` is the only canonical byte value. Do not introduce a
  package-specific byte alias.

## Naming

- Name every declaration for its database-domain responsibility, observable behavior, state transition, ownership, or lifetime contract.
- Follow the Swift API Design Guidelines at every access level, including tests and generated support.
- Do not encode implementation language, ABI, calling convention, module identity, binary layout, toolchain, build mode, or optimization strategy in ordinary names.
- Keep externally fixed spellings only in protocol constants or boundary descriptors, and translate them into semantic domain names immediately.
- Distinguish owned byte storage from borrowed views in both names and API contracts.
- Names such as `regular`, `legacy`, `impl`, `helper`, `manager`, or a bare `callback` are invalid unless they precisely describe a domain contract.

## Data and Error Contracts

- Foundation, Codable, URLSession, and platform date or data types must not enter the canonical model or Wire targets.
- Primitive byte and field values come from `DatabaseTypes`; do not create
  duplicate value containers or module-identifying aliases.
- Large binary paths use one owned buffer plus bounded ranges or views. Materialize a copy only at an explicit ownership or external API boundary.
- A required copy must be documented at the implementation site and verified when described as a performance improvement.
- Do not silently substitute defaults for malformed input. Return a typed DatabaseWire error.
- The standard Wire contract is version 3. `MultiBase` replaces it with
  target-bound version 5; it is not a compatibility layer or a version to
  negotiate at runtime.

## Verification

- Native verification uses `scripts/xcode-test-harness` with the pinned Swift
  snapshot. The standard graph must execute exactly 632 tests. An isolated
  `MultiBase` graph uses `DATABASE_KIT_TEST_TRAITS=MultiBase` and must
  execute exactly 647 tests. The harness selects the trait in an isolated source
  copy and derives the expected count. Both runs require zero failures,
  skips, expected failures, runtime warnings, compiler-plugin internal errors,
  profile errors, or debug-information verification warnings.
- The harness uses the `database-kit-Package` scheme, separates
  `build-for-testing` from `test-without-building`, injects the pinned
  `libTesting.dylib` path into the generated `.xctestrun`, and applies a timeout
  to both phases.
- Standard and Embedded WASM verification uses the exact Swift 6.4 snapshot
  SDK identifiers and the release commands documented in `README.md`.
- Cross-platform release verification uses `-debug-info-format none`. The
  pinned snapshot emits invalid host-side DWARF name indexes while linking the
  macro dependency graph; release verification must neither emit nor ignore
  those input-verification warnings.
- A successful compile is not proof of decoder behavior or buffer ownership;
  the native behavioral suite remains mandatory.
