# Rules backlog

Tools/targets to add after V1, ordered by expected disk-space payoff. Contributions welcome — copy an existing rule in `tools/`, keep `status: "draft"`, and verify via the in-app Doctor panel before proposing `verified`.

1. **Hugging Face model cache** — `~/.cache/huggingface` (routinely tens of GB; highest payoff)
2. **Playwright browsers** — `~/Library/Caches/ms-playwright`
3. **Xcode** — DerivedData, old simulator runtimes
4. **pip / uv / cargo registry / Go build cache / Gradle / Maven**
5. **pnpm store, yarn cache**
6. **Gemini CLI** (`~/.gemini`), **Cursor**, **VS Code** Cache/CachedData/workspaceStorage
7. **Ollama** model directory
8. **Homebrew** download cache — `~/Library/Caches/Homebrew`
9. **CocoaPods, JetBrains caches**
10. **Docker Desktop** app-level caches (distinct from engine-side resources, which V1 already manages)

## V2 TODOs recorded from SPEC

- Nested monorepo sub-project attribution (V1 attributes to the outermost project root)
- Docker over UDS HTTP client (V1 shells out to the docker CLI)
- Podman machine management (V1 detects and shows "not yet supported")
