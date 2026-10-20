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

## 原理

git 遇到 `anon::<别名>` 形式的地址时，会调用 `git-remote-anon` 这个程序处理。它在 `~/.config/git-anon/map`（权限 `600`）里查出真实地址，再交给 git 自己的传输层（HTTPS / SSH / 本地路径）完成连接。

因此 `.git/config`、`git remote -v`、`git remote get-url` 里只有别名，看不到域名、组织名和仓库名。SSH key、`~/.ssh/config`、凭据管理器都照常工作。

## 安装

```sh
curl -fsSL https://raw.githubusercontent.com/scott-leung/git-anon/main/install.sh | sh
```

或在源码目录执行 `make install`。默认装到 `~/.local/bin`（可用 `BINDIR=…` 修改），该目录需要在 `PATH` 中。卸载：`sh install.sh --uninstall`。

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

`make test` 运行离线端到端测试，`make lint` 运行 shellcheck。CI 覆盖 Ubuntu（dash）、macOS 和 Alpine（busybox ash）。推送与 `bin/git-anon` 中 `VERSION` 一致的 `vX.Y.Z` 标签会自动发布 Release。
