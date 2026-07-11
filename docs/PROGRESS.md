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

## M1 — Rule engine + disk scanner + Tools view — not started

## M2 — Cleanup executor + safety gate — not started

## M3 — Project discovery + attribution — not started

## M4 — Runtime detection — not started

## M5 — Container resources — not started

## M6 — Onboarding + release infrastructure — not started
