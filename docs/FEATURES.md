# FEATURES.md: Feature / Behavior Inventory

> The standing feature inventory for Imageglass-Ithmb-Plugin. Every IN SCOPE item is an `approved` entry. Every `applied` feature has linked tests (test anchoring per RULES.md section 9). Statuses: proposed / approved / applied / archived.

## Feature Entries

| ID | Feature | Status | Intent (one line) | Linked tests |
|----|---------|--------|--------------------|--------------|
| F-001 | C ABI entry point `ig_plugin_get_api` | applied | Return a valid IGPluginApi table, or null on ABI mismatch / null / undersized host | lib.rs: entry_point_rejects_null_host_api, entry_point_rejects_mismatched_abi_major, entry_point_rejects_undersized_host_api, entry_point_returns_valid_plugin_api |
| F-002 | ABI struct layout contract | applied | Struct sizes match the C header exactly (IGCodecApi 112, IGCodecCapability 104, IGAnimationInfo 16, IGAnimationFrameInfo 8) | lib.rs: test_abi_struct_sizes; scripts/abi-smoke.py struct_size assertions |
| F-003 | Codec capability query | applied | Return the plugin-allocated IGCodecCapability advertising decode-only support | codec.rs: capability_rejects_null_output_slot, capability_reports_v110_contract |
| F-004 | Extension matching | applied | Return 1 for .ithmb and .ipm (case-insensitive), 0 otherwise | codec.rs: can_handle_extension_matches_known_extensions, can_handle_extension_is_case_insensitive, can_handle_extension_rejects_unmatched_and_empty |
| F-005 | Metadata loading | applied | Fill IGImageInfo dimensions from the profile database (device profiles fast path, ProfileDb fallback) | codec.rs: load_metadata_rejects_null_info, load_metadata_missing_file_is_io_error, load_metadata_reads_known_profile_fixture, test_parse_dimensions |
| F-006 | Static raster decode + buffer lifecycle | applied | Decode frame 0 into a registered BGRA buffer; free zeroes the struct, unregisters, and frees | decode.rs: decode_rejects_null_buffer, decode_rejects_nonzero_frame_index, decode_missing_file_is_io_error, decode_roundtrips_encoded_fixture; buffer_registry.rs: all 7 tests |
| F-007 | Decoder never panics on hostile input | applied | 3000 mutated inputs decode to Ok or Err, never unwind | decode.rs fuzz: mutated_inputs_never_panic_the_decoder |
| F-008 | ABI smoke test | applied | Drive the real C entry point through the full codec path without the GUI | scripts/abi-smoke.py (integration, runs in CI on Linux and in check-local.sh) |
| F-009 | Packaging as .igplugin.zip | applied | Build and package the cdylib + manifest for linux/macos/windows | scripts/package.sh (verified by CI artifact upload) |
| F-010 | CI gates | applied | 3-OS build + symbol export verify, clippy, test, deny, gitleaks, release-on-tag | .github/workflows/ci.yml (all 5 jobs) |

## Trace Tags

Tests reference their feature ID in the test name or module doc comment. A test proving no feature contract is flagged, not silently carried. An `applied` feature with no linked test is untested intent and blocks at REVIEW.

## Status Legend

- **proposed**: drafted at AMBITION, not yet approved
- **approved**: in V1 scope, locked at SPECIFICATION
- **applied**: implemented and shipped
- **archived**: previously applied, now out of scope with a recorded reason