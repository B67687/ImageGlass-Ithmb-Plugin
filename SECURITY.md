# Security Policy

## Scope

This policy covers the **ImageGlass-Ithmb-Plugin** repository — the ImageGlass v10 native codec plugin that decodes Apple `.ithmb` thumbnail files. The plugin is a thin C ABI layer over the Rust `ithmb-core` codec.

## Reporting a Vulnerability

If you discover a security issue in this plugin, please report it privately:

- **Email**: enterprise@ithmb-codec.dev
- **Response**: We aim to acknowledge within 48 hours and provide a fix timeline within 5 business days.

## Security Properties

### Decode-only surface

- The plugin never encodes. The SDK v1.1.0 `IGCodecApi` encode function pointers are null, so no plugin code path can write image data.
- File parsing happens in `ithmb-core` — memory-safe Rust; the only unsafe code there is audited SIMD intrinsics and the C ABI bindings.

### File-size pre-check

- Every decode request is rejected up front when the source file exceeds the 8 MiB pre-check limit, before any parsing begins. ImageGlass thumbnails are small by construction; oversized inputs are refused, not parsed.

### FFI entry safety

- Every `extern "C"` entry point runs inside `catch_unwind`, so a Rust panic never unwinds across the C boundary into ImageGlass.

### Ownership model

- Pixel buffers are allocated by the plugin (via its own allocator, `libc::malloc`) and freed by the plugin — never by the host. Whoever allocates, frees.
- The `BufferRegistry` tracks live pixel allocations to prevent double-free and use-after-free.

## Acknowledgments

We believe in coordinated disclosure. Contributors who report valid issues will be credited in our acknowledgments (with consent).
