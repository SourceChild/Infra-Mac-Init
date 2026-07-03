#!/usr/bin/env bash
# =============================================================================
# Infra-Mac-Init · provision.sh — macOS system/user preferences.
#
# SCAFFOLD. The values below are conservative, widely-safe EXAMPLES. Replace /
# extend them with the real baseline captured from a known-good clean machine.
#
#   HOW TO CAPTURE A BASELINE (run on the clean reference Mac — e.g. Mini or MP):
#     # 1. snapshot every domain's defaults BEFORE you change anything:
#     defaults read > ~/defaults-baseline-$(scutil --get LocalHostName)-$(date +%F).txt
#     # 2. change a setting in System Settings, then diff to find the exact key:
#     defaults read > /tmp/after.txt; diff ~/defaults-baseline-*.txt /tmp/after.txt
#     # (see the repo notes for the full capture recipe)
#
# Default group always applies. Optional groups are opt-in:
#   PROVISION_DEV=1 PROVISION_MEDIA=1 PROVISION_PRIVACY=1 ./provision.sh
# Idempotent: re-running just re-asserts the same values.
# =============================================================================
set -euo pipefail
log()  { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
setd() { # setd <domain> <key> <type> <value>   — write + echo what changed
  defaults write "$1" "$2" "$3" "$4" && printf '  %s %s = %s\n' "$1" "$2" "$4"
}

log "Applying macOS preferences on $(scutil --get LocalHostName 2>/dev/null || hostname -s)"
# close System Settings so it doesn't overwrite on exit
osascript -e 'tell application "System Settings" to quit' >/dev/null 2>&1 || true

# ---- DEFAULT (every machine) — EXAMPLES, reconcile with the captured baseline ----
log "Default group"
setd NSGlobalDomain KeyRepeat -int 2                       # fast key repeat
setd NSGlobalDomain InitialKeyRepeat -int 15
setd NSGlobalDomain ApplePressAndHoldEnabled -bool false   # key repeat over accents
setd NSGlobalDomain AppleShowAllExtensions -bool true      # show all file extensions
setd com.apple.finder AppleShowAllFiles -bool true         # show hidden files
setd com.apple.finder ShowPathbar -bool true
setd com.apple.finder FXPreferredViewStyle -string "Nlsv"  # list view
setd com.apple.finder _FXSortFoldersFirst -bool true
setd com.apple.screencapture location -string "$HOME/Desktop"
setd com.apple.screencapture type -string "png"
setd com.apple.dock autohide -bool true
setd com.apple.dock show-recents -bool false

# ---- OPTIONAL: developer ----------------------------------------------------
if [ "${PROVISION_DEV:-0}" = 1 ]; then
  log "Optional: developer"
  setd com.apple.dock tilesize -int 44
  setd NSGlobalDomain AppleKeyboardUIMode -int 3           # full keyboard control
  setd com.apple.desktopservices DSDontWriteNetworkStores -bool true  # no .DS_Store on shares
fi

# ---- OPTIONAL: media / capture ---------------------------------------------
if [ "${PROVISION_MEDIA:-0}" = 1 ]; then
  log "Optional: media"
  setd com.apple.screencapture disable-shadow -bool true
  setd com.apple.QuickTimePlayerX MGPlayMovieOnOpen -bool true
fi

# ---- OPTIONAL: privacy / security ------------------------------------------
if [ "${PROVISION_PRIVACY:-0}" = 1 ]; then
  log "Optional: privacy"
  setd com.apple.screensaver askForPassword -int 1
  setd com.apple.screensaver askForPasswordDelay -int 0
fi

log "Restarting affected UI services…"
for app in Dock Finder SystemUIServer; do killall "$app" >/dev/null 2>&1 || true; done
log "Done. Some changes need a logout/restart to fully apply."
