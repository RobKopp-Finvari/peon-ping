# CLAUDE.md

Developer guide for AI coding agents working on this codebase.

## Commands

```bash
# Syntax check all scripts
bash -n play.sh && bash -n sounds.sh && bash -n setup.sh

# Run setup locally
bash setup.sh
```

There is no build step, linter, or formatter configured.

## Architecture

### Files

| File | Purpose |
|---|---|
| `play.sh` | Hook script — called by Claude Code with event name as `$1`. Sources config, resolves pack, checks suppression conditions, plays sound via `afplay`. |
| `sounds.sh` | CLI — `sounds toggle`, `sounds status`, `sounds pack use`, etc. Reads/writes `~/.claude/sounds/config`. |
| `setup.sh` | Installer — copies scripts, creates sound directory, registers hooks in `~/.claude/settings.json`, compiles `meeting-detect`, installs skills, adds `sounds` to PATH. |
| `sounds/config` | Config template — copied to `~/.claude/sounds/config` on first install. Shell-sourced key=value format. |
| `scripts/meeting-detect.swift` | Swift source for the `meeting-detect` binary. Queries CoreAudio `kAudioDevicePropertyDeviceIsRunningSomewhere` to detect active mic input. Compiled by `setup.sh` via `swiftc`. |
| `skills/sounds-toggle/SKILL.md` | Claude Code skill — `/sounds-toggle` in-session command. |
| `skills/sounds-use/SKILL.md` | Claude Code skill — `/sounds-use` in-session command. |

### Event flow

1. Claude Code fires hook → calls `bash ~/.claude/hooks/sounds/play.sh <EventName>`
2. `play.sh` sources `~/.claude/sounds/config`
3. Checks master `ENABLED` switch
4. Records timestamp if `UserPromptSubmit` + `SILENT_WINDOW_SECONDS` is set
5. Resolves active pack directory (pinned `PACK` → cycling index → flat `SOUNDS_DIR`)
6. Maps event name to config key + sound file stem
7. Checks per-event enabled flag
8. Checks `SILENT_WINDOW_SECONDS` for `Stop` events
9. Finds sound file (tries `.wav`, `.mp3`, `.aiff`, `.m4a`)
10. Runs pre-play checks: tab focus (`SUPPRESS_SOUND_WHEN_TAB_FOCUSED`), headphones (`HEADPHONES_ONLY`), meeting (`MEETING_DETECT`)
11. Plays: `afplay -v $VOLUME $FILE &`

### State files

| File | Contents |
|---|---|
| `~/.claude/sounds/.pack_index` | Single integer — index into the sorted pack directory list for round-robin cycling |
| `~/.claude/sounds/.state` | `last_prompt_time=<unix_timestamp>` — used by `SILENT_WINDOW_SECONDS` |

### Hook events registered

`SessionStart`, `SessionEnd`, `SubagentStart`, `SubagentStop`, `UserPromptSubmit`, `Stop`, `Notification`, `PermissionRequest`, `PostToolUseFailure` (matcher: `Bash`), `PreCompact`

All run async (`"async": true`) with a 10s timeout.

## Skills

| Skill | Invocation | What Claude does |
|---|---|---|
| `sounds-toggle` | `/sounds-toggle` | Runs `sounds toggle` / `sounds enable` / `sounds disable` / `sounds status` via Bash |
| `sounds-use` | `/sounds-use` | Runs `sounds pack list` then `sounds pack use <name>` / `cycle` / `next` via Bash |

Skills are installed to `~/.claude/skills/` by `setup.sh`.

## Config keys reference

See `sounds/config` for the full template with inline documentation. All keys are optional — `play.sh` uses `:-` defaults for every key, so the config file can be partial.

## Releasing

1. `bash -n play.sh && bash -n sounds.sh && bash -n setup.sh` — all must pass
2. Update `CHANGELOG.md` — add section at top with version, date, and changes
3. Bump `VERSION` file
4. `git commit -m "chore: bump version to X.Y.Z"`
5. `git tag vX.Y.Z && git push && git push --tags`
