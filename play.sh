#!/usr/bin/env bash
# play.sh — minimal Claude Code sound hook for macOS
#
# Called by Claude Code with the hook event name as $1.
#
# Sound packs
# -----------
# Create subdirectories in ~/.claude/sounds/ — each is a pack:
#   ~/.claude/sounds/pack-a/stop.wav
#   ~/.claude/sounds/pack-b/stop.wav
# Packs cycle (round-robin) on each new session (SessionStart).
# With no subdirectories, sounds are loaded from ~/.claude/sounds/ directly.
#
# Configure hooks:   sounds help  or  ~/.claude/sounds/config
# Supported formats: .wav  .mp3  .aiff  .m4a

EVENT="${1:-}"
SOUNDS_DIR="${CLAUDE_SOUNDS_DIR:-$HOME/.claude/sounds}"
CONFIG="$SOUNDS_DIR/config"
STATE_FILE="$SOUNDS_DIR/.state"

# Load user config — simple KEY=value pairs
[[ -f "$CONFIG" ]] && source "$CONFIG"

# Master on/off switch
[[ "${ENABLED:-true}" == "true" ]] || exit 0

# --- Silent window: track when the user last submitted a prompt ---
# Records a timestamp on UserPromptSubmit so Stop can suppress sounds for
# tasks that finish too quickly (SILENT_WINDOW_SECONDS).
# Runs regardless of whether a sound plays for UserPromptSubmit itself.
if [[ "$EVENT" == "UserPromptSubmit" && "${SILENT_WINDOW_SECONDS:-0}" != "0" ]]; then
  echo "last_prompt_time=$(date +%s)" > "$STATE_FILE"
fi

# --- Pack resolution ---

PACKS=()
while IFS= read -r dir; do
  PACKS+=("$dir")
done < <(find "$SOUNDS_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)

if [[ -n "${PACK:-}" && -d "$SOUNDS_DIR/${PACK}" ]]; then
  # Pinned to a specific pack via `sounds pack use <name>`
  PACK_DIR="$SOUNDS_DIR/${PACK}"
elif [[ ${#PACKS[@]} -eq 0 ]]; then
  # No packs — use SOUNDS_DIR directly
  PACK_DIR="$SOUNDS_DIR"
else
  INDEX_FILE="$SOUNDS_DIR/.pack_index"
  INDEX=0
  [[ -f "$INDEX_FILE" ]] && INDEX=$(< "$INDEX_FILE")
  INDEX=$(( INDEX % ${#PACKS[@]} ))
  PACK_DIR="${PACKS[$INDEX]}"

  # Select pack on SessionStart — even if no sound plays for that event
  if [[ "$EVENT" == "SessionStart" && ${#PACKS[@]} -gt 1 ]]; then
    if [[ "${PACK_ORDER:-random}" == "random" ]]; then
      INDEX=$(( RANDOM % ${#PACKS[@]} ))
      PACK_DIR="${PACKS[$INDEX]}"
    fi
    echo $(( (INDEX + 1) % ${#PACKS[@]} )) > "$INDEX_FILE"
  fi
fi

# --- Map hook event → per-event enabled flag + sound file stem ---
# Defaults: Stop, Notification, PermissionRequest, PostToolUseFailure, SubagentStop on
#           Everything else off (noisy without a clear use case)
case "$EVENT" in
  Stop)               enabled="${STOP:-true}";                  sound="stop"                 ;;
  Notification)       enabled="${NOTIFICATION:-true}";          sound="notification"         ;;
  PermissionRequest)  enabled="${PERMISSION_REQUEST:-true}";    sound="permission_request"   ;;
  PostToolUseFailure) enabled="${POST_TOOL_USE_FAILURE:-true}"; sound="post_tool_use_failure" ;;
  SubagentStop)       enabled="${SUBAGENT_STOP:-true}";         sound="subagent_stop"        ;;
  SessionStart)       enabled="${SESSION_START:-false}";        sound="session_start"        ;;
  SessionEnd)         enabled="${SESSION_END:-false}";          sound="session_end"          ;;
  SubagentStart)      enabled="${SUBAGENT_START:-false}";       sound="subagent_start"       ;;
  UserPromptSubmit)   enabled="${USER_PROMPT_SUBMIT:-false}";   sound="user_prompt_submit"   ;;
  PreCompact)         enabled="${PRE_COMPACT:-false}";          sound="pre_compact"          ;;
  *)                  exit 0                                                                  ;;
esac

[[ "$enabled" == "true" ]] || exit 0

# --- Silent window: suppress Stop sounds for very short tasks ---
if [[ "$EVENT" == "Stop" && "${SILENT_WINDOW_SECONDS:-0}" != "0" && -f "$STATE_FILE" ]]; then
  last=$(grep "^last_prompt_time=" "$STATE_FILE" 2>/dev/null | cut -d= -f2 || echo "0")
  if [[ -n "$last" && "$last" != "0" ]]; then
    now=$(date +%s)
    elapsed=$(( now - last ))
    threshold=${SILENT_WINDOW_SECONDS%.*}  # truncate float to integer seconds
    [[ $elapsed -lt $threshold ]] && exit 0
  fi
fi

# --- Find the sound file ---
FILE=""

# CESP manifest pack: read openpeon.json and pick a random sound for this event
if [[ -f "$PACK_DIR/openpeon.json" ]]; then
  cesp_cat=""
  case "$EVENT" in
    Stop|SubagentStop)              cesp_cat="task.complete" ;;
    Notification)                   cesp_cat="task.progress" ;;
    PermissionRequest)              cesp_cat="input.required" ;;
    PostToolUseFailure)             cesp_cat="task.error" ;;
    SessionStart)                   cesp_cat="session.start" ;;
    SessionEnd)                     cesp_cat="session.end" ;;
    UserPromptSubmit|SubagentStart) cesp_cat="task.acknowledge" ;;
    PreCompact)                     cesp_cat="resource.limit" ;;
  esac

  if [[ -n "$cesp_cat" ]]; then
    FILE=$(python3 - "$PACK_DIR" "$cesp_cat" <<'PYEOF'
import json, sys, random, os
pack_dir, category = sys.argv[1], sys.argv[2]
try:
    m = json.load(open(os.path.join(pack_dir, 'openpeon.json')))
    sounds = m.get('categories', {}).get(category, {}).get('sounds', [])
    if sounds:
        s = random.choice(sounds)
        p = os.path.join(pack_dir, s['file'])
        if os.path.isfile(p):
            print(p)
except Exception:
    pass
PYEOF
    )
  fi
fi

# Flat-file fallback (hand-rolled packs without a manifest)
if [[ -z "$FILE" ]]; then
  flat_files=()
  for f in "$PACK_DIR/$sound".*; do
    [[ -f "$f" ]] || continue
    case "${f##*.}" in wav|mp3|aiff|m4a) flat_files+=("$f") ;; esac
  done
  [[ ${#flat_files[@]} -gt 0 ]] && FILE="${flat_files[$(( RANDOM % ${#flat_files[@]} ))]}"
fi

# No sound file for this event — silent exit (not an error)
[[ -z "$FILE" ]] && exit 0

# --- Pre-play checks (only run when there's actually a sound to play) ---

# Tab focus: suppress sound when this terminal session is the frontmost window/tab.
# For iTerm2, checks the specific tab using its TTY rather than just the app.
terminal_is_focused() {
  local frontmost
  frontmost=$(osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' 2>/dev/null) || return 1

  local my_tty
  my_tty=$(tty 2>/dev/null) || my_tty=""

  case "$frontmost" in
    iTerm2)
      [[ -z "$my_tty" ]] && return 1
      local active_ttys
      active_ttys=$(osascript -e 'tell application "iTerm2"
        set ttys to {}
        repeat with w in windows
          try
            set end of ttys to tty of current session of current tab of w
          end try
        end repeat
        return ttys
      end tell' 2>/dev/null || echo "")
      local IFS=','
      for t in $active_ttys; do
        t="${t//[[:space:]]/}"  # strip all whitespace (spaces, newlines)
        [[ "$t" == "$my_tty" ]] && return 0
      done
      return 1
      ;;
    Terminal)
      [[ -z "$my_tty" ]] && return 1
      local active_ttys
      active_ttys=$(osascript -e 'tell application "Terminal"
        set ttys to {}
        repeat with w in windows
          try
            set end of ttys to tty of selected tab of w
          end try
        end repeat
        return ttys
      end tell' 2>/dev/null || echo "")
      local IFS=','
      for t in $active_ttys; do
        t="${t//[[:space:]]/}"  # strip all whitespace (spaces, newlines)
        [[ "$t" == "$my_tty" ]] && return 0
      done
      return 1
      ;;
    Ghostty|ghostty|Warp|Alacritty|kitty|WezTerm)
      return 0  # Terminal app is frontmost — assume our session is focused
      ;;
    *)
      return 1  # Non-terminal app is frontmost
      ;;
  esac
}

if [[ "${SUPPRESS_SOUND_WHEN_TAB_FOCUSED:-true}" == "true" ]]; then
  terminal_is_focused && exit 0
fi

# Headphones only: suppress sounds when playing through built-in speakers.
# Uses system_profiler — adds ~1s latency when enabled.
if [[ "${HEADPHONES_ONLY:-false}" == "true" ]]; then
  output=$(system_profiler SPAudioDataType 2>/dev/null) || true
  section=$(echo "$output" | grep -B10 -A5 "Default Output Device: Yes" | tr '[:upper:]' '[:lower:]')
  if echo "$section" | grep -q "transport: built-in" && echo "$section" | grep -q "speaker"; then
    exit 0  # Built-in speakers detected — skip sound
  fi
fi

# Meeting detect: suppress sounds when the microphone is in use (e.g. on a call).
# Requires meeting-detect binary compiled by setup.sh.
MEETING_BIN="$HOME/.claude/hooks/sounds/meeting-detect"
if [[ "${MEETING_DETECT:-false}" == "true" && -x "$MEETING_BIN" ]]; then
  [[ "$("$MEETING_BIN" 2>/dev/null)" == "MIC_IN_USE" ]] && exit 0
fi

# --- Play ---
afplay -v "${VOLUME:-0.5}" "$FILE" &

exit 0
