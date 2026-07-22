#!/usr/bin/env bash
# Agent Layer Symlink Hub - portable setup script (bash / macOS / Linux)
#
# Resolves its own location dynamically so the same repo works on any machine
# after `git clone`. Detects which AI tools are installed (CLI binary on PATH)
# and links the sources of truth (AGENTS.md, skills/) into each installed
# tool's global config dir.
#
# Usage:
#   bash scripts/setup-symlinks.sh
#   bash scripts/setup-symlinks.sh --force-all     # or: FORCE_ALL=1 bash ...
#
# --force-all links every supported tool regardless of detection.
# Note: on Windows use scripts\setup-symlinks.ps1 (Git Bash ln -s needs
# MSYS=winsymlinks:nativestrict and an elevated shell to make real symlinks).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
SOURCE_AGENTS="$REPO_ROOT/AGENTS.md"
SOURCE_SKILLS="$REPO_ROOT/skills"

FORCE_ALL="${FORCE_ALL:-0}"
while [ $# -gt 0 ]; do
  case "$1" in
    --force-all) FORCE_ALL=1 ;;
    -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done

# --- tool detection ---------------------------------------------------------
# A tool counts as installed when its CLI binary is on PATH.
detect_tool() { # $1 = binary name -> prints Installed | Not found | Forced
  if [ "$FORCE_ALL" = "1" ]; then
    echo "Forced"
  elif command -v "$1" >/dev/null 2>&1; then
    echo "Installed"
  else
    echo "Not found"
  fi
}

STATE_OPENCODE="$(detect_tool opencode)"
STATE_CLAUDE="$(detect_tool claude)"
STATE_GEMINI="$(detect_tool gemini)"
STATE_CODEX="$(detect_tool codex)"

enabled() { [ "$1" != "Not found" ]; }

# --- report state -----------------------------------------------------------
declare -a REPORT_ROWS=()
declare -a VERIFY_ROWS=()
FAILED_COUNT=0

add_row() { # $1 tool | $2 installed | $3 linktype | $4 status | $5 target | $6 points-to
  REPORT_ROWS+=("$1|$2|$3|$4|$5|$6")
}

add_verify() { # $1 kind | $2 target
  VERIFY_ROWS+=("$1|$2")
}

# Resolve a path (following symlinks) on gnu and bsd userlands.
resolve_path() {
  local p="$1"
  if command -v realpath >/dev/null 2>&1; then
    realpath "$p" 2>/dev/null && return 0
  fi
  readlink -f "$p" 2>/dev/null || echo "$p"
}

# --- link helper (idempotent) ----------------------------------------------
# Ensures $target is a symlink pointing to $source.
# args: $1 tool, $2 installed-state, $3 target, $4 source, $5 kind (file|dir)
#       $6 (optional) verify kind to record on success
link_target() {
  local tool="$1" state="$2" target="$3" source="$4" kind="$5" vkind="${6:-}"

  # Safety guard: never let the source get deleted.
  if [ "$target" = "$source" ]; then
    echo "ERROR: target equals source ($target). Skipping to protect the source." >&2
    add_row "$tool" "$state" "Symlink($kind)" "Failed" "$target" "$source"
    FAILED_COUNT=$((FAILED_COUNT + 1))
    return 0
  fi

  # Create parent dir of target if missing.
  mkdir -p "$(dirname "$target")"

  if [ -L "$target" ]; then
    local resolved
    resolved="$(resolve_path "$target")"
    if [ "$resolved" = "$source" ]; then
      echo "Already linked: $target -> $source"
      add_row "$tool" "$state" "Symlink($kind)" "Already linked" "$target" "$source"
      [ -n "$vkind" ] && add_verify "$vkind" "$target"
      return 0
    fi
    # Symlink exists but points elsewhere - replace it.
    echo "Replacing symlink pointing elsewhere: $target"
    rm -f "$target"
  elif [ -e "$target" ]; then
    if [ -d "$target" ]; then
      echo "Replacing existing directory copy: $target"
      rm -rf "$target"
    else
      # Stale real-file copy: rename out of the way instead of deleting.
      if [ -e "$target.bak" ] || [ -L "$target.bak" ]; then rm -rf "$target.bak"; fi
      echo "Renaming stale file copy: $target -> $target.bak"
      mv "$target" "$target.bak"
    fi
  fi

  # `ln -s` works for both files and dirs on unix.
  if ln -s "$source" "$target" 2>/dev/null; then
    echo "Linked: $target -> $source"
    add_row "$tool" "$state" "Symlink($kind)" "Linked" "$target" "$source"
    [ -n "$vkind" ] && add_verify "$vkind" "$target"
  else
    echo "ERROR: failed to create symlink $target -> $source" >&2
    add_row "$tool" "$state" "Symlink($kind)" "Failed" "$target" "$source"
    FAILED_COUNT=$((FAILED_COUNT + 1))
  fi
  return 0
}

# --- Codex: rules file (RTK-aware) ------------------------------------------
codex_rules() {
  local dest="$HOME/.codex/AGENTS.md"
  local rtk="$HOME/.codex/RTK.md"

  if [ "$dest" = "$SOURCE_AGENTS" ]; then
    echo "ERROR: codex rules target equals source ($dest). Skipping." >&2
    FAILED_COUNT=$((FAILED_COUNT + 1))
    return 0
  fi

  mkdir -p "$(dirname "$dest")"

  if [ -f "$rtk" ]; then
    # Compose a REAL file referencing the canonical rules + the user's RTK file.
    local want
    want="$(printf '@%s\n@%s' "$SOURCE_AGENTS" "$rtk")"
    if [ -L "$dest" ]; then
      # Remove a stale symlink BEFORE writing (> would follow it into the repo).
      rm -f "$dest"
    fi
    if [ -f "$dest" ] && [ "$(cat "$dest" 2>/dev/null)" = "$want" ]; then
      echo "Already linked (composed file): $dest"
      add_row "Codex" "$STATE_CODEX" "File(composed)" "Already linked" "$dest" "$SOURCE_AGENTS + $rtk"
    else
      printf '@%s\n@%s\n' "$SOURCE_AGENTS" "$rtk" > "$dest"
      echo "Composed: $dest (references repo AGENTS.md + RTK.md)"
      add_row "Codex" "$STATE_CODEX" "File(composed)" "Linked" "$dest" "$SOURCE_AGENTS + $rtk"
    fi
    add_verify "codex-composed" "$dest"
    return 0
  fi

  link_target "Codex" "$STATE_CODEX" "$dest" "$SOURCE_AGENTS" "file" "file"
}

# --- Codex: in-repo alias symlinks (flatten nested shared skills) -----------
link_source_aliases() {
  local aliases=(
    "engineering/create-architecture-documentation"
    "engineering/debug-mantra"
    "engineering/generate-tests"
    "engineering/post-mortem"
    "engineering/scrutinize"
    "productivity/management-talk"
  )
  local rel base dest
  for rel in "${aliases[@]}"; do
    base="$(basename "$rel")"
    dest="$SOURCE_SKILLS/$base"
    if [ -L "$dest" ]; then
      if [ "$(readlink "$dest")" = "$rel" ]; then
        echo "Alias already linked: $dest -> $rel"
        continue
      fi
      echo "Replacing stale alias symlink: $dest"
      rm -f "$dest"
    elif [ -e "$dest" ]; then
      echo "WARN: $dest exists and is not a symlink - skipping alias $rel" >&2
      continue
    fi
    # Relative target, resolved against the link's own directory.
    if ln -s "$rel" "$dest"; then
      echo "Alias linked: $dest -> $rel"
    else
      echo "ERROR: failed to create alias $dest -> $rel" >&2
      FAILED_COUNT=$((FAILED_COUNT + 1))
    fi
  done
}

# --- Codex: skills dir (real dir of per-skill links, flat layout) -----------
codex_skills() {
  local cskills="$HOME/.codex/skills"

  if [ "$cskills" = "$SOURCE_SKILLS" ]; then
    echo "ERROR: codex skills target equals source ($cskills). Skipping." >&2
    FAILED_COUNT=$((FAILED_COUNT + 1))
    return 0
  fi

  # Codex expects a REAL directory of per-skill links, not one dir symlink.
  if [ -L "$cskills" ]; then
    echo "Removing dir symlink at $cskills (Codex needs a real directory)."
    rm -f "$cskills"
  fi
  mkdir -p "$cskills"

  # Flatten nested shared skills via aliases inside the repo, then link.
  link_source_aliases

  local skill
  for skill in "$SOURCE_SKILLS"/*; do
    [ -d "$skill" ] || continue
    [ -f "$skill/SKILL.md" ] || continue
    link_target "Codex" "$STATE_CODEX" "$cskills/$(basename "$skill")" "$skill" "dir"
  done

  # Internal .system skills, linked flat (when present in the repo).
  local name
  for name in imagegen openai-docs plugin-creator skill-creator skill-installer; do
    if [ -d "$SOURCE_SKILLS/.system/$name" ]; then
      link_target "Codex" "$STATE_CODEX" "$cskills/$name" "$SOURCE_SKILLS/.system/$name" "dir"
    fi
  done

  add_verify "codex-skills" "$cskills"
}

# --- header -----------------------------------------------------------------
echo "Agent Layer Symlink Hub (bash)"
echo "Repo root : $REPO_ROOT"
echo "HOME      : $HOME"
echo
echo "Tool detection (CLI binary on PATH):"
printf '  %-12s: %s\n' "OpenCode" "$STATE_OPENCODE"
printf '  %-12s: %s\n' "Claude Code" "$STATE_CLAUDE"
printf '  %-12s: %s\n' "Gemini" "$STATE_GEMINI"
printf '  %-12s: %s\n' "Codex" "$STATE_CODEX"
if [ "$FORCE_ALL" = "1" ]; then
  echo "  (--force-all set: linking all tools regardless of detection)"
fi
echo

# --- link per installed tool --------------------------------------------------
if enabled "$STATE_OPENCODE"; then
  link_target "OpenCode" "$STATE_OPENCODE" "$HOME/.config/opencode/AGENTS.md" "$SOURCE_AGENTS" "file" "file"
  link_target "OpenCode" "$STATE_OPENCODE" "$HOME/.config/opencode/skills" "$SOURCE_SKILLS" "dir" "dir"
fi

if enabled "$STATE_CLAUDE"; then
  link_target "Claude Code" "$STATE_CLAUDE" "$HOME/.claude/CLAUDE.md" "$SOURCE_AGENTS" "file" "file"
  link_target "Claude Code" "$STATE_CLAUDE" "$HOME/.claude/skills" "$SOURCE_SKILLS" "dir" "dir"
fi

if enabled "$STATE_GEMINI"; then
  link_target "Gemini" "$STATE_GEMINI" "$HOME/.gemini/GEMINI.md" "$SOURCE_AGENTS" "file" "file"
  link_target "Gemini" "$STATE_GEMINI" "$HOME/.gemini/skills" "$SOURCE_SKILLS" "dir" "dir"
fi

if enabled "$STATE_CODEX"; then
  codex_rules
  codex_skills
fi

# Record skipped tools in the report.
record_skip() { # $1 tool name, $2 state
  if [ "$2" = "Not found" ]; then
    add_row "$1" "$2" "-" "Skipped-not-installed" "-" "-"
  fi
}
record_skip "OpenCode" "$STATE_OPENCODE"
record_skip "Claude Code" "$STATE_CLAUDE"
record_skip "Gemini" "$STATE_GEMINI"
record_skip "Codex" "$STATE_CODEX"

# --- verification -----------------------------------------------------------
verify_entry() {
  local kind="$1" target="$2"
  echo "--- verify: $target ---"
  case "$kind" in
    file)
      ls -la "$target" 2>/dev/null || echo "target does not exist"
      local resolved
      resolved="$(resolve_path "$target")"
      echo "first 3 lines of resolved content:"
      sed -n '1,3p' "$resolved" 2>/dev/null || true
      if [ -r "$resolved" ] && cmp -s <(sed -n '1,3p' "$resolved") <(sed -n '1,3p' "$SOURCE_AGENTS"); then
        echo "content head matches source: OK"
      else
        echo "WARN: content head differs from source"
      fi
      ;;
    dir)
      ls -la "$target" 2>/dev/null || echo "target does not exist"
      echo "first 5 child entries:"
      ls -1 "$target" 2>/dev/null | head -n 5 || true
      ;;
    codex-composed)
      ls -la "$target" 2>/dev/null || echo "target does not exist"
      echo "composed file contents:"
      cat "$target" 2>/dev/null || true
      ;;
    codex-skills)
      echo "per-skill symlinks:"
      ls -la "$target" 2>/dev/null || echo "target does not exist"
      ;;
  esac
  echo
}

echo
echo "=== Verification ==="
if [ "${#VERIFY_ROWS[@]}" -gt 0 ]; then
  for row in "${VERIFY_ROWS[@]}"; do
    IFS='|' read -r kind target <<< "$row"
    verify_entry "$kind" "$target"
  done
else
  echo "(nothing to verify - no installed tools were linked)"
fi

# --- final report -----------------------------------------------------------
echo
echo "=== Final report ==="
printf '| %-11s | %-11s | %-16s | %-22s | %s | %s |\n' "Tool" "Installed?" "Link Type" "Status" "Target Path" "Points To"
printf '|-------------|-------------|------------------|------------------------|------------|-----------|\n'
for row in "${REPORT_ROWS[@]}"; do
  IFS='|' read -r tool state ltype status target source <<< "$row"
  printf '| %-11s | %-11s | %-16s | %-22s | %s | %s |\n' "$tool" "$state" "$ltype" "$status" "$target" "$source"
done
echo

if [ "$FAILED_COUNT" -gt 0 ]; then
  echo "FAILED_COUNT=$FAILED_COUNT"
  exit 1
fi
echo "All targets linked successfully."
