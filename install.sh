#!/bin/sh
# Install git-anon.
#
#   curl -fsSL https://raw.githubusercontent.com/scott-leung/git-anon/main/install.sh | sh
#   ./install.sh                 # from a checkout
#   ./install.sh --uninstall
#
# Env: BINDIR (default ~/.local/bin), GIT_ANON_REF (default main).

set -eu

REPO=scott-leung/git-anon
REF=${GIT_ANON_REF:-main}
BINDIR=${BINDIR:-$HOME/.local/bin}
FILES="git-anon git-remote-anon"

if [ "${1:-}" = "--uninstall" ]; then
  for f in $FILES; do rm -f "$BINDIR/$f"; done
  echo "removed git-anon from $BINDIR (alias map in ~/.config/git-anon kept)"
  exit 0
fi

# Running from a checkout uses local files; `curl | sh` downloads them.
src=
case "$0" in
  */install.sh|install.sh) src=$(cd "$(dirname "$0")" && pwd)/bin ;;
esac

mkdir -p "$BINDIR"
for f in $FILES; do
  if [ -n "$src" ] && [ -f "$src/$f" ]; then
    cp "$src/$f" "$BINDIR/$f.tmp"
  else
    curl -fsSL "https://raw.githubusercontent.com/$REPO/$REF/bin/$f" -o "$BINDIR/$f.tmp"
  fi
  chmod 755 "$BINDIR/$f.tmp"
  mv "$BINDIR/$f.tmp" "$BINDIR/$f"
done

echo "installed $FILES to $BINDIR"
case ":$PATH:" in
  *":$BINDIR:"*) ;;
  *) echo "warning: $BINDIR is not on PATH; add it to your shell profile" ;;
esac
echo "next: cd <repo> && git anon init"
