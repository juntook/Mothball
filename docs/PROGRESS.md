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

## M2 — Cleanup executor + safety gate — DONE (2026-07-11)

Shipped (gate tests written first, per CLAUDE.md):
- `DeletionGate` — all six SPEC §5.6 rules, below the UI: immutable confirmed paths only; realpath-prefix containment (parent chain resolved, leaf symlink never followed); hard-rejects `/`, home itself, `..`, short paths, `/System`, system `/Library`; protected → no path to deletion; user_data → trash only; direct delete only behind the setting.
- `CleanupExecutor` — per-item gate check + injectable `FileRemover`; user_data trash failure aborts the run and skips the rest (abort-and-ask, never a direct-delete fallback); regenerable failures don't stop the run.
- `AuditLog` — JSONL at `~/Library/Logs/Mothball/operations.jsonl` (timestamp, rule, target, path, bytes, method, result), always English.
- `IgnoreList` — persisted at Application Support; ignored rows collapse and can't be selected.
- UI: tier-appropriate selection (regenerable pre-checked, user_data opt-in, protected shows a lock, no checkbox); preview sheet with per-item user_data confirmation; progress; results page with reclaimed total, per-item outcomes, and the fixed APFS-snapshot note; direct-delete setting with per-session first-use re-confirmation; Settings pane (toggle, audit-log reveal, ignored paths).
- 23 new tests: 15 gate rejection/acceptance branches, executor abort semantics, audit JSONL, ignore list round-trip. 54 total, all green.
- Real `FileManager.trashItem` round-trip verified on-machine (file landed in `~/.Trash`, restorable).

Needs human verification:
- Full sheet flow visually (en + zh-Hans), including the user_data highlight and confirm interaction.

## M3 — Project discovery + attribution — DONE (2026-07-11)

Shipped:
- `ProjectDiscovery`: BFS under configured code roots, depth ≤ 6, skips hidden/`node_modules`/`Library`/`.Trash`; 12 marker files; project roots never descended (outermost wins); exclusions supported. `ProjectActivity`: last git commit (fixed-path git candidates, no PATH) falling back to root mtime.
- `AttributionEngine`: evidence 1 (path containment, nearest root wins), 2 (process cwd — consumed in M4), 3 (compose labels — M5), 4 (dashed-absolute encoded buckets), 5 (bind mounts — M5). Case-insensitive (APFS default), realpath-normalized. Lossy dashed encoding decoded by comparing against known roots' encodings — dashes in project names ("my-app", "shop-admin") disambiguate correctly.
- `DiskScanner.discoverProjectItems`: projectGlobs matched per root, gated by guardFiles (stray `node_modules` without `package.json` excluded). `explodeEncodedTargets`: per-bucket items with inherited safety; unmatched buckets → unattributed. `scanAll` combines everything.
- Projects view (default home): cards with name/path/relative last-active/footprint/item count; detail grouped by kind with per-item attribution evidence; "Unattributed / Global" bucket last. Code-roots management in Settings (folder picker).
- `mothball projects <root>` CLI for on-machine verification.
- 16 new tests incl. the SPEC-mandated constructed tree (nested git, guardless node_modules, hidden/Library distractors, depth limit, Chinese + space paths). 70 total, green.

Verified on this machine: 13 projects discovered (incl. `回声`, `petne中文推广/assets/app-extract`); `~/.claude/projects` buckets attributed to the right projects including dot-containing paths (`ai.nvwork.com` → `-Users-…-ai-nvwork-com-upstream`) and child-session buckets (`…-Sourcebotics-site` → Sourcebotics).

Needs human verification:
- Projects view + detail visually (en/zh-Hans).

## M4 — Runtime detection — DONE (2026-07-11)

Shipped:
- `LibprocProcessProvider`: full SPEC §5.4 chain — `proc_listpids(PROC_UID_ONLY)` → `proc_pidinfo(PROC_PIDLISTFDS)` + `proc_pidfdinfo(PROC_PIDFDSOCKETINFO)` for LISTEN TCP ports → `proc_pidpath` → `proc_pidvnodepathinfo` (cwd) → `proc_pid_rusage` (memory) + `PROC_PIDTBSDINFO` (start time). Pure user-space, no privileges.
- `RuntimeScanner`: current-user only; kept when listening on TCP or cwd attributed to a project; system exclusion list from bundled `rules/system-exclusions.json`; excludes Mothball itself.
- `ServiceStopper`: (pid, startTime) verified before every signal (PID-reuse guard); SIGTERM → 5 s poll → `stillRunning` (UI offers Force Quit; SIGKILL never sent implicitly); force kill re-verifies again. Injectable provider/poll/grace for tests.
- Runtime view: table (ports, process+PID, project/cwd, memory, started), auto-refresh on entry + manual refresh, per-row Stop, force-quit confirmation dialog, stale-pid alert. Stop/kill operations audited to operations.jsonl.
- `mothball runtime [root]` and `mothball stop <pid>` CLI.
- 10 new tests (filtering, cwd attribution, graceful stop, no auto-SIGKILL, PID-reuse abort on both paths, signal failure). 80 total, green.

Verified on this machine: real `node` dev server on :3000 attributed to `回声`; a test server on :5199 discovered with correct cwd (etour) and stopped via `mothball stop` (SIGTERM, confirmed gone); rapportd and friends filtered out.

Needs human verification:
- Runtime table + force-quit dialog visually (en/zh-Hans).

## M5 — Container resources — not started

## M6 — Onboarding + release infrastructure — not started
