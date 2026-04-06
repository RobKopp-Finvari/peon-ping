#!/usr/bin/env bash
# sounds — CLI for Claude Code sound hook
# Usage: sounds <command> [args]

set -euo pipefail

SOUNDS_DIR="${CLAUDE_SOUNDS_DIR:-$HOME/.claude/sounds}"
CONFIG="$SOUNDS_DIR/config"

if [[ ! -f "$CONFIG" ]]; then
  echo "sounds: config not found at $CONFIG" >&2
  echo "Run setup.sh to initialize." >&2
  exit 1
fi

# --- Config helpers ---

config_get() {
  local key="$1" default="${2:-}"
  local val
  val=$(grep "^${key}=" "$CONFIG" 2>/dev/null | tail -1 | cut -d= -f2-)
  echo "${val:-$default}"
}

config_set() {
  local key="$1" value="$2"
  if grep -q "^${key}=" "$CONFIG" 2>/dev/null; then
    sed -i '' "s|^${key}=.*|${key}=${value}|" "$CONFIG"
  else
    echo "${key}=${value}" >> "$CONFIG"
  fi
}

config_unset() {
  local key="$1"
  sed -i '' "/^${key}=/d" "$CONFIG"
}

# --- Pack helpers ---

list_pack_dirs() {
  find "$SOUNDS_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort
}

current_pack_dir() {
  local pinned
  pinned=$(config_get PACK "")
  if [[ -n "$pinned" && -d "$SOUNDS_DIR/$pinned" ]]; then
    echo "$SOUNDS_DIR/$pinned"
    return
  fi

  local packs=()
  while IFS= read -r dir; do
    [[ -n "$dir" ]] && packs+=("$dir")
  done < <(list_pack_dirs)

  if [[ ${#packs[@]} -eq 0 ]]; then
    echo "$SOUNDS_DIR"
    return
  fi

  local index=0
  [[ -f "$SOUNDS_DIR/.pack_index" ]] && index=$(< "$SOUNDS_DIR/.pack_index")
  index=$(( index % ${#packs[@]} ))
  echo "${packs[$index]}"
}

# --- Hook name mappings ---

hook_key() {
  case "$1" in
    stop)                          echo "STOP" ;;
    notification|notify)           echo "NOTIFICATION" ;;
    permission|permission_request) echo "PERMISSION_REQUEST" ;;
    failure|post_tool_use_failure) echo "POST_TOOL_USE_FAILURE" ;;
    subagent_stop)                 echo "SUBAGENT_STOP" ;;
    session_start)                 echo "SESSION_START" ;;
    session_end)                   echo "SESSION_END" ;;
    subagent_start)                echo "SUBAGENT_START" ;;
    prompt|user_prompt_submit)     echo "USER_PROMPT_SUBMIT" ;;
    compact|pre_compact)           echo "PRE_COMPACT" ;;
    *)                             echo "" ;;
  esac
}

hook_sound() {
  case "$1" in
    stop)                          echo "stop" ;;
    notification|notify)           echo "notification" ;;
    permission|permission_request) echo "permission_request" ;;
    failure|post_tool_use_failure) echo "post_tool_use_failure" ;;
    subagent_stop)                 echo "subagent_stop" ;;
    session_start)                 echo "session_start" ;;
    session_end)                   echo "session_end" ;;
    subagent_start)                echo "subagent_start" ;;
    prompt|user_prompt_submit)     echo "user_prompt_submit" ;;
    compact|pre_compact)           echo "pre_compact" ;;
    *)                             echo "" ;;
  esac
}

hook_cesp_cat() {
  case "$1" in
    stop|subagent_stop)                       echo "task.complete" ;;
    notification|notify)                      echo "task.progress" ;;
    permission|permission_request)            echo "input.required" ;;
    failure|post_tool_use_failure)            echo "task.error" ;;
    session_start)                            echo "session.start" ;;
    session_end)                              echo "session.end" ;;
    subagent_start|prompt|user_prompt_submit) echo "task.acknowledge" ;;
    compact|pre_compact)                      echo "resource.limit" ;;
    *)                                        echo "" ;;
  esac
}

find_sound_file() {
  local pack_dir="$1" stem="$2"
  local files=()
  for f in "$pack_dir/$stem".*; do
    [[ -f "$f" ]] || continue
    case "${f##*.}" in wav|mp3|aiff|m4a) files+=("$f") ;; esac
  done
  [[ ${#files[@]} -gt 0 ]] && echo "${files[$(( RANDOM % ${#files[@]} ))]}" || echo ""
}

count_sound_files() {
  local pack_dir="$1" stem="$2"
  local count=0
  for f in "$pack_dir/$stem".*; do
    [[ -f "$f" ]] || continue
    case "${f##*.}" in wav|mp3|aiff|m4a) (( count++ )) ;; esac
  done
  echo "$count"
}

cesp_find_sound() {
  local pack_dir="$1" category="$2"
  python3 - "$pack_dir" "$category" <<'PYEOF'
import json, sys, os
pack_dir, category = sys.argv[1], sys.argv[2]
try:
    m = json.load(open(os.path.join(pack_dir, 'openpeon.json')))
    sounds = m.get('categories', {}).get(category, {}).get('sounds', [])
    if sounds:
        p = os.path.join(pack_dir, sounds[0]['file'])
        if os.path.isfile(p):
            print(p)
except Exception:
    pass
PYEOF
}

pack_install() {
  local name="$1"

  if ! echo "$name" | grep -qE '^[a-z0-9][a-z0-9_-]{0,63}$'; then
    echo "sounds: invalid pack name '$name'" >&2; exit 1
  fi

  local pack_dir="$SOUNDS_DIR/$name"

  # Fetch registry to a temp file (avoid stdin conflict with heredoc)
  local tmp_reg
  tmp_reg=$(mktemp)
  echo "  Fetching registry..."
  if ! curl -sf "https://raw.githubusercontent.com/PeonPing/registry/main/index.json" -o "$tmp_reg"; then
    rm -f "$tmp_reg"
    echo "sounds: failed to fetch registry" >&2; exit 1
  fi

  # Extract pack metadata
  local pack_meta
  if ! pack_meta=$(python3 - "$name" "$tmp_reg" <<'PYEOF'
import json, sys
name, reg_file = sys.argv[1], sys.argv[2]
data = json.load(open(reg_file))
p = next((p for p in data.get('packs', []) if p['name'] == name), None)
if not p:
    sys.exit(1)
print(p.get('source_repo', ''))
print(p.get('source_ref', 'main'))
print(p.get('source_path', name))
print(p.get('display_name', name))
PYEOF
  ); then
    rm -f "$tmp_reg"
    echo "sounds: pack '$name' not found in registry" >&2; exit 1
  fi
  rm -f "$tmp_reg"

  local source_repo source_ref source_path display_name
  source_repo=$(echo "$pack_meta" | sed -n '1p')
  source_ref=$(echo "$pack_meta"  | sed -n '2p')
  source_path=$(echo "$pack_meta" | sed -n '3p')
  display_name=$(echo "$pack_meta" | sed -n '4p')

  local base_url="https://raw.githubusercontent.com/${source_repo}/${source_ref}/${source_path}"

  # Download manifest
  echo "  Installing $display_name..."
  mkdir -p "$pack_dir/sounds"
  if ! curl -sf "$base_url/openpeon.json" -o "$pack_dir/openpeon.json"; then
    rm -rf "$pack_dir"
    echo "sounds: failed to download manifest for '$name'" >&2; exit 1
  fi

  # Parse manifest: emit encoded_url|local_path|sha256 per unique sound file
  local file_list
  if ! file_list=$(python3 - "$pack_dir" <<'PYEOF'
import json, sys, os, urllib.parse
pack_dir = sys.argv[1]
m = json.load(open(os.path.join(pack_dir, 'openpeon.json')))
seen = set()
for cat in m.get('categories', {}).values():
    for s in cat.get('sounds', []):
        f = s['file']
        if f in seen:
            continue
        seen.add(f)
        norm = os.path.normpath(f)
        if norm.startswith('..') or os.path.isabs(norm):
            continue
        encoded = urllib.parse.quote(f, safe='/')
        print('{}|{}|{}'.format(encoded, f, s.get('sha256', '')))
PYEOF
  ); then
    rm -rf "$pack_dir"
    echo "sounds: failed to parse manifest for '$name'" >&2; exit 1
  fi

  # Download each sound file
  local failed=0
  while IFS='|' read -r encoded_path local_path expected_sha; do
    [[ -z "$local_path" ]] && continue
    local dest="$pack_dir/$local_path"
    mkdir -p "$(dirname "$dest")"
    printf "    %-38s" "$(basename "$local_path")"
    if ! curl -sf "$base_url/$encoded_path" -o "$dest"; then
      echo "FAILED"
      failed=1
      continue
    fi
    if [[ -n "$expected_sha" ]]; then
      local actual_sha
      actual_sha=$(shasum -a 256 "$dest" | cut -d' ' -f1)
      if [[ "$actual_sha" != "$expected_sha" ]]; then
        echo "CHECKSUM MISMATCH"
        failed=1
        continue
      fi
    fi
    echo "OK"
  done <<< "$file_list"

  if [[ $failed -ne 0 ]]; then
    rm -rf "$pack_dir"
    echo "sounds: install failed — removing partial download" >&2; exit 1
  fi

  echo "  '$name' installed"
}

ALL_HOOKS=(stop notification permission_request post_tool_use_failure subagent_stop
           session_start session_end subagent_start user_prompt_submit pre_compact)
DEFAULT_ON=(stop notification permission_request post_tool_use_failure subagent_stop)

is_default_on() {
  local hook="$1"
  for d in "${DEFAULT_ON[@]}"; do [[ "$d" == "$hook" ]] && return 0; done
  return 1
}

# --- Commands ---

cmd_toggle() {
  local current
  current=$(config_get ENABLED "true")
  if [[ "$current" == "true" ]]; then
    config_set ENABLED false
    echo "sounds: paused"
  else
    config_set ENABLED true
    echo "sounds: resumed"
  fi
}

cmd_status() {
  local enabled pinned pack_dir pack_name
  enabled=$(config_get ENABLED "true")
  pinned=$(config_get PACK "")
  pack_dir=$(current_pack_dir)
  pack_name=$(basename "$pack_dir")

  echo "Sounds:  $([ "$enabled" == "true" ] && echo "ON" || echo "OFF (paused)")"
  echo "Volume:  $(config_get VOLUME "0.5")"

  # Pack info
  local packs=()
  while IFS= read -r dir; do
    [[ -n "$dir" ]] && packs+=("$dir")
  done < <(list_pack_dirs)

  if [[ ${#packs[@]} -eq 0 ]]; then
    echo "Pack:    (no packs — loading from $SOUNDS_DIR directly)"
  elif [[ -n "$pinned" ]]; then
    echo "Pack:    $pinned (pinned)"
  else
    local index=0 pack_order
    [[ -f "$SOUNDS_DIR/.pack_index" ]] && index=$(< "$SOUNDS_DIR/.pack_index")
    index=$(( index % ${#packs[@]} ))
    pack_order=$(config_get PACK_ORDER "random")
    echo "Pack:    $pack_name ($(( index + 1 )) of ${#packs[@]}, $pack_order)"
  fi

  # Optional features
  local meeting headphones focused silent
  meeting=$(config_get MEETING_DETECT "false")
  headphones=$(config_get HEADPHONES_ONLY "false")
  focused=$(config_get SUPPRESS_SOUND_WHEN_TAB_FOCUSED "true")
  silent=$(config_get SILENT_WINDOW_SECONDS "0")

  echo ""
  echo "Options:"
  local meeting_bin="$HOME/.claude/hooks/sounds/meeting-detect"
  local meeting_status=""
  if [[ "$meeting" == "true" ]]; then
    [[ -x "$meeting_bin" ]] && meeting_status=" (binary ready)" || meeting_status=" (binary missing — run setup.sh)"
  fi
  echo "  meeting_detect               $([ "$meeting" == "true" ] && echo "on${meeting_status}" || echo "off")"
  echo "  headphones_only              $([ "$headphones" == "true" ] && echo "on" || echo "off")"
  echo "  suppress_sound_when_focused  $([ "$focused" == "true" ] && echo "on" || echo "off")"
  echo "  silent_window_seconds        $silent"

  echo ""
  printf "%-26s %-5s %s\n" "Hook" "State" "Sound file"
  printf "%-26s %-5s %s\n" "─────────────────────────" "─────" "───────────────────"

  for hook in "${ALL_HOOKS[@]}"; do
    local key sound_stem file state
    key=$(hook_key "$hook")
    sound_stem=$(hook_sound "$hook")
    file=$(find_sound_file "$pack_dir" "$sound_stem")

    local default; is_default_on "$hook" && default="true" || default="false"
    state=$(config_get "$key" "$default")

    if [[ "$state" == "true" ]]; then
      local display_file count
      if [[ -n "$file" ]]; then
        count=$(count_sound_files "$pack_dir" "$sound_stem")
        display_file=$(basename "$file")
        [[ $count -gt 1 ]] && display_file="$display_file  (+$(( count - 1 )) more)"
      else
        display_file="— no sound file"
      fi
      printf "%-26s %-5s %s\n" "$hook" "on" "$display_file"
    else
      printf "%-26s %s\n" "$hook" "off"
    fi
  done
}

cmd_enable() {
  local hook="${1:-}"
  if [[ -z "$hook" || "$hook" == "all" ]]; then
    for h in "${ALL_HOOKS[@]}"; do config_set "$(hook_key "$h")" true; done
    echo "sounds: all hooks enabled"
    return
  fi
  local key
  key=$(hook_key "$hook")
  if [[ -z "$key" ]]; then
    echo "sounds: unknown hook '$hook'" >&2
    echo "Valid: ${ALL_HOOKS[*]}" >&2; exit 1
  fi
  config_set "$key" true
  echo "sounds: $hook enabled"
}

cmd_disable() {
  local hook="${1:-}"
  if [[ -z "$hook" || "$hook" == "all" ]]; then
    for h in "${ALL_HOOKS[@]}"; do config_set "$(hook_key "$h")" false; done
    echo "sounds: all hooks disabled"
    return
  fi
  local key
  key=$(hook_key "$hook")
  if [[ -z "$key" ]]; then
    echo "sounds: unknown hook '$hook'" >&2
    echo "Valid: ${ALL_HOOKS[*]}" >&2; exit 1
  fi
  config_set "$key" false
  echo "sounds: $hook disabled"
}

cmd_volume() {
  local val="${1:-}"
  if [[ -z "$val" ]]; then
    echo "Volume: $(config_get VOLUME "0.5")"
    return
  fi
  if ! echo "$val" | grep -qE '^(0(\.[0-9]+)?|1(\.0+)?)$'; then
    echo "sounds: volume must be between 0.0 and 1.0" >&2; exit 1
  fi
  config_set VOLUME "$val"
  echo "sounds: volume set to $val"
}

cmd_meeting() {
  local val="${1:-}"
  if [[ -z "$val" ]]; then
    local current meeting_bin
    current=$(config_get MEETING_DETECT "false")
    meeting_bin="$HOME/.claude/hooks/sounds/meeting-detect"
    echo "meeting_detect: $current"
    [[ "$current" == "true" && ! -x "$meeting_bin" ]] && echo "  Warning: binary not found — run setup.sh to compile it"
    return
  fi
  case "$val" in
    on|true)   config_set MEETING_DETECT true;  echo "sounds: meeting detect enabled" ;;
    off|false) config_set MEETING_DETECT false; echo "sounds: meeting detect disabled" ;;
    *)
      echo "Usage: sounds meeting [on|off]" >&2; exit 1
      ;;
  esac
}

cmd_headphones() {
  local val="${1:-}"
  if [[ -z "$val" ]]; then
    echo "headphones_only: $(config_get HEADPHONES_ONLY "false")"
    return
  fi
  case "$val" in
    on|true)   config_set HEADPHONES_ONLY true;  echo "sounds: headphones only enabled" ;;
    off|false) config_set HEADPHONES_ONLY false; echo "sounds: headphones only disabled" ;;
    *)
      echo "Usage: sounds headphones [on|off]" >&2; exit 1
      ;;
  esac
}

cmd_focused() {
  local val="${1:-}"
  if [[ -z "$val" ]]; then
    echo "suppress_sound_when_tab_focused: $(config_get SUPPRESS_SOUND_WHEN_TAB_FOCUSED "true")"
    return
  fi
  case "$val" in
    on|true)   config_set SUPPRESS_SOUND_WHEN_TAB_FOCUSED true;  echo "sounds: tab focus suppression enabled" ;;
    off|false) config_set SUPPRESS_SOUND_WHEN_TAB_FOCUSED false; echo "sounds: tab focus suppression disabled" ;;
    *)
      echo "Usage: sounds focused [on|off]" >&2; exit 1
      ;;
  esac
}

cmd_silent() {
  local val="${1:-}"
  if [[ -z "$val" ]]; then
    echo "silent_window_seconds: $(config_get SILENT_WINDOW_SECONDS "0")"
    return
  fi
  if ! echo "$val" | grep -qE '^[0-9]+(\.[0-9]+)?$'; then
    echo "sounds: value must be a number of seconds (e.g. 3 or 3.5)" >&2; exit 1
  fi
  config_set SILENT_WINDOW_SECONDS "$val"
  echo "sounds: silent window set to ${val}s"
}

cmd_pack() {
  local sub="${1:-list}"
  shift || true

  case "$sub" in
    list)
      local packs=()
      while IFS= read -r dir; do
        [[ -n "$dir" ]] && packs+=("$dir")
      done < <(list_pack_dirs)

      if [[ ${#packs[@]} -eq 0 ]]; then
        echo "No packs installed."
        echo "Create subdirectories in $SOUNDS_DIR/ to define packs."
        return
      fi

      local pinned index
      pinned=$(config_get PACK "")
      index=0
      [[ -f "$SOUNDS_DIR/.pack_index" ]] && index=$(< "$SOUNDS_DIR/.pack_index")
      index=$(( index % ${#packs[@]} ))

      for i in "${!packs[@]}"; do
        local name marker=""
        name=$(basename "${packs[$i]}")
        if [[ -n "$pinned" && "$name" == "$pinned" ]]; then
          marker="  (pinned)"
        elif [[ -z "$pinned" && $i -eq $index ]]; then
          marker="  (active)"
        fi
        echo "$name$marker"
      done
      ;;

    use)
      local name="${1:-}"
      [[ -z "$name" ]] && { echo "Usage: sounds pack use <name>" >&2; exit 1; }
      if [[ ! -f "$SOUNDS_DIR/$name/openpeon.json" ]]; then
        [[ -d "$SOUNDS_DIR/$name" ]] && rm -rf "$SOUNDS_DIR/$name"
        pack_install "$name"
      fi

      # If random mode is active and no pack is pinned, ask before pinning
      local current_order current_pin
      current_order=$(config_get PACK_ORDER "random")
      current_pin=$(config_get PACK "")
      if [[ "$current_order" == "random" && -z "$current_pin" && -t 0 ]]; then
        local choice=""
        echo "Random mode is active. Pin to '$name' or just add to rotation?"
        read -rp "  [p] Pin to this pack  [r] Add to rotation (default): " choice
        case "$choice" in
          p|P)
            config_set PACK "$name"
            echo "sounds: pinned to '$name' (random cycling paused)"
            ;;
          *)
            echo "sounds: '$name' added to rotation"
            ;;
        esac
      else
        config_set PACK "$name"
        echo "sounds: using pack '$name'"
      fi
      ;;

    install)
      local name="${1:-}"
      [[ -z "$name" ]] && { echo "Usage: sounds pack install <name>" >&2; exit 1; }
      if [[ -f "$SOUNDS_DIR/$name/openpeon.json" ]]; then
        echo "sounds: pack '$name' is already installed"
      else
        [[ -d "$SOUNDS_DIR/$name" ]] && rm -rf "$SOUNDS_DIR/$name"
        pack_install "$name"
        echo "sounds: '$name' installed and added to rotation"
      fi
      ;;

    cycle)
      config_unset PACK
      config_set PACK_ORDER cycle
      echo "sounds: cycling resumed (round-robin)"
      ;;

    random)
      config_unset PACK
      config_set PACK_ORDER random
      echo "sounds: cycling resumed (random)"
      ;;

    next)
      local packs=()
      while IFS= read -r dir; do
        [[ -n "$dir" ]] && packs+=("$dir")
      done < <(list_pack_dirs)

      if [[ ${#packs[@]} -le 1 ]]; then
        echo "sounds: only one pack available" >&2; exit 1
      fi

      local index=0
      [[ -f "$SOUNDS_DIR/.pack_index" ]] && index=$(< "$SOUNDS_DIR/.pack_index")
      index=$(( (index + 1) % ${#packs[@]} ))
      echo "$index" > "$SOUNDS_DIR/.pack_index"
      echo "sounds: switched to '$(basename "${packs[$index]}")'"
      ;;

    remove)
      local name="${1:-}"
      [[ -z "$name" ]] && { echo "Usage: sounds pack remove <name>" >&2; exit 1; }
      if [[ ! -d "$SOUNDS_DIR/$name" ]]; then
        echo "sounds: pack '$name' is not installed" >&2; exit 1
      fi
      rm -rf "$SOUNDS_DIR/$name"
      local pinned
      pinned=$(config_get PACK "")
      if [[ "$pinned" == "$name" ]]; then
        config_unset PACK
        echo "sounds: '$name' removed (was pinned — cycling resumed)"
      else
        echo "sounds: '$name' removed"
      fi
      ;;

    *)
      echo "Usage: sounds pack [list|use <name>|install <name>|remove <name>|cycle|random|next]" >&2; exit 1
      ;;
  esac
}

cmd_preview() {
  local hook="${1:-stop}"
  local sound_stem
  sound_stem=$(hook_sound "$hook")
  if [[ -z "$sound_stem" ]]; then
    echo "sounds: unknown hook '$hook'" >&2; exit 1
  fi
  local pack_dir file
  pack_dir=$(current_pack_dir)
  file=$(find_sound_file "$pack_dir" "$sound_stem")

  # CESP manifest fallback for packs that use openpeon.json
  if [[ -z "$file" && -f "$pack_dir/openpeon.json" ]]; then
    local cesp_cat
    cesp_cat=$(hook_cesp_cat "$hook")
    [[ -n "$cesp_cat" ]] && file=$(cesp_find_sound "$pack_dir" "$cesp_cat")
  fi

  if [[ -z "$file" ]]; then
    echo "sounds: no sound file for '$hook' in $(basename "$pack_dir")" >&2; exit 1
  fi
  echo "Playing: $file"
  afplay -v "$(config_get VOLUME "0.5")" "$file"
}

cmd_help() {
  cat <<EOF
Usage: sounds <command> [args]

Control
  toggle                    pause or resume all sounds
  enable [hook|all]         enable a specific hook or all
  disable [hook|all]        disable a specific hook or all
  status                    show full state — sounds, pack, options, hooks
  preview [hook]            play the sound for a hook to test it (default: stop)

Volume & options
  volume [0.0-1.0]          get or set playback volume
  meeting [on|off]          suppress sounds when microphone is in use
  headphones [on|off]       only play sounds through headphones (not speakers)
  focused [on|off]          suppress sounds when this terminal tab is focused
  silent [seconds]          suppress Stop sounds for tasks shorter than N seconds

Packs
  pack list                 list installed packs
  pack use <name>           pin to a pack (prompts in random mode)
  pack install <name>       install a pack without pinning
  pack remove <name>        uninstall a pack
  pack cycle                unpin, resume round-robin cycling
  pack random               unpin, pick a random pack each session
  pack next                 manually advance to the next pack

Hooks
  stop                      agent finished a task              (on by default)
  notification              agent sent a notification          (on by default)
  permission_request        waiting for tool approval          (on by default)
  post_tool_use_failure     a tool call (Bash) failed          (on by default)
  subagent_stop             a subagent finished                (on by default)
  session_start             new session                        (off by default)
  session_end               session ended                      (off by default)
  subagent_start            subagent started                   (off by default)
  user_prompt_submit        prompt submitted                   (off by default)
  pre_compact               context compacting                 (off by default)

Sound files: $SOUNDS_DIR
Config:      $CONFIG
EOF
}

# --- Dispatch ---

CMD="${1:-help}"
shift || true

case "$CMD" in
  toggle)         cmd_toggle ;;
  status)         cmd_status ;;
  enable)         cmd_enable "${1:-}" ;;
  disable)        cmd_disable "${1:-}" ;;
  volume)         cmd_volume "${1:-}" ;;
  meeting)        cmd_meeting "${1:-}" ;;
  headphones)     cmd_headphones "${1:-}" ;;
  focused)        cmd_focused "${1:-}" ;;
  silent)         cmd_silent "${1:-}" ;;
  pack)           cmd_pack "$@" ;;
  preview)        cmd_preview "${1:-stop}" ;;
  help|--help|-h) cmd_help ;;
  *)
    echo "sounds: unknown command '$CMD'" >&2
    echo "Run 'sounds help' for usage." >&2
    exit 1
    ;;
esac
