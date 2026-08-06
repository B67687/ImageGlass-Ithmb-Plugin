# AGENTS.md — AI Agent Guide for ImageGlass-Ithmb-Plugin

This file tells AI coding agents how to work with this repository. Read this first before editing any code.

## Repository Purpose

C ABI shared library plugin for [ImageGlass v10](https://imageglass.org) that enables decoding Apple `.ithmb` thumbnail files. This is a **thin FFI wrapper** around the core decoding library in `ithmb-core`.

## Architecture

```
ImageGlass (cross-platform Avalonia UI)
    ↓ ig_plugin_get_api()
ImageGlass-Ithmb-Plugin (C ABI cdylib)
    ↓ FFI
ithmb-core (Rust library, loaded as shared lib)
    ithmb-core (Rust library, loaded as shared lib, decode-only)
    ↔ 8 decoders, 54 profiles, PhotoDB (no encoder)
```

## Key Facts

- **Language**: Rust (cdylib)
- **ABI**: ImageGlass v10 native codec plugin (SDK v1.1.0)
- **Platforms**: Linux, macOS, Windows (CI builds all 3)
- **Memory rule**: Plugin allocates pixel buffers via its own allocator (`libc::malloc`), not the host allocator. Whoever allocates, frees.
- **Buffer tracking**: `BufferRegistry` in `buffer_registry.rs` tracks live pixel buffers to prevent double-free and use-after-free.
- **Build**: `cargo build --release`, then `./scripts/package.sh [linux|macos|windows]` produces `.igplugin.zip`
- **CI**: GitHub Actions builds + clippy + deny for all 3 platforms on every push, automatically creates releases on `v*` tags
- **Dependency**: [`ithmb-core`](https://github.com/B67687/Ithmb-Codec)

## Why `unsafe_code = "allow"`

`Cargo.toml` sets `[lints.rust] unsafe_code = "allow"` — deliberately. This
crate is a C ABI cdylib whose entire surface is `extern "C"` entry points;
every exported function is `unsafe` by contract because the host (ImageGlass)
calls across the FFI boundary with raw pointers it owns. The `unsafe` blocks
inside are the bridge, and each carries a `// SAFETY:` comment stating the
invariants it relies on (null checks, struct layout, ownership). Denying the
lint would flag the ABI surface itself — the point of the crate. The other
lints stay strict: `unused_crate_dependencies` and clippy `all` + `pedantic`
are deny.

## SDK v1.1.0 Contract

The plugin implements the ImageGlass SDK v1.1.0 codec contract:

- **Decode-only** — `IGCodecApi` exposes decode; the encode function pointers
  are null. Encoding is deliberately deferred: it would require an ithmb
  *encoder* in `ithmb-core`, which does not exist yet (the upstream crate
  decodes raw formats and synthesizes samples; it has no production encoder).
- **StructSize-validated** — `IGCodecApi` and `IGCodecCapability` carry
  `StructSize` as the first field; the plugin validates it on entry before
  touching any other field, so a host/plugin SDK version mismatch fails safely
  instead of reading garbage.
- **Two-argument entry** — `ig_plugin_get_api(int32_t host_abi_version, const
  IGHostApi* host_api)` (the one-argument form is the pre-1.1.0 ABI).
- **Entry-point safety** — every FFI entry runs inside `catch_unwind` so a Rust
  panic cannot unwind across the C boundary.

## Plugin Files

| Path | Purpose |
|------|---------|
| `src/lib.rs` | C ABI entry point, plugin lifecycle, API table construction |
| `src/codec.rs` | Codec capability, extension matching, metadata loading |
| `src/decode.rs` | Static-raster decode, pixel-buffer free, buffer registry access |
| `src/state.rs` | Plugin state, statics (OnceLocks), initialization |
| `src/strings.rs` | UTF-16 conversion helpers |
| `src/allocator.rs` | `pixel_buffer_alloc`/`pixel_buffer_free` wrappers (own allocator, not host) |
| `src/buffer_registry.rs` | Thread-safe HashMap tracking live pixel allocations |
| `src/types.rs` | `#[repr(C)]` ABI type definitions mirroring ImageGlass C# SDK structs |
| `src/logging.rs` | Thin wrapper around host logging callback |
| `igplugin.json` | Plugin manifest (id, name, executable, kind) |
| `scripts/package.sh` | Build + package into `.igplugin.zip` per platform |

## load_metadata Flow

1. Read 4-byte format prefix from file
2. Try `device_profiles::find_formats_by_id()` (fast path, ~41 of 54 profiles)
3. If not found, fall back to `ProfileDb::load_builtin() + get(prefix)` (all 54 profiles)
4. Return correct dimensions or `NotImplemented`

## free_pixel_buffer Safety

- Always clears buffer struct fields first (prevents ImageGlass from accessing stale pointers)
- Checks `BufferRegistry` before freeing
- Uses own allocator (`allocator::pixel_buffer_free`) — NOT the host allocator
- Safe during shutdown: host allocator may have been torn down, but our allocator is always available

## Relationship to Ithmb-Codec

All decoding logic is in the main [`Ithmb-Codec`](https://github.com/B67687/Ithmb-Codec) repo. This plugin is the C ABI glue layer. Changes to decoding behavior belong in the upstream crate, not here.

## For Agents

- This is a thin wrapper — all decode logic is in the `ithmb-core` dependency.
- The `#[repr(C)]` ABI types in `types.rs` must match ImageGlass's C# SDK structs exactly.
- `git commit` uses `-S` (GPG sign). Author date is preserved via `GIT_COMMITTER_DATE`.
- CI enforces `#[deny(clippy::pedantic)]` — run `cargo clippy --fix` before pushing.
- Releases are created by pushing a `v*` tag — CI builds all 3 platforms and publishes.
