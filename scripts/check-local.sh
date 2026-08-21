#!/usr/bin/env bash
# check-local.sh — the full local CI for the ImageGlass Ithmb plugin.
#
# One command runs every local-movable gate the GitHub CI runs, locally:
#
#   1. cargo clippy   (matches CI verify_clippy, -D warnings)
#   2. cargo test     (matches CI verify_clippy)
#   3. cargo build --release + symbol export verify + ABI smoke (matches CI build, Linux)
#   4. cargo-deny     (matches CI verify_deny, pinned musl binary)
#   5. gitleaks       (matches CI secrets, all commits)
#
# Checks that MUST stay remote (hardware ceiling / release infra) are NOT here:
#   - 3-OS matrix builds (macOS / Windows) + Windows PE export table verify
#   - package.sh artifact assembly (dist/*.igplugin.zip)
#   - GitHub Release creation (tags)
#
# Exit 0 = everything green. Non-zero = a gate failed.
set -e
cd "$(dirname "$0")/.."

echo "── check:local — full local CI ──"

echo "── [1] cargo clippy (all-features, all-targets, -D warnings)"
cargo clippy --all-features --all-targets -- -D warnings

echo "── [2] cargo test"
cargo test

echo "── [3] cargo build --release + symbol export + ABI smoke (Linux)"
cargo build --release
LIB=""
for cand in target/release/libithmb_core_cabi.so target/release/libithmb_core_cabi.dylib; do
  if [ -e "$cand" ]; then LIB="$cand"; break; fi
done
if [ -n "$LIB" ]; then
  if nm -D "$LIB" 2>/dev/null | grep -q ig_plugin_get_api \
     || nm -gU "$LIB" 2>/dev/null | grep -q ig_plugin_get_api; then
    echo "Symbol verified"
  else
    echo "Missing symbol!"
    exit 1
  fi
else
  echo "No cdylib artifact found"
  exit 1
fi
python3 scripts/abi-smoke.py tests/fixtures/test1.ithmb

echo "── [4] cargo-deny (pinned 0.20.2 musl, matches CI)"
DENY_BIN="${CARGO_DENY_BIN:-/tmp/cargo-deny}"
if [ ! -x "$DENY_BIN" ]; then
  curl -sSfL https://github.com/EmbarkStudios/cargo-deny/releases/download/0.20.2/cargo-deny-0.20.2-x86_64-unknown-linux-musl.tar.gz -o /tmp/cargo-deny.tar.gz
  tar -xzf /tmp/cargo-deny.tar.gz -C /tmp --strip-components=1
  DENY_BIN=/tmp/cargo-deny
fi
"$DENY_BIN" --log-level warn --manifest-path ./Cargo.toml --all-features check

echo "── [5] gitleaks (secrets in history, matches CI)"
GITLEAKS_BIN="${GITLEAKS_BIN:-/tmp/gitleaks}"
if [ ! -x "$GITLEAKS_BIN" ]; then
  curl -sSfL "https://github.com/gitleaks/gitleaks/releases/download/v8.24.3/gitleaks_8.24.3_linux_x64.tar.gz" -o /tmp/gitleaks.tar.gz
  tar -xzf /tmp/gitleaks.tar.gz -C /tmp gitleaks
  GITLEAKS_BIN=/tmp/gitleaks
fi
"$GITLEAKS_BIN" git --no-banner --log-opts="--no-merges --all"

echo
echo "── check:local — ALL GREEN ──"
