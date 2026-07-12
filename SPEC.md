# Mothball — V2 产品规格(SPEC)

> 阅读约定:
> 1. 按 §7 的里程碑顺序实现,每个里程碑独立可运行、可验收,不跨里程碑赶工。
> 2. 遇到本文未覆盖或与真机现实冲突的决策点:先列出选项与建议,经确认后再动手。
> 3. §4.3 安全分级和 §5.6 删除闸门是不可协商的硬约束,任何情况下不得为实现便利绕过。
> 4. 文中标注 `[待真机核实]` 的信息来自公开资料,实现时必须先在开发机上验证。
>
> 版本说明:V2(2026-07-12)取代 V1。V1 的 M1–M6 已交付(见 docs/PROGRESS.md);V2 扩展产品面(活动资源、开发会话、菜单栏、通知),重构 UI 信息架构,并引入展示层风险评级。§4.3、§5.1–§5.6、§5.8、§8.5、§9 各锚点语义与 V1 保持一致,代码内 `SPEC §x.y` 引用继续有效。

---

## 1. 产品定位

**产品名**:Mothball(取自 "mothball a project"——把闲置项目封存入库)。App 显示名 Mothball(各语言下不翻译);GitHub 仓库、Homebrew cask token、cli 二进制统一小写 `mothball`。官网 mothball.dev。

**一句话**:安全地发现并结束遗留的本地开发资源。(英文:Find and safely retire leftover development resources on your Mac.)

**产品形态**:面向开发者的原生 macOS 应用——一个**可解释、可预览、可恢复、面向项目上下文的开发资源控制台**,覆盖四类资源:

1. **运行时资源**:占用端口的进程、长时间未关闭的开发服务、容器运行时中的容器;
2. **磁盘资源**:项目内可再生产物(node_modules、.next、target…)、工具全局缓存(AI CLI、包管理器…)、Docker 存储;
3. **后台服务**(V2 后期):Homebrew Services 启动的数据库与中间件;
4. **开发会话**(V2 后期):一组相互关联的进程/端口/容器/服务,可整体预览并结束。

**明确不是什么**:不做"系统优化"或"垃圾清理";不做照片/下载目录清理、重复文件、病毒查杀、内存加速动画、浏览器清理、应用卸载。

**目标用户**:Apple Silicon Mac 上的前端/全栈/移动端/AI 开发者,重度使用 AI 编程工具(Claude Code、Codex、CodeBuddy 等)、Node/Python 工具链与 Docker,手里同时有多个项目。

**核心差异化**:市面工具都是"资源类型视角"(只看 Docker、只看 node_modules)。Mothball 是"项目视角"——每个资源都尽力回答:属于哪个项目、为什么占用、能不能安全处理、怎么恢复。归属识别引擎(§5.3)是全产品最核心的模块。

**产品原则**:默认安全(先预览、优雅停止、进废纸篓、危险数据默认保护);可解释(来源/归属/风险/恢复方式);原生轻量(SwiftUI,无 Electron,空闲不轮询);本地优先(所有分析在本机完成,不上传路径/进程/容器信息)。

---

## 2. 范围边界

### 2.1 In scope(V2)

| # | 模块 | 一句话 | 里程碑 |
|---|------|--------|--------|
| A | 规则引擎与规则库 | 声明式 JSON 规则,描述各工具的缓存/历史/配置位置与安全级 | 已交付 |
| B | 磁盘扫描器 | 按规则扫描全局目标 + 项目内构建产物,计算占用 | 已交付 |
| C | 项目发现与归属识别 | 找到用户的项目,把每个资源映射到项目 | 已交付 |
| D | 运行时探测 | 监听端口的进程、cwd、内存;优雅停止 | 已交付 |
| E | 容器资源 | 多运行时端点发现;容器/镜像/卷/构建缓存的列表与清理 | 已交付 |
| F | 清理执行器与安全机制 | 预览、废纸篓、审计日志、删除闸门 | 已交付 |
| G | V2 UI 信息架构 | 概览 / 活动资源 / 磁盘空间 / 设置 的原生界面(§5.7) | M7 |
| H | 端口视角与进程指标 | 端口表、CPU/内存采样、进程树 | M8 |
| I | 风险展示层 | S0–S3 评分,叠加在安全分级之上(§4.4) | M8 |
| J | Homebrew 服务 | brew services 列表/停止/禁用自启 | M9 |
| K | 保护规则中心 | 路径/进程名/端口等维度的保护与忽略(§5.12) | M9 |
| L | 开发会话 | 会话识别、影响预览、编排结束、模板(§5.13) | M10 |
| M | 菜单栏 | MenuBarExtra 摘要与快捷操作(§5.14) | M10 |
| N | 通知与定时扫描 | 阈值提醒、定时只扫不删(§5.15) | M11 |
| O | 历史记录视图 | 审计日志 UI、诊断导出(§5.16) | M11 |

### 2.2 Out of scope(V2 明确不做,防 scope creep)

- Windows / Linux / Intel Mac / WSL(架构上不为其妥协,规则库 schema 保留 platform 字段即可)
- **特权操作**:永不 sudo、永不安装特权 helper(§3)。终止他人/系统进程、系统级目录清理一律不做,权限不足时给出明确错误与"在活动监视器中查看"引导
- 工具官方清理命令的**代执行**(`npm cache clean` 等):UI 只提供"复制命令";实际清理一律走删除闸门 + 废纸篓(§5.6)
- 匿名使用统计/遥测(与零第三方依赖及隐私原则冲突,暂缓)
- 项目归档(打包成 tar 移走)
- 任何付费/授权/账号体系
- 系统级清理(浏览器缓存、系统日志、重复文件——不做 CleanMyMac)、应用卸载(不做 AppCleaner)
- Podman machine 的深度管理(仅检测并提示)
- 嵌套 monorepo 的子项目粒度归属(以最外层项目根为准)
- Kubernetes 本地资源、规则插件市场、Raycast/Shortcuts 扩展(V3 候选)

---

## 3. 平台与技术约束

- **平台**:macOS 14.0+,仅 arm64(Apple Silicon)。不做 Intel 切片。
- **语言/框架**:Swift(Swift 6 toolchain,开启 strict concurrency),SwiftUI。禁止引入 Electron/Tauri/webview。
- **视觉基调**:系统原生控件 + SF Symbols + 系统材质;不自绘仪表盘、不引入自定义设计系统。在新系统上由系统控件自动获得当代外观(Liquid Glass 等),在 macOS 14/15 上优雅降级;**不为特定系统版本写分叉的自定义视觉代码**。
- **架构分层**:
  - `Core`(SwiftPM 包):规则引擎、扫描器、归属识别、运行时探测、Docker 客户端、清理执行器。零 UI 依赖,全部可单元测试,不持有偏好设置(由 App 传入)。
  - `App`(SwiftUI target):纯展示层,只调用 Core 的公开接口。
  - `cli`(调试 target):把 Core 能力暴露成命令行,便于开发期验证。
- **权限模型**:全程以当前登录用户身份运行。**永不请求 sudo,永不安装特权 helper**。做不到的事(如管理其他用户的进程)直接不做,失败时给出可执行的下一步(如打开活动监视器)。
- **沙盒**:App 不开启 App Sandbox(核心功能与沙盒不兼容),因此不上 Mac App Store;分发走 Developer ID 签名 + 公证。
- **UI 语言**:en(Base)+ zh-Hans,执行 §8.5 的 i18n 规范;支持应用内覆盖系统语言并即时生效;README 双语。
- **依赖策略**:优先零第三方依赖。允许引入:Sparkle(更新)。其余需先论证。本地索引暂用 UserDefaults + JSONL(审计日志);若 M10/M11 的会话模板与历史查询需要结构化存储,优先评估 SwiftData(系统框架),不引入第三方数据库。

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

—— V2 新增 ——
PortEntry     一个监听端口条目(端口 + 协议 + 进程 + 归属,§5.9,M8)
BrewService   一个 Homebrew 服务(名称/状态/端口/数据目录,§5.11,M9)
DevSession    一个开发会话(项目 + 进程/端口/容器/服务集合,§5.13,M10)
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

### 4.4 风险展示层 S0–S3(展示层,M8 起)

安全分级(§4.3)是**执行层**,驱动删除闸门,永不弱化。S0–S3 是叠加其上的**展示层**评分,由 RiskEngine 结合上下文信号计算,只影响排序、角标与默认勾选的收紧(只收紧、不放宽):

| 评级 | 名称 | 判定(示例) | UI |
|------|------|------------|-----|
| S0 | 安全 | regenerable 且无活跃信号(近 30 天未用、无运行中进程占用、Git 干净) | 绿色角标,默认勾选 |
| S1 | 低风险 | regenerable 但有活跃信号(近期使用过、重建成本较高) | 黄色角标,默认勾选可配置 |
| S2 | 谨慎 | regenerable 但正被使用(运行中进程 cwd 命中、容器 bind mount、Git 有未提交变更) | 橙色角标,**默认不勾选** |
| S3 | 高风险 | 一切 user_data 与 protected | 红/灰角标,遵循 §4.3 行为 |

映射规则:`user_data`/`protected` 恒为 S3;`regenerable` 依信号落在 S0–S2。信号计算全部本地、可解释(评级角标悬停显示原因)。

---

## 5. 模块规格

### 5.1 规则引擎与规则库

- 规则为 JSON 文件,存放于仓库 `rules/tools/*.json`,每工具一个文件;`rules/schema/rule.schema.json` 提供 JSON Schema(draft-07),CI 强制校验全部规则通过 schema + 语义检查(id 唯一、路径合法、safety 枚举合法)。
- 规则文件随 App 打包为资源;同时支持从 `~/Library/Application Support/Mothball/rules/` 加载用户本地追加规则(同 id 时本地覆盖内置)。
- 路径支持 `~` 展开与 glob(仅 `*`,不支持 `**` 与 `..`)。
- 每条规则有 `status` 字段:`draft`(路径来自公开资料,未核实)/ `verified`(在真机核实过)+ `verifiedOn` 日期。UI 对 draft 规则的结果打"未验证"角标,清理前额外提示。
- **Doctor 诊断面板**(设置 → 高级):逐条列出每个 target 在本机的存在性、实际大小、权限可读性;这是把规则从 draft 升级为 verified 的工作台,也是社区贡献规则的验证工具。
- 规则的 `description`/`regenerateHint` 用英文书写(社区资产单一语言);UI 展示时按 §8.5 第 5 条做键映射本地化,未命中回退英文原文。

### 5.2 磁盘扫描器

- 手动触发(工具栏"扫描"按钮 + 首次启动引导后自动跑一次)。后台增量索引与定时扫描见 §5.15(M11,只扫不删)。
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
| 4 | 规则声明的路径编码:target 标注 `attribution.encoding = "dashed-absolute"` 时,子目录名如 `-Users-me-dev-shop` 解码为 `/Users/me/dev/shop` 再匹配项目根 | 工具的按项目分桶数据 | 高 |
| 5 | 容器 bind mount 的宿主机源路径落在某项目根内 | 容器 | 中 |

- 归属结果附带证据类型,UI 悬停可见("通过 compose 标签归属")。
- 解码/匹配必须做路径规范化(realpath、大小写按 APFS 默认不敏感处理)。

### 5.4 运行时探测

- **发现链路**(全部走 libproc 用户态 API,无需特权):
  `proc_listpids` 列本用户进程 → `proc_pidfdinfo` 找处于 LISTEN 状态的 TCP socket 及端口 → `proc_pidpath` 取可执行路径 → `proc_pidvnodepathinfo` 取 cwd → `proc_pid_rusage` 取内存/启动时间。
- **展示范围**:仅当前用户的进程,且满足其一:监听 TCP 端口;或 cwd 归属到某已发现项目。系统守护即使同 uid 也按内置排除名单过滤(名单放规则库 `rules/system-exclusions.json` 便于社区补充)。
- **列表字段**:端口、进程名、PID、cwd、归属项目、内存、已运行时长;M8 起补充 CPU 占用采样与进程树(§5.10)。
- **停止流程**:先展示影响说明 → 发送 SIGTERM → 轮询 5 秒 → 仍存活则弹窗提供"强制结束"(SIGKILL,需确认)。SIGKILL 永不自动发送。
- **PID 复用防护**:发信号前重新校验(pid, 启动时间)二元组一致,否则中止并刷新列表。

### 5.5 容器资源

- **端点发现**(按序,全部记录到诊断信息):
  1. `docker context ls / inspect` 取 current context 的 endpoint;
  2. 探测常见 socket:`~/.docker/run/docker.sock`(Docker Desktop)、`~/.orbstack/run/docker.sock`(OrbStack)、`~/.colima/default/docker.sock`(Colima)、`/var/run/docker.sock`;
  3. 环境变量 `DOCKER_HOST`。
  Podman:仅检测存在并在 UI 提示"暂不支持管理",不报错。
- **执行方式**:shell-out 到 `docker` CLI(`--format json` / `system df --format json`),不实现 UDS HTTP 客户端(记为后续优化)。**注意 GUI App 的 PATH 不含 Homebrew 路径**:必须在固定候选列表中解析二进制(`/opt/homebrew/bin/docker`、`/usr/local/bin/docker`、`~/.orbstack/bin/docker`、`/Applications/Docker.app/Contents/Resources/bin/docker`),找不到则空状态引导。
- **资源与操作矩阵**:

| 资源 | 展示 | 操作 | 安全级 |
|------|------|------|--------|
| 运行中容器 | 名称、镜像、端口映射、compose 项目、启动时长 | 停止 | regenerable 级确认 |
| 已停止容器 | 同上 + 停止时间 | 删除(`rm`) | regenerable |
| 悬空镜像(dangling) | 大小、创建时间 | 删除 | regenerable,可一键 |
| 有 tag 且无容器引用的镜像 | tag、大小 | 删除 | user_data 级逐项确认(重新 pull/build 有成本) |
| 卷(volume) | 名称、compose 项目、是否被引用 | 单个删除 | **protected 展示 + 强确认单删**,永不进批量 |
| 构建缓存 | 总大小 | `builder prune` | regenerable |

- compose 项目按 label 聚合,并通过 §5.3 证据 3 归属到本地项目;M10 起 compose 项目可作为整体加入开发会话统一停止。
- Docker 守护未运行:空状态卡片说明原因与启动方式,不弹错误。
- **空间统计**:以 `system df` 的 reclaimable 口径为准,避免把共享层大小重复累加。

### 5.6 清理执行器与安全机制

**流程**:勾选(批量操作栏常驻显示"已选择 N 项 · 预计释放 X GB")→ 点"查看影响/处理" → 预览确认页(sheet,逐项列出:路径、大小、安全级、恢复提示;user_data 项高亮并要求单独勾选确认;protected 项永不出现)→ 执行(进度)→ 结果页(共释放 X GB + 操作明细;部分失败时逐项给出原因与下一步)。

**删除闸门(执行器内的最后一道硬校验,独立于 UI 逻辑,违反任何一条即拒绝该项并记录)**:
1. 只接受来自本次预览清单的不可变路径集合,UI 与执行器之间不传"规则",只传"已确认的具体路径"。
2. 路径 realpath 规范化后,必须以某条**已启用规则展开出的前缀**开头。
3. 硬拒绝:`/`、用户家目录本身、任何包含 `..` 的路径、长度 < 8 的路径、位于 `/System` `/Library`(系统级)之下的路径。
4. 删除操作不跟随符号链接。
5. `user_data` 只允许 `FileManager.trashItem`(进废纸篓);废纸篓失败(跨卷等)时**中止并询问**,不静默转直删。
6. `regenerable` 默认进废纸篓;"直接删除"是全局设置项,开启时每次会话首个直删操作需二次确认。

**官方清理命令**:对存在官方清理命令的工具缓存(如 npm/pnpm/brew),详情页展示命令并提供"复制命令";**不代执行**——代执行会绕过闸门的路径校验,收益不抵风险。

**审计日志**:每次操作追加 JSONL 到 `~/Library/Logs/Mothball/operations.jsonl`,字段:时间、规则 id、target id、路径、字节数、方式(trash/delete/stop/docker-*)、结果。设置页提供"打开日志"入口;M11 提供应用内历史视图(§5.16)。

**忽略列表**:任何条目可"忽略"(路径级),忽略项持久化,扫描仍统计但默认折叠且不可勾选。M9 扩展为保护规则中心(§5.12)。

**APFS 快照提示**:清理结果页固定附带说明文案——"macOS 本地快照可能暂时保留已删除数据,Finder 显示的可用空间会在快照过期后(通常 24 小时内)更新"。这是该品类差评的头号来源,必须主动解释。

### 5.7 UI 信息架构(V2)

`NavigationSplitView`,侧边栏分组导航;各区随里程碑逐步出现(未实现的区**不显示**,不做"敬请期待"占位):

| 侧栏项 | 快捷键 | 内容 | 里程碑 |
|--------|--------|------|--------|
| 概览 | ⌘1 | 问候语 + 指标卡(运行中资源/活动端口/开发内存占用/可释放空间)+ "需要关注"列表 + 当前会话卡(M10 起) | M7 |
| 活动资源 | ⌘2 | 标签页:进程 / 容器(M7);端口(M8);后台服务(M9) | M7 起 |
| 磁盘空间 | ⌘3 | 标签页:项目产物 / 工具缓存 / Docker 存储 | M7 |
| 开发会话 | ⌘4 | 当前会话 / 模板 | M10 |
| 历史记录 | ⌘5 | 操作历史 / 失败记录 / 诊断导出 | M11 |
| 设置 | ⌘, | §5.8 之外的全部偏好(独立 Settings 场景亦可达) | M7 |

- **侧栏底部**固定:上次扫描时间、累计已释放空间、版本号、帮助与反馈入口。
- **工具栏**:扫描按钮(⌘R)+ 搜索框(⌘K;M7 为当前页面内过滤,跨页全局搜索随 M11)。
- **概览"需要关注"**按优先级混排:扫描失败/权限不足 > 高资源占用(M8 起)> 长时间运行(M8 起)> 大体积可回收 > 长期未用项目产物。每条给出"查看"跳转。
- **详情呈现**:列表行 → 右侧 inspector 或 sheet(端口/进程详情用 inspector,项目清理详情用 sheet);危险确认一律 sheet + 明确的角色按钮。
- **批量操作栏**:列表有选中项时吸底显示"已选择 N 项 · 预计释放 X GB [取消] [查看影响] [处理]"。
- **设计基调**:见 §3 视觉基调。大小数字用等宽数字字体,排序默认按占用降序;风险/安全角标用系统语义色。
- **空状态**:每个页面都有明确空态(无资源/未授权/运行时不可用),给出下一步动作;错误绝不静默。

### 5.8 Onboarding 与权限

两页式首启引导(sheet):

1. **欢迎页**:产品一句话 + 四条能力(发现端口进程/停止容器服务/清理可再生缓存/全部本地分析)+ "默认只读扫描 · 不上传任何数据"脚注 + [开始使用]。
2. **权限与隐私页**:逐项列出——进程与端口检测(无需授权,已可用)/ 项目目录(选择代码根目录,可稍后)/ 完全磁盘访问(可选,说明只用于扫描所选开发目录)/ 登录时启动菜单栏(M10 起显示,默认关)。[稍后设置] 与 [继续]。
3. **FDA 探测**:以能否读取受 TCC 保护的标志路径为探针;未授权时进入**降级模式**——正常运行,但扫描结果顶部持续显示"结果不完整:未授予完全磁盘访问"横幅,绝不呈现"看起来正常但数据莫名偏少"的假坏状态。
4. 引导结束自动开始首次扫描,渐进出结果。

### 5.9 端口扫描(M8)

- 在 §5.4 发现链路之上提供**端口视角**:每行一个监听端口(端口、协议 TCP/UDP、IPv4/6、进程、PID、归属项目、运行时长、内存),支持"仅开发端口"过滤(常用开发端口范围可在设置-高级配置)。
- 端口详情(inspector):进程命令行、父进程、子进程数、启动时间、停止后影响说明(可重启方式)+ [在终端打开] [保护] [停止]。
- 端口被系统/他人进程占用时:展示但不可操作,给出活动监视器引导。

### 5.10 进程指标与进程树(M8)

- CPU 占用:两次 `proc_pid_rusage` 采样差分,采样仅在活动资源页可见时进行,空闲不轮询(§3)。
- 进程树:按 ppid 聚合展示,可整树停止(逐个 SIGTERM,顺序子先父后)。
- 电量影响:V2 仅以"长时间高 CPU"信号呈现,不做能耗建模。

### 5.11 Homebrew 服务(M9)

- 通过 `brew services list --json` 读取(固定候选路径解析 brew 二进制,同 §5.5 PATH 约束);展示:服务名、状态、版本、端口(尽力探测)、数据目录、是否登录自启。
- 操作:停止一次 / 停止并禁用自启 / 重新启动 / 在 Finder 显示配置。数据目录本身按 `protected` 处理(只展示占用,永不删除)。
- brew 未安装:该标签页空态说明,不报错。

### 5.12 保护规则中心(M9)

- 忽略列表(§5.6)升级为统一的保护规则:精确路径 / 路径前缀 / 进程名 / 端口 / Docker 卷名。
- 被保护对象:不进任何批量操作、默认不勾选、列表带锁形角标;保护优先级:用户保护 > 内置高风险规则 > 自动推荐。
- 存储沿用 `~/Library/Application Support/Mothball/`(JSON),schema 版本化以便迁移。

### 5.13 开发会话(M10)

- **定义**:一组相互关联的资源——项目目录、进程树、端口、compose 项目、Homebrew 服务。
- **识别**:同项目归属(§5.3)自动聚合;用户可手动增删资源、命名、存为模板、标记保留项。
- **结束流程**:影响预览(逐类列出,受保护项默认排除并说明)→ 逐步执行(先进程 SIGTERM,再容器 stop,再按设置停服务)→ 结果总结(成功/失败/跳过,失败项可单独重试)。可选附带"清理该项目临时构建缓存"(走 §5.6 闸门)。
- 概览页出现"当前会话"卡片;菜单栏提供"结束开发会话"入口。

### 5.14 菜单栏(M10)

- `MenuBarExtra`(用户可选开启):摘要(活动端口数/运行资源数/可释放空间)+ 当前会话与结束入口 + 查找端口/扫描/打开主窗口 + 暂停提醒。
- 图标状态:常规 / 有高占用(小圆点)/ 扫描中(轻量进度)。不使用持续动画;空闲内存目标 < 80 MB。

### 5.15 通知与定时扫描(M11)

- 通知类型:服务运行超时长阈值、进程持续高 CPU、可释放空间超阈值、扫描失败/权限失效。全部可独立关闭,默认保守(存储提醒每周至多一次)。
- 定时扫描:手动 / 每天 / 每周 / 登录后。**自动扫描只生成报告,绝不自动删除。**
- 通知提供"今天不再提醒"与"保护此资源"快捷动作。

### 5.16 历史记录视图(M11)

- 数据源即审计日志(§5.6 JSONL),按天分组展示:时间、操作、对象、大小、结果;失败项给出原因与重试/引导。
- 文件操作提供"打开废纸篓";停止的服务提供"重新启动"提示;不尝试自行恢复容器/卷。
- 诊断导出:打包审计日志 + 规则清单 + 环境诊断(脱敏路径)为 zip。
- 保留策略:默认 90 天,可配置。

---

## 6. 种子规则库

### 6.1 Schema 与存放

规则 schema 由 `rules/schema/rule.schema.json`(draft-07)定义并经 CI 强制校验;字段结构见 schema 本身与 §5.1。`rules/` 目录保持零代码依赖、自包含(schema + 数据 + 文档),未来可原样拆为独立仓库。

### 6.2 已收录规则(`rules/tools/*.json`)

`claude-code`、`codex`、`codebuddy-cli`、`workbuddy`、`npm`、`node-modules`。安全分级要点:AI CLI 的会话历史/todo 一律 `user_data`,凭证与配置 `protected`,缓存/日志 `regenerable`(§4.3)。

### 6.3 收录 backlog(`rules/BACKLOG.md`,按预期收益排序)

1. Hugging Face 模型缓存 `~/.cache/huggingface`(动辄几十 GB,收益最高)
2. Playwright 浏览器 `~/Library/Caches/ms-playwright`
3. Xcode DerivedData 与旧模拟器运行时(M9 前后随"Xcode 存储"标签页评估)
4. pip / uv / cargo registry / Go build cache / Gradle / Maven
5. pnpm store、yarn cache、Bun、Corepack、npx 临时包
6. 前端框架产物:`.next` `.nuxt` `.svelte-kit` `.vite` `.turbo` `dist` `build` `coverage`(扩充 node-modules 同族规则)
7. Python 项目产物:`.venv` `__pycache__` `.pytest_cache` `.mypy_cache` `.ruff_cache`
8. Gemini CLI(`~/.gemini`)、Cursor、VS Code 的 Cache/CachedData/workspaceStorage
9. Ollama 模型目录(仅展示,不默认清理)
10. Homebrew 下载缓存、CocoaPods、JetBrains caches
11. Docker Desktop 应用自身的缓存目录(区别于引擎内资源)

---

## 7. 里程碑与验收标准

每个里程碑独立可运行、可验收;完成后更新 `docs/PROGRESS.md` 并停下等人工验收。M1–M6(V1)已交付,验收记录见 docs/PROGRESS.md。

**M7 — V2 信息架构与新壳**
交付:§5.7 的侧栏骨架(概览/活动资源/磁盘空间/设置 + ⌘1-3/⌘R/⌘K)、概览页(四指标卡 + 需要关注)、磁盘空间页(项目产物/工具缓存/Docker 存储三标签 + 批量操作栏 + 项目清理详情 sheet)、活动资源页(进程/容器两标签,详情 inspector)、设置页(常规/扫描范围/语言与地区/隐私/高级 五组,Doctor 迁入高级)、两页式 Onboarding(§5.8)、应用内语言即时切换、SPEC/CLAUDE.md 同步更新。
验收:全部既有能力(扫描/清理/停止进程/容器操作/Doctor/忽略/FDA 降级/更新检查)在新 IA 下可达且行为不回退;`swift test` 绿;系统语言 zh-Hans 与应用内切换 en/zh 均无英文残留(规则库回退除外);闸门与安全分级行为与 V1 完全一致。

**M8 — 端口视角 + 进程指标 + 风险展示层**
交付:§5.9 端口标签页与详情、§5.10 CPU 采样与进程树、§4.4 RiskEngine 及全列表角标、"仅开发端口"过滤、概览"需要关注"接入高占用/长运行信号。
验收:手工起 `vite` 与 `python -m http.server`,端口表正确显示归属与指标;CPU 采样在页面不可见时停止;S0–S3 角标原因可解释;user_data 永不因评分变为默认勾选。

**M9 — Homebrew 服务 + 保护规则中心**
交付:§5.11 后台服务标签页与三种停止语义、§5.12 保护规则中心(路径前缀/进程名/端口/卷名)、Xcode 存储规则评估结论(进 backlog 或立项)。
验收:brew 启动的 postgres 可被列出、停止、禁用自启;无 brew 机器空态正确;保护规则命中的对象在全部批量路径中被跳过(单测覆盖)。

**M10 — 开发会话 + 菜单栏**
交付:§5.13 会话识别/预览/编排结束/模板、§5.14 MenuBarExtra、概览当前会话卡。
验收:compose + 前端 dev server 的混合会话可一键结束且顺序正确;受保护项被跳过并在结果中说明;部分失败可单独重试;菜单栏空闲内存 < 80 MB。

**M11 — 通知/定时扫描 + 历史视图**
交付:§5.15 通知与定时扫描(只扫不删)、§5.16 历史记录页与诊断导出、跨页全局搜索(⌘K)。
验收:阈值通知可独立开关且不重复轰炸;定时扫描从不执行删除(代码路径断言 + 单测);历史页与 JSONL 一致;诊断包不含敏感明文路径(脱敏抽查)。

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
├── scripts/                  # notarize.sh, release.sh, validate-rules.sh, gen-localizations.py
├── .github/workflows/ci.yml
├── LICENSE                   # Apache-2.0 全文
├── NOTICE                    # 项目名 + copyright 行
├── CLAUDE.md                 # 工程约束摘要(§8.3)
├── README.md                 # 英文为主 + 简中段落
└── SPEC.md                   # 本文档
```

### 8.2 协议

- Apache License 2.0:根目录放 LICENSE 全文与 NOTICE;新源文件顶部加 SPDX 标识 `// SPDX-License-Identifier: Apache-2.0`(轻量,不贴全款头)。
- 第三方依赖(Sparkle 等)在 NOTICE/致谢中列明其协议。

### 8.3 工程约束文档(CLAUDE.md)

仓库根维护一份工程约束摘要,内容与本 SPEC 同步:平台约束(§3)、§4.3 与 §5.6 硬约束、测试先行要求、提交规范、规则校验、i18n 纪律。SPEC 与 CLAUDE.md 冲突时以 SPEC 为准并立即修正。

### 8.4 测试要求

- Core 全模块可单测;文件系统操作经协议抽象以便注入临时目录夹具。
- 必测清单:规则校验失败样例;路径展开与 glob 边界;删除闸门全部拒绝分支(含 `/`、`..`、symlink、越界前缀);dashed-absolute 解码(含中文路径、空格);guardFiles 判定;PID 复用防护;M8 起新增 RiskEngine 映射(user_data 恒 S3、评分只收紧不放宽)与保护规则命中逻辑。
- UI 不强制自动化测试,以每里程碑人工验收替代。

### 8.5 多语言(i18n)规范

**语言与范围**
- 支持 en(Base/源语言)与 zh-Hans。String Catalog 架构下,后续新增语言 = 翻译一份资源文件,零代码改动,天然适配社区贡献。
- 需本地化:全部 UI 文案、安全分级与风险评级说明、错误与空状态、Onboarding、清理预览/结果页、APFS 提示文案、通知文案。
- 明确不本地化:品牌名 Mothball、文件路径、规则与 target 的 id、审计日志 JSONL(机器可读,恒为英文,便于跨语言用户提 issue 时直接粘贴)、cli 调试输出、代码注释与提交信息。

**技术落法**
1. 全项目统一使用 String Catalog(.xcstrings)作为源:App target `App/Localizable.xcstrings`,Core 包 `Sources/Core/Localizable.xcstrings`;构建机无完整 Xcode 时,由 `scripts/gen-localizations.py` 生成并签入 `.lproj/Localizable.strings`,CI 校验二者同步。
2. 禁止在视图与逻辑中硬编码用户可见字符串;非 SwiftUI 场景用 `String(localized:comment:)` 且 comment 必填。
3. 禁止字符串拼接组句,一律用插值占位,允许各语言重排语序。
4. 格式化全部走 locale 感知 API:字节数用 `ByteCountFormatStyle`,相对时间用 `Date.RelativeFormatStyle`,数字与日期用 FormatStyle;名称排序用 `localizedStandardCompare`。
5. 规则库桥接:rules JSON 保持纯英文;UI 展示 `description`/`regenerateHint` 前,先查 catalog 中键 `rule.<ruleId>.<targetId>.description` / `rule.<ruleId>.<targetId>.hint`,未命中则回退 JSON 英文原文。
6. **应用内语言覆盖**:设置提供 跟随系统 / 简体中文 / English;切换即时生效(通过语言子 bundle 解析字符串 + 注入 `\.locale` 环境,不要求重启);未设置时跟随系统首选语言。
7. CI:脚本报告 zh-Hans 中 stale / untranslated 词条(报告不阻断,允许英文回退上线)。

**验收挂钩**:每个里程碑的验收隐含一条——系统语言为简体中文、以及应用内切换语言后,该里程碑全部新增界面无英文残留(规则库回退文案除外)。

---

## 9. 已知风险与坑(实现时主动规避)

1. **GUI App 的 PATH 不含 Homebrew** → 所有外部二进制(docker、git、brew)一律走固定候选路径解析,禁止依赖 `PATH`。
2. **APFS 本地快照** → 释放的空间可能延迟可见,必须按 §5.6 主动解释,否则被当骗子。
3. **iCloud dataless 文件** → sizing 时绝不触发下载(§5.2)。
4. **node_modules 海量小文件** → 只用批量枚举 API,按顶层并发;进度渐进呈现。
5. **规则漂移**(AI 工具月更)→ draft/verified 状态 + Doctor 面板 + 社区 PR 流程,这是产品机制而非一次性工作。
6. **PID 复用竞态** → (pid, 启动时间) 二元组校验。
7. **符号链接逃逸** → 扫描与删除均不跟随 symlink。
8. **TCC/FDA 未授权的"假坏"状态** → 降级横幅常驻(§5.8)。
9. **会话历史误删** → user_data 分级 + 只进废纸篓,双保险,不接受任何"提效"妥协。
10. **Docker 空间重复统计** → 共享层不可直接累加,以 `system df` reclaimable 口径为准(§5.5)。
11. **CPU 采样变常驻轮询** → 指标采样必须绑定页面可见性,空闲零轮询(§5.10、§3)。
12. **语言即时切换的字符串缓存** → 语言覆盖走显式子 bundle 解析,禁止依赖进程级 `AppleLanguages` 热切换(不可靠)。
