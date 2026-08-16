# Changelog

# Changelog

## v1.1.3 (2026-08-16) — Update ithmb-core to 1.9.9

### Changed
- **ithmb-core 1.9.6 → 1.9.9**: JPEG decoding migrated from the maintenance-mode `jpeg-decoder` to `zune-jpeg` 0.5.15 (actively maintained, SIMD-accelerated). Pixel output is equivalent (±1-3/255 IDCT rounding variance — standards-compliant; grayscale JPEGs now decode correctly). The CWE-400 oversized-frame guard is preserved.
- Version bumped to 1.1.3 (Cargo.toml, igplugin.json, state.rs).

### Notes
- Cargo.lock regenerated against the crates.io index (pins ithmb-core 1.9.9).

## v1.1.1 (2026-08-14) — Update ithmb-core to 1.9.6

### Changed
- **ithmb-core 1.9.5 → 1.9.6**: ships the Nano 7G cover-art alternates fix,
  reordered-RGB555 endianness fix, `swaps_dimensions` encoder fix, and profile
  1044 disablement (53 active profiles) from the upstream codec release.
- Version bumped to 1.1.1 (Cargo.toml, igplugin.json, state.rs).

### Notes
- Cargo.lock regenerated against the crates.io index (pins ithmb-core 1.9.6).

## v1.1.0 (2026-08-06) — SDK v1.1.0 ABI port & hardening

### Changed
- **SDK v1.1.0 ABI port (decode-only)**: `IGCodecApi` is now StructSize-first
  (112-byte table, 13 function pointers incl. 4 encode pointers, all null).
  GetCapability now returns a plugin-allocated `IGCodecCapability` by pointer.
- **IGCodecCapability**: rewritten StructSize-first to the exact v1.1.0 field
  order (decode flags, extension count/pointers, encode flags, null encode
  extensions).
- **IGAnimationInfo**: corrected to `{frame_count, loop_count, frames}` with
  the new `IGAnimationFrameInfo` element type.
- **IGStatus**: added `EncodeFailed = 9`.
- **IGImageInfo.IccProfileData**: now `*const u8` per the official header.
- Version bumped to 1.1.0 (Cargo.toml, igplugin.json, lib.rs).

### Security
- File reads pre-checked via `fs::metadata` before `fs::read` (reject >8 MiB
  with `DecodeFailed` before allocating).
- `stride`/`buf_size` computed with checked arithmetic (`OutOfMemory` on
  overflow).
- `can_handle_extension` fully wrapped in `catch_unwind` (host logging inside
  the guarded region).
- Cargo.lock committed + `rust-toolchain.toml` (1.88.0) for reproducible builds.
- CI actions SHA-pinned; dependabot removed.

### Structure
- `lib.rs` split into `codec.rs`, `decode.rs`, `state.rs`, `strings.rs`
  (all modules under the 250-LOC non-test ceiling).
- 16 new tests: ABI contract, entry-point validation, decode paths, and a
  deterministic pseudo-fuzz harness (mutated inputs never panic the decoder).

### Notes
- Requires ImageGlass build 10.0.3.805+ (host validates `IGCodecApi.StructSize`).


## v1.0.0 (2026-07-13) — Fixed plugin manifest & ABI

### Fixed
- **igplugin.json**: Set correct executable name (was `unset`, now per-platform so ImageGlass can load the native codec)
- **Critical ABI fix**: Rewrote FFI layer to match C# SDK struct layouts exactly
  (IGCodecApi had phantom struct_size/abi_version fields, wrong function signatures,
  entry point signature was missing host API parameter)
- `ig_plugin_get_api` now takes `(hostAbiVersion, hostApi)` per C# signature
- GetCodec returns IGStatus via output pointer instead of direct pointer return
- All codec callbacks now use IGStringRef by value (not by pointer)
- Initialize/Shutdown take no arguments
- Added null animation function pointers to match struct layout
- FreePixelBuffer returns void (was returning IGStatus)
- Capability flags: SupportsMetadata=1, SupportsStaticRaster=1,
  SupportsColorProfiles=0, SupportsAnimation=0
- Fixed codec priority to 200 (was 0, losing selection to Magick.NET)
- Removed broken magic signature check (ithmb has no header magic)
Initial ImageGlass v10 native codec plugin for decoding Apple `.ithmb` thumbnail files.

### Features
- Decodes `.ithmb` and `.ipm` files natively in ImageGlass v10
- 54 SIMD-optimized processing profiles via ithmb-core
- Supports cancellation, multi-frame, and thread-safe decoding
- Cross-platform: Windows, macOS, Linux

### Packaging
- `.igplugin.zip` format for ImageGlass v10 plugin manager
- Install via Settings -> Plugins -> Add
- Pre-compiled binaries for all 3 platforms in GitHub Releases
