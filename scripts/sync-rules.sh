#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Mirrors the canonical rules/ library into the Core bundle resources.
# rules/ stays the single source of truth (self-contained, zero code deps);
# the copy under Sources/Core/Resources exists because SwiftPM resources must
# live inside the target directory. CI runs with --check to catch drift.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC_ITEMS=(rules/schema rules/tools rules/system-exclusions.json)
DEST=Sources/Core/Resources/rules

if [[ "${1:-}" == "--check" ]]; then
    for item in "${SRC_ITEMS[@]}"; do
        if ! diff -r "$item" "$DEST/$(basename "$item")" >/dev/null 2>&1; then
            echo "OUT OF SYNC: $item vs $DEST — run scripts/sync-rules.sh"
            exit 1
        fi
    done
    echo "OK — bundled rules in sync"
else
    mkdir -p "$DEST"
    rsync -a --delete rules/schema rules/tools rules/system-exclusions.json "$DEST/"
    echo "synced rules -> $DEST"
fi
