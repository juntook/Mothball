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

## M5 — Container resources — DONE (2026-07-11)

Shipped:
- `DockerEnvironment`: fixed binary candidates (Homebrew/`/usr/local`/OrbStack/Docker.app — PATH never consulted), socket probing (Docker Desktop/OrbStack/Colima/`/var/run`), `DOCKER_HOST`, current-context endpoint, daemon liveness probe, Podman detection. Everything recorded in a diagnostics struct.
- `DockerClient`: shell-out with `--format json` (JSONL parsing), human-size parser (SI units), compose label extraction, dangling detection, volume dangling cross-reference, `system df`, bind-mount sources via `container inspect`. Actions: stop / rm / rmi / volume rm / builder prune — none pass force flags; volumes only ever removed singly.
- `ContainerResourceScanner`: SPEC §5.5 matrix — running/stopped containers (regenerable), dangling images (regenerable, one-click batch), tagged-unreferenced images (user_data, per-item confirm; images backing *any* container incl. stopped ones are never offered), volumes (protected display, strong single confirm, no batch), build cache (prune). Attribution: compose working_dir (evidence 3) → bind-mount source (evidence 5); volumes correlate through compose sibling containers.
- Runtime view now splits: process table on top, container resources below; daemon-down and no-binary empty-state cards (not errors); Podman notice row; all Docker operations audited.
- `mothball docker [root]` CLI.
- 13 new tests over canned CLI output recorded from a real engine. 93 total, green.

Verified on this machine (Colima): compose containers attributed correctly (`echo-pg` → `回声`, `aigw-*` → `ai-gateway`); dangling images, volumes and 13.4 GB build cache listed.

Needs human verification:
- SPEC acceptance names Docker Desktop AND OrbStack environments — this machine runs Colima (a third supported endpoint). Re-run `mothball docker` under Docker Desktop and OrbStack.
- Volume strong-confirm and tagged-image confirm dialogs visually.

## M6 — Onboarding + release infrastructure — DONE (2026-07-11)

Shipped:
- Onboarding (first launch): welcome (value + open-source/local/no-sudo statement) → code-roots picker (skippable) → Full Disk Access step with live status polling and a deep link to the settings pane → finish auto-starts the first scan.
- `FullDiskAccess` probe (Core): opendir on TCC-protected paths (`~/Library/Safari` et al.) → granted/denied/indeterminate; no private API. Persistent degraded-mode banner (`FDABanner`) above all views while denied (SPEC §5.8 — no silent-incomplete state).
- Sparkle 2 integrated ("Check for Updates…" in the app menu). Gracefully disabled in bare SwiftPM dev runs; active only inside a bundle with `SUFeedURL` (release.sh injects it).
- `scripts/release.sh`: SwiftPM release build → .app assembly (Info.plist, resource bundles, Sparkle.framework) → codesign (Developer ID via `CODESIGN_IDENTITY`, ad-hoc fallback) → dmg.
- `scripts/notarize.sh`: notarytool submit + staple + Gatekeeper assessment (keychain profile based).
- `scripts/homebrew/mothball.rb`: cask draft for the self-hosted tap (`juntook/homebrew-tap`); official homebrew/cask deferred until notability thresholds are met.
- README bilingual install section (brew + dmg + Sparkle + why-not-MAS).
- Build-environment workaround: this machine's sandbox stalls SwiftPM's binary-artifact downloader, so `scripts/fetch-sparkle.sh` + `MOTHBALL_LOCAL_SPARKLE=1` builds against a vendored (gitignored, checksum-verified) xcframework. CI and normal checkouts use the standard remote artifact.
- 3 FDA tests; 96 total, green.

Needs human verification (requires Xcode + Developer ID certificates — intentionally left for you):
- Run `scripts/release.sh` with `CODESIGN_IDENTITY` set, then `scripts/notarize.sh` — produce a notarized, Gatekeeper-passing dmg.
- Generate Sparkle EdDSA keys (`generate_keys`), set `SPARKLE_ED_KEY`, publish appcast.
- Create the `juntook/homebrew-tap` repo, copy the cask, fill the real sha256, test `brew install --cask juntook/tap/mothball` on a clean machine.
- Onboarding + FDA flow visually (en/zh-Hans), degraded banner with FDA revoked.

## M7 — V2 information architecture + new shell — DONE (2026-07-12)

Shipped:
- SPEC rewritten to V2 (same-anchor policy: §4.3, §5.1–§5.6, §5.8, §8.5, §9 keep their V1 meaning; code references stay valid). New sections: V2 IA (§5.7), S0–S3 presentation-layer risk scores (§4.4, M8), ports (§5.9), process metrics (§5.10), Homebrew services (§5.11), protection rules (§5.12), sessions (§5.13), menu bar (§5.14), notifications (§5.15), history view (§5.16), M7–M11 roadmap.
- App layer rebuilt on the V2 IA: sidebar Overview / Active Resources / Storage / Settings (⌘1–⌘3; Sessions and History intentionally absent until M10/M11 — no placeholder sections), sidebar footer (last scan, lifetime reclaimed, version, help link), toolbar scan (⌘R) + search field.
- Overview: greeting with running-resource count, four metric cards (running resources, active ports, dev memory, reclaimable space — all fed by existing Core scanners), prioritized "needs attention" list (docker daemon down, biggest reclaimables ≥ 1 GB, stale projects ≥ 90 days holding ≥ 500 MB), each row deep-links to its page. First launch auto-scans.
- Active Resources: Processes tab (former Runtime table) with row-selection inspector (detail grid, stop-impact note, stop/force-kill flow unchanged); Containers tab (running/stopped lifecycle kinds).
- Storage: Project Artifacts / Tool Caches / Docker tabs. Project rows open the cleanup-detail sheet (kind-grouped selectable items, per-project clean button); persistent bottom selection bar ("N selected · X reclaimable · Review & Clean…") — the mandatory §5.6 preview is the only path to execution, so the prototype's separate "Proceed" button is deliberately folded into review. Docker tab hosts the disk-weight kinds (dangling/tagged images, volumes, build cache, stopped containers).
- Settings regrouped per §5.7: General (direct delete), Scan Scope (roots + exclusions, newly exposed), Language & Region (System/中文/English), Privacy & Updates (Sparkle check + audit log), Advanced (Doctor entry + ignore list). Doctor stays a separate window, now reachable from Settings and the Developer menu.
- Onboarding rebuilt as the §5.8 two-page flow (welcome features + combined permissions page with live FDA status).
- In-app language override with immediate effect: explicit `<lang>.lproj` sub-bundle resolution for both App and Core catalogs (`CoreResources.bundle` accessor added to Core), plus `\.locale` environment injection for FormatStyles. No `AppleLanguages` mutation.
- Search: current-page filtering (processes, projects, tool caches) per SPEC §5.7; global search deferred to M11. ⌘K focuses the field on macOS 15+ (`searchFocused` API); the menu item is hidden on macOS 14.
- Strings: 81 keys added, 15 obsolete removed; en + zh-Hans complete; generated .strings in sync (`--check` green).
- 96 tests green; rule validation green; 12-second launch smoke test passed.

Needs human verification:
- Visual pass of every page in en and zh-Hans, plus the in-app language switch (per §8.5 acceptance hook).
- Cleanup flow end-to-end on real data in the new Storage UI (selection bar → preview → trash → result).
- Process inspector + stop/force-kill visually; container tabs under a running daemon.
- Onboarding two-page flow on a fresh user account (delete the `onboardingComplete` default to re-trigger).

## M8 — Ports view + process metrics + risk display layer — DONE (2026-07-12)

Shipped:
- `ProcessSnapshot`/`RunningService` gain `parentPID` and `cpuTimeNanos` (mach-time converted); CPU percentages come from differencing consecutive snapshots, sampled only while a runtime tab is visible (5 s loop bound to the view's task — idle means zero polling, SPEC §5.10/§9.11).
- Ports tab (SPEC §5.9): one row per listening port with protocol/process/project/uptime/memory/stop, "development ports only" filter (hides the ephemeral range ≥ 49152), selection shares the process inspector.
- Process tree: outline table grouped by ppid when not searching; context menu "Stop Process Tree" stops depth-first children-before-parents; inspector shows child count and offers the tree stop.
- `RiskEngine` (SPEC §4.4): S0–S3 presentation scores — user_data/protected always S3; regenerable → S2 when the project has a running process or uncommitted changes, S1 when recently active or a global tool cache, S0 only with no activity signals. `GitStatusProbe` feeds the dirty signal (fixed-path git, nil-safe). 10 mapping-invariant tests.
- Risk badges with explanatory hover on every resource row (disk + container); default selection now skips S2+ items (tighten-only — enforcement unchanged).
- Overview attention list adds sustained-high-CPU and long-running-listener rows; list capped at 8.
- Window activation fix: bare `swift run` executables now front their window (activation policy set on appear).
- 106 tests green.

Needs human verification:
- CPU column values against Activity Monitor for a busy process.
- Port rows against `lsof -iTCP -sTCP:LISTEN` output.
- S2 badge appears for a project with a running dev server and its artifacts start unchecked.

## M9 — Homebrew services + protection rules + rule library expansion — DONE (2026-07-12)

Shipped:
- `BrewServicesClient` (SPEC §5.11): `brew services list --json` parsing; stop semantics mapped to brew subcommands — stop once = `kill` (keeps login registration), stop & disable = `stop` (unregisters), start = `run` (no registration). Fixed-path binary resolution (§9.1). Services tab with status badges, autostart/exit-code detail, split-button actions; brew-missing and no-services empty states; all operations audited.
- `ProtectionRule`/`ProtectionRuleStore`/`ProtectionEvaluator` (SPEC §5.12): exact path, path prefix (case-insensitive, descendants only), process name, port, docker volume name; versioned JSON store under Application Support. Settings gains a Protection Rules section (add/remove with kind picker).
- Enforcement wired through every batch path: default selection, row selectability, and preview all consult the protection check (CleanupModel.protectedPathCheck); protected services show locks in the process/port tables; protected volumes lose their delete button entirely.
- Rule library: 18 new draft rules (24 files total) — xcode (DerivedData/DeviceSupport/simulator caches/SPM cache regenerable, Archives user_data), huggingface, playwright, pnpm, yarn, pip, uv, cargo, go, gradle, homebrew, cocoapods, ollama (models kept user_data so they never enter one-click cleanup), plus project-scope artifact rules for frontend (.next/.vite/dist/…), python (.venv/…), rust (target), jvm (build/.gradle/target), swift (.build). All schema-valid; zh-Hans copy seeded for every new target (SPEC §8.5(5)).
- 8 new tests (protection store/evaluator semantics, brew JSON parsing, stop-subcommand mapping). 114 total, green.

Needs human verification:
- `brew services` flows against a real postgres/redis install (kill vs stop vs run semantics).
- New draft rules against this machine via Doctor; promote what checks out.
- A path-prefix protection rule visibly locks a project's artifacts and survives restart.

## M10 — Dev sessions + menu bar — DONE (2026-07-12)

Shipped:
- `SessionResolver` (SPEC §5.13): running services and running containers group into per-project sessions via the existing attribution chain (no new heuristics); stopped containers and unattributed resources never join. `SessionTemplate` + versioned store (save/apply/remove; replace-by-name).
- Sessions page (⌘4): session cards with resource chips (protected ones locked), memory/port impact line, save-as-template, end-session; templates section with apply (routes to the live session's confirmation, or explains there is nothing running).
- End-session sheet: per-resource checkboxes grouped processes/containers, protected resources listed under "Kept" and never selectable, live progress ("Stopping X…"), per-step results with partial-failure summary; optional "review this project's regenerable artifacts" hands off to the mandatory cleanup preview afterwards — the sheet itself never deletes files. Processes stop via SIGTERM + grace (no auto-SIGKILL; survivors are reported and can be force-quit individually), then containers via `docker stop`. Every step audited under ruleID "session".
- Overview gains the current-session card; sidebar gains Sessions with a live badge.
- `MenuBarExtra` (SPEC §5.14, opt-in via Settings → General): port/resource/reclaimable summary, current session with "End Development Session…" (opens the main-window confirmation — nothing destructive fires from the menu), find port, scan, open main window, quit. Static SF Symbol icon, no animation.
- 5 new tests (session grouping/sorting/exclusions, template store). 119 total, green.

Needs human verification:
- End a real mixed session (vite + compose) and check stop order, partial-failure reporting, and container refresh.
- Menu bar toggle on/off, and the end-session path from the menu bar.

## M11 — History view + notifications + scheduled scan + global search — DONE (2026-07-12)

Shipped:
- History page (⌘5, SPEC §5.16): audit log grouped by day (newest first, capped at 500 rows), method icons and localized labels, failure rows show the raw result in orange, successful trash operations offer "Open Trash". Toolbar: open log file, export diagnostics (operations.jsonl + environment.txt zipped via /usr/bin/ditto — version, macOS, FDA state, rule counts, docker/brew presence; no extra user paths beyond the log itself).
- Notifications (SPEC §5.15): reclaimable-space alert (configurable GB threshold, at most weekly) and long-running-services alert (at most daily), independently switchable, authorization requested on first enable. Gated on a real bundle identifier — bare `swift run` shows an explanatory footer instead. Notifications never trigger actions.
- Scheduled scan: manual/daily/weekly picker; an hourly in-app ticker starts a scan when due. The timer path calls only `scan()` — the deletion pipeline stays exclusively behind the interactive preview.
- Global search: with text in the search field, Overview switches to cross-page results (processes, projects, cache items, capped at 5 each) with jump links; other pages keep their local filtering.
- 119 tests green; localization sync green (317 app keys, 86 core keys).

Needs human verification:
- History rows against real operations; diagnostics zip contents.
- Notifications from the bundled .app (threshold + rate caps).
- Daily scheduled scan fires after 24 h of app uptime (or by clearing lastAutoScanDate).

## M11.1 — Environment edge-case hardening — DONE (2026-07-12)

- Homebrew present but `brew services list` failing now shows an explicit error state with a retry button (was silently rendered as "no services").
- Rule-library load errors now surface on the Storage → Projects tab too (previously only on Tool Caches).
- Overview greeting has a dedicated idle variant instead of "0 resources running".
- Docker-missing empty state mentions Podman ("detected, not yet manageable") when only Podman is installed.
- Already covered and re-verified: no Docker CLI / daemon down (informational cards, standard install locations listed), no Homebrew, no code roots (guided to settings), FDA denied (persistent banner), empty scan, no listening ports, no sessions, empty history, notifications unavailable outside a bundle.

## M12 — Hardening + cleanup ergonomics + AI Tools section — DONE (2026-07-13)

Shipped (motivated by a full-codebase review):

Release/CI defects:
- **v0.1.0 shipped with only 6 of 24 rules**: M9 added 18 rules to `rules/tools/` without running `scripts/sync-rules.sh`, so the bundled copy (what the app actually loads) never got them. Synced; `sync-rules.sh --check` in CI would have caught it, but CI was red for an unrelated reason so the signal drowned.
- CI ran on macos-14 with an Xcode 15.4 selection (Swift 5.10) — the Swift 6 manifest could not even parse, so the build job had been failing since day one while the macos-15 release workflow was green. Both CI jobs now run on macos-15.
- `huggingface` rule targeted all of `~/.cache/huggingface` as regenerable — which contains the HF login token, violating the credentials-are-protected rule. Narrowed to `~/.cache/huggingface/hub`; token paths added as an explicit `protected` target.

Safety-layer fixes (gate tests first, per CLAUDE.md):
- **Gate rule 2 restored to independence**: the app passed `scan.items` paths as the gate's allowed prefixes, making containment a tautology (preview items are a subset of scan items). New `DiskScanner.allowedDeletionPrefixes(rules:projects:)` re-expands prefixes from the enabled rules at execution time; `CleanupModel.execute` now takes rules+projects and can no longer be fed raw paths.
- `AuditLog.append` could replace the whole log with a single line if an existing file failed to open (the fallback whole-file write was meant for first-write only). Now create-if-missing + append handle only; an open failure is an error, never a truncation. Invariant pinned by test.
- `ServiceStopper.stop` busy-waited against libproc for the full grace period when its task was cancelled (`try? Task.sleep` swallowed the cancellation). Cancellation now exits the poll loop immediately (test measures promptness).

App-layer fixes:
- Rescans never re-ran default selection/risk rebuild/notifications: reactions keyed on `hasScanned`, which only changes on the first scan. New monotonic `scanGeneration` drives them on every scan.
- The async git-probe completion re-ran `defaultSelect`, silently resetting any selection the user made while the probe ran. Now a tighten-only `tightenSelection` drops newly-S2 items and touches nothing else.
- Cleaned items stayed in every list until the next scan happened to run (nothing pruned `scan.items` after a run and cleanup never triggered a rescan; reported from real use on the AI Tools page). A finished run now removes its trashed/deleted paths from the scan results immediately; the next scan still re-verifies from disk.
- Full post-action refresh audit prompted by that report, fixing the same class everywhere:
  - The `isRefreshing` guard in RuntimeModel/ContainerModel/BrewModel silently dropped refreshes requested mid-refresh, so concurrent actions (the dangling-image batch, parallel process stops, parallel brew actions) could end on a snapshot taken mid-batch. Refreshes are now coalesced: a request during a running refresh queues exactly one trailing re-run.
  - Ending a session refreshed the process/container tables only via the sheet's Done button — Esc or clicking outside at the results page skipped it entirely, and the tables/menu bar stayed stale while the results page was open. AppShell now refreshes both the moment the run reaches `.finished` (the Done-path refresh remains and coalesces away).
  - Adding a protection rule locked matching rows but left already-selected paths in the selection bar (enforcement was never at risk — the preview and gate both filter — but the count/bytes were misleading). Selections are now tightened the moment the rules change.

Cleanup ergonomics (SPEC §4.4 note):
- `gitDirty` downgraded S2→S1: uncommitted changes are the steady state of active development and build artifacts are not part of git state, so dirty repos no longer start deselected everywhere (that was most of the "have to re-check everything" pain). `projectInUse` stays S2.
- Group select-all checkboxes on tool-cache and project-kind group headers (regenerable only); "Select Low-Risk" button on Storage and AI Tools adds every sub-S2 regenerable item without dropping manual picks; selection bar extracted to a shared `CleanupSelectionBar`.

AI Tools section (SPEC §5.17, sidebar ⌘6):
- One card per AI tool (ai-cli/ai-app categories + ollama/huggingface): regenerable caches with group select, user_data grouped by attributed project (dashed-bucket decoding already existed), protected rows display-only. Doctor entry in the toolbar (AI layouts drift fast; all rules are draft). AI rules are removed from Storage→Tool Caches (mutually exclusive listings); dashboard deep links route AI items to the new section.

Docs/scripts:
- SPEC §6.2/§6.3 and rules/BACKLOG.md caught up with the 24-rule reality (both still described the 6-rule seed library).
- Removed the `SPARKLE_ED_KEY` branch from release.sh: gen-appcast.py never emits `sparkle:edSignature`, so setting the key would have broken every future update. notarize.sh closing hint now points at gen-appcast.py (the tool CI actually uses) instead of Sparkle's generate_appcast with a different URL scheme.
- 122 tests green (3 new).

Needs human verification:
- AI Tools page visually (en/zh-Hans): card grouping, per-project session buckets, group select, ⌘6.
- "Select Low-Risk" + group checkboxes against a real scan; confirm user_data never auto-selects.
- A rescan (⌘R) after deleting something re-applies default selection and refreshes badges.
- Upgrade path: install v0.1.0, let Sparkle offer v0.1.1, confirm the update applies (first real Sparkle round-trip).

## Release pipeline — CI signing + notarization (2026-07-12)

- `.github/workflows/release-build.yml`: workflow_dispatch + v* tags. Imports the Developer ID .p12 from `MAC_CSC_LINK`/`MAC_CSC_KEY_PASSWORD` into a throwaway keychain, parses the team id from the identity, runs `scripts/release.sh` (hardened runtime on because a real identity is present), notarizes with `APPLE_ID`/`APPLE_APP_SPECIFIC_PASSWORD`, staples, Gatekeeper-asserts, generates a Sparkle appcast (`scripts/gen-appcast.py` — Apple-code-signature validation, no EdDSA needed since SUPublicEDKey is unset), uploads artifacts, and publishes a GitHub Release on tags.
- Release recipe: bump CFBundleShortVersionString + CFBundleVersion in App/Info.plist → tag `v<version>` → push tag. Users on older builds get the update via Sparkle from releases/latest/download/appcast.xml.
