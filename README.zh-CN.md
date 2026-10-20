# git-anon

[English](README.md)

把 git 远程仓库的真实地址藏起来，不让读取它的工具（AI 编码助手、IDE 插件、遥测上报等）拿到，同时日常使用 git 的方式完全不变。

```console
$ git anon init
remote.origin.url -> anon::r3f9a1c07

$ git remote -v
origin  anon::r3f9a1c07 (fetch)
origin  anon::r3f9a1c07 (push)

$ git pull && git push        # 和以前一样
```

## 背景

Claude Code、Codex 这类闭源 AI 编码 Agent 会读取仓库的 git 信息（分支、最近的提交、remote 地址）来构建上下文，也可能把 remote 地址随遥测数据一起上报，而有些版本没有提供关闭的开关。remote 地址是本机上最能暴露身份的信息之一：从中能看出你公司的 git 服务器、所在组织，以及你参与的每一个私有项目。

git-anon 让任何工具读到的 remote 地址都只是一个看不出含义的别名，git 本身仍然连接真实服务器，日常使用方式完全不变。

## 方案对比

选定当前方案之前，评估过这几种做法：

| 方案 | 隐藏域名 | 隐藏组织/仓库名 | git 在任何地方都正常 | 不管工具怎么读都有效¹ | 配置成本 |
|---|:-:|:-:|:-:|:-:|---|
| 改 `/etc/hosts` | ✗ | ✗ | ✓ | ✗ | — |
| `url.<真实>.insteadOf=<假>` | ✗² | ✗² | ✓ | ✗ | 每个域名一次 |
| `~/.ssh/config` 里配 Host 别名 | ✓ | ✗ | ✓ | ✓ | 每个域名一次 |
| 只给 Agent 进程用 `GIT_CONFIG_*` 环境变量注入假地址 | ✓ | ✓ | ✗³ | ✗ | 一次 |
| **remote helper（git-anon）** | **✓** | **✓** | **✓** | **✓** | **每个仓库一条命令** |

¹ 工具可能执行 `git remote get-url`、`git config`，也可能直接解析 `.git/config`。  
² `.git/config` 里存的是假地址，但 `git remote -v` / `get-url` 会显示改写后的真实地址。  
³ Agent 里发起的 fetch/push 会连到假地址，导致失败。

为什么改 hosts 没用：hosts 只决定域名解析到哪个 IP，而工具上报的是 git 配置里的 URL **字符串**，这个字符串并没有变。

git-anon 用的是 git 自带的扩展机制 remote helper：仓库里存的 URL 是 `anon::<随机别名>`，真实地址只存在本地文件 `~/.config/git-anon/map`（权限 `600`）里。不管工具用哪种方式读取 remote，拿到的都是别名；git 需要联网时，helper 再把别名解析成真实地址，用你原有的 SSH key 或凭据连接。默认别名是随机生成的，连仓库名都不会泄露。

## 原理

git 遇到 `anon::<别名>` 形式的地址时，会调用 `git-remote-anon` 这个程序处理。它在 `~/.config/git-anon/map`（权限 `600`）里查出真实地址，HTTPS 交给 git 自带的 helper，SSH 和本地路径直接调用 `ssh` / `git upload-pack`（支持 `GIT_SSH_COMMAND`、`core.sshCommand`）。

因此 `.git/config`、`git remote -v`、`git remote get-url` 里只有别名，看不到域名、组织名和仓库名。SSH key、`~/.ssh/config`、凭据管理器都照常工作。

## 安装

```sh
npm install -g git-anon
```

不用 Node.js 的话：

```sh
curl -fsSL https://raw.githubusercontent.com/scott-leung/git-anon/main/install.sh | sh
```

或在源码目录执行 `make install`。默认装到 `~/.local/bin`（可用 `BINDIR=…` 修改），该目录需要在 `PATH` 中。卸载：`npm uninstall -g git-anon` 或 `sh install.sh --uninstall`。

## 使用

```sh
cd 你的仓库
git anon init       # 一条命令匿名化当前仓库的所有 remote
git anon status     # 查看状态
git anon off        # 恢复真实地址
```

- `git anon init [--alias 名字]`：默认生成随机别名（`r` + 8 位十六进制），不会从仓库名推导，避免泄露；`origin` 用该别名，其它 remote 用 `名字-<remote>`。可重复执行。
- `git anon add <别名> [remote]` / `git anon restore [remote]`：单个 remote 的匿名化与恢复。
- `git anon list`：列出别名（不显示地址）；`git anon show <别名>`：显示真实地址。
- `git anon clone <别名> [目录]`：通过别名克隆。换电脑时把 map 文件拷过去即可。

## 局限

- 只隐藏**远程地址**。分支名、commit 信息、文件路径和内容仍然可以被读取仓库的工具看到。
- git 运行期间，本机进程仍可通过 `ps`、`GIT_TRACE=1` 看到真实地址。
- `gh`、IDE 的"在 GitHub 上打开"等依赖 remote 识别托管平台的功能会失效，可临时 `git anon off` 或用 `gh -R owner/repo`。
- 子模块需要执行 `git config --global protocol.anon.allow always`。

## 开发

`make test` 运行离线端到端测试，`make lint` 运行 shellcheck。CI 覆盖 Ubuntu（dash）、macOS 和 Alpine（busybox ash）。CI 还会在 Ubuntu 和 macOS 上安装 npm 包做冒烟测试。

发版：同时修改 `bin/git-anon` 的 `VERSION` 和 `package.json` 的 `version`，推送 `vX.Y.Z` 标签。Release 工作流会校验版本、跑测试、创建 GitHub Release 并发布到 npm（带 provenance，使用 npm trusted publishing 或仓库 secret `NPM_TOKEN`）。
