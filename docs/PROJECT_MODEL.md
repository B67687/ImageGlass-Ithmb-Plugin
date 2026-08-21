# PROJECT_MODEL.md: The Imageglass-Ithmb-Plugin State Machine

> **Purpose:** This document is the project's whole-project state machine, mandated by SPECIFICATION.md section 2. Every feature addition is a state transition; a documented transition table catches invariant violations at spec time, not as production regressions.
>
> **Current state:** POLISHED (code hardened, CI green, governance documentation in place, REVIEW gate pending before DISTRIBUTE).

## States

| State | Meaning |
|---|---|
| `IDEA` | Raw intent: ImageGlass has no native .ithmb support; a C ABI plugin could add it |
| `SPEC'D` | The ImageGlass SDK v1.1.0 ABI contract and ithmb-core crate API are understood; scope locked to decode-only |
| `PROTOTYPED` | Initial FFI layer built and validated against the SDK header |
| `IMPLEMENTED` | v1.0.0 shipped: entry point, codec surface, decode path, packaging |
| `POLISHED` | v1.1.x hardening: SDK v1.1.0 ABI port, struct-size validation, buffer registry, CI hardening, standards audit fixes |
| `SHIPPED` | A release tag pushed and GitHub Release created with all three platform packages |
| `MAINTAINED` | Bugfix-only cadence; no new features |
| `EVOLVED` | A new feature (e.g. encoding) is added after V1 |

## Valid Transitions

| Transition | When valid |
|---|---|
| `IDEA → SPEC'D` | ABI contract and dependency understood; scope locked |
| `SPEC'D → PROTOTYPED` | FFI layout validated against the SDK header |
| `PROTOTYPED → IMPLEMENTED` | v1.0.0 milestone shipped |
| `IMPLEMENTED → POLISHED` | Hardening work: ABI port, safety, CI, audits (v1.1.0 → v1.1.3) |
| `POLISHED → SHIPPED` | REVIEW gate passes; release tag pushed |
| `SHIPPED → MAINTAINED` | Bugfix-only cadence begins |
| `SHIPPED → EVOLVED` | New feature added (e.g. encoding once ithmb-core ships an encoder) |
| `MAINTAINED → EVOLVED` | New feature added after maintenance began |
| `EVOLVED → POLISHED` | New feature hardened |
| Any state → earlier state | Rollback: a regression reverts the ithmb-core bump and re-releases the previous version |

## Invalid Transitions

```
IMPLEMENTED → SHIPPED (must pass through POLISHED)
POLISHED → SHIPPED without passing REVIEW (the REVIEW gate is mandatory)
PROTOTYPED → SHIPPED (skipping IMPLEMENTED and POLISHED)
SPEC'D → IMPLEMENTED (skipping PROTOTYPED validation)
```

> These are invariants: **no release ships without passing POLISHED and REVIEW. No feature is added without passing through the state machine.**

## Invariants (What Must Never Change)

1. **The C ABI contract is stable.** `ig_plugin_get_api` is the only exported symbol; `IGCodecApi` is 112 bytes and `IGCodecCapability` is 104 bytes on 64-bit. A struct-size change is a breaking ABI change and requires a major version bump.
2. **No panic may unwind across the C boundary.** Every FFI entry point stays wrapped in `catch_unwind`.
3. **The plugin never uses the host allocator for pixel buffers.** Whoever allocates, frees; the plugin's own allocator is always available, even during host shutdown.
4. **Every buffer handed to the host is registered until freed.** The BufferRegistry is the single source of truth for live allocations.
5. **The decode dependency is static.** ithmb-core is compiled into the cdylib; no runtime-loaded shared library is introduced.
6. **The registry source is crates.io only.** deny.toml denies all other registries and git sources.
7. **Version bumps stay in sync.** Cargo.toml, igplugin.json, and the plugin_version string in state.rs change together.

## Blast Radius Map (coupled co-changing components)

| Change | Coupled components | Why |
|---|---|---|
| ABI struct layout change (types.rs) | types.rs, lib.rs (entry validation), codec.rs (capability), decode.rs (pixel buffer), scripts/abi-smoke.py (ctypes mirrors), test_abi_struct_sizes | The struct sizes are asserted in tests and mirrored in the Python smoke test; a layout change breaks all of them |
| ithmb-core version bump | Cargo.toml, Cargo.lock, CHANGELOG.md, state.rs (plugin_version), igplugin.json, package.sh (manifest version) | Every release bumps the version string in four places plus the manifest |
| Entry point behavior change (lib.rs) | lib.rs, state.rs (HOST_API storage), scripts/abi-smoke.py (entry call), entry-point tests | The entry point is the contract with the host |
| Buffer lifecycle change (decode.rs / buffer_registry.rs) | decode.rs, buffer_registry.rs, state.rs (BUFFER_REGISTRY static), decode tests, ABI smoke free step | Free must unregister before freeing; the registry is the guard |
| CI gate change | .github/workflows/ci.yml, scripts/check-local.sh, scripts/check-parity.sh, scripts/check-parity.config | check-parity.sh asserts local and GitHub CI agree on the same commit |
| Profile database change | ithmb-core (upstream), codec.rs (metadata lookup), decode.rs (decode) | The plugin consumes the profile DB; a profile change is an upstream release |
| SDK version change (host side) | types.rs, lib.rs (struct-size validation), codec.rs, decode.rs | A host SDK bump changes the ABI contract the plugin mirrors |

## Test

The transition-table test for this project:

- [ ] Every feature addition in FEATURES.md has a valid transition in this table
- [ ] No path skips POLISHED → REVIEW → SHIPPED
- [ ] ABI struct sizes are asserted in test_abi_struct_sizes and mirrored in scripts/abi-smoke.py
- [ ] Version bumps touch Cargo.toml, igplugin.json, and state.rs together
- [ ] check-parity.sh passes: local and GitHub CI agree on the same commit