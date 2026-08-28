# TECH_DEBT_AUDIT.md — ImageGlass-Ithmb-Plugin

**Date:** 2026-08-28
**Reviewed:** 2026-08-21
**Auditor:** Sisyphus-Junior (automated)
**HEAD:** 627c184
**Language:** Rust (cdylib), Python (ABI smoke test), Bash (scripts)

## Executive Summary

Overall health is **good**. This is a small, focused cdylib (~1,400 non-test LOC across 9 Rust modules) with rigorous safety practices — every `extern "C"` function wraps its body in `catch_unwind`, all `unsafe` blocks have `// SAFETY:` comments, the C ABI struct sizes are validated, and there are 28 unit tests plus a deterministic pseudo-fuzz harness. 14 of 14 original findings are now resolved or accepted. No critical bugs, no security holes, no panics reachable from the C ABI.

## Mental Model

A thin FFI layer (`ithmb-core-cabi`) wraps the `ithmb-core` crate (1.9.x from crates.io) into a cdylib that implements the ImageGlass v10 plugin ABI. The host calls `ig_plugin_get_api` to get a function table, which exposes one codec. That codec handles `.ithmb` and `.ipm` files — Apple thumbnail databases from iPods/iPhones. The plugin self-allocates pixel buffers via `libc::malloc` (not the host allocator), tracks them in a mutex-protected `BufferRegistry`, and frees them on `free_pixel_buffer`. All plugin-lifetime state lives behind `OnceLock`s for pointer stability.

## Resolved (14)

| ID | Category | File:Line | Resolved In | Description |
|----|----------|-----------|-------------|-------------|
| D1 | Dead Code | types.rs:369 | `D1/M3/M5/A1 fix` | `IGNativeAbi` struct defined but never used — removed |
| D2 | Dead Code | types.rs:62-92 | `439f2b5` | `IGPixelFormat`, `IGColorSpace`, `IGHdrTransferFn` enums removed — were never imported, only raw `i32` literals used |
| D3 | Dead Code | buffer_registry.rs:101-122 | `d9018a3` | `BufferRegistry::contains()` and `len()` gated behind `#[cfg(test)]` |
| D4 | Bloat | types.rs:179-223 | — (OK) | Encode structs exist for ABI contract only — no action needed |
| M1 | Duplication | codec.rs + decode.rs | `e9cfda9` | Duplicate file-read pattern extracted into shared helper |
| M2 | Illogical | decode.rs:77-78 | `e9cfda9` | Misleading cancellation comment corrected |
| M3 | Version Drift | igplugin.json:5 | `D1/M3/M5/A1 fix` | Version SST enforced via check-local.sh gate [5] — `package.sh` generates from Cargo.toml, check-local.sh verifies match |
| M4 | Performance | codec.rs:160 | `e9cfda9` | Metadata load now reads only the 4-byte prefix instead of entire file |
| M5 | Performance | codec.rs:69 | `D1/M3/M5/A1 fix` | `String::from_utf16_lossy` replaced with zero-alloc stack buffer in `can_handle_extension` |
| M6 | Inconsistency | decode.rs:26-28 | `e9cfda9` | `BUFFER_REGISTRY` init pattern aligned with other `OnceLock`s |
| M7 | Stale Comment | codec.rs:174 | `f20a9b6` | "54 profiles" corrected to "53 active" |
| M8 | Stale Comment | decode.rs:385 | `2739461` | "no real fixtures" comment updated — `tests/fixtures/test1.ithmb` exists |
| A1 | Module Size | codec.rs | `D1/M3/M5/A1 fix` | False positive — non-test LOC is 224 (audit incorrectly counted test LOC in total of 438) |
| A2 | Module Size | types.rs | — (OK) | 430 LOC but pure ABI type definitions — no logic, just struct/enum declarations. Acceptable for a types-only module |

## Active (0)

| ID | Category | File:Line | Severity | Effort | Description | Recommendation |
|----|----------|-----------|----------|--------|-------------|----------------|
| — | — | — | — | — | All debts resolved or accepted | — |

## Priority Matrix

_No active debts remaining._

## Looks Bad But Is Fine

1. **`#[allow(dead_code)]` on PluginState (state.rs:53)** — The struct fields are never read after initialization, but they MUST exist to keep the heap-allocated `Vec<u16>` buffers alive. The raw pointers in `plugin_api` and `capability` point into these buffers.

2. **`unsafe impl Send/Sync` on multiple types** — Required because they contain raw pointers not `Send/Sync` by default. Pointed-to data is either immutable static or protected by `Mutex`/`OnceLock`.

3. **`catch_unwind` in every extern "C" function** — Essential: Rust panics unwinding through C ABI is undefined behavior. Each function has different return types and fallback values.

4. **`ig_string_ref_from_str` returns `(Vec<u16>, IGStringRef)`** — The `IGStringRef` borrows from the `Vec<u16>`, so returning both enforces the lifetime at the type level.

5. **Encode types defined but never used** — Required by the `IGCodecApi` function pointer table layout. The ABI contract says these slots must exist even if `None`.

## Open Questions

1. **Cancellation wiring**: Should the plugin wire the host's `is_cancellation_requested` callback to the `AtomicBool` passed to `decode_ithmb`? Currently cancellation is non-functional from the host's perspective.

2. **Profile count**: Verify whether `53 active` is accurate for the current `ithmb-core` version. The comment was updated from 54 to 53 per commit `f20a9b6`.

---

*Last refreshed: 2026-08-28. All 14 debts resolved or accepted. Audited: 9 Rust source files, 5 script files, Cargo.toml, deny.toml, igplugin.json. ~2,418 total lines of Rust, ~1,400 non-test LOC.*
