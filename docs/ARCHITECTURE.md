# ARCHITECTURE.md: System Architecture

> Created at REVIEW gate (August 2026). Describes the plugin boundary, internal module structure, and fitness functions.

## System Context (C4 Level 1)

```
┌─────────────────────────────────────────────────────┐
│                  ImageGlass Host (C#)                │
│  ┌───────────────────────────────────────────────┐  │
│  │  Plugin Loader (via C ABI: dlopen / LoadLibrary)│ │
│  └──────────────────────┬────────────────────────┘  │
│                         │ calls ig_plugin_get_api()  │
│                         ▼                            │
│  ┌───────────────────────────────────────────────┐  │
│  │  IGPluginApi table (function pointers)         │  │
│  │  → codec_init → codec_can_handle_extension     │  │
│  │  → codec_load_metadata → codec_decode_frame    │  │
│  │  → codec_free_pixel_buffer                     │  │
│  └───────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────┘
                         │ FFI boundary (#[repr(C)])
                         ▼
┌─────────────────────────────────────────────────────┐
│            ithmb-core-cabi (this plugin)            │
│                                                     │
│  ┌─────────┐  ┌──────────┐  ┌────────────────┐     │
│  │  lib.rs │  │ codec.rs │  │   decode.rs    │     │
│  │ (entry) │  │ (query)  │  │  (rasterize)   │     │
│  └────┬────┘  └────┬─────┘  └───────┬────────┘     │
│       │            │                │               │
│  ┌────▼────┐  ┌────▼─────┐  ┌──────▼────────┐     │
│  │state.rs │  │strings.rs│  │buffer_registry│     │
│  │(statics)│  │(UTF-16)  │  │  (HashMap)    │     │
│  └────┬────┘  └──────────┘  └───────┬────────┘     │
│       │                             │               │
│  ┌────▼──────────┐          ┌───────▼────────┐     │
│  │logging.rs     │          │allocator.rs    │     │
│  │(IGHost logger)│          │(libc malloc)   │     │
│  └───────────────┘          └────────────────┘     │
│                                                     │
│  ┌──────────────────────────────────────────────┐   │
│  │            ithmb-core (dependency)           │   │
│  │  ProfileDb, device_profiles, decode, encode  │   │
│  └──────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────┘
```

## Module Map

| Module | LOC | Responsibility |
|--------|-----|----------------|
| `src/lib.rs` | 316 | C ABI entry point (`ig_plugin_get_api`), plugin lifecycle |
| `src/types.rs` | 430 | `#[repr(C)]` ABI types, helper functions, status conversion |
| `src/codec.rs` | 420 | Capability query, extension matching, metadata loading |
| `src/decode.rs` | 482 | Static raster decode, buffer allocation, pseudo-fuzz harness |
| `src/buffer_registry.rs` | 223 | Thread-safe buffer tracking (Mutex<HashMap>) |
| `src/state.rs` | 261 | OnceLock statics, initialization, capability builder |
| `src/strings.rs` | 23 | UTF-16 encode/decode for ABI string refs |
| `src/allocator.rs` | 35 | libc malloc/free wrappers |
| `src/logging.rs` | 177 | Logger wrapping IGHostCoreApi::log |
| `src/file_io.rs` | 51 | File read helpers (full and prefix-only) |
| **Total** | **~2418** | |

## Data Flow

```
Host calls ig_plugin_get_api(host_api)
  → lib.rs: validate ABI, store HOST_API
  → returns IGPluginApi with function pointers

Host calls codec_init()
  → state.rs: ensure_initialized()
    → build_capability() → populate CAPABILITY
    → init extensions → populate PLUGIN_EXTENSIONS

Host calls codec_can_handle_extension(ext)
  → codec.rs: case-insensitive match (.ithmb, .ipm)

Host calls codec_load_metadata(path, info)
  → codec.rs: parse file prefix → lookup device_profiles → fill width/height

Host calls codec_decode_frame(path, info, buffer)
  → decode.rs: read file → dispatch to ithmb-core decode → fill BGRA buffer
  → buffer_registry.rs: register buffer pointer

Host calls codec_free_pixel_buffer(buffer)
  → buffer_registry.rs: unregister
  → allocator.rs: libc::free
  → zero the IGPixelBuffer struct
```

## Fitness Functions

| Metric | Threshold | Enforced by |
|--------|-----------|-------------|
| File LOC | ≤ 250 (non-test, non-generated) | `check-local.sh` wc -l gate |
| Function LOC | ≤ 40 | Manual review + clippy |
| Cyclomatic complexity | ≤ 10 | clippy (metadata complexity lint) |
| unwrap() in non-test src | 0 | `check-local.sh` grep gate |
| Panic in FFI | 0 | catch_unwind + fuzz test (F-007) |
| CI all-green | Required | `.github/workflows/ci.yml` |

### Current fitness status

| File | LOC | ≤250? | Status |
|------|-----|-------|--------|
| src/lib.rs | 316 | No | ⚠️ Over threshold (see TECH_DEBT_AUDIT.md A1) |
| src/types.rs | 430 | No | ⚠️ Over threshold (see TECH_DEBT_AUDIT.md A1) |
| src/codec.rs | 420 | No | ⚠️ Over threshold (see TECH_DEBT_AUDIT.md A1) |
| src/decode.rs | 482 | No | ⚠️ Over threshold (see TECH_DEBT_AUDIT.md A1) |
| src/buffer_registry.rs | 223 | Yes | ✅ |
| src/state.rs | 261 | No | ⚠️ Over threshold (see TECH_DEBT_AUDIT.md A2) |
| src/strings.rs | 23 | Yes | ✅ |
| src/allocator.rs | 35 | Yes | ✅ |
| src/logging.rs | 177 | Yes | ✅ |
| src/file_io.rs | 51 | Yes | ✅ |

## Local vs GitHub CI Split

| Gate | Local (`check-local.sh`) | GitHub CI (`.github/workflows/ci.yml`) |
|------|--------------------------|----------------------------------------|
| Clippy | `cargo clippy -- -D warnings` | ✅ verify_clippy job |
| Unit tests | `cargo test` | ✅ verify_clippy job |
| Release build | `cargo build --release` | ✅ build job (3 OS) |
| Symbol export | `nm -D` check | ✅ build job |
| ABI smoke | `abi-smoke.py` | ✅ build job |
| Package | `package.sh` | ✅ build job (artifact upload) |
| cargo-deny | `cargo deny check` | ✅ verify_deny job |
| gitleaks | `gitleaks detect` | ✅ secrets job |
| F-### anchor grep | `check-local.sh` | ❌ Not in CI |
| wc -l fitness | `check-local.sh` | ❌ Not in CI |
| Release-on-tag | ❌ Local only | ✅ release-on-tag job |
