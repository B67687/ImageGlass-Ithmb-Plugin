# TECH_DEBT_AUDIT.md — ImageGlass-Ithmb-Plugin

> **Generated:** 2026-09-02 | **HEAD:** main | **Method:** 9-dim audit (grep + ast-grep + cargo) | **Auditor:** Sisyphus
> **Stack:** Rust cdylib (ImageGlass v10 ABI), ithmb-core 1.9.x | **LOC:** ~2,418 Rust (~1,400 non-test)

## Executive Summary

Health is **excellent (9.5/10)** — small focused cdylib, 0 active debt. Every `extern \"C\"` is `catch_unwind`-wrapped, every `unsafe` has `// SAFETY:`, C ABI sizes validated, 28 unit tests + deterministic pseudo-fuzz. 14/14 prior findings resolved or accepted. No `TODO`/`FIXME`, no `as any` equivalent, `npm audit` N/A, `cargo audit` clean.

## Mental Model

Thin FFI layer `ithmb-core-cabi` wraps `ithmb-core` into a cdylib implementing ImageGlass v10 plugin ABI. Host calls `ig_plugin_get_api(host_abi, host_api)` → function table → one codec for `.ithmb`/`.ipm`. Self-allocates via `libc::malloc`, tracked in `Mutex<HashMap>` `BufferRegistry`, freed on `free_pixel_buffer`. Lifetime state behind `OnceLock`s for pointer stability.

## Resolved (14)

| ID  | Category      | File:Line                  | Resolved In | Description                                |
| --- | ------------- | -------------------------- | ----------- | ------------------------------------------ |
| D1  | Dead Code     | types.rs:369               | D1/M3/M5/A1 | `IGNativeAbi` unused — removed             |
| D2  | Dead Code     | types.rs:62-92             | 439f2b5     | `IGPixelFormat` etc. enums dead — removed  |
| D3  | Dead Code     | buffer_registry.rs:101-122 | d9018a3     | `contains`/`len` → `#[cfg(test)]`          |
| D4  | Bloat         | types.rs:179-223           | —           | Encode structs for ABI contract — accepted |
| M1  | Duplication   | codec.rs + decode.rs       | e9cfda9     | File-read helper extracted                 |
| M2  | Illogical     | decode.rs:77-78            | e9cfda9     | Cancellation comment fixed                 |
| M3  | Version Drift | igplugin.json:5            | D1/M3/M5/A1 | SST via check-local.sh gate 5              |
| M4  | Performance   | codec.rs:160               | e9cfda9     | Metadata now reads 4-byte prefix only      |
| M5  | Performance   | codec.rs:69                | D1/M3/M5/A1 | `from_utf16_lossy` → zero-alloc stack buf  |
| M6  | Inconsistency | decode.rs:26-28            | e9cfda9     | `BUFFER_REGISTRY` `OnceLock` aligned       |
| M7  | Stale Comment | codec.rs:174               | f20a9b6     | \"54 profiles\" → \"53 active\"            |
| M8  | Stale Comment | decode.rs:385              | 2739461     | \"no fixtures\" → `test1.ithmb` exists     |
| A1  | Module Size   | codec.rs                   | D1/M3/M5/A1 | False positive — 224 non-test LOC          |
| A2  | Module Size   | types.rs                   | —           | 430 LOC pure ABI types — accepted          |

## Active (0) — 2026-09-02 rescan clean

| ID  | Category | File:Line | Severity | Effort | Description                    | Recommendation |
| --- | -------- | --------- | -------- | ------ | ------------------------------ | -------------- |
| —   | —        | —         | —        | —      | All debts resolved or accepted | —              |

9-dim rescan: 0 `unsafe` hygiene issues (all `SAFETY:` + `Send/Sync` justified), 0 empty `catch`, 0 `SELECT`/`innerHTML`/`eval`, 0 `await` loops, 0 hardcoded secrets, binary ~same.

## Looks Bad But Is Fine

1. **`#[allow(dead_code)]` on PluginState (state.rs:53)** — Fields unread but must live to keep `Vec<u16>` buffers alive for raw pointers in `plugin_api`/`capability`.
2. **`unsafe impl Send/Sync`** — Raw pointers not `Send` by default; data is immutable or `Mutex`/`OnceLock`-guarded.
3. **`catch_unwind` in every `extern \"C\"`** — Required; unwinding through C is UB, each has different fallback.
4. **`ig_string_ref_from_str → (Vec<u16>, IGStringRef)`** — Lifetime enforced at type level (`IGStringRef` borrows `Vec`).
5. **Encode types defined never used** — Required by `IGCodecApi` function-table layout (`None` slots).

## Open Questions

1. **Cancellation wiring** — Wire host `is_cancellation_requested` to `AtomicBool` in `decode_ithmb`? Currently non-functional from host.
2. **Profile count** — Verify \"53 active\" still matches current `ithmb-core` version.

---

_Last refreshed: 2026-09-02. Audited: 9 Rust source files, 5 scripts, Cargo.toml, deny.toml, igplugin.json. ~2,418 LOC._
