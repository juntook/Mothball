# Progress

Milestones per SPEC §7. Each entry records what shipped and what still needs human verification.

## M0 — Engineering skeleton — DONE (2026-07-11)

Shipped:
- Repo structure per SPEC §8.1; SwiftPM package with `Core` (library), `cli` (`mothball` binary), `MothballApp` (SwiftUI shell) and `CoreTests`.
- Apache-2.0 LICENSE + NOTICE; SPDX headers on all sources; CLAUDE.md with hard constraints.
- Rule library seeds (§6) + JSON Schema + `scripts/validate-rules.sh` (schema + semantic checks, negative-tested).
- GitHub Actions CI: rule validation, localization sync check, build + test.
- i18n scaffold: String Catalogs (`App/Localizable.xcstrings`, `Sources/Core/Localizable.xcstrings`) as the source of truth; `scripts/gen-localizations.py` generates the checked-in `.lproj/Localizable.strings` bundled as resources; en + zh-Hans.
- Empty-shell app: `NavigationSplitView` with Projects/Tools/Runtime/Settings sidebar, localized placeholders.

Environment-driven decisions (documented deviations):
- Build machine has Command Line Tools only (no full Xcode). The CLT SDK cannot compile `.xcstrings` and lacks the `Testing`/`XCTest` modules, so:
  - `.xcstrings` remains authoritative but generated `.strings` files are checked in (CI enforces sync). Migrating back to direct catalog compilation is a no-op once builds happen in full Xcode.
  - `swift-testing` is declared as a test-only package dependency (Apple's own framework) so `swift test` runs everywhere.
- `Sources/Core/Resources/rules` is a symlink to the top-level `rules/` so rule JSON ships inside the Core bundle without duplication.

Needs human verification:
- App UI smoke test on a machine with full Xcode (`swift run MothballApp`, or the M6 app-bundle script): sidebar shows, and shows Chinese when system language is zh-Hans.
- CI green on GitHub after first push.

## M1 — Rule engine + disk scanner + Tools view — DONE (2026-07-11)

Shipped:
- `RuleLoader`: bundled rules + user overrides from `~/Library/Application Support/Mothball/rules/` (same id overrides built-in; broken user rules degrade to warnings). Load-time semantic validation mirrors CI (defense in depth for user rules).
- `PathExpansion`: `~` expansion; single-segment `*` globs (fnmatch, FNM_PERIOD); `..` and `**` rejected.
- `DirectorySizer`: fts(3) bulk traversal, allocated (physical) size, FTS_PHYSICAL (symlinks never followed), SF_DATALESS subtrees never descended (predicate unit-tested; flag not settable from userland), concurrent across top-level subdirectories.
- `DiskScanner`: progressive `AsyncStream` — items appear on discovery, sizes stream in after.
- `ToolDetection`: fixed binary candidate dirs (no PATH reliance), path/app detection.
- `Doctor` engine + Doctor window in the app (Developer menu, ⇧⌘D): per-target existence/readability/size.
- Tools view: grouped by rule, sorted by footprint, draft rules badged "Unverified", safety badges, monospaced-digit locale-aware sizes, progressive updates.
- `mothball` CLI: `rules`, `scan`, `detect`, `doctor`, `size <path>`.
- zh-Hans catalog entries for all seed-rule descriptions/hints (en falls back to rule JSON).

Measured on this machine (debug build):
- Real scan: 13 items, 5.47 GB total in 0.65 s.
- Synthetic 100 000-file tree sized in 0.16 s (SPEC target: 500 k files ≤ 60 s).

Needs human verification:
- Doctor-driven promotion of seed rules from `draft` to `verified` (SPEC marks this a manual acceptance step).
- Tools view visual check with system language zh-Hans.

## M2 — Cleanup executor + safety gate — not started

## M3 — Project discovery + attribution — not started

## M4 — Runtime detection — not started

## M5 — Container resources — not started

## M6 — Onboarding + release infrastructure — not started
