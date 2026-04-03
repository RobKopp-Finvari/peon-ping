---
name: sounds-use
description: Switch to a specific sound pack for this session, or manage pack cycling. Use when user wants a particular pack, wants to advance to the next pack, or wants to resume automatic cycling.
user_invocable: true
---

# sounds-use

Switch to a specific sound pack or manage pack rotation.

## List available packs

```bash
bash ~/.claude/hooks/sounds/sounds.sh pack list
```

## Pin a specific pack

```bash
bash ~/.claude/hooks/sounds/sounds.sh pack use <name>
```

The pack stays active until you unpin it. Packs are subdirectories of `~/.claude/sounds/`.

## Resume automatic cycling

```bash
bash ~/.claude/hooks/sounds/sounds.sh pack cycle
```

Clears the pin and resumes round-robin cycling through packs on each new session.

## Randomize pack selection

```bash
bash ~/.claude/hooks/sounds/sounds.sh pack random
```

Clears the pin and picks a random pack on each new session instead of cycling sequentially.

## Advance to the next pack manually

```bash
bash ~/.claude/hooks/sounds/sounds.sh pack next
```

## Examples

- "Use the warcraft pack" → list packs, then run `pack use warcraft`
- "Switch to glados" → list packs, then run `pack use glados`
- "Go back to cycling through packs" → run `pack cycle`
- "Randomize packs" → run `pack random`
- "What packs do I have?" → run `pack list`
- "Next pack" → run `pack next`
