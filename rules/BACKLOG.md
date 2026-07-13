# Rules backlog

Tools/targets to add, ordered by expected disk-space payoff. Contributions welcome — copy an existing rule in `tools/`, keep `status: "draft"`, and verify via the in-app Doctor panel before proposing `verified`.

Landed in M9 (now in `tools/`, most still `draft` — verifying them on real machines is the highest-value contribution): Hugging Face, Playwright, Xcode, pip, uv, cargo, Go build cache, Gradle, pnpm, yarn, Ollama, Homebrew, CocoaPods, plus the frontend/python/rust/jvm/swift project-artifact rules.

1. **Gemini CLI** (`~/.gemini`), **Cursor**, **VS Code** Cache/CachedData/workspaceStorage
2. **JetBrains caches** (per-IDE caches, logs, leftover old versions)
3. **Docker Desktop** app-level caches (distinct from engine-side resources, which the app already manages)
4. **Maven repository** `~/.m2/repository` and **Go module cache** `~/go/pkg/mod` — both routinely multi-GB; deletion semantics need care (`go clean -modcache` owns the read-only module cache)
5. **Bun, Corepack, npx** temporary packages

## V2 TODOs recorded from SPEC

- Nested monorepo sub-project attribution (V1 attributes to the outermost project root)
- Docker over UDS HTTP client (V1 shells out to the docker CLI)
- Podman machine management (V1 detects and shows "not yet supported")
