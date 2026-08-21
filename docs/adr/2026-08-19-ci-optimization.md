# ADR-0001: CI optimization — pinned prebuilt tools, unit tests, Windows export verification

**Status:** Accepted (2026-08-19)

## Context

The plugin's CI ran five jobs on every push/PR (build ×3-OS, verify_clippy,
verify_deny, secrets, release-on-tag). Three inefficiencies and one coverage
gap were identified during the family-wide CI review:

1. **verify_deny used `EmbarkStudios/cargo-deny-action` (Docker)**: the action
   re-installs the pinned toolchain (~80-150MB) and re-clones the RustSec
   advisory DB (~30-50MB) into a fresh container on *every* run, and the
   runner-side `setup-rust-toolchain` step feeding it was 100% unused. The
   prebuilt `cargo-deny` musl binary is byte-identical to what the action
   downloads and runs standalone.
2. **CI ran zero `cargo test`**: `cargo clippy --all-targets` only type-checks
   the ~15+ unit tests in `src/` (decode.rs, buffer_registry.rs, lib.rs); none
   were ever executed on GitHub. This was the largest problem-finding gap.
3. **The Windows build verified nothing**: symbol export verification (`nm -D`
   / `nm -gU`) was skipped on Windows — the DLL for the primary runtime
   platform (ImageGlass is Windows-only) shipped unverified, so a vanished
   `ig_plugin_get_api` export would pass CI and break every ImageGlass user.

**Decision**

1. Replace the `cargo-deny-action` Docker job with a direct pinned-binary
   download: `curl` the `cargo-deny-0.20.2-x86_64-unknown-linux-musl.tar.gz`
   release asset, extract with `--strip-components=1`, run
   `/tmp/cargo-deny --log-level warn --manifest-path ./Cargo.toml --all-features check`.
   Delete the now-unused `setup-rust-toolchain` step in that job. The URL pins
   the exact release version, matching the gitleaks pinned-binary pattern
   already used in this repo's secrets job.
2. Add `cargo test` to the existing `verify_clippy` job (same dev-profile
   cache), executing all unit tests on every run.
3. Add a Windows PE export-table check: a pure-PowerShell parser reads the DLL
   bytes, locates the export directory via the PE header, and asserts
   `ig_plugin_get_api` is present in `AddressOfNames`. No external tools, ~2-5s.
4. Add `[profile.dev.package."*"] debug = "line-tables-only"` to `Cargo.toml`:
   line tables preserve backtrace `file:line` resolution while dropping full
   DWARF from dependencies. The dependency tree is tiny (~8 packages), so the
   saving is small (~3-10s on clippy) but consistent with the parent repo
   (Ithmb-Codec ADR-0008).

**Consequences**

- Positive: verify_deny ~30-60s faster per cold run, ~10-30s warm; unit tests
  now execute in CI; Windows DLL exports verified before release; supply-chain
  posture unchanged (same binary, tighter pinning — version in URL is explicit).
- Negative: none. The Docker action's container isolation is not needed here —
  the binary is the same upstream artifact the action itself downloads.
- Neutral: this ADR establishes the plugin's ADR practice at `docs/adr/`,
  matching the convention used by the parent Ithmb-Codec repo.

**Related**

- Ithmb-Codec ADR-0008 (CI optimization — pinned prebuilt tools, dep debug
  stripping, full fuzz coverage)
- gitleaks pinned-binary-curl precedent in this repo's secrets job
