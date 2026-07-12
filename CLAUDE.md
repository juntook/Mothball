# CLAUDE.md — Mothball engineering constraints

Read SPEC.md first. This file distills the non-negotiable rules for any agent or contributor working in this repo.

## Platform constraints (SPEC §3)

- macOS 14.0+, arm64 (Apple Silicon) only. No Intel slice, no Windows/Linux.
- Swift 6 toolchain, strict concurrency enabled. SwiftUI for all UI. No Electron/Tauri/webview.
- Native SwiftUI controls and SF Symbols as the base, styled to match the product prototype (colored sidebar icon chips, rounded cards, capsule badges, tinted metric glyphs, prominent blue primary actions). Light/dark adaptive; no webview, no custom-drawn controls, no version-forked visuals.
- Layering: `Sources/Core` (SwiftPM library, zero UI dependencies, fully unit-testable) → `App` (SwiftUI, presentation only, calls Core public API) → `Sources/cli` (debug CLI over Core).
- Runs as the logged-in user only. **Never request sudo. Never install a privileged helper.** Features that would require privileges are simply not built.
- No App Sandbox (incompatible with core features); distribution is Developer ID signing + notarization, not the App Store.
- Dependencies: zero third-party by default. Sparkle (updates) is pre-approved. Anything else requires justification first.

## Hard constraints — never bypass, even for implementation convenience

Any proposal to weaken these requires explicit human sign-off.

### Safety tiers (SPEC §4.3)

- `regenerable`: caches/logs/build artifacts. Checked by default; trash by default, direct delete only via settings + confirmation.
- `user_data`: session history, todos, tagged images. **Unchecked by default; per-item confirmation; trash only — never direct delete.**
- `protected`: credentials, config, volume contents. **Display only. No delete affordance anywhere. Batch operations must skip.**
- AI tool session history (`~/.claude/projects`, `~/.codex/sessions`, …) is always `user_data`. Never in one-click cleanup.

### Deletion gate (SPEC §5.6)

The executor enforces all six rules independently of UI logic; a violation rejects the item and is logged:
1. Accepts only the immutable path set from the confirmed preview — never rules.
2. Each realpath-normalized path must be prefixed by a path expanded from an enabled rule.
3. Hard-reject: `/`, the home directory itself, any path containing `..`, paths shorter than 8 chars, anything under `/System` or system-level `/Library`.
4. Deletion never follows symlinks.
5. `user_data` only via `FileManager.trashItem`; if trashing fails (cross-volume, etc.), abort and ask — never silently fall back to direct delete.
6. `regenerable` defaults to trash; "direct delete" is a global setting and the first direct delete per session requires re-confirmation.

Official tool cleanup commands (`npm cache clean`, …) are shown copy-only in the UI; the app never executes them — that would bypass the gate (SPEC §5.6).

### Risk display layer (SPEC §4.4, M8+)

S0–S3 risk scores are presentation-only, computed on top of the safety tiers. They may tighten defaults (e.g. uncheck an in-use regenerable item) but never loosen them; `user_data`/`protected` are always S3. Enforcement stays exclusively with the safety tiers and the deletion gate.

## Process rules

- Cleaner and deletion gate: **test-first** — write the failing rejection-branch tests before the implementation.
- One PR-sized commit sequence per milestone; commit messages in imperative English.
- Rule JSON changes must pass `rules/schema/rule.schema.json` validation (CI enforces). New rules default to `status: "draft"`; only flip to `verified` after on-machine verification via the Doctor panel, with `verifiedOn` set.
- All user-visible strings go through String Catalogs (SPEC §8.5). Hard-coded UI copy in a PR is a defect. After editing an `.xcstrings` catalog, run `scripts/gen-localizations.py` to regenerate the checked-in `.strings` files (CI fails on drift).
- The in-app language override resolves strings through explicit language sub-bundles (SPEC §8.5(6)); never rely on mutating `AppleLanguages` at runtime.
- New source files start with `// SPDX-License-Identifier: Apache-2.0`.
- Audit log JSONL is machine-readable and always English. CLI output, code comments, and commit messages are English.

## Build & test

```sh
swift build           # builds Core, cli, MothballApp (SwiftPM)
swift test            # Core unit tests
scripts/validate-rules.sh   # rule schema + semantic checks (also run in CI)
```

If SwiftPM hangs downloading the Sparkle binary artifact (restricted networks):

```sh
scripts/fetch-sparkle.sh
MOTHBALL_LOCAL_SPARKLE=1 swift build
```
