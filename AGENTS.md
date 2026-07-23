# AGENTS.md

## Responsibility

- This package owns the Foundation-independent database value model, record identity, QueryIR, and the canonical DatabaseWire v1 contract.
- It does not own transport, database execution, storage, application schemas, or platform adapters.
- DatabaseWire is deterministic and bounded. Every decoder must reject truncated, oversized, invalid, unknown, or trailing input explicitly.

## Naming

- Name every declaration for its database-domain responsibility, observable behavior, state transition, ownership, or lifetime contract.
- Follow the Swift API Design Guidelines at every access level, including tests and generated support.
- Do not encode implementation language, ABI, calling convention, module identity, binary layout, toolchain, build mode, or optimization strategy in ordinary names.
- Keep externally fixed spellings only in protocol constants or boundary descriptors, and translate them into semantic domain names immediately.
- Distinguish owned byte storage from borrowed views in both names and API contracts.
- Names such as `regular`, `legacy`, `impl`, `helper`, `manager`, or a bare `callback` are invalid unless they precisely describe a domain contract.

## Data and Error Contracts

- Foundation, Codable, URLSession, and platform date or data types must not enter the canonical model or Wire targets.
- Large binary paths use one owned buffer plus bounded ranges or views. Materialize a copy only at an explicit ownership or external API boundary.
- A required copy must be documented at the implementation site and verified when described as a performance improvement.
- Do not silently substitute defaults for malformed input. Return a typed DatabaseWire error.
- This is protocol version 1. Do not add compatibility aliases, version negotiation, or deprecated duplicate models.
