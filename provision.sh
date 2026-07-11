#!/usr/bin/env bash
# =============================================================================
# infra-mac-init · provision.sh — POINTER ONLY (intentionally zero logic).
#
# macOS preferences are data-driven and PERSONAL, so they don't live in this public
# repo. They live in your PRIVATE config repo as an editable table, SETTINGS.md,
# applied by THAT repo's provision.sh. init.sh already auto-offers to run it after
# the clone (opt out with INFRA_SKIP_PROVISION=1), so normally you never call this.
#
# Run the real thing directly any time:
#     cd ~/dev/infra/ansible          # your private config repo (cloned by init.sh)
#     DRY=1 ./provision.sh            # preview what would change
#     ./provision.sh                  # apply SETTINGS.md (idempotent)
#
# Kept as a pure pointer on purpose: with no logic here, it can never drift from the
# private applier (the same reason the old bootstrap.sh was folded into install.sh).
# =============================================================================
echo "Settings live in SETTINGS.md in your PRIVATE config repo (cloned by init.sh)."
echo "Apply them with:  cd ~/dev/infra/ansible && ./provision.sh   (DRY=1 to preview)"
echo "init.sh already offers this automatically after cloning."
