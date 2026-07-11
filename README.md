# infra-mac-init

Public first-touch bootstrap for a fresh Mac. Carries **no secrets** — no keys, passwords, hostnames,
IPs, or app lists; the only identifiers are the public GitHub owner + config-repo name (a convenience
default, overridable by passing a URL). All real configuration lives in a separate **private** repo that
`init.sh` fetches *after* the machine mints its own key and proves it's authorized.

## Start here — one command on the new Mac

Open **Terminal** on the freshly-imaged Mac and run (pass your private config repo's SSH URL):

```bash
curl -fsSL https://raw.githubusercontent.com/SourceChild/infra-mac-init/main/init.sh \
  | bash -s -- git@github.com:SourceChild/infra-mac-deploy.git
```

Run with **no argument** and it defaults to `SourceChild/infra-mac-deploy` (pass a different SSH URL to
override). `curl | bash` needs no git — `init.sh` installs it (via Command Line Tools) first.

## What `init.sh` does (bare minimum to reach the private repo)

1. **Command Line Tools** — with a **beta-OS guard** (on a beta build, Apple doesn't serve public
   CLT, so it stops with a link instead of hanging).
2. **Accepts the Xcode license** — built in, so you never hit the license wall by hand.
3. **Homebrew** (needed to install `gh`).
4. **A per-machine GitHub SSH key `<hostname>-gh`** — generated on the machine and **registered on
   GitHub** for you (via `gh`, or by paste). Private keys never leave the machine.
5. **Authorization gate** — if this GitHub account can read the private repo it continues; if not it
   **halts and explains** (the owner hasn't shared it with your account yet). Nothing else installs.
6. On a **remote** session only, an optional return-access key `new-<hostname>-<operator>`.
7. **Clones** the private repo → `~/dev/infra-mac-deploy`.
8. Offers to apply your macOS **settings** (`provision.sh`) — decline with `n`.
9. Hands off to the private **installer** (`install.sh`) for apps & services — decline with `n`.

Steps are idempotent and recorded under `~/.infra-mac/`, so re-running skips what's done. For
unattended runs, opt out of the tail with `INFRA_SKIP_PROVISION=1` and/or `INFRA_SKIP_INSTALL=1`.

> **GitHub key scope:** adding a key with `gh` needs `admin:public_key`. `init.sh` requests it
> (`gh auth login`/`refresh` opens a browser); if `gh` can't, it prints the key to paste at
> `https://github.com/settings/ssh/new`.

## `provision.sh` — pointer only

macOS preferences are personal, so they don't live here. They live as `SETTINGS.md` in your private
repo, applied by *that* repo's `provision.sh` (which `init.sh` already offers to run). This file just
tells you that. It has **zero logic on purpose** so it can never drift.

---

*Nothing here is secret. The private config repo — and only it — holds the fleet's real data.*
