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

## Build

```sh
swift build          # Core library, `mothball` debug CLI, app shell
swift test           # unit tests
./scripts/validate-rules.sh   # rule library validation
```

Requires the Swift 6 toolchain. Building the distributable, signed app requires full Xcode (see `scripts/`, arriving with M6).

## Contributing rules

Tool layouts move fast — especially AI CLIs. Rules carry a `status` field: `draft` (paths from public docs, unverified) or `verified` (checked on a real machine via the in-app Doctor panel). PRs that add tools or verify drafts are the most valuable contribution. Start from `rules/BACKLOG.md`.

## License

Apache License 2.0 — see [LICENSE](LICENSE) and [NOTICE](NOTICE).

---

# Mothball(简体中文)

**把开发工具留下的磁盘空间收回来。**

Mothball 是一个 macOS 原生小工具,把散落在你电脑各处的开发资源——AI 编程工具的缓存与会话历史、项目构建产物、还在后台监听端口的开发服务、Docker 容器与镜像——按**项目**聚合起来,可视化地一键释放。

市面工具都是"资源类型视角"(只看 Docker、只看 node_modules);Mothball 是"项目视角":选中一个项目,看到它拖着的全部占用,一键收拾。

- **原生**:Swift 6 + SwiftUI,Apple Silicon(macOS 14+),不用 Electron。
- **安全优先**:三级安全分级——缓存可一键清理;会话历史只进废纸篓且逐项确认;凭证与配置只读展示,代码里根本不存在删除它们的路径。
- **本地开源**:Apache-2.0,数据不出本机,无账号体系,永不请求 sudo。
- **社区规则库**:每个工具把什么存在哪里、删了是否安全,都写在声明式 JSON 规则库(`rules/`)里,欢迎共同维护。

## 构建

```sh
swift build
swift test
./scripts/validate-rules.sh
```

需要 Swift 6 工具链;产出可分发的签名 App 需要完整 Xcode(见 `scripts/`,随 M6 交付)。

## 参与规则库

AI 工具的目录布局变化很快。规则带有 `status` 字段:`draft`(路径来自公开资料,未核实)/ `verified`(在真机上通过应用内 Doctor 面板核实)。新增工具或核实 draft 规则是最有价值的贡献,可从 `rules/BACKLOG.md` 开始。
