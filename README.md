# Infra-Mac-Init

Prerequisite-free bootstrap scripts for a fresh Mac. **Public and generic on purpose** — these
files carry no hostnames, IPs, usernames, app lists, or keys. All machine-specific configuration
lives in a separate **private** repo that these scripts fetch *after* the machine authenticates
with its own key.

Two scripts, run **on the new Mac**, in Terminal:

## `init.sh` — get from bare metal to a cloned private config repo

```bash
curl -fsSL https://raw.githubusercontent.com/SourceChild/Infra-Mac-Init/main/init.sh \
  | bash -s -- git@github.com:<owner>/<private-config-repo>.git
```

(Run with no argument and it prompts for the private repo URL.)

It installs Command Line Tools + Homebrew (no git needed to start — `curl` only), mints a
per-machine GitHub SSH key **`<hostname>-gh`** and registers it on GitHub interactively, then
**verifies authorization**: if this GitHub account can read the private repo it clones it and hands
off to the repo's installer; if it can't, it **halts and explains** (the owner hasn't shared the
private repo with that account). On a *remote* session it can also mint a return-access key
**`new-<hostname>-<operator>`**; run directly at the machine and no return key is created.

**Note on the GitHub key step:** adding a key with `gh` needs the `admin:public_key` scope. If `gh`
doesn't have it, the script runs `gh auth refresh -s admin:public_key` (opens a browser); if `gh`
isn't present/authed it falls back to printing the key for you to paste at
`https://github.com/settings/ssh/new`.

## `provision.sh` — apply macOS system/user preferences

```bash
curl -fsSL https://raw.githubusercontent.com/SourceChild/Infra-Mac-Init/main/provision.sh | bash
```

Applies a baseline of macOS `defaults`/system settings (Dock, Finder, keyboard, trackpad, screenshots,
security, etc.) with a **default set** plus **selectable option groups**. The concrete values are
derived from a known-good clean machine — see the header of `provision.sh` for how to (re)capture a
baseline. Safe to re-run (idempotent); logs what it changed.

---

*Nothing here is secret. The private config repo — and only it — holds the fleet's real data.*
