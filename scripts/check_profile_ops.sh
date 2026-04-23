#!/usr/bin/env bash
# scripts/check_profile_ops.sh
#
# Enforce the "no DSL-bypass" rule from docs/profile-and-orchestration.md
# §2.5 and .claude/CLAUDE.md "Profile Evaluation Bypass".
#
# Fails loud if the staged / unstaged diff or recent git log contains a
# hand-rolled pod-side file op that should have gone through the
# Profile DSL + profile_service expansion instead:
#
#   - vdsl_exec / vdsl_task_run shelling out to mv / cp / ln / rclone /
#     wget / curl (pod-op side channel)
#   - pod subprocess strings invoking the same commands against
#     /workspace/* paths
#
# Usage:
#   scripts/check_profile_ops.sh             # diff-mode: staged + unstaged
#   scripts/check_profile_ops.sh --log 10    # also scan last 10 commits
#   scripts/check_profile_ops.sh --help
#
# Integrate into pre-commit: copy or symlink into .git/hooks/pre-commit.
# Integrate into CI: just ./scripts/check_profile_ops.sh as a step.
#
# The script intentionally only flags — it does not auto-fix. The fix
# is always "extend the DSL", never "silence the regex".

set -euo pipefail

usage() {
  sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'
}

LOG_DEPTH=0
MODE="diff"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --log)     MODE="log"; LOG_DEPTH="${2:-20}"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; usage >&2; exit 2 ;;
  esac
done

# Pod-op side-channel patterns. Quote metacharacters carefully.
# NOTE: MCP-internal emission in profile_service.rs / the batch tests
# is explicitly exempted below so this lint does not fight its own
# implementation.
PATTERNS=(
  'vdsl_exec[^"]*\b(mv|cp|ln|rclone|wget|curl)\b'
  'vdsl_task_run[^"]*\b(mv|cp|ln|rclone|wget|curl)\b'
  # A raw rclone copy against a /workspace or b2:// path in any script
  # file is suspicious regardless of the invoking tool.
  'rclone +(copy|copyto|move) +.*(/workspace/|b2://)'
)

# Files and paths where MCP/DSL-internal emission is legitimate and
# must be skipped. Keep tight: only the files that legitimately
# construct the exec step scripts consumed by the evaluated plan.
EXEMPT_PATHS=(
  'lua/vdsl/runtime/profile.lua'
  'tests/test_profile.lua'
  'scripts/check_profile_ops.sh'
  'scripts/new_profile.sh'
  'docs/profile-and-orchestration.md'
  '.claude/CLAUDE.md'
  # vdsl-mcp worktree counterparts are the canonical emission site
  # for the same patterns; they are in a sibling repo and not reached
  # by git diff here, but guard the path fragments just in case.
  'profile_service.rs'
  'profile_service_tests.rs'
  'batch_service.rs'
)

is_exempt() {
  local path="$1"
  for ex in "${EXEMPT_PATHS[@]}"; do
    case "$path" in *"$ex"*) return 0 ;; esac
  done
  return 1
}

scan_payload() {
  # Args:
  #   $1: label for the hunk being scanned (shown on hit)
  #   $2: path the hunk is from (used for exempt lookup)
  #   stdin: the text to scan
  local label="$1" path="$2"
  if is_exempt "$path"; then
    return 0
  fi
  local any_hit=0
  local text
  text="$(cat)"
  for pat in "${PATTERNS[@]}"; do
    local hits
    hits="$(printf '%s' "$text" | grep -En "$pat" || true)"
    if [[ -n "$hits" ]]; then
      any_hit=1
      echo "=== BYPASS CANDIDATE: $label ($path) ==="
      echo "pattern: $pat"
      echo "$hits"
      echo
    fi
  done
  return $any_hit
}

overall=0

scan_diff() {
  local diff_cmd=("$@")
  local diff_out
  diff_out="$("${diff_cmd[@]}" || true)"
  [[ -z "$diff_out" ]] && return 0

  local cur_path=""
  local cur_buf=""
  local label="${diff_cmd[*]}"

  # Walk per-file sections of the unified diff. Added/context lines
  # beginning with '+' are scanned; header '+++' lines are stripped.
  while IFS= read -r line; do
    if [[ "$line" == "+++ "* ]]; then
      if [[ -n "$cur_path" && -n "$cur_buf" ]]; then
        printf '%s' "$cur_buf" | scan_payload "$label" "$cur_path" || overall=1
      fi
      cur_path="${line#+++ }"
      cur_path="${cur_path#b/}"
      cur_buf=""
      continue
    fi
    if [[ "$line" == "+"* && "$line" != "+++ "* ]]; then
      cur_buf+="${line#+}"$'\n'
    fi
  done <<< "$diff_out"

  if [[ -n "$cur_path" && -n "$cur_buf" ]]; then
    printf '%s' "$cur_buf" | scan_payload "$label" "$cur_path" || overall=1
  fi
}

case "$MODE" in
  diff)
    scan_diff git --no-pager diff --cached
    scan_diff git --no-pager diff
    ;;
  log)
    scan_diff git --no-pager log -p -n "$LOG_DEPTH"
    ;;
esac

if [[ "$overall" -eq 0 ]]; then
  echo "check_profile_ops: OK (no DSL-bypass patterns detected)"
  exit 0
else
  cat >&2 <<'EOF'

-------------------------------------------------------------
check_profile_ops: FAIL
One or more diff/log hunks match a DSL-bypass pattern. Correct
fix is to extend the Profile DSL (lua/vdsl/runtime/profile.lua
+ vdsl-mcp profile_service.rs) so the operation is expressible
as a BatchStep emitted by expand_phases. See
docs/profile-and-orchestration.md §2.5.
-------------------------------------------------------------
EOF
  exit 1
fi
