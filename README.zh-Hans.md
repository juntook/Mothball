[English](README.md) | **简体中文**

# Mothball

**把开发工具留下的磁盘空间收回来。**

Mothball 是一个 macOS 原生小工具,把散落在你电脑各处的开发资源——AI 编程工具的缓存与会话历史、项目构建产物、还在后台监听端口的开发服务、Docker 容器与镜像——按**项目**聚合起来,可视化地一键释放。

市面工具都是"资源类型视角"(只看 Docker、只看 node_modules);Mothball 是"项目视角":选中一个项目,看到它拖着的全部占用,一键收拾。

- **原生**:Swift 6 + SwiftUI,Apple Silicon(macOS 14+),不用 Electron。
- **安全优先**:三级安全分级——缓存可一键清理;会话历史只进废纸篓且逐项确认;凭证与配置只读展示,代码里根本不存在删除它们的路径。
- **本地开源**:Apache-2.0,数据不出本机,无账号体系,永不请求 sudo。
- **社区规则库**:每个工具把什么存在哪里、删了是否安全,都写在声明式 JSON 规则库(`rules/`)里,欢迎共同维护。

## 状态

预发布,活跃开发中。进展见 [docs/PROGRESS.md](docs/PROGRESS.md)。

## 安装

从 [Releases](https://github.com/juntook/Mothball/releases) 下载经过公证的 dmg,应用内通过 Sparkle 自动更新。

Homebrew cask 即将提供:

```sh
brew install --cask juntook/tap/mothball
```

不上 Mac App Store——核心功能(扫描任意工具目录、进程管理)与 App Sandbox 不兼容。

## 构建

```sh
swift build          # Core 库、`mothball` 调试 CLI、App 壳
swift test           # 单元测试
./scripts/validate-rules.sh   # 规则库校验
```

需要 Swift 6 工具链。`scripts/release.sh` 组装可分发的签名 App;CI 在 `v*` 标签上自动公证并发布 Release。

## 参与规则库

AI 工具的目录布局变化很快。规则带有 `status` 字段:`draft`(路径来自公开资料,未核实)/ `verified`(在真机上通过应用内 Doctor 面板核实)。新增工具或核实 draft 规则是最有价值的贡献,可从 `rules/BACKLOG.md` 开始。

## 许可证

Apache License 2.0——见 [LICENSE](LICENSE) 与 [NOTICE](NOTICE)。
