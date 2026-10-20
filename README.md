# git-anon

[![CI](https://github.com/scott-leung/git-anon/actions/workflows/ci.yml/badge.svg)](https://github.com/scott-leung/git-anon/actions/workflows/ci.yml)
[![npm](https://img.shields.io/npm/v/git-anon)](https://www.npmjs.com/package/git-anon)

[中文说明](README.zh-CN.md)

Hide the real URLs of your git remotes from tools that read them — AI coding
agents, IDE plugins, telemetry — without changing how you use git.

```console
$ git anon init
remote.origin.url -> anon::r3f9a1c07

$ git remote -v
origin  anon::r3f9a1c07 (fetch)
origin  anon::r3f9a1c07 (push)

$ git pull && git push        # works exactly as before
```

## How it works

git treats a URL like `anon::<alias>` as "ask the program `git-remote-anon`".
That helper looks up the alias in `~/.config/git-anon/map` (mode `600`) and
hands the connection to git's own transport:

| Real URL in the map               | Handed to                           |
|-----------------------------------|-------------------------------------|
| `https://…`, `http://…`           | `git remote-https` / `remote-http`  |
| `git@host:path`, `ssh://host/path` | `ssh` (honors `GIT_SSH_COMMAND`, `core.sshCommand`, `GIT_SSH`) |
| `/path`, `file:///path`           | local `git upload-pack` / `receive-pack` |

So `.git/config`, `git remote -v` and `git remote get-url` contain only the
alias — no host, no org, no repo name. Your SSH keys, `~/.ssh/config` and
credential helpers keep working unchanged.

## Install

```sh
npm install -g git-anon
```

or without Node.js:

```sh
curl -fsSL https://raw.githubusercontent.com/scott-leung/git-anon/main/install.sh | sh
```

The script installs into `~/.local/bin` (override with `BINDIR=…`), which must
be on your `PATH`; `make install` does the same from a checkout. Uninstall with
`npm uninstall -g git-anon` or `sh install.sh --uninstall`.
Requires git and a POSIX shell (macOS / Linux).

## Usage

```sh
cd your-repo
git anon init                  # anonymize every remote (one command)
git anon status                # what is anonymized
git anon off                   # put the real URLs back
```

| Command | |
|---|---|
| `git anon init [--alias NAME]` | Anonymize all remotes. Default alias is random (`r` + 8 hex) so it reveals nothing; `origin` gets `NAME`, other remotes `NAME-<remote>`. Idempotent. |
| `git anon off` | Restore all remotes of the current repo. |
| `git anon status` | Show which remotes are anonymized. |
| `git anon add <alias> [remote]` | Anonymize one remote with a chosen alias. |
| `git anon restore [remote]` | Restore one remote. |
| `git anon list` | List aliases (never prints URLs). |
| `git anon show <alias>` | Print the real URL behind an alias. |
| `git anon clone <alias> [dir]` | Clone through an alias. |

A `pushurl`, if set, is anonymized as `<alias>.push`.
On a new machine, copy `~/.config/git-anon/map` over and use `git anon clone`.

## Limitations

- Only the **remote URL** is hidden. Branch names, commit messages, file paths
  and file contents are still visible to any tool that reads your repo.
- The real URL is still visible to *local* processes while git runs
  (`ps`, `GIT_TRACE=1`).
- Tools that parse the remote to find the hosting service (`gh`, "open on
  GitHub" in IDEs) will no longer recognize the repo. Run `git anon off`
  temporarily, or pass the repo explicitly (`gh -R owner/repo`).
- Submodules: git blocks unknown protocols for submodules by default. Allow it
  with `git config --global protocol.anon.allow always`.
- A remote with several `url` values must be handled manually.

## Security notes

- The map may contain credentials if your URLs do (`https://token@…`); it is
  created with mode `600` in a `700` directory.
- Aliases are restricted to `[A-Za-z0-9._-]`, and URLs containing whitespace,
  quotes or shell metacharacters are refused before they reach `ssh`.

## Development

```sh
make test   # offline end-to-end tests (local bare repos + fake ssh)
make lint   # shellcheck
```

CI runs the tests on Ubuntu (dash), macOS (bash as sh) and Alpine
(busybox ash), and installs the npm tarball on Ubuntu and macOS.

Releasing: bump `VERSION` in `bin/git-anon` and `version` in `package.json`,
then push a tag `vX.Y.Z`. The release workflow verifies versions, runs the
tests, creates a GitHub release and publishes to npm with provenance (via npm
trusted publishing, or an `NPM_TOKEN` repository secret).

## License

MIT
