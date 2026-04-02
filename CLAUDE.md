# CLAUDE.md

Developer guide for AI coding agents working on this codebase. For user-facing docs (install, configuration, CLI, sound packs), see [README.md](README.md).

## Commands

```bash
# Syntax-check all shell scripts
bash -n play.sh && bash -n sounds.sh && bash -n setup.sh

# Install locally for development
bash setup.sh

# Test a specific hook sound manually
bash play.sh Stop
bash play.sh Notification

# Preview via CLI
sounds preview stop
sounds preview notification
```

There is no build step, linter, test suite, or formatter configured.

## Architecture

### Files

- **`play.sh`** — Hook script called by Claude Code. Receives the event name as `$1`. Sources `~/.claude/sounds/config`, resolves the active pack directory, checks suppression conditions, finds the matching sound file, and plays it via `afplay`.
- **`sounds.sh`** — CLI (`sounds <command>`). Installed to PATH as `sounds` by `setup.sh`. Manages config (toggle, enable/disable, volume, meeting, headphones, focused, silent), pack selection (list, use, cycle, next), and sound preview.
- **`setup.sh`** — Installer. Copies `play.sh` and `sounds.sh` to `~/.claude/hooks/sounds/`, creates `~/.claude/sounds/` with a default `config` file, registers all hook events in `~/.claude/settings.json` (via Python stdlib), compiles `meeting-detect.swift` if `swiftc` is available, installs the two Claude Code skills, and symlinks `sounds` into PATH.
- **`sounds/config`** — Template config copied to `~/.claude/sounds/config` on install. Shell-sourced key=value format. Changes take effect immediately (no restart).
- **`scripts/meeting-detect.swift`** — CoreAudio mic detection binary. Compiled by `setup.sh` to `~/.claude/hooks/sounds/meeting-detect`. Outputs `MIC_IN_USE` or `MIC_NOT_IN_USE`.
- **`skills/sounds-toggle/SKILL.md`** — Claude Code skill (`/sounds-toggle`). Tells Claude to run the `sounds` CLI to mute/unmute or check status.
- **`skills/sounds-use/SKILL.md`** — Claude Code skill (`/sounds-use`). Tells Claude to list packs and switch via `sounds pack use <name>` / `cycle` / `next`.

### Event Flow

```
Claude Code fires hook → calls play.sh <EventName>
  → source config
  → check ENABLED
  → resolve pack dir (pinned PACK → cycling index → flat dir)
  → map event → config key + sound stem
  → check per-event enabled flag
  → check SILENT_WINDOW_SECONDS (Stop only)
  → find sound file (.wav .mp3 .aiff .m4a)
  → check tab focus (osascript)
  → check headphones (system_profiler)
  → check mic (meeting-detect)
  → afplay -v $VOLUME $FILE &
```

### Config

`~/.claude/sounds/config` is sourced directly by `play.sh`. All keys have defaults in `play.sh` using `${KEY:-default}` syntax, so the config file is only needed to override defaults.

### Pack Cycling

Subdirectories in `~/.claude/sounds/` are packs. On `SessionStart`, `play.sh` increments `.pack_index` (mod pack count). `sounds pack use <name>` sets `PACK=name` in config to pin; `sounds pack cycle` removes the key to resume round-robin.

### State Files

- `~/.claude/sounds/.pack_index` — Current pack index (integer). Written by `play.sh` on `SessionStart`.
- `~/.claude/sounds/.state` — Stores `last_prompt_time` timestamp for `SILENT_WINDOW_SECONDS`. Written on `UserPromptSubmit`, read on `Stop`.

## Skills

- **`/sounds-toggle`** — Mute, unmute, enable/disable specific hooks, or check status via the `sounds` CLI.
- **`/sounds-use`** — Switch sound pack, resume cycling, or advance to next pack via the `sounds` CLI.

## Releasing

1. `bash -n play.sh && bash -n sounds.sh && bash -n setup.sh` — all must pass
2. Update `CHANGELOG.md` — add new section at top
3. Bump `VERSION` if present, or tag directly
4. `git commit -m "chore: bump version to X.Y.Z"`
5. `git tag vX.Y.Z && git push && git push --tags`
