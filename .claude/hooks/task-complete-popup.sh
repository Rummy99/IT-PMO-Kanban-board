#!/usr/bin/env bash
#
# Stop hook — congratulate the user when Claude finishes a task.
#
# Wired up in .claude/settings.json under hooks.Stop. Claude Code pipes the
# hook payload in on stdin (unused here) and reads JSON back on stdout.
#
# Two things this deliberately does NOT do:
#
#   1. Block. A modal dialog that waits for a click would stall the session
#      until someone dismissed it, and Stop fires at the end of every turn.
#      The GUI call is therefore detached and auto-dismisses on a timer.
#   2. Fail loudly. A hook that errors interrupts the session, and a missing
#      dialog binary is not worth that, so every branch swallows its errors
#      and the terminal message below always prints regardless.
#
# On a headless machine (CI, a container, SSH with no display) no popup is
# possible; the systemMessage on stdout is then the whole effect.

set -uo pipefail

TITLE="Claude Code"
HEADLINE="Congratulations — task complete!"
PROJECT="$(basename "${CLAUDE_PROJECT_DIR:-$PWD}")"
BODY="Claude Code has finished its task in ${PROJECT}."
DISMISS_AFTER=12   # seconds before the dialog closes itself

# Escape for AppleScript / shell-embedded double-quoted strings.
esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

show_popup() {
  case "$(uname -s)" in
    Darwin)
      if command -v osascript >/dev/null 2>&1; then
        osascript -e "display dialog \"$(esc "$BODY")\" \
          with title \"$(esc "$TITLE")\" \
          buttons {\"Thanks\"} default button 1 \
          with icon note \
          giving up after ${DISMISS_AFTER}" >/dev/null 2>&1 && return 0
      fi
      ;;
    Linux)
      # Only attempt a GUI on Linux when a display is actually attached.
      if [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
        if command -v zenity >/dev/null 2>&1; then
          zenity --info --title="$TITLE" --text="$HEADLINE\n\n$BODY" \
            --timeout="$DISMISS_AFTER" >/dev/null 2>&1 && return 0
        elif command -v kdialog >/dev/null 2>&1; then
          kdialog --title "$TITLE" --msgbox "$HEADLINE

$BODY" >/dev/null 2>&1 && return 0
        elif command -v notify-send >/dev/null 2>&1; then
          notify-send -t "$((DISMISS_AFTER * 1000))" "$HEADLINE" "$BODY" \
            >/dev/null 2>&1 && return 0
        elif command -v xmessage >/dev/null 2>&1; then
          xmessage -center -timeout "$DISMISS_AFTER" "$HEADLINE

$BODY" >/dev/null 2>&1 && return 0
        fi
      fi
      ;;
    MINGW* | MSYS* | CYGWIN*)
      if command -v powershell.exe >/dev/null 2>&1; then
        powershell.exe -NoProfile -WindowStyle Hidden -Command \
          "Add-Type -AssemblyName System.Windows.Forms; \
           [System.Windows.Forms.MessageBox]::Show('$(esc "$BODY")','$(esc "$TITLE")')" \
          >/dev/null 2>&1 && return 0
      fi
      ;;
  esac
  return 1
}

# Detach so the dialog's lifetime is never on the session's critical path.
( show_popup & ) >/dev/null 2>&1
disown 2>/dev/null || true

# Always emit the terminal message. This is the only visible effect on a
# headless machine, and a useful confirmation everywhere else.
printf '{"systemMessage": "%s %s"}\n' "🎉" "$HEADLINE"

exit 0
