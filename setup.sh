#!/usr/bin/env bash
# setup.sh — install the Claude Code sound hook (macOS)
#
# What this does:
#   1. Copies play.sh and sounds.sh to ~/.claude/hooks/sounds/
#   2. Creates ~/.claude/sounds/ for your sound files
#   3. Writes ~/.claude/sounds/config if it doesn't exist yet
#   4. Registers all hook events in ~/.claude/settings.json
#   5. Compiles meeting-detect binary (requires swiftc / Xcode CLI tools)
#   6. Installs skills (sounds-toggle, sounds-use) to ~/.claude/skills/
#   7. Creates a `sounds` command in PATH (~/.local/bin or /usr/local/bin)
#
# Run again at any time to update scripts after pulling changes.
# Your config and sound files are never overwritten.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_DIR="$HOME/.claude/hooks/sounds"
SOUNDS_DIR="${CLAUDE_SOUNDS_DIR:-$HOME/.claude/sounds}"
SKILLS_DIR="$HOME/.claude/skills"
SETTINGS="$HOME/.claude/settings.json"

echo "Installing Claude sound hook..."

# 1. Install hook scripts
mkdir -p "$HOOK_DIR"
cp "$REPO_DIR/play.sh"   "$HOOK_DIR/play.sh"
cp "$REPO_DIR/sounds.sh" "$HOOK_DIR/sounds.sh"
chmod +x "$HOOK_DIR/play.sh" "$HOOK_DIR/sounds.sh"
echo "  play.sh   → $HOOK_DIR/play.sh"
echo "  sounds.sh → $HOOK_DIR/sounds.sh"

# 2. Create sounds directory + config
mkdir -p "$SOUNDS_DIR"
if [[ ! -f "$SOUNDS_DIR/config" ]]; then
  cp "$REPO_DIR/sounds/config" "$SOUNDS_DIR/config"
  echo "  config    → $SOUNDS_DIR/config"
else
  echo "  config       kept: $SOUNDS_DIR/config"
fi

# 3. Register hooks in ~/.claude/settings.json
python3 - "$HOOK_DIR/play.sh" "$SETTINGS" <<'PYTHON'
import json, os, sys

hook_script = sys.argv[1]
settings_path = sys.argv[2]

events = [
    'SessionStart', 'SessionEnd',
    'SubagentStart', 'SubagentStop',
    'UserPromptSubmit',
    'Stop', 'Notification', 'PermissionRequest',
    'PostToolUseFailure', 'PreCompact',
]

# PostToolUseFailure only fires for Bash tool errors; scope it with matcher
bash_only = {'PostToolUseFailure'}

if os.path.exists(settings_path):
    with open(settings_path) as f:
        settings = json.load(f)
else:
    settings = {}

hooks = settings.setdefault('hooks', {})

for event in events:
    command = f'bash {hook_script} {event}'
    matcher = 'Bash' if event in bash_only else ''
    entry = {
        'matcher': matcher,
        'hooks': [{'type': 'command', 'command': command, 'timeout': 10, 'async': True}],
    }

    event_hooks = hooks.get(event, [])
    # Remove any previous entry from this script (makes re-runs idempotent)
    event_hooks = [
        h for h in event_hooks
        if not any('hooks/sounds/play.sh' in hk.get('command', '')
                   for hk in h.get('hooks', []))
    ]
    event_hooks.append(entry)
    hooks[event] = event_hooks

settings['hooks'] = hooks

with open(settings_path, 'w') as f:
    json.dump(settings, f, indent=2)
    f.write('\n')

print(f'  hooks     → {settings_path}')
print(f'              ({", ".join(events)})')
PYTHON

# 4. Compile meeting-detect (requires Xcode command line tools)
MEETING_SWIFT="$REPO_DIR/scripts/meeting-detect.swift"
MEETING_BIN="$HOOK_DIR/meeting-detect"
if [[ -f "$MEETING_SWIFT" ]]; then
  if command -v swiftc &>/dev/null; then
    echo "  Compiling meeting-detect..."
    if swiftc -O -o "$MEETING_BIN" "$MEETING_SWIFT" -framework CoreAudio 2>/dev/null; then
      echo "  meeting-detect → $MEETING_BIN"
      echo "  Enable with: sounds meeting on"
    else
      echo "  Warning: meeting-detect compilation failed (skipping)"
    fi
  else
    echo "  Skipping meeting-detect (swiftc not found — install Xcode command line tools to enable)"
  fi
fi

# 6. Install skills
mkdir -p "$SKILLS_DIR"
for skill in sounds-toggle sounds-use; do
  if [[ -d "$REPO_DIR/skills/$skill" ]]; then
    mkdir -p "$SKILLS_DIR/$skill"
    cp "$REPO_DIR/skills/$skill/SKILL.md" "$SKILLS_DIR/$skill/SKILL.md"
    echo "  skill     → $SKILLS_DIR/$skill/"
  fi
done

# 7. Add `sounds` to PATH
SOUNDS_CMD="$HOOK_DIR/sounds.sh"
BIN_DIR=""
for candidate in "$HOME/.local/bin" "/usr/local/bin"; do
  if [[ -d "$candidate" && -w "$candidate" ]]; then
    BIN_DIR="$candidate"
    break
  fi
done

if [[ -n "$BIN_DIR" ]]; then
  ln -sf "$SOUNDS_CMD" "$BIN_DIR/sounds"
  echo "  sounds    → $BIN_DIR/sounds"
else
  mkdir -p "$HOME/.local/bin"
  ln -sf "$SOUNDS_CMD" "$HOME/.local/bin/sounds"
  echo "  sounds    → $HOME/.local/bin/sounds"
  echo ""
  echo "  Add ~/.local/bin to your PATH if it isn't already:"
  echo "    echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.zshrc"
fi

echo ""
echo "Done. Drop sound files into $SOUNDS_DIR/ to get started."
echo ""
echo "  Filenames map to hook events:"
echo "    stop.wav                  ← agent finished"
echo "    notification.wav          ← agent sent a notification"
echo "    permission_request.wav    ← waiting for tool approval"
echo "    post_tool_use_failure.wav ← tool call failed"
echo "    subagent_stop.wav         ← subagent finished"
echo ""
echo "  Supported formats: .wav  .mp3  .aiff  .m4a"
echo "  Manage packs and hooks: sounds help"
echo "  Toggle from a session:  /sounds-toggle"
