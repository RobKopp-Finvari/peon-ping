---
name: sounds-toggle
description: Toggle Claude Code sounds on/off. Use when user wants to mute, unmute, pause, or resume sounds during a session. Also handles enabling/disabling specific hooks.
user_invocable: true
---

# sounds-toggle

Toggle sounds on or off for the current Claude Code session.

## Toggle all sounds

Run using the Bash tool:

```bash
bash ~/.claude/hooks/sounds/sounds.sh toggle
```

Report the output to the user:
- `sounds: paused` — all sounds are now muted
- `sounds: resumed` — sounds are now active

## Enable or disable a specific hook

```bash
bash ~/.claude/hooks/sounds/sounds.sh enable <hook>
bash ~/.claude/hooks/sounds/sounds.sh disable <hook>
```

Valid hooks: `stop`, `notification`, `permission_request`, `post_tool_use_failure`,
`subagent_stop`, `session_start`, `session_end`, `subagent_start`, `user_prompt_submit`, `pre_compact`

Example — user says "mute the notification sound":
```bash
bash ~/.claude/hooks/sounds/sounds.sh disable notification
```

## Check current state

```bash
bash ~/.claude/hooks/sounds/sounds.sh status
```

## Examples

- "Mute sounds" / "pause sounds" → run `toggle` (if currently on)
- "Unmute" / "resume sounds" → run `toggle` (if currently off)
- "Turn off the notification sound" → run `disable notification`
- "Enable session start sound" → run `enable session_start`
- "What sounds are on?" → run `status`
