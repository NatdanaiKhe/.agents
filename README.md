# Agent Layer — Universal Agent Symlink Hub

One repo is the single source of truth for your global AI-agent rules
(`AGENTS.md`) and skills (`skills/`). One setup script symlinks them into the
global config directory of every AI coding tool you actually have installed,
so every tool reads the same files — on Windows, macOS, and Linux.

## Quick start

Clone this repo anywhere, then run **one** command.

**Windows (PowerShell 5.1+)**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\setup-symlinks.ps1
```

Self-elevates via UAC when needed (no elevation required from an admin shell,
or when Developer Mode is on).

**macOS / Linux**

```bash
bash scripts/setup-symlinks.sh
```

The script detects which tools are installed (CLI binary on `PATH`) and links
only those. To link everything regardless of detection, use `-ForceAll`
(PowerShell) or `--force-all` / `FORCE_ALL=1` (bash).

**Re-run anytime.** The scripts are idempotent — re-run after installing a new
AI tool to pick it up automatically.

## Supported tools

| Tool | Rules | Skills |
|------|-------|--------|
| OpenCode | `~/.config/opencode/AGENTS.md` | `~/.config/opencode/skills` |
| Claude Code (global) | `~/.claude/CLAUDE.md` | `~/.claude/skills` |
| Gemini | `~/.gemini/GEMINI.md` | `~/.gemini/skills` |
| Codex | `~/.codex/AGENTS.md` \* | `~/.codex/skills/` (real dir of per-skill links) † |

\* If `~/.codex/RTK.md` exists, this is written as a small real file that
`@`-references the repo `AGENTS.md` and your `RTK.md`; otherwise it's a plain
symlink.

† Codex expects a flat per-skill layout, so nested skills (e.g.
`skills/engineering/debug-mantra`) are exposed via in-repo alias symlinks
(git-ignored), and internal `skills/.system/*` skills are linked flat too.

## Sources of truth

- `AGENTS.md` — global rules shared by every tool
- `skills/` — all skills, nested by category; each skill has a `SKILL.md` at
  its root (e.g. `skills/engineering/debug-mantra/SKILL.md`)

## Listing skills

```bash
bash scripts/list-skills.sh
```

Prints every discovered skill under `skills/`.
