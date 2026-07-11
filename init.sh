#!/usr/bin/env bash
# =============================================================================
# infra-mac-init · init.sh — anonymous first-touch bootstrapper for a fresh Mac.
#
# BARE MINIMUM to get a bare machine ready to reach your PRIVATE config repo, and
# nothing more. Contains NO personal / host / app / repo data — the only per-user
# value (the private repo URL) is passed in or prompted, never baked in.
#
#   Run ON the new machine, in Terminal:
#     curl -fsSL https://raw.githubusercontent.com/SourceChild/infra-mac-init/main/init.sh \
#       | bash -s -- git@github.com:SourceChild/infra-mac-deploy.git
#   …or run with no argument: it defaults to SourceChild/infra-mac-deploy (override by passing a URL).
#
# What it does, in order (each step is idempotent + recorded under ~/.infra-mac/):
#   1. Command Line Tools     (gives git; curl-only to get here)   ── + BETA guard
#   2. Accept the Xcode license (built in — no-op unless full Xcode is already here)
#   3. Homebrew               (non-interactive; needed to install `gh`)
#   4. A per-machine GitHub SSH key  <hostname>-gh  — created AND registered on GitHub
#   5. AUTHORIZATION GATE: can this GitHub account actually reach the private repo?
#      yes → continue · no → HALT and explain (owner hasn't shared it with you)
#   6. (remote sessions only) an optional return-access key  new-<hostname>-<operator>
#   7. clone the private repo
#   8. auto-trigger provision.sh (settings) — OPT-OUT
#   9. hand off to install.sh (apps & services) — OPT-OUT
#
# Opt-outs (for unattended runs):  INFRA_SKIP_PROVISION=1   INFRA_SKIP_INSTALL=1
# =============================================================================
set -euo pipefail
SCRIPT=init

log()  { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }
die()  { printf '\n\033[1;31m[halt]\033[0m %s\n\n' "$*" >&2; exit 1; }
ask()  { local a; read -r -p "$1" a </dev/tty || a=""; printf '%s' "$a"; }

# ---- shared state markers (~/.infra-mac): so install.sh's preflight can see ---
# what init already did — and so a re-run skips finished steps.
STATE_DIR="${INFRA_STATE_DIR:-$HOME/.infra-mac}"; mkdir -p "$STATE_DIR" 2>/dev/null || true
_host()  { scutil --get LocalHostName 2>/dev/null || hostname -s; }
mark()   { printf '%s\t%s\t%s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$(_host)" "$SCRIPT${2:+ — $2}" > "$STATE_DIR/$1" 2>/dev/null || true; }

[ "$(uname -s)" = "Darwin" ] || die "macOS only."

# ---- identity / mode --------------------------------------------------------
HOST="$(_host)"
GH_KEY="$HOME/.ssh/${HOST}-gh"                        # naming: <hostname>-gh
REMOTE_SESSION=false; [ -n "${SSH_CONNECTION:-}" ] && REMOTE_SESSION=true
PRIVATE_REPO="${1:-git@github.com:SourceChild/infra-mac-deploy.git}"   # concrete default; pass a URL to override
TARGET_DIR="${2:-$HOME/dev/infra-mac-deploy}"        # where the private repo lands
OSVER="$(sw_vers -productVersion)"; BUILD="$(sw_vers -buildVersion)"
IS_BETA=false; [[ "$BUILD" =~ [a-z]$ ]] && IS_BETA=true
log "init on '${HOST}'  ($OSVER $BUILD$( $IS_BETA && printf ' — BETA'); remote session: ${REMOTE_SESSION})"

# ---- 0. sudo up front -------------------------------------------------------
# Homebrew's non-interactive installer checks for ALREADY-cached sudo (`sudo -n -v`)
# and hard-fails if it isn't primed — so grab it once here (one password prompt) and
# keep it alive through the long CLT wait + the Homebrew install. The Xcode-license
# step also uses it. Without this, Homebrew dies with "Need sudo access on macOS".
log "Requesting administrator (sudo) access up front…"
sudo -v || die "This account needs administrator rights (sudo).
      Make '$(id -un)' an Administrator (System Settings ▸ Users & Groups), then re-run this command."
( while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done ) >/dev/null 2>&1 &
SUDO_KEEPALIVE=$!
trap 'kill "$SUDO_KEEPALIVE" 2>/dev/null || true' EXIT INT TERM

# ---- 1. Command Line Tools (+ beta guard) -----------------------------------
if ! /usr/bin/xcode-select -p >/dev/null 2>&1; then
  # On a beta OS, `xcode-select --install` can't fetch CLT — the wait loop would hang forever.
  $IS_BETA && die "Beta macOS ($OSVER $BUILD): Apple doesn't serve the public Command Line Tools.
      Download the Command Line Tools BETA from https://developer.apple.com/download/all
      (Apple ID sign-in; no paid membership), install it, then re-run this command."
  log "Installing Command Line Tools (a GUI installer may appear)…"
  /usr/bin/xcode-select --install || true
  printf 'Waiting for Command Line Tools'
  until /usr/bin/xcode-select -p >/dev/null 2>&1; do printf '.'; sleep 15; done; printf ' done\n'
fi
mark clt

# ---- 2. Accept the Xcode license (built in) ---------------------------------
# Full Xcode (not CLT-only) blocks git/brew until its license is accepted. On a fresh
# machine Xcode.app isn't here yet, so this is a no-op now; install.sh accepts it again
# AFTER the App-Store Xcode install (and site.yml does too). Building it in here means
# it's handled the moment Xcode ever exists — you never hit the license wall by hand.
if [ -d /Applications/Xcode.app ] || /usr/bin/xcode-select -p 2>/dev/null | grep -q 'Xcode.app'; then
  if ! /usr/bin/xcodebuild -version >/dev/null 2>&1; then
    log "Accepting the Xcode license…"; sudo /usr/bin/xcodebuild -license accept 2>/dev/null || warn "Could not accept Xcode license (needs admin)."
  fi
  mark xcode-license
else
  mark xcode-license "n/a (CLT only)"
fi

# ---- 3. Homebrew ------------------------------------------------------------
BREW=/opt/homebrew/bin/brew
if [ ! -x "$BREW" ]; then
  log "Installing Homebrew…"
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
eval "$("$BREW" shellenv)"
grep -q 'brew shellenv' "$HOME/.zprofile" 2>/dev/null || \
  printf '\neval "$(%s shellenv)"\n' "$BREW" >> "$HOME/.zprofile"
mark homebrew

mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"

# ---- 4. GitHub SSH key: create + REGISTER on GitHub -------------------------
if [ ! -f "$GH_KEY" ]; then
  log "Generating GitHub key: ${GH_KEY##*/}"
  ssh-keygen -t ed25519 -N "" -f "$GH_KEY" -C "${HOST}-gh" >/dev/null
fi

register_github_key() {
  # Add the key via gh. On a clean Mac gh isn't present — install it (brew is available)
  # and sign in interactively with admin:public_key (required to add an SSH key). This is
  # also the AUTH step: whoever signs in here is the account the gate below checks.
  command -v gh >/dev/null 2>&1 || { log "Installing gh…"; "$BREW" install gh; }
  if ! gh auth status >/dev/null 2>&1; then
    log "Sign in to GitHub (a browser window will open)…"
    gh auth login -h github.com -w -s admin:public_key || true
  fi
  if gh ssh-key add "${GH_KEY}.pub" --title "${HOST}-gh" 2>/dev/null; then
    log "Key registered on GitHub (gh)."; return 0; fi
  if gh auth refresh -h github.com -s admin:public_key >/dev/null 2>&1 \
     && gh ssh-key add "${GH_KEY}.pub" --title "${HOST}-gh"; then
    log "Key registered on GitHub (gh, after scope refresh)."; return 0; fi
  warn "gh could not add the key automatically — add it by hand:"
  printf '\n----- copy the line below into GitHub -----\n%s\n-------------------------------------------\n' "$(cat "${GH_KEY}.pub")"
  printf 'Add it at:  https://github.com/settings/ssh/new   (Title: %s)\n' "${HOST}-gh"
  ask "Press Enter once the key is saved on GitHub… " >/dev/null
}
log "Registering the GitHub key (interactive)…"
register_github_key
mark github-key "${HOST}-gh"

# make git use this key for github.com
if ! grep -q '^Host github.com$' "$HOME/.ssh/config" 2>/dev/null; then
  printf '\nHost github.com\n  HostName github.com\n  User git\n  IdentityFile %s\n  IdentitiesOnly yes\n' "$GH_KEY" >> "$HOME/.ssh/config"
fi
ssh-keygen -F github.com >/dev/null 2>&1 || ssh-keyscan -t ed25519 github.com >> "$HOME/.ssh/known_hosts" 2>/dev/null || true

# ---- 5. AUTHORIZATION GATE --------------------------------------------------
# Authorized iff this account can actually reach the private repo. Owner: automatic.
# Others: only if the owner shared the private repo with their GitHub account.
[ -n "$PRIVATE_REPO" ] || PRIVATE_REPO="$(ask 'Private config repo (git SSH URL, e.g. git@github.com:owner/repo.git): ')"
[ -n "$PRIVATE_REPO" ] || die "No private repo URL provided."
log "Verifying this account is authorized for ${PRIVATE_REPO} …"
if ! GIT_SSH_COMMAND="ssh -i $GH_KEY -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new" \
     git ls-remote "$PRIVATE_REPO" >/dev/null 2>&1; then
  die "NOT AUTHORIZED for ${PRIVATE_REPO}.
      The GitHub key '${HOST}-gh' is on the account, but that account cannot read the
      private config repo. If you are the owner: check the repo URL. If you were invited:
      the owner has not shared the private repo with your GitHub account yet — ask them to
      add you as a collaborator, then re-run this script. Nothing else was installed."
fi
log "Authorized ✓"

# ---- 6. (remote only) optional return-access key ----------------------------
# Return access is meaningful only when driving this box from ANOTHER machine over SSH.
# Running directly at the new machine → not created (per spec).
if $REMOTE_SESSION; then
  OP="$(ask 'Operator hostname for return SSH access (blank to skip): ')"
  if [ -n "$OP" ]; then
    RK="$HOME/.ssh/new-${HOST}-${OP}"                # naming: new-<hostname>-<operator>
    [ -f "$RK" ] || ssh-keygen -t ed25519 -N "" -f "$RK" -C "new-${HOST}-${OP}" >/dev/null
    log "Return key ${RK##*/} created. Add its PUBLIC half to ${OP}:~/.ssh/authorized_keys —"
    printf '\n%s\n\n' "$(cat "${RK}.pub")"
  fi
fi

# ---- 7. clone the private repo ----------------------------------------------
mkdir -p "$(dirname "$TARGET_DIR")"
export GIT_SSH_COMMAND="ssh -i $GH_KEY -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"
if [ -d "$TARGET_DIR/.git" ]; then
  log "Updating existing checkout at ${TARGET_DIR} …"; git -C "$TARGET_DIR" pull --ff-only || warn "pull skipped"
else
  log "Cloning private config repo → ${TARGET_DIR} …"
  git clone "$PRIVATE_REPO" "$TARGET_DIR"
fi
mark repo "$TARGET_DIR"

# ---- 8. auto-trigger provision.sh (settings) — OPT-OUT ----------------------
if [ "${INFRA_SKIP_PROVISION:-}" = 1 ]; then
  log "Skipping settings (INFRA_SKIP_PROVISION=1)."
elif [ -x "$TARGET_DIR/provision.sh" ]; then
  case "$(ask 'Apply your base macOS settings now (provision.sh)? [Y/n]: ')" in
    n|N|no|NO) log "Skipped. Apply later:  cd $TARGET_DIR && ./provision.sh   (DRY=1 to preview)" ;;
    *) log "Applying settings…"; ( cd "$TARGET_DIR" && ./provision.sh ) || warn "provision.sh reported issues." ;;
  esac
else
  warn "No provision.sh in the repo — skipping settings."
fi

# ---- 9. hand off to install.sh (apps & services) — OPT-OUT ------------------
if [ "${INFRA_SKIP_INSTALL:-}" = 1 ]; then
  log "Init complete. Install apps when ready:  cd $TARGET_DIR && ./install.sh"
  exit 0
fi
if [ -x "$TARGET_DIR/install.sh" ]; then
  case "$(ask 'Install apps & services now (install.sh)? [Y/n]: ')" in
    n|N|no|NO) log "Clone ready. Run later:  cd $TARGET_DIR && ./install.sh" ;;
    *) log "Handing off to the installer…"; kill "$SUDO_KEEPALIVE" 2>/dev/null || true; exec "$TARGET_DIR/install.sh" ;;
  esac
else
  warn "No install.sh in the repo — clone is ready at ${TARGET_DIR}."
fi
