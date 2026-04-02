# claude-sounds

Minimal macOS sound hook for Claude Code. Plays a sound when Claude finishes a task, needs your attention, or hits an error. No registry, no network, no external dependencies beyond `afplay`.

## Install

```bash
git clone https://github.com/RobKopp-Finvari/peon-ping.git
cd peon-ping
bash setup.sh
```

`setup.sh` will:
1. Copy `play.sh` and `sounds.sh` to `~/.claude/hooks/sounds/`
2. Create `~/.claude/sounds/` and write a default `config` file
3. Register all hook events in `~/.claude/settings.json`
4. Compile `meeting-detect` binary (requires Xcode CLI tools — optional)
5. Install `/sounds-toggle` and `/sounds-use` Claude Code skills
6. Add a `sounds` command to your PATH

Then drop sound files into `~/.claude/sounds/` and you're done.

## Adding sounds

Name your sound files after the hook event they should play for:

| Filename | Fires when |
|---|---|
| `stop.wav` | Agent finished a task |
| `notification.wav` | Agent sent a notification |
| `permission_request.wav` | Waiting for tool approval |
| `post_tool_use_failure.wav` | A Bash tool call failed |
| `subagent_stop.wav` | A subagent finished |
| `session_start.wav` | New Claude session began *(off by default)* |
| `session_end.wav` | Claude session ended *(off by default)* |
| `subagent_start.wav` | A subagent started *(off by default)* |
| `user_prompt_submit.wav` | You submitted a prompt *(off by default)* |
| `pre_compact.wav` | Context is about to be compacted *(off by default)* |

**Supported formats:** `.wav` `.mp3` `.aiff` `.m4a`

Missing sound files are silently skipped — you only need files for events you care about.

## Sound packs

Create subdirectories in `~/.claude/sounds/` to define multiple packs. The system cycles through them (round-robin) on each new Claude session:

```
~/.claude/sounds/
  warcraft/
    stop.wav
    notification.wav
  portal/
    stop.wav
    notification.wav
  config
```

- Packs don't need to be complete — missing files are silently skipped
- Packs cycle on `SessionStart` whether or not that event has a sound
- Pin a specific pack: `sounds pack use <name>`
- Resume cycling: `sounds pack cycle`

With no subdirectories, sounds load from `~/.claude/sounds/` directly.

## Configuration

`~/.claude/sounds/config` is a shell-sourced key=value file. Changes take effect immediately — no restart needed.

### Options

| Key | Default | Description |
|---|---|---|
| `ENABLED` | `true` | Master on/off switch |
| `VOLUME` | `0.5` | Playback volume (0.0–1.0) |
| `SUPPRESS_SOUND_WHEN_TAB_FOCUSED` | `true` | Skip sound when this terminal tab is in the foreground |
| `MEETING_DETECT` | `false` | Skip sounds when the microphone is in use — requires `meeting-detect` binary (compiled by `setup.sh` if `swiftc` is available) |
| `HEADPHONES_ONLY` | `false` | Skip sounds when playing through built-in speakers — uses `system_profiler`, adds ~1s latency |
| `SILENT_WINDOW_SECONDS` | `0` | Skip `Stop` sounds for tasks that finish in under N seconds (0 = disabled) |
| `PACK` | *(unset)* | Pin to a specific pack by name; set by `sounds pack use`, cleared by `sounds pack cycle` |

### Per-hook toggles

| Key | Default |
|---|---|
| `STOP` | `true` |
| `NOTIFICATION` | `true` |
| `PERMISSION_REQUEST` | `true` |
| `POST_TOOL_USE_FAILURE` | `true` |
| `SUBAGENT_STOP` | `true` |
| `SESSION_START` | `false` |
| `SESSION_END` | `false` |
| `SUBAGENT_START` | `false` |
| `USER_PROMPT_SUBMIT` | `false` |
| `PRE_COMPACT` | `false` |

## CLI

```
sounds toggle                    pause or resume all sounds
sounds status                    show state, active pack, options, and per-hook config
sounds enable [hook|all]         enable a hook or all hooks
sounds disable [hook|all]        disable a hook or all hooks
sounds preview [hook]            play the sound for a hook to test it (default: stop)

sounds volume [0.0-1.0]          get or set playback volume
sounds meeting [on|off]          toggle meeting detection
sounds headphones [on|off]       toggle headphones-only mode
sounds focused [on|off]          toggle tab-focus suppression
sounds silent [seconds]          get or set the silent window

sounds pack list                 list installed packs
sounds pack use <name>           pin to a specific pack
sounds pack cycle                unpin, resume round-robin cycling
sounds pack next                 manually advance to the next pack
```

Hook aliases: `notification` = `notify`, `permission_request` = `permission`, `post_tool_use_failure` = `failure`, `user_prompt_submit` = `prompt`, `pre_compact` = `compact`.

## Claude Code skills

After running `setup.sh`, two slash commands are available in any Claude session:

**`/sounds-toggle`** — Mute, unmute, enable/disable specific hooks, or check status. Claude runs `sounds toggle` (or `sounds enable/disable/status`) via Bash and reports the result.

**`/sounds-use`** — Switch to a specific pack, resume cycling, or advance to the next pack. Claude lists available packs and runs `sounds pack use <name>` (or `cycle`/`next`).

## Uninstall

```bash
# Remove installed files
rm -rf ~/.claude/hooks/sounds
rm -rf ~/.claude/sounds
rm -f ~/.local/bin/sounds   # or /usr/local/bin/sounds

# Remove skills
rm -rf ~/.claude/skills/sounds-toggle
rm -rf ~/.claude/skills/sounds-use

# Remove hooks from Claude Code settings
# Edit ~/.claude/settings.json and delete all entries under "hooks" that
# reference hooks/sounds/play.sh
```

## Requirements

| Requirement | Notes |
|---|---|
| macOS | `afplay` is used for audio playback |
| Python 3 | For hook registration in `setup.sh` — ships with macOS |
| Xcode CLI tools | Optional — only needed for `MEETING_DETECT` (`swiftc` compiles `meeting-detect`) |

## How it works

1. Claude Code fires a hook event (e.g. `Stop`) and calls `play.sh Stop`
2. `play.sh` sources `~/.claude/sounds/config`, resolves the active pack, and checks suppression conditions (master switch, tab focus, meeting, headphones, silent window)
3. If all checks pass, it finds the matching sound file and runs `afplay -v $VOLUME $file &`

State is minimal: `~/.claude/sounds/.pack_index` (one number, tracks cycling position) and `~/.claude/sounds/.state` (last prompt timestamp, for `SILENT_WINDOW_SECONDS`).
