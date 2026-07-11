# Mothball — V1 产品规格(SPEC)

> 本文档是交给 Claude Code 的唯一需求源。阅读约定:
> 1. 按 §7 的里程碑顺序实现,每个里程碑结束后停下等人工验收,不要跨里程碑赶工。
> 2. 遇到本文未覆盖或与真机现实冲突的决策点:先列出选项与建议,经确认后再动手。
> 3. §4.3 安全分级和 §5.6 删除闸门是不可协商的硬约束,任何情况下不得为实现便利绕过。
> 4. 文中标注 `[待真机核实]` 的信息来自公开资料,实现时必须先在开发机上验证。

---

## 1. 产品定位

**产品名**:Mothball(取自 "mothball a project"——把闲置项目封存入库)。App 显示名 Mothball(各语言下不翻译);bundle id 占位 `com.example.mothball`,首次构建前替换为你自己的反向域名;GitHub 仓库、Homebrew cask token、cli 二进制统一小写 `mothball`。

**一句话**:一个 macOS 原生小工具,把开发者电脑上散落的开发资源——AI 编程工具的缓存与历史、项目构建产物、还在后台跑的服务进程和端口、Docker 容器与镜像——按"项目"聚合起来,可视化地一键释放。

**目标用户**:重度使用 AI 编程工具(Claude Code、Codex、CodeBuddy 等)的开发者,手里同时有多个项目,机器是 Apple Silicon Mac。

**核心差异化**:市面工具都是"资源类型视角"(只看 Docker、只看 node_modules)。本产品是"项目视角"——选中一个项目,看到它拖着的全部磁盘占用和运行时资源,一键收拾。归属识别引擎(§5.3)是全产品最核心的模块。

**V1 交付物**:一个可直接下载(非 App Store)的开源 macOS App,Apache-2.0 协议,含一份社区可维护的声明式规则库。

---

## 2. 范围边界

### 2.1 In scope(V1 做)

| # | 模块 | 一句话 |
|---|------|--------|
| A | 规则引擎与规则库 | 声明式 JSON 规则,描述各工具的缓存/历史/配置位置与安全级 |
| B | 磁盘扫描器 | 按规则扫描全局目标 + 项目内构建产物,计算占用 |
| C | 项目发现与归属识别 | 找到用户的项目,把每个资源映射到项目 |
| D | 运行时探测 | 监听端口的进程、其工作目录、内存占用;优雅停止 |
| E | 容器资源 | 多运行时端点发现;容器/镜像/卷/构建缓存的列表与清理 |
| F | 清理执行器与安全机制 | 预览、废纸篓、审计日志、删除闸门 |
| G | UI(项目/工具/运行时三视图) | SwiftUI 原生界面 |
| H | Onboarding 与发布基建 | 完全磁盘访问引导、签名公证、Sparkle、Homebrew tap |

### 2.2 Out of scope(V1 明确不做,防 scope creep)

- Windows / Linux / Intel Mac / WSL(架构上不为其妥协,规则库 schema 保留 platform 字段即可)
- 后台常驻监控、菜单栏提醒、定时自动清理(未来 Pro 层,V1 只做手动扫描)
- 项目归档(打包成 tar 移走)
- 任何付费/授权/账号体系
- 系统级清理(浏览器缓存、系统日志、重复文件查找——不做 CleanMyMac)
- 应用卸载(不做 AppCleaner)
- Podman machine 的深度管理(仅检测并提示)
- 嵌套 monorepo 的子项目粒度归属(以最外层项目根为准,记录为 V2 TODO)

---

## 3. 平台与技术约束

- **平台**:macOS 14.0+,仅 arm64(Apple Silicon)。不做 Intel 切片。
- **语言/框架**:Swift(Swift 6 toolchain,开启 strict concurrency),SwiftUI。禁止引入 Electron/Tauri/webview。
- **架构分层**:
  - `Core`(SwiftPM 包):规则引擎、扫描器、归属识别、运行时探测、Docker 客户端、清理执行器。零 UI 依赖,全部可单元测试。
  - `App`(SwiftUI target):纯展示层,只调用 Core 的公开接口。
  - `cli`(可选调试 target):把 Core 能力暴露成命令行,便于开发期验证与自动化测试。
- **权限模型**:全程以当前登录用户身份运行。**永不请求 sudo,永不安装特权 helper**。做不到的事(如管理其他用户的进程)直接不做。
- **沙盒**:App 不开启 App Sandbox(核心功能与沙盒不兼容),因此不上 Mac App Store;分发走 Developer ID 签名 + 公证。
- **UI 语言**:en(Base)+ zh-Hans,自 M0 起执行 §8.5 的 i18n 规范;README 双语。
- **依赖策略**:优先零第三方依赖。允许引入:Sparkle(更新)。其余需先论证。

---

## 4. 核心概念与数据模型

### 4.1 实体

```
Rule          一个工具的管理规则(如 claude-code)
└── Target    该工具的一个可管理位置(如 ~/.claude/statsig)

Project       用户的一个项目(由标志文件识别的目录)
ResourceItem  一条被发现的磁盘资源(target 的一次命中,含路径、大小、归属)
RunningService一个被发现的运行时服务(进程 + 监听端口 + cwd + 归属)
ContainerResource  一条容器侧资源(容器/镜像/卷/构建缓存,含归属)
```

### 4.2 Target 的维度

- `kind`:`cache` | `log` | `history` | `config` | `credential` | `artifact` | `state`
- `scope`:`global`(固定路径,如 `~/.npm/_cacache`)| `project`(相对项目根匹配,如 `node_modules`)
- `safety`:见 4.3

### 4.3 三级安全分级(硬约束)

| 级别 | 含义 | 典型例子 | UI 行为 | 允许的删除方式 |
|------|------|----------|---------|----------------|
| `regenerable` | 可再生,删了自动重建 | 缓存、日志、遥测、构建产物、悬空镜像 | 默认勾选,可一键清理 | 废纸篓(默认)/ 直接删除(设置项,需二次确认) |
| `user_data` | 用户资产,删了不可再生 | 会话历史、todo、工作区状态、有 tag 的镜像 | **默认不勾选**;勾选时逐项展示明细并单独确认 | **只允许进废纸篓** |
| `protected` | 受保护 | 凭证、配置文件、数据卷内容 | 只读展示(帮助理解占用),**无任何删除入口**,批量操作必须跳过 | 禁止 |

设计原则:AI 编程工具的会话历史(`~/.claude/projects`、`~/.codex/sessions` 等)是用户的思考记录,一律 `user_data`,绝不进入一键清理。这是产品信任的底线。

---

## 5. 模块规格

### 5.1 规则引擎与规则库

- 规则为 JSON 文件,存放于仓库 `rules/tools/*.json`,每工具一个文件;`rules/schema/rule.schema.json` 提供 JSON Schema(draft-07),CI 强制校验全部规则通过 schema + 语义检查(id 唯一、路径合法、safety 枚举合法)。
- 规则文件随 App 打包为资源;同时支持从 `~/Library/Application Support/Mothball/rules/` 加载用户本地追加规则(同 id 时本地覆盖内置)。
- 路径支持 `~` 展开与 glob(仅 `*`,不支持 `**` 与 `..`)。
- 每条规则有 `status` 字段:`draft`(路径来自公开资料,未核实)/ `verified`(在真机核实过)+ `verifiedOn` 日期。UI 对 draft 规则的结果打"未验证"角标,清理前额外提示。
- App 内置 **Doctor 调试面板**(开发者菜单):逐条列出每个 target 在本机的存在性、实际大小、权限可读性;这是把规则从 draft 升级为 verified 的工作台,也是社区贡献规则的验证工具。
- 规则的 `description`/`regenerateHint` 用英文书写(社区资产单一语言);UI 展示时按 §8.5 第 5 条做键映射本地化,未命中回退英文原文。

### 5.2 磁盘扫描器

- 手动触发(工具栏"扫描"按钮 + 首次启动引导后自动跑一次)。V1 不做后台增量索引。
- 两类扫描:
  1. **全局目标**:遍历所有已启用规则的 `scope=global` targets,存在则计算大小。
  2. **项目内产物**:对每个已发现项目根,匹配 `scope=project` 的 `projectGlobs`,且 `guardFiles` 中至少一个标志文件在同级存在时才认定(防止把非 Node 目录里碰巧叫 node_modules 的东西算进来)。
- **大小计算**:用 `fts(3)` 或 `getattrlistbulk` 做批量枚举(禁止 FileManager 逐项 stat,量级差 10 倍);按顶层目录并发;统计 allocated size(物理占用)而非 logical size。
- **不跟随符号链接**;遇到 dataless 文件(iCloud 占位,`SF_DATALESS`)只计元数据、**绝不触发下载**。
- **性能目标**:典型开发机(几十万文件的 node_modules 若干)首次完整扫描 ≤ 60 秒,目标 30 秒;UI 渐进呈现——条目先出现,大小异步补齐,不允许白屏等待。

### 5.3 项目发现与归属识别引擎(核心模块)

**项目发现**
- Onboarding 时用户选择一个或多个"代码根目录"(默认建议 `~/`,可添加排除项);仅在这些根内发现项目。
- 自根目录向下 BFS,深度上限 6;跳过隐藏目录、`node_modules`、`Library`、`.Trash`。
- 目录内命中任一标志文件即认定为项目根,并**不再向其内部深入**:`.git`、`package.json`、`pyproject.toml`、`Cargo.toml`、`go.mod`、`Gemfile`、`pom.xml`、`build.gradle(.kts)`、`CMakeLists.txt`、`Package.swift`、`docker-compose.yml`。
- 项目属性:名称(目录名)、路径、最后活跃时间(优先 `git log -1 --format=%ct`,无 git 则根目录 mtime)。

**归属证据源**(按置信度排序,任一命中即归属;全部未命中进"未归属/全局"桶)

| # | 证据 | 适用资源 | 置信度 |
|---|------|----------|--------|
| 1 | 资源路径本身位于某项目根之内 | 项目内产物(node_modules 等) | 天然归属 |
| 2 | 进程 cwd 落在某项目根内(含子目录,向上取最近项目根) | 运行时服务 | 高 |
| 3 | 容器标签 `com.docker.compose.project` + `com.docker.compose.project.working_dir` | 容器/compose 卷与网络 | 高 |
| 4 | 规则声明的路径编码:target 标注 `attribution.encoding = "dashed-absolute"` 时,子目录名如 `-Users-me-dev-shop` 解码为 `/Users/me/dev/shop` 再匹配项目根(Claude Code 的 `~/.claude/projects` 与其缓存目录采用此编码) | 工具的按项目分桶数据 | 高 |
| 5 | 容器 bind mount 的宿主机源路径落在某项目根内 | 容器 | 中 |

- 归属结果附带证据类型,UI 悬停可见("通过 compose 标签归属")。
- 解码/匹配必须做路径规范化(realpath、大小写按 APFS 默认不敏感处理)。

### 5.4 运行时探测

- **发现链路**(全部走 libproc 用户态 API,无需特权):
  `proc_listpids` 列本用户进程 → `proc_pidfdinfo` 找处于 LISTEN 状态的 TCP socket 及端口 → `proc_pidpath` 取可执行路径 → `proc_pidvnodepathinfo` 取 cwd → `proc_pid_rusage` 取内存/启动时间。
- **展示范围**:仅当前用户的进程,且满足其一:监听 TCP 端口;或 cwd 归属到某已发现项目。系统守护即使同 uid 也按内置排除名单过滤(如 `rapportd` 等,名单放规则库 `rules/system-exclusions.json` 便于社区补充)。
- **列表字段**:端口、进程名、PID、cwd、归属项目、内存、已运行时长。
- **停止流程**:发送 SIGTERM → 轮询 5 秒 → 仍存活则弹窗提供"强制结束"(SIGKILL,需确认)。
- **PID 复用防护**:发信号前重新校验(pid, 启动时间)二元组一致,否则中止并刷新列表。

### 5.5 容器资源

- **端点发现**(按序,全部记录到诊断信息):
  1. `docker context ls / inspect` 取 current context 的 endpoint;
  2. 探测常见 socket:`~/.docker/run/docker.sock`(Docker Desktop)、`~/.orbstack/run/docker.sock`(OrbStack)、`~/.colima/default/docker.sock`(Colima)、`/var/run/docker.sock`;
  3. 环境变量 `DOCKER_HOST`。
  Podman:仅检测存在并在 UI 提示"暂不支持管理",不报错。
- **V1 执行方式**:shell-out 到 `docker` CLI(`--format json` / `system df --format json`),不实现 UDS HTTP 客户端(记为 V2 优化)。**注意 GUI App 的 PATH 不含 Homebrew 路径**:必须在固定候选列表中解析二进制(`/opt/homebrew/bin/docker`、`/usr/local/bin/docker`、`~/.orbstack/bin/docker`、`/Applications/Docker.app/Contents/Resources/bin/docker`),找不到则空状态引导。
- **资源与操作矩阵**:

| 资源 | 展示 | 操作 | 安全级 |
|------|------|------|--------|
| 运行中容器 | 名称、镜像、端口映射、compose 项目、启动时长 | 停止 | regenerable 级确认 |
| 已停止容器 | 同上 + 停止时间 | 删除(`rm`) | regenerable |
| 悬空镜像(dangling) | 大小、创建时间 | 删除 | regenerable,可一键 |
| 有 tag 且无容器引用的镜像 | tag、大小 | 删除 | user_data 级逐项确认(重新 pull/build 有成本) |
| 卷(volume) | 名称、compose 项目、是否被引用 | 单个删除 | **protected 展示 + 强确认单删**,永不进批量 |
| 构建缓存 | 总大小 | `builder prune` | regenerable |

- compose 项目按 label 聚合,并通过 §5.3 证据 3 归属到本地项目。
- Docker 守护未运行:空状态卡片说明原因与启动方式,不弹错误。

### 5.6 清理执行器与安全机制

**流程**:勾选 → 点"清理" → 预览确认页(sheet,逐项列出:路径、大小、安全级、恢复提示;user_data 项高亮并要求单独勾选确认;protected 项永不出现)→ 执行(进度)→ 结果页(共释放 X GB + 操作明细)。

**删除闸门(执行器内的最后一道硬校验,独立于 UI 逻辑,违反任何一条即拒绝该项并记录)**:
1. 只接受来自本次预览清单的不可变路径集合,UI 与执行器之间不传"规则",只传"已确认的具体路径"。
2. 路径 realpath 规范化后,必须以某条**已启用规则展开出的前缀**开头。
3. 硬拒绝:`/`、用户家目录本身、任何包含 `..` 的路径、长度 < 8 的路径、位于 `/System` `/Library`(系统级)之下的路径。
4. 删除操作不跟随符号链接。
5. `user_data` 只允许 `FileManager.trashItem`(进废纸篓);废纸篓失败(跨卷等)时**中止并询问**,不静默转直删。
6. `regenerable` 默认进废纸篓;"直接删除"是全局设置项,开启时每次会话首个直删操作需二次确认。

**审计日志**:每次操作追加 JSONL 到 `~/Library/Logs/Mothball/operations.jsonl`,字段:时间、规则 id、target id、路径、字节数、方式(trash/delete/stop/docker-*)、结果。设置页提供"打开日志"入口。

**忽略列表**:任何条目可"忽略"(路径级),忽略项持久化,扫描仍统计但默认折叠且不可勾选。

**APFS 快照提示**:清理结果页固定附带说明文案——"macOS 本地快照可能暂时保留已删除数据,Finder 显示的可用空间会在快照过期后(通常 24 小时内)更新"。这是该品类差评的头号来源,必须主动解释。

### 5.7 UI 信息架构

- `NavigationSplitView`,侧边栏:**项目** / **工具** / **运行时** / 设置。V1 不做"概览"仪表盘。
- **项目视图(默认首页,产品灵魂)**:项目卡片列表,每卡:名称、路径、最后活跃(如"3 个月前")、磁盘占用合计、运行中资源角标(如"2 个进程 · 1 个容器")。点入详情:该项目的全部 ResourceItem / RunningService / ContainerResource,按类型分组,可勾选清理。列表末尾固定"未归属 / 全局"分组。
- **工具视图**:按规则(Claude Code、Codex…)分组的全局目标,展示每工具占用合计与明细,draft 规则带"未验证"角标。
- **运行时视图**:§5.4 进程表 + §5.5 容器资源表,手动刷新按钮,进入页面时自动刷新一次。
- **设计基调**:克制的原生感——系统标准控件、SF Symbols、无自绘仪表盘;像"系统设置"而不是霓虹灯监控面板。大小数字用等宽数字字体,排序默认按占用降序。

### 5.8 Onboarding 与权限

1. 欢迎页:一句话价值 + 开源与本地运行声明(不上传任何数据)。
2. 选择代码根目录(§5.3),可跳过(则只扫全局目标)。
3. **完全磁盘访问(FDA)引导**:说明为什么需要(扫描受 TCC 保护的目录)、一键打开系统设置对应面板、检测授权状态(以能否读取一个受 TCC 保护的标志路径为探针)。
4. 未授权时进入**降级模式**:正常运行,但在扫描结果顶部持续显示"结果不完整:未授予完全磁盘访问"横幅——绝不能呈现"看起来正常但数据莫名偏少"的假坏状态。
5. 首次扫描自动开始,渐进出结果。

---

## 6. 种子规则库

### 6.1 规则 Schema(示意,正式版生成 `rules/schema/rule.schema.json`)

```jsonc
{
  "schemaVersion": 1,
  "id": "kebab-case-unique-id",
  "name": "Display Name",
  "vendor": "Vendor",
  "category": "ai-cli | ai-app | package-manager | build-tool | ide | runtime",
  "homepage": "https://…",
  "platforms": ["macos"],
  "status": "draft | verified",
  "verifiedOn": "YYYY-MM-DD",
  "notes": "Known unknowns, verification hints for contributors",
  "detection": {
    "anyPaths": ["~/.tool"],        // 任一存在即认为该工具在本机出现过
    "anyBinaries": ["tool"],         // PATH 候选列表中可解析
    "anyApps": ["/Applications/Tool.app"]
  },
  "targets": [
    {
      "id": "kebab-case",
      "scope": "global | project",
      "paths": ["~/.tool/cache"],    // scope=global 用
      "projectGlobs": ["node_modules"], // scope=project 用,相对项目根
      "guardFiles": ["package.json"],   // scope=project 用,同级标志文件
      "kind": "cache | log | history | config | credential | artifact | state",
      "safety": "regenerable | user_data | protected",
      "description": "English, community-facing",
      "regenerateHint": "How it comes back after deletion",
      "attribution": { "encoding": "dashed-absolute" } // 可选,子目录名可解码为项目路径
    }
  ]
}
```

### 6.2 `rules/tools/claude-code.json`

```json
{
  "schemaVersion": 1,
  "id": "claude-code",
  "name": "Claude Code",
  "vendor": "Anthropic",
  "category": "ai-cli",
  "homepage": "https://github.com/anthropics/claude-code",
  "platforms": ["macos"],
  "status": "draft",
  "notes": "Layout moves fast; verify each target via Doctor before flipping to verified. Also check version install dirs (~/.claude/local or ~/.local/share/claude) which can be large — add as a target once confirmed.",
  "detection": {
    "anyPaths": ["~/.claude"],
    "anyBinaries": ["claude"]
  },
  "targets": [
    {
      "id": "cli-cache",
      "scope": "global",
      "paths": ["~/Library/Caches/claude-cli-nodejs"],
      "kind": "cache",
      "safety": "regenerable",
      "description": "CLI runtime cache and MCP server logs, bucketed per project",
      "regenerateHint": "Recreated automatically on next run",
      "attribution": { "encoding": "dashed-absolute" }
    },
    {
      "id": "statsig",
      "scope": "global",
      "paths": ["~/.claude/statsig"],
      "kind": "cache",
      "safety": "regenerable",
      "description": "Telemetry/feature-flag cache",
      "regenerateHint": "Recreated automatically"
    },
    {
      "id": "shell-snapshots",
      "scope": "global",
      "paths": ["~/.claude/shell-snapshots"],
      "kind": "cache",
      "safety": "regenerable",
      "description": "Shell environment snapshots",
      "regenerateHint": "Recreated automatically"
    },
    {
      "id": "session-history",
      "scope": "global",
      "paths": ["~/.claude/projects"],
      "kind": "history",
      "safety": "user_data",
      "description": "Full conversation transcripts (JSONL), one folder per project",
      "regenerateHint": "NOT recoverable — these are your session records",
      "attribution": { "encoding": "dashed-absolute" }
    },
    {
      "id": "todos",
      "scope": "global",
      "paths": ["~/.claude/todos"],
      "kind": "state",
      "safety": "user_data",
      "description": "Persisted task lists from sessions",
      "regenerateHint": "NOT recoverable"
    },
    {
      "id": "config",
      "scope": "global",
      "paths": ["~/.claude/settings.json", "~/.claude/CLAUDE.md", "~/.claude.json"],
      "kind": "config",
      "safety": "protected",
      "description": "User settings, global memory, onboarding state"
    }
  ]
}
```

### 6.3 `rules/tools/codex.json`

```json
{
  "schemaVersion": 1,
  "id": "codex",
  "name": "Codex CLI",
  "vendor": "OpenAI",
  "category": "ai-cli",
  "homepage": "https://github.com/openai/codex",
  "platforms": ["macos"],
  "status": "draft",
  "notes": "Verify exact filenames under ~/.codex (sessions/, log/, history.jsonl) on-machine; layout changes across releases.",
  "detection": {
    "anyPaths": ["~/.codex"],
    "anyBinaries": ["codex"]
  },
  "targets": [
    {
      "id": "sessions",
      "scope": "global",
      "paths": ["~/.codex/sessions"],
      "kind": "history",
      "safety": "user_data",
      "description": "Session rollout records (JSONL, bucketed by date)",
      "regenerateHint": "NOT recoverable — these are your session records"
    },
    {
      "id": "logs",
      "scope": "global",
      "paths": ["~/.codex/log"],
      "kind": "log",
      "safety": "regenerable",
      "description": "CLI/TUI logs",
      "regenerateHint": "Recreated on next run"
    },
    {
      "id": "history",
      "scope": "global",
      "paths": ["~/.codex/history.jsonl"],
      "kind": "history",
      "safety": "user_data",
      "description": "Prompt history",
      "regenerateHint": "NOT recoverable"
    },
    {
      "id": "auth",
      "scope": "global",
      "paths": ["~/.codex/auth.json"],
      "kind": "credential",
      "safety": "protected",
      "description": "Login credentials — never touched by cleanup"
    },
    {
      "id": "config",
      "scope": "global",
      "paths": ["~/.codex/config.toml"],
      "kind": "config",
      "safety": "protected",
      "description": "User configuration"
    }
  ]
}
```

### 6.4 `rules/tools/codebuddy-cli.json`(腾讯 CodeBuddy Code)

```json
{
  "schemaVersion": 1,
  "id": "codebuddy-cli",
  "name": "CodeBuddy Code",
  "vendor": "Tencent Cloud",
  "category": "ai-cli",
  "homepage": "https://www.codebuddy.ai",
  "platforms": ["macos"],
  "status": "draft",
  "notes": "Docs confirm ~/.codebuddy/settings.json and ~/.codebuddy/skills. Session/history/cache subdirectory names are NOT publicly documented — inventory ~/.codebuddy on a machine with real usage, then split 'home-dir' into proper cache/history targets and flip to verified.",
  "detection": {
    "anyPaths": ["~/.codebuddy"],
    "anyBinaries": ["codebuddy"]
  },
  "targets": [
    {
      "id": "settings",
      "scope": "global",
      "paths": ["~/.codebuddy/settings.json"],
      "kind": "config",
      "safety": "protected",
      "description": "User-level settings"
    },
    {
      "id": "skills",
      "scope": "global",
      "paths": ["~/.codebuddy/skills"],
      "kind": "config",
      "safety": "protected",
      "description": "User-authored global skills — user assets, display only"
    },
    {
      "id": "home-dir",
      "scope": "global",
      "paths": ["~/.codebuddy"],
      "kind": "state",
      "safety": "protected",
      "description": "Entire user dir shown for size awareness until cache/history subpaths are verified and split out"
    }
  ]
}
```

### 6.5 `rules/tools/workbuddy.json`(腾讯 WorkBuddy 桌面 Agent)

```json
{
  "schemaVersion": 1,
  "id": "workbuddy",
  "name": "WorkBuddy",
  "vendor": "Tencent Cloud",
  "category": "ai-app",
  "homepage": "https://www.workbuddy.ai",
  "platforms": ["macos"],
  "status": "draft",
  "notes": "Desktop agent app (public beta since 2026-03). Bundle id and cache layout unverified — inspect /Applications/WorkBuddy.app/Contents/Info.plist for the real bundle id, then replace the Caches glob with the exact path and split Application Support into cache vs. user-data targets.",
  "detection": {
    "anyApps": ["/Applications/WorkBuddy.app"]
  },
  "targets": [
    {
      "id": "app-caches",
      "scope": "global",
      "paths": ["~/Library/Caches/*WorkBuddy*", "~/Library/Caches/*workbuddy*"],
      "kind": "cache",
      "safety": "regenerable",
      "description": "App caches (path pattern pending bundle-id verification)",
      "regenerateHint": "Recreated automatically by the app"
    },
    {
      "id": "app-logs",
      "scope": "global",
      "paths": ["~/Library/Logs/*WorkBuddy*"],
      "kind": "log",
      "safety": "regenerable",
      "description": "App logs (path pattern pending verification)",
      "regenerateHint": "Recreated automatically"
    },
    {
      "id": "app-support",
      "scope": "global",
      "paths": ["~/Library/Application Support/WorkBuddy"],
      "kind": "state",
      "safety": "protected",
      "description": "App data incl. possible session history — display only until layout is verified and split"
    }
  ]
}
```

### 6.6 `rules/tools/npm.json`

```json
{
  "schemaVersion": 1,
  "id": "npm",
  "name": "npm",
  "vendor": "npm / Node.js",
  "category": "package-manager",
  "homepage": "https://www.npmjs.com",
  "platforms": ["macos"],
  "status": "draft",
  "detection": {
    "anyPaths": ["~/.npm"],
    "anyBinaries": ["npm"]
  },
  "targets": [
    {
      "id": "cacache",
      "scope": "global",
      "paths": ["~/.npm/_cacache"],
      "kind": "cache",
      "safety": "regenerable",
      "description": "Content-addressable package cache",
      "regenerateHint": "Repopulated on next install"
    },
    {
      "id": "npx-cache",
      "scope": "global",
      "paths": ["~/.npm/_npx"],
      "kind": "cache",
      "safety": "regenerable",
      "description": "npx package cache",
      "regenerateHint": "Repopulated on next npx run"
    },
    {
      "id": "logs",
      "scope": "global",
      "paths": ["~/.npm/_logs"],
      "kind": "log",
      "safety": "regenerable",
      "description": "npm debug logs",
      "regenerateHint": "Recreated as needed"
    }
  ]
}
```

### 6.7 `rules/tools/node-modules.json`(项目内产物示范)

```json
{
  "schemaVersion": 1,
  "id": "node-modules",
  "name": "Node.js project dependencies",
  "vendor": "generic",
  "category": "runtime",
  "platforms": ["macos"],
  "status": "verified",
  "detection": { "anyBinaries": ["node"] },
  "targets": [
    {
      "id": "node-modules",
      "scope": "project",
      "projectGlobs": ["node_modules"],
      "guardFiles": ["package.json"],
      "kind": "artifact",
      "safety": "regenerable",
      "description": "Installed dependencies for a project",
      "regenerateHint": "Rebuilt by npm/pnpm/yarn install"
    }
  ]
}
```

### 6.8 后续收录 backlog(V1 不做,写入 `rules/BACKLOG.md`,按预期收益排序)

1. Hugging Face 模型缓存 `~/.cache/huggingface`(动辄几十 GB,收益最高)
2. Playwright 浏览器 `~/Library/Caches/ms-playwright`
3. Xcode DerivedData 与旧模拟器运行时
4. pip / uv / cargo registry / Go build cache / Gradle / Maven
5. pnpm store、yarn cache
6. Gemini CLI(`~/.gemini`)、Cursor、VS Code 的 Cache/CachedData/workspaceStorage
7. Ollama 模型目录
8. Homebrew 下载缓存 `~/Library/Caches/Homebrew`
9. CocoaPods、JetBrains caches
10. Docker Desktop 应用自身的缓存目录(区别于引擎内资源)

---

## 7. 里程碑与验收标准

每个里程碑独立可运行、可验收;完成后更新 `docs/PROGRESS.md` 并停下等人工验收。

**M0 — 工程骨架**
交付:仓库结构(§8.1)、SwiftPM workspace(Core + App + cli)、Apache-2.0 的 LICENSE 与 NOTICE、CLAUDE.md、GitHub Actions CI(build + test + 规则 schema 校验)、i18n 脚手架(App 与 Core 各一个 String Catalog、`defaultLocalization: "en"`、zh-Hans 语言资源,§8.5)、可启动的空壳 App。
验收:`swift test` 绿;CI 绿;App 启动显示占位界面;系统语言切至简体中文后,占位界面显示中文。

**M1 — 规则引擎 + 磁盘扫描 + 工具视图(只读)**
交付:规则加载/校验/`~` 展开/glob;全局目标扫描与并发 sizing;工具视图列表(渐进出数);Doctor 面板;种子规则文案的 zh-Hans 词条(§8.5 第 5 条)。
验收:在开发机上真实显示 Claude Code / Codex / npm 的占用;含 50 万文件的目录 sizing ≤ 60s;dataless 文件不触发下载(单测模拟);用 Doctor 核实种子规则并把属实者升级 `verified`(此项为人工验收动作)。

**M2 — 清理执行器 + 安全机制**
交付:预览确认页、废纸篓删除、删除闸门全部 6 条、审计日志、忽略列表、APFS 提示文案。
验收:删除的条目可在废纸篓找回;user_data 需逐项确认且只能进废纸篓;protected 无删除入口;闸门单测覆盖全部拒绝分支(含 `/`、`..`、symlink、越界前缀);审计日志逐条落盘。

**M3 — 项目发现 + 归属识别(磁盘侧)**
交付:代码根目录配置、项目发现、项目内 artifact 扫描、dashed-absolute 解码归属、项目视图。
验收:对一棵构造的测试目录树(含嵌套 git、假 node_modules、无 guard 文件的干扰目录),项目发现与归属结果 100% 符合预期(固化为单测);`~/.claude/projects` 的子目录正确归属到对应项目。

**M4 — 运行时探测**
交付:libproc 发现链、过滤启发式、系统排除名单、SIGTERM→SIGKILL 流程、PID 复用防护、运行时视图。
验收:手工起一个 `vite`/`node` 开发服务,能被发现且端口、cwd、归属项目正确;结束流程按规格工作;不展示其他用户或系统守护进程。

**M5 — 容器资源**
交付:端点发现、docker CLI 解析(固定候选路径)、资源列表、操作矩阵、compose 归属。
验收:在 Docker Desktop 与 OrbStack 两种环境下均能列出四类资源;compose 起的容器归属到正确项目;守护未运行时呈现空状态引导而非报错;卷不出现在任何批量操作里。

**M6 — Onboarding + 发布基建**
交付:欢迎流程、FDA 引导与降级横幅、Sparkle 集成、签名公证脚本(`scripts/notarize.sh`)、自有 Homebrew tap 的 cask 草稿、README(双语)。
验收:无 FDA 时降级模式表现正确;产出一个公证通过、Gatekeeper 放行的 dmg;`brew install --cask <你的GitHub用户名>/tap/mothball` 在干净机器可装。
说明:官方 homebrew/cask 主库有知名度门槛(按 star 数等),初期发自有 tap,达标后再提主库。

---

## 8. 工程规范

### 8.1 仓库结构

```
/
├── App/                      # SwiftUI app target
├── Sources/Core/             # 纯逻辑包:Rules, Scanner, Attribution, Runtime, Docker, Cleaner
├── Sources/cli/              # 调试 CLI
├── Tests/CoreTests/
├── rules/
│   ├── schema/rule.schema.json
│   ├── tools/*.json          # 种子规则(§6)
│   ├── system-exclusions.json
│   └── BACKLOG.md
├── docs/PROGRESS.md
├── scripts/                  # notarize.sh, release.sh
├── .github/workflows/ci.yml
├── LICENSE                   # Apache-2.0 全文
├── NOTICE                    # 项目名 + copyright 行
├── CLAUDE.md
├── README.md                 # 英文为主 + 简中段落
└── SPEC.md                   # 本文档
```

`rules/` 目录保持零代码依赖、自包含(schema + 数据 + 文档),未来可原样拆为独立仓库。

### 8.2 协议

- Apache License 2.0:根目录放 LICENSE 全文与 NOTICE;新源文件顶部加 SPDX 标识 `// SPDX-License-Identifier: Apache-2.0`(轻量,不贴全款头)。
- 第三方依赖(Sparkle 等)在 NOTICE/致谢中列明其协议。

### 8.3 CLAUDE.md 必须包含的约束(M0 时生成)

- 平台约束(§3)照抄;永不 sudo、永不特权 helper。
- §4.3 与 §5.6 为硬约束,提出任何绕过均需人工确认。
- Cleaner 与删除闸门模块:测试先行(先写拒绝分支的失败用例)。
- 每个里程碑一个 PR 粒度的提交序列;提交信息用祈使句英文。
- 规则 JSON 改动必须过 schema 校验;新增规则默认 `status: draft`。
- 用户可见字符串必须走 String Catalog(§8.5);PR 中出现硬编码 UI 文案按缺陷处理。

### 8.4 测试要求

- Core 全模块可单测;文件系统操作经协议抽象以便注入临时目录夹具。
- 必测清单:规则校验失败样例;路径展开与 glob 边界;删除闸门全部拒绝分支;dashed-absolute 解码(含中文路径、空格);guardFiles 判定;PID 复用防护(可注入时钟/进程信息)。
- UI 不强制自动化测试,以每里程碑人工验收替代。

### 8.5 多语言(i18n)规范(M0 起生效,不做补课式国际化)

**语言与范围**
- V1 支持 en(Base/源语言)与 zh-Hans。String Catalog 架构下,后续新增语言 = 翻译一份资源文件,零代码改动,天然适配社区贡献。
- 需本地化:全部 UI 文案、三级安全分级说明、错误与空状态、Onboarding、清理预览/结果页、APFS 提示文案。
- 明确不本地化:品牌名 Mothball、文件路径、规则与 target 的 id、审计日志 JSONL(机器可读,恒为英文,便于跨语言用户提 issue 时直接粘贴)、cli 调试输出、代码注释与提交信息。

**技术落法**
1. 全项目统一使用 String Catalog(.xcstrings):App target 建 `Localizable.xcstrings`;Core 包内的用户可见文案(错误信息、安全提示)单独建 catalog,`Package.swift` 声明 `defaultLocalization: "en"`,取串一律 `String(localized:bundle: .module)`。
2. 禁止在视图与逻辑中硬编码用户可见字符串:SwiftUI 场景由 LocalizedStringKey 自动抽取;其余位置用 `String(localized:comment:)` 且 comment 必填(给译者的上下文说明)。
3. 禁止字符串拼接组句,一律用插值占位,允许各语言重排语序;数量表达用 String Catalog 内建的复数变体。
4. 格式化全部走 locale 感知 API:字节数用 `ByteCountFormatStyle`,相对时间(如"3 个月前")用 `Date.RelativeFormatStyle`,数字与日期用 FormatStyle;名称排序用 `localizedStandardCompare`。
5. 规则库桥接:rules JSON 保持纯英文;UI 展示 `description`/`regenerateHint` 前,先查 catalog 中键 `rule.<ruleId>.<targetId>.description` / `rule.<ruleId>.<targetId>.hint`,未命中则回退 JSON 英文原文。种子规则的 zh-Hans 词条随 M1 交付。
6. CI:构建开启 `SWIFT_EMIT_LOC_STRINGS`;增加脚本报告 zh-Hans 中 stale / untranslated 词条(V1 仅报告不阻断,允许英文回退上线)。

**验收挂钩**:每个里程碑的验收隐含一条——系统语言切至简体中文后,该里程碑全部新增界面无英文残留(规则库回退文案除外)。

---

## 9. 已知风险与坑(实现时主动规避)

1. **GUI App 的 PATH 不含 Homebrew** → 所有外部二进制(docker、git)一律走固定候选路径解析,禁止依赖 `PATH`。
2. **APFS 本地快照** → 释放的空间可能延迟可见,必须按 §5.6 主动解释,否则被当骗子。
3. **iCloud dataless 文件** → sizing 时绝不触发下载(§5.2)。
4. **node_modules 海量小文件** → 只用批量枚举 API,按顶层并发;进度渐进呈现。
5. **规则漂移**(AI 工具月更)→ draft/verified 状态 + Doctor 面板 + 社区 PR 流程,这是产品机制而非一次性工作。
6. **PID 复用竞态** → (pid, 启动时间) 二元组校验。
7. **符号链接逃逸** → 扫描与删除均不跟随 symlink。
8. **TCC/FDA 未授权的"假坏"状态** → 降级横幅常驻(§5.8)。
9. **会话历史误删** → user_data 分级 + 只进废纸篓,双保险,不接受任何"提效"妥协。

---

## 10. 附录:交给 Claude Code 的开场指令(复制即用)

> 请先通读 SPEC.md。我们按 §7 里程碑推进,现在从 M0 开始。
> 规则:(1)任何 SPEC 未覆盖或与真机现实冲突的决策,先列出选项和你的建议,确认后再动手;(2)§4.3 安全分级与 §5.6 删除闸门是硬约束,不得为实现便利绕过;(3)每完成一个里程碑,更新 docs/PROGRESS.md,停下来等我验收;(4)所有标注"待真机核实"的路径,在 M1 的 Doctor 面板完成前不得标记为 verified。
> 现在开始 M0:先给出你计划创建的文件清单和 CI 配置要点,确认后再写代码。
