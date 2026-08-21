#!/usr/bin/env bash
# check-parity.sh — canonical local-vs-GitHub parity gate (canonical layer, D2).
#
# The single most important verification artifact of the local-first CI
# restructure: it asserts that the LOCAL check result and the GITHUB CI result
# AGREE on the same commit. A divergence means local and remote check
# definitions have drifted — false confidence — which is exactly what the
# canonical layer (D2) exists to prevent.
#
# Semantics (transition gate + drift sentinel):
#   For a given commit SHA, run the repo's canonical local check and compare its
#   pass/fail against the GitHub Actions run status for that same commit, for the
#   workflows that carry the repo's verification. If they diverge -> PARITY_FAIL
#   (exit non-zero). This halts a migration until parity is restored (signal B).
#
# Usage:
#   scripts/check-parity.sh [<commit-sha>]   # default: current HEAD
#
# Exit codes:
#   0  PARITY_OK     local and GitHub agree on the expected state
#   1  PARITY_FAIL   local and GitHub disagree (drift / false confidence)
#   2  USAGE/ENV     misconfiguration (missing gh, config, etc.)
#
# Config: read from scripts/check-parity.config (next to this script).
#   REPO_SLUG      the Dev repo where CI runs, e.g. B67687/Ithmb-Codec-Web-Dev
#   WORKFLOWS      space-separated workflow names carrying the migrated checks
#   LOCAL_CMD      command that runs ALL migrated checks locally (exit 0 = pass)
#   EXPECT_LOCAL   expected local status: pass | fail
#   EXPECT_REMOTE  expected remote status: success | failure
#
# The EXPECT_* pair encodes the "correct" state. Default: both pass/success
# (a green repo stays green). Set them if a known-broken state is intentional.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG="$SCRIPT_DIR/check-parity.config"

if [[ ! -f "$CONFIG" ]]; then
  echo "PARITY_ERROR: no config at $CONFIG" >&2
  exit 2
fi
# shellcheck source=/dev/null
source "$CONFIG"

for var in REPO_SLUG WORKFLOWS LOCAL_CMD; do
  if [[ -z "${!var:-}" ]]; then
    echo "PARITY_ERROR: check-parity.config must set $var" >&2
    exit 2
  fi
done
EXPECT_LOCAL="${EXPECT_LOCAL:-pass}"
EXPECT_REMOTE="${EXPECT_REMOTE:-success}"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SHA="${1:-$(git -C "$REPO_ROOT" rev-parse HEAD)}"

# Same-commit guarantee (REVIEW CRITICAL 3.3): the local check runs against the
# working tree, so it is only a valid comparison for the commit actually checked
# out. Refuse unless (a) the requested SHA == checked-out HEAD and (b) the tree
# has no source changes that would make local != that commit. Agent ephemera
# under .omo/ is exempt (documented to never affect check results).
LOCAL_HEAD="$(git -C "$REPO_ROOT" rev-parse HEAD)"
if [[ "$SHA" != "$LOCAL_HEAD" ]]; then
  echo "PARITY_ERROR: requested SHA ${SHA:0:12} != checked-out HEAD ${LOCAL_HEAD:0:12}" >&2
  echo "  checkout the target commit first (or run parity on HEAD) so local and" >&2
  echo "  remote compare the SAME commit (REVIEW 3.3)." >&2
  exit 2
fi
DIRTY="$(git -C "$REPO_ROOT" status --porcelain | grep -v '^.. \.omo/' || true)"
if [[ -n "$DIRTY" ]]; then
  echo "PARITY_ERROR: working tree has uncommitted changes outside .omo/ that would" >&2
  echo "  make local != the commit being compared (REVIEW 3.3):" >&2
  echo "$DIRTY" >&2
  exit 2
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "PARITY_ERROR: gh CLI not found" >&2
  exit 2
fi

echo "── check-parity — $REPO_SLUG @ ${SHA:0:12} ──"

# ── 1. Local check result ─────────────────────────────────────────────────
echo "── [local] running canonical check: $LOCAL_CMD"
LOCAL_EXIT=0
(cd "$SCRIPT_DIR/.." && eval "$LOCAL_CMD") >/tmp/check-parity-local.log 2>&1 || LOCAL_EXIT=$?
if [[ "$LOCAL_EXIT" -eq 0 ]]; then
  LOCAL_STATUS="pass"
else
  LOCAL_STATUS="fail"
fi
echo "    local=$LOCAL_STATUS (exit $LOCAL_EXIT)"

# ── 2. GitHub CI result for the same commit ──────────────────────────────
# Query the workflow runs for this SHA, filtered to the named workflows.
echo "── [remote] querying GitHub Actions runs for ${SHA:0:12}"
RUNS_JSON="$(gh api "repos/$REPO_SLUG/actions/runs?head_sha=$SHA&per_page=50" --jq \
  "[.workflow_runs[] | select(.name as \$n | (\"$WORKFLOWS\" | split(\" \") | index(\$n))) | {name, status, conclusion}]" 2>/dev/null)" \
  || { echo "PARITY_ERROR: gh query failed for $REPO_SLUG" >&2; exit 2; }

if [[ "$(jq length <<<"$RUNS_JSON")" -eq 0 ]]; then
  echo "PARITY_FAIL: no GitHub Actions run found for $REPO_SLUG @ ${SHA:0:12} on workflows: $WORKFLOWS" >&2
  exit 1
fi

REMOTE_ALL_GREEN=true
REMOTE_ALL_COMPLETE=true
while IFS=$'\t' read -r name status conclusion; do
  echo "    remote workflow '$name': status=$status conclusion=${conclusion:-n/a}"
  if [[ "$status" != "completed" ]]; then
    REMOTE_ALL_COMPLETE=false
  fi
  if [[ "$conclusion" != "success" ]]; then
    REMOTE_ALL_GREEN=false
  fi
done < <(jq -r '.[] | [.name, .status, (.conclusion // "")] | @tsv' <<<"$RUNS_JSON")

if [[ "$REMOTE_ALL_GREEN" == "true" ]]; then
  REMOTE_STATUS="success"
elif [[ "$REMOTE_ALL_COMPLETE" == "true" ]]; then
  REMOTE_STATUS="failure"
else
  REMOTE_STATUS="pending"
fi

# ── 3. Compare against expected state ────────────────────────────────────
echo
LOCAL_OK=false; REMOTE_OK=false
[[ "$LOCAL_STATUS" == "$EXPECT_LOCAL" ]] && LOCAL_OK=true
[[ "$REMOTE_STATUS" == "$EXPECT_REMOTE" ]] && REMOTE_OK=true

if [[ "$LOCAL_OK" == "true" && "$REMOTE_OK" == "true" ]]; then
  echo "── check-parity — PARITY_OK (local=$LOCAL_STATUS, remote=$REMOTE_STATUS) ──"
  exit 0
fi

echo "── check-parity — PARITY_FAIL ──" >&2
echo "  local  = $LOCAL_STATUS  (expected $EXPECT_LOCAL)" >&2
echo "  remote = $REMOTE_STATUS (expected $EXPECT_REMOTE)" >&2
echo "  Divergence detected on ${SHA:0:12}. Local and remote check definitions" >&2
echo "  have drifted — FALSE CONFIDENCE. Halt this repo's migration until parity" >&2
echo "  is restored (falsification signal B)." >&2
echo "  Local log tail:" >&2
tail -n 15 /tmp/check-parity-local.log >&2 || true
exit 1
