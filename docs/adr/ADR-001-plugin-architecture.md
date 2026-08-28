# ADR-001: Plugin Architecture — Thin C ABI Wrapper over ithmb-core

- **Status:** accepted
- **Date:** 2026-08-19 (retroactive)
- **Reviewed:** 2026-08-27

## Context

ImageGlass v10+ uses a C ABI plugin SDK (`IGCodecApi`) to discover and invoke image decoders at runtime. The plugin must be a cdylib that exports `ig_plugin_get_api`, returning a table of function pointers. The existing `ithmb-core` crate provides the actual decode logic but targets a Rust API, not C.

## Decision

Build `ithmb-core-cabi` as a thin cdylib wrapper that:

1. **Re-exports ithmb-core** as the decode engine — no duplicate decode logic.
2. **Implements the C ABI boundary** with `#[repr(C)]` types in `types.rs`, validated by compile-time size assertions.
3. **Uses OnceLock statics** (`state.rs`) for global initialization — no lazy_static, no thread-local storage.
4. **Wraps every FFI entry point** in `catch_unwind` (lib.rs) — panics never cross the FFI boundary.
5. **Tracks buffer lifecycle** via a `Mutex<HashMap>` registry (`buffer_registry.rs`) — the host holds an opaque pointer; we track its allocation.
6. **Delegates allocation to libc** (`allocator.rs`) — the host frees with its own allocator, so we must use `malloc`/`free`.

## Consequences

- **Positive:** Single source of truth for decode logic (ithmb-core). Safe FFI boundary. Testable without ImageGlass GUI.
- **Negative:** Additional indirection layer. ABI struct sizes must stay in sync with the C header manually (mitigated by compile-time assertions + CI smoke test).
- **Trade-off:** Chose Mutex<HashMap> buffer registry over arena allocation because the host can free buffers in any order, and the registry provides leak detection.

## Alternatives Considered

1. **Link ithmb-core statically into ImageGlass** — rejected: would couple plugin updates to host releases.
2. **Use CXX instead of raw C ABI** — rejected: ImageGlass SDK is C, not C++.
3. **Arena allocator for buffers** — rejected: host can free in arbitrary order; arena would prevent individual deallocation.

## References

- `src/lib.rs` — entry point implementation
- `src/types.rs` — ABI type definitions
- `src/state.rs` — OnceLock initialization
- `src/buffer_registry.rs` — buffer lifecycle tracking
- `.github/workflows/ci.yml` — ABI size verification in CI
- `scripts/abi-smoke.py` — cross-language ABI validation
