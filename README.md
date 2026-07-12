**English** | [简体中文](README.zh-Hans.md)

# Mothball

**Reclaim the disk space your dev tools leave behind.**

Mothball is a native macOS utility that aggregates the development resources scattered across your machine — AI coding tool caches and histories, project build artifacts, dev servers still listening on ports, Docker containers and images — **by project**, and lets you visually reclaim them in one sweep.

Every disk tool out there takes a *resource-type* view (only Docker, only `node_modules`). Mothball takes a *project* view: pick a project, see everything it drags along, clean it up in one click.

- **Native**: Swift 6 + SwiftUI, Apple Silicon (macOS 14+). No Electron.
- **Safe by design**: three safety tiers. Caches are one-click; session history only ever goes to the Trash with per-item confirmation; credentials and configs are display-only — no delete path exists for them in the code.
- **Local & open**: Apache-2.0, nothing leaves your machine, no accounts, no sudo, ever.
- **Community rules**: which tool stores what, where, and how safe it is to remove lives in a declarative JSON rule library (`rules/`) anyone can extend.

## Status

Pre-release, under active development. See [docs/PROGRESS.md](docs/PROGRESS.md).

## Install

Download the notarized dmg from [Releases](https://github.com/juntook/Mothball/releases). Updates arrive in-app via Sparkle.

Homebrew cask coming soon:

```sh
brew install --cask juntook/tap/mothball
```

Not on the Mac App Store — the core features (scanning arbitrary tool directories, process management) are incompatible with App Sandbox.

## Build

```sh
swift build          # Core library, `mothball` debug CLI, app shell
swift test           # unit tests
./scripts/validate-rules.sh   # rule library validation
```

Requires the Swift 6 toolchain. `scripts/release.sh` assembles the signed, distributable app; CI notarizes and publishes releases on `v*` tags.

## Contributing rules

Tool layouts move fast — especially AI CLIs. Rules carry a `status` field: `draft` (paths from public docs, unverified) or `verified` (checked on a real machine via the in-app Doctor panel). PRs that add tools or verify drafts are the most valuable contribution. Start from `rules/BACKLOG.md`.

## License

Apache License 2.0 — see [LICENSE](LICENSE) and [NOTICE](NOTICE).
