# FEATURES.md: Standing Feature & Behavior Inventory

> **Backfill note:** this inventory was created at the REVIEW gate (August 2026) for a codebase that shipped before the inventory discipline landed. Every feature below is `applied` (implemented, tested, spec-synced). Tests anchor to features via the Test Anchoring tables; per-test F-### tags are the forward convention. FR-## traceability added to SPECIFICATION.md (§16).

## Lifecycle

```
proposed -> approved -> applied -> archived
```

| Status | Meaning | Can be shipped? |
| --- | --- | --- |
| `proposed` | Intended, not yet ratified into V1 | No |
| `approved` | In V1 scope (IN SCOPE, RULES section 5) | No: needs `applied` |
| `applied` | Implemented, tests anchored, spec-synced | Yes |
| `archived` | Removed/superseded; entry kept for history | No |

## Features

### F-001: C ABI entry point `ig_plugin_get_api`

- **Status:** applied
- **Reviewed:** 2026-08-27

**Behavior Contract:** Preconditions: ImageGlass host loads the cdylib and calls `ig_plugin_get_api` with a pointer to `IGHostApi`. Postconditions: returns a pointer to a populated `IGPluginApi` table on success; returns `null` on null input, ABI version mismatch, or undersized host struct. Invariants: never panics — all paths wrapped in `catch_unwind`. Error cases: null host_api → null; ABI major mismatch → null; struct_size too small → null.

**Test Anchoring:**

| Test file / name | Covers |
|---|---|
| `src/lib.rs::entry_point_rejects_null_host_api` | null host_api → null |
| `src/lib.rs::entry_point_rejects_mismatched_abi_major` | ABI version mismatch → null |
| `src/lib.rs::entry_point_rejects_undersized_host_api` | undersized struct → null |
| `src/lib.rs::entry_point_returns_valid_plugin_api` | valid → populated API table |

### F-002: ABI struct layout contract

- **Status:** applied
- **Reviewed:** 2026-08-27

**Behavior Contract:** Preconditions: plugin compiled with `#[repr(C)]` types. Postconditions: struct sizes match C header exactly (IGCodecApi 112, IGCodecCapability 104, IGAnimationInfo 16, IGAnimationFrameInfo 8, IGImageInfo 24, IGPixelBuffer 48, IGPluginApi 48, IGStatus 16, IGHostCoreApi 112). Invariants: size assertions compile-fail if layout drifts. Error cases: none (compile-time gate).

**Test Anchoring:**

| Test file / name | Covers |
|---|---|
| `src/lib.rs::test_abi_struct_sizes` | struct size assertions |
| `scripts/abi-smoke.py` | cross-language struct size verification |

### F-003: Codec capability query

- **Status:** applied
- **Reviewed:** 2026-08-27

**Behavior Contract:** Preconditions: plugin initialized, valid `IGCodecCapability` output pointer. Postconditions: capability struct filled with codec_id, contract version, codec type (decode-only), codec name (UTF-16), magic bytes, max frame size, animation support flags. Invariants: null output pointer returns `IGStatus::InvalidArg`. Error cases: null output slot → InvalidArg.

**Test Anchoring:**

| Test file / name | Covers |
|---|---|
| `src/codec.rs::capability_rejects_null_output_slot` | null → InvalidArg |
| `src/codec.rs::capability_reports_v110_contract` | valid → full capability fields |

### F-004: Extension matching

- **Status:** applied
- **Reviewed:** 2026-08-27

**Behavior Contract:** Preconditions: file extension string provided. Postconditions: returns 1 for `.ithmb` and `.ipm` (case-insensitive), 0 for all others (including null). Invariants: matching is case-insensitive ASCII fold. Error cases: null extension → 0; unknown extension → 0.

**Test Anchoring:**

| Test file / name | Covers |
|---|---|
| `src/codec.rs::can_handle_extension_matches_known_extensions` | .ithmb/.ipm → 1 |
| `src/codec.rs::can_handle_extension_is_case_insensitive` | mixed case → 1 |
| `src/codec.rs::can_handle_extension_rejects_unmatched_and_empty` | .jpg/null → 0 |

### F-005: Metadata loading with device profile lookup

- **Status:** applied
- **Reviewed:** 2026-08-27

**Behavior Contract:** Preconditions: valid file path, non-null `IGImageInfo` output pointer. Postconditions: width and height populated from the device profile database (53 profiles, 54 prefixes). The lookup first tries the device_profiles fast path (prefix → profile), then falls back to ProfileDb. Invariants: null info pointer → InvalidArg; missing file → IoError; parse_dimensions validates `"WxH"` format. Error cases: null info → InvalidArg; missing file → IoError.

**Test Anchoring:**

| Test file / name | Covers |
|---|---|
| `src/codec.rs::load_metadata_rejects_null_info` | null → InvalidArg |
| `src/codec.rs::load_metadata_missing_file_is_io_error` | missing file → IoError |
| `src/codec.rs::load_metadata_reads_known_profile_fixture` | prefix 1024 → 320×240 |
| `src/codec.rs::test_parse_dimensions` | WxH parse validation |

### F-006: Static raster decode + buffer lifecycle

- **Status:** applied
- **Reviewed:** 2026-08-27

**Behavior Contract:** Preconditions: valid file, `IGImageInfo` with width/height populated, `IGPixelBuffer` output pointer. Postconditions: frame 0 decoded into a registered BGRA buffer; buffer tracked in the global `BufferRegistry` (Mutex<HashMap>). `free_pixel_buffer` zeroes the struct, unregisters, and frees via libc::free. Invariants: null buffer pointer → InvalidArg; nonzero frame index → InvalidArg; double-register is an error. Error cases: null buffer → InvalidArg; frame ≠ 0 → InvalidArg; missing file → IoError.

**Test Anchoring:**

| Test file / name | Covers |
|---|---|
| `src/decode.rs::decode_rejects_null_buffer` | null buffer → InvalidArg |
| `src/decode.rs::decode_rejects_nonzero_frame_index` | frame 1 → InvalidArg |
| `src/decode.rs::decode_missing_file_is_io_error` | missing file → IoError |
| `src/decode.rs::decode_roundtrips_encoded_fixture` | encode+decode roundtrip |
| `src/buffer_registry.rs::register_and_contains` | register + lookup |
| `src/buffer_registry.rs::register_double_is_error` | double register → error |
| `src/buffer_registry.rs::unregister_removes_entry` | unregister removes |
| `src/buffer_registry.rs::unregister_unknown_is_error` | unknown unregister → error |
| `src/buffer_registry.rs::empty_registry` | empty → len 0 |
| `src/buffer_registry.rs::multiple_entries` | 3 entries → correct state |
| `src/buffer_registry.rs::null_pointer_is_valid_key` | null key → valid |

### F-007: Decoder never panics on hostile input

- **Status:** applied
- **Reviewed:** 2026-08-27

**Behavior Contract:** Preconditions: arbitrary byte slices (up to 3000 mutations per seed). Postconditions: every mutation decodes to `Ok` or `Err` — never unwinds. Invariants: `catch_unwind` wraps the entire decode path; the pseudo-fuzz harness validates 3000 mutations per seed with seed `0x5EED_2026_1B8E_F00D`. Error cases: none (property: no panic).

**Test Anchoring:**

| Test file / name | Covers |
|---|---|
| `src/decode.rs::fuzz::mutated_inputs_never_panic_the_decoder` | 3000-mutation pseudo-fuzz |

### F-008: ABI smoke test (integration)

- **Status:** applied
- **Reviewed:** 2026-08-27

**Behavior Contract:** Preconditions: cdylib built for the host platform. Postconditions: Python script loads the cdylib, calls `ig_plugin_get_api` with a valid host API, exercises the full codec path (capability, extension, metadata, decode), and asserts exit code 0. Invariants: runs on Linux in CI and in check-local.sh. Error cases: any failure → non-zero exit.

**Test Anchoring:**

| Test file / name | Covers |
|---|---|
| `scripts/abi-smoke.py` | full C ABI path without GUI |

### F-009: Packaging as .igplugin.zip

- **Status:** applied
- **Reviewed:** 2026-08-27

**Behavior Contract:** Preconditions: release build completed for the target OS. Postconditions: `package.sh` produces a `.igplugin.zip` containing the cdylib + manifest, named per platform convention. Invariants: package is uploaded as a CI artifact on release-on-tag. Error cases: build failure → package not created.

**Test Anchoring:**

| Test file / name | Covers |
|---|---|
| `scripts/package.sh` | packaging script |
| `.github/workflows/ci.yml` (build job) | CI artifact upload verification |

### F-010: CI gates

- **Status:** applied
- **Reviewed:** 2026-08-27

**Behavior Contract:** Preconditions: code pushed or tag created. Postconditions: 5 CI jobs run — build×3OS (symbol export verify, ABI smoke, package), verify_clippy (clippy + test), verify_deny (license/ban audit), secrets (gitleaks), release-on-tag (upload + GitHub Release). Invariants: any job failure blocks merge. Error cases: clippy warnings, test failures, deny violations, or leaked secrets → CI red.

**Test Anchoring:**

| Test file / name | Covers |
|---|---|
| `.github/workflows/ci.yml` (all 5 jobs) | full CI gate suite |
| `scripts/check-local.sh` | local CI parity |

## Relationship to other artifacts

| Artifact | Role | Static or living? |
| --- | --- | --- |
| **SPECIFICATION.md** | The plan-IS-spec: how the system is built | Static (locked) |
| **FEATURES.md** | The reference of what exists + how it behaves | **Living** |
| **docs/PROJECT_MODEL.md** | Whole-project state machine (valid transitions, invariants) | Living |
| **EXPLAINER.md** | Code explainer for the owner | Living |
| **Tests** | Prove the contracts | Living |

SPECIFICATION says how it is built; FEATURES says what it does and what "working" means. They describe the same system at different levels: FEATURES is the differential that stays true as the code evolves.

## Status Legend

- **proposed**: drafted at AMBITION, not yet approved
- **approved**: in V1 scope, locked at SPECIFICATION
- **applied**: implemented, tests anchored, spec-synced
- **archived**: previously applied, now out of scope with a recorded reason
