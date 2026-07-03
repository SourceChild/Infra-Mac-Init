#!/usr/bin/env bash
# =============================================================================
# Infra-Mac-Init · init.sh — anonymous first-touch bootstrapper for a fresh Mac.
#
# Contains NO personal / host / app / repo data. It is a generic "install the
# prerequisites, mint a GitHub key, verify access, clone the private config repo,
# hand off" script. The only per-user value (the private repo URL) is passed in
# or prompted — never baked in.
#
#   Run ON the new machine, in Terminal:
#     curl -fsSL https://raw.githubusercontent.com/SourceChild/Infra-Mac-Init/main/init.sh \
#       | bash -s -- git@github.com:<owner>/<private-config-repo>.git
#   …or run with no argument and it prompts for the private repo URL.
#
# What it does, in order:
#   1. Command Line Tools  (gives git; needs no git to get here — curl only)
#   2. Homebrew            (non-interactive)
#   3. A per-machine GitHub SSH key  <hostname>-gh  — created AND registered on
#      GitHub interactively (via `gh`, or by paste).
#   4. AUTHORIZATION GATE: can this GitHub account actually reach the private repo?
#      • yes → continue (you own it, or the owner shared it with you)
#      • no  → HALT and explain (the owner has not shared it with your account)
#   5. (remote sessions only) an optional return-access key  new-<hostname>-<operator>
#   6. clone the private repo → hand off to its installer
# =============================================================================
set -euo pipefail

log()  { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }
die()  { printf '\n\033[1;31m[halt]\033[0m %s\n\n' "$*" >&2; exit 1; }
ask()  { local a; read -r -p "$1" a </dev/tty || a=""; printf '%s' "$a"; }

[ "$(uname -s)" = "Darwin" ] || die "macOS only."

# ---- identity / mode --------------------------------------------------------
HOST="$(scutil --get LocalHostName 2>/dev/null || hostname -s)"
GH_KEY="$HOME/.ssh/${HOST}-gh"                       # naming: <hostname>-gh
REMOTE_SESSION=false; [ -n "${SSH_CONNECTION:-}" ] && REMOTE_SESSION=true
PRIVATE_REPO="${1:-}"
TARGET_DIR="${2:-$HOME/dev/infra/ansible}"           # where the private repo lands
log "init on '${HOST}'  (remote session: ${REMOTE_SESSION})"

# ---- 1. Command Line Tools --------------------------------------------------
if ! /usr/bin/xcode-select -p >/dev/null 2>&1; then
  log "Installing Command Line Tools (a GUI installer may appear)…"
  /usr/bin/xcode-select --install || true
  printf 'Waiting for Command Line Tools'
  until /usr/bin/xcode-select -p >/dev/null 2>&1; do printf '.'; sleep 15; done; printf ' done\n'
fi

# ---- 2. Homebrew ------------------------------------------------------------
BREW=/opt/homebrew/bin/brew
if [ ! -x "$BREW" ]; then
  log "Installing Homebrew…"
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
eval "$("$BREW" shellenv)"
grep -q 'brew shellenv' "$HOME/.zprofile" 2>/dev/null || \
  printf '\neval "$(%s shellenv)"\n' "$BREW" >> "$HOME/.zprofile"

mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"

# ---- 3. GitHub SSH key: create + REGISTER on GitHub -------------------------
if [ ! -f "$GH_KEY" ]; then
  log "Generating GitHub key: ${GH_KEY##*/}"
  ssh-keygen -t ed25519 -N "" -f "$GH_KEY" -C "${HOST}-gh" >/dev/null
fi

register_github_key() {
  # Actually add the key via gh. On a clean Mac gh isn't present — install it (brew
  # is available by now) and sign in interactively with the admin:public_key scope
  # (that scope is required to add an SSH key). This is also the AUTH step: whoever
  # signs in here is the account whose repo access the gate below checks.
  command -v gh >/dev/null 2>&1 || { log "Installing gh…"; "$BREW" install gh; }
  if ! gh auth status >/dev/null 2>&1; then
    log "Sign in to GitHub (a browser window will open)…"
    gh auth login -h github.com -w -s admin:public_key || true
  fi
  if gh ssh-key add "${GH_KEY}.pub" --title "${HOST}-gh" 2>/dev/null; then
    log "Key registered on GitHub (gh)."; return 0; fi
  # authed but without the scope → request it, then retry
  if gh auth refresh -h github.com -s admin:public_key >/dev/null 2>&1 \
     && gh ssh-key add "${GH_KEY}.pub" --title "${HOST}-gh"; then
    log "Key registered on GitHub (gh, after scope refresh)."; return 0; fi
  # last resort: manual paste
  warn "gh could not add the key automatically — add it by hand:"
  printf '\n----- copy the line below into GitHub -----\n%s\n-------------------------------------------\n' "$(cat "${GH_KEY}.pub")"
  printf 'Add it at:  https://github.com/settings/ssh/new   (Title: %s)\n' "${HOST}-gh"
  ask "Press Enter once the key is saved on GitHub… " >/dev/null
}
log "Registering the GitHub key (interactive)…"
register_github_key

# make git use this key for github.com
if ! grep -q '^Host github.com$' "$HOME/.ssh/config" 2>/dev/null; then
  printf '\nHost github.com\n  HostName github.com\n  User git\n  IdentityFile %s\n  IdentitiesOnly yes\n' "$GH_KEY" >> "$HOME/.ssh/config"
fi
ssh-keygen -F github.com >/dev/null 2>&1 || ssh-keyscan -t ed25519 github.com >> "$HOME/.ssh/known_hosts" 2>/dev/null || true

# ---- 4. AUTHORIZATION GATE --------------------------------------------------
# Whoever runs this — owner or invited collaborator — is "authorized" iff this
# account can actually reach the private repo. Owner: automatic. Others: only if
# the owner shared the private repo with their GitHub account.
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

# ---- 5. (remote only) optional return-access key ----------------------------
# Return access is meaningful only when someone is driving this box from ANOTHER
# machine over SSH. Running directly at the new machine → not created (per spec).
if $REMOTE_SESSION; then
  OP="$(ask 'Operator hostname for return SSH access (blank to skip): ')"
  if [ -n "$OP" ]; then
    RK="$HOME/.ssh/new-${HOST}-${OP}"                # naming: new-<hostname>-<operator>
    [ -f "$RK" ] || ssh-keygen -t ed25519 -N "" -f "$RK" -C "new-${HOST}-${OP}" >/dev/null
    log "Return key ${RK##*/} created. Add its PUBLIC half to ${OP}:~/.ssh/authorized_keys —"
    printf '\n%s\n\n' "$(cat "${RK}.pub")"
  fi
fi

# ---- 6. clone + hand off ----------------------------------------------------
mkdir -p "$(dirname "$TARGET_DIR")"
export GIT_SSH_COMMAND="ssh -i $GH_KEY -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"
if [ -d "$TARGET_DIR/.git" ]; then
  log "Updating existing checkout at ${TARGET_DIR} …"; git -C "$TARGET_DIR" pull --ff-only || warn "pull skipped"
else
  log "Cloning private config repo → ${TARGET_DIR} …"
  git clone "$PRIVATE_REPO" "$TARGET_DIR"
fi

log "Handing off to the installer in the private repo…"
if   [ -x "$TARGET_DIR/install.sh" ];   then exec "$TARGET_DIR/install.sh"
elif [ -x "$TARGET_DIR/bootstrap.sh" ]; then exec "$TARGET_DIR/bootstrap.sh"
else warn "No install.sh / bootstrap.sh in the repo — clone is ready at ${TARGET_DIR}."; fi
