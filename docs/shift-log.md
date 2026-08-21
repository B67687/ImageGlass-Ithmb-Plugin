# Shift Log

Learning shifts recorded per RULES.md section 5. Up to 5 shifts per project. Each shift is a documented discovery that changed direction during WORK or hardening.

---

LEARNING SHIFT
  What we learned: The v1.0.0 ABI surface did not match the ImageGlass SDK v1.1.0 contract: IGCodecApi had phantom struct_size/abi_version fields, wrong function signatures, and the entry point was missing the host API parameter. The host could not safely read the tables.
  Decision: Ported the whole FFI layer to the SDK v1.1.0 contract: StructSize-first tables, plugin-allocated IGCodecCapability returned by pointer, corrected IGAnimationInfo layout, two-argument entry point, and a module split of lib.rs into codec.rs, decode.rs, state.rs, strings.rs.
  Cost: A full ABI rewrite and 16 new tests (v1.1.0 milestone).
  What this enables: A host/plugin version mismatch now fails safely via StructSize validation instead of reading garbage, and the module split keeps every file under the 250-LOC ceiling.

---

LEARNING SHIFT
  What we learned: A Rust panic unwinding through an extern "C" boundary is undefined behavior and aborts the host process. The plugin's entry points could panic on hostile input (e.g. an absurd IGStringRef length in the logging path).
  Decision: Wrapped every FFI entry point body in std::panic::catch_unwind, mapping any panic to IGStatus::Internal, and added host ABI struct-size validation at the entry point (commit 86e6745).
  Cost: A small per-call overhead and a deliberate unsafe_code = "allow" lint with SAFETY comments on every block.
  What this enables: The plugin can never crash ImageGlass; a hostile or malformed input degrades to an error status the host can surface.

---

LEARNING SHIFT
  What we learned: The built-in profile database shipped 54 profiles, but prefix 1044 produced wrong output for its device model (iOpenPod #81).
  Decision: Disabled prefix 1044, leaving 53 active profiles, and shipped the change with the ithmb-core 1.9.6 bump (v1.1.1).
  Cost: Files from the affected device model are not decoded until the profile is fixed upstream.
  What this enables: Every decoded file is now correct; the plugin no longer silently renders wrong dimensions for a real device.

---

LEARNING SHIFT
  What we learned: CI ran five jobs on every push but never executed a single unit test, the Windows DLL shipped unverified, and the cargo-deny Docker action reinstalled the toolchain and advisory DB on every run.
  Decision: ADR-0001: added cargo test to verify_clippy, added a Windows PE export-table check, and replaced the Docker action with a pinned prebuilt cargo-deny binary (0.20.2 musl).
  Cost: ~30-60s of one-time setup per job replaced by a direct download; a hardcoded version URL that must be bumped deliberately.
  What this enables: Unit tests now execute in CI, the primary runtime platform (Windows) has its exports verified before release, and supply-chain checks run faster with the same posture.

---

LEARNING SHIFT
  What we learned: The standards audit found 40 failures across the repo, mostly documentation and governance gaps that the code itself did not cause.
  Decision: Fixed the audit failures in a dedicated hardening pass, reducing them from 40 to 9, and added the unified local check gate (check-local.sh) plus the local/GitHub parity gate (check-parity.sh) so the same gates run locally and in CI.
  Cost: A dedicated hardening milestone with no new features.
  What this enables: The repo now passes the audit's remaining gates, and the parity gate guarantees local and CI results agree on the same commit before any push.