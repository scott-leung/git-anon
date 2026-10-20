#!/bin/sh
# End-to-end tests for git-anon. Offline: uses local bare repos and a fake ssh.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/git-anon-test.XXXXXX")
trap 'rm -rf "$T"' EXIT

# Isolate from the user's git config and alias map.
export HOME="$T/home" GIT_CONFIG_NOSYSTEM=1 GIT_ANON_MAP="$T/home/.config/git-anon/map"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
mkdir -p "$HOME" "$T/fakebin"
git config --global init.defaultBranch main
git config --global advice.detachedHead false

# Fake ssh: record argv, then run the remote command locally.
cat > "$T/fakebin/ssh" <<EOF
#!/bin/sh
echo "\$*" >> "$T/ssh.log"
while [ "\$1" = "-p" ]; do shift 2; done
shift
exec sh -c "\$*"
EOF
chmod +x "$T/fakebin/ssh"
PATH="$ROOT/bin:$T/fakebin:$PATH"
export PATH

pass=0
fail=0
ok()  { pass=$((pass + 1)); echo "ok   - $1"; }
bad() { fail=$((fail + 1)); echo "FAIL - $1"; }
check() {  # description, command...
  d=$1; shift
  if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi
}
check_not() {
  d=$1; shift
  if "$@" >/dev/null 2>&1; then bad "$d"; else ok "$d"; fi
}

commit() {  # dir msg
  echo "$2" >> "$1/f.txt"
  git -C "$1" add f.txt
  git -C "$1" commit -qm "$2"
}

git init -q --bare "$T/remote.git"
git init -q --bare "$T/upstream.git"
git init -q "$T/work"
W=$T/work
commit "$W" one
git -C "$W" remote add origin "$T/remote.git"
git -C "$W" remote add upstream "$T/upstream.git"
git -C "$W" push -q origin main
git -C "$W" push -q upstream main

echo "# init"
(cd "$W" && git anon init) >/dev/null
check "origin url is anon::" sh -c "git -C '$W' remote get-url origin | grep -q '^anon::r[0-9a-f]\{8\}$'"
check "upstream url is anon::" sh -c "git -C '$W' remote get-url upstream | grep -q '^anon::r[0-9a-f]\{8\}-upstream$'"
check_not ".git/config has no real path" grep -q "$T" "$W/.git/config"
check_not "remote -v has no real path" sh -c "git -C '$W' remote -v | grep -q '$T'"
check "map is mode 600" sh -c "ls -l '$GIT_ANON_MAP' | grep -q '^-rw-------'"
check "map dir is mode 700" sh -c "ls -ld '$(dirname "$GIT_ANON_MAP")' | grep -q '^drwx------'"
check "init is idempotent" sh -c "cd '$W' && git anon init | grep -q 'already anonymized'"
check "status reports anonymized" sh -c "cd '$W' && git anon status | grep -q 'origin: anonymized'"
check_not "list never prints URLs" sh -c "git anon list | grep -q '$T'"

echo "# transport (local)"
commit "$W" two
check "push through alias" git -C "$W" push -q origin main
check "fetch through alias" git -C "$W" fetch -q upstream
check "ls-remote through alias" sh -c "git -C '$W' ls-remote origin | grep -q refs/heads/main"
alias=$(git -C "$W" remote get-url origin | sed 's/^anon:://')
check "clone through alias" git anon clone "$alias" "$T/clone"
check "clone keeps alias" sh -c "git -C '$T/clone' remote get-url origin | grep -q '^anon::'"
commit "$W" three
git -C "$W" push -q origin main
check "pull through alias" git -C "$T/clone" pull -q

echo "# off / restore"
(cd "$W" && git anon off) >/dev/null
check "off restores origin" sh -c "[ \"\$(git -C '$W' remote get-url origin)\" = '$T/remote.git' ]"
check "off restores upstream" sh -c "[ \"\$(git -C '$W' remote get-url upstream)\" = '$T/upstream.git' ]"
check "status reports not anonymized" sh -c "cd '$W' && git anon status | grep -q 'origin: NOT'"

echo "# add / pushurl / --alias"
git -C "$W" remote set-url --push origin "$T/remote.git"
(cd "$W" && git anon add myalias) >/dev/null
check "add sets chosen alias" sh -c "[ \"\$(git -C '$W' config remote.origin.url)\" = anon::myalias ]"
check "pushurl anonymized" sh -c "[ \"\$(git -C '$W' config remote.origin.pushurl)\" = anon::myalias.push ]"
check "push through pushurl alias" sh -c "cd '$W' && echo x >> f.txt && git commit -qam x && git push -q origin main"
(cd "$W" && git anon restore) >/dev/null
check "restore restores pushurl" sh -c "[ \"\$(git -C '$W' config remote.origin.pushurl)\" = '$T/remote.git' ]"
git -C "$W" config --unset remote.origin.pushurl
(cd "$W" && git anon off && git anon init --alias=named) >/dev/null
check "init --alias=NAME" sh -c "[ \"\$(git -C '$W' config remote.origin.url)\" = anon::named ]"
check "show prints real url" sh -c "[ \"\$(git anon show named)\" = '$T/remote.git' ]"

echo "# ssh transports (fake ssh)"
printf 'scp1 git@fakehost:%s\nurl1 ssh://git@fakehost:2222%s\n' "$T/remote.git" "$T/remote.git" >> "$GIT_ANON_MAP"
for a in scp1 url1; do
  git -C "$W" remote set-url origin "anon::$a"
  commit "$W" "$a"
  check "$a: push" git -C "$W" push -q origin main
  check "$a: clone" git clone -q "anon::$a" "$T/clone-$a"
done
check "scp form argv" grep -qx "git@fakehost git-receive-pack $T/remote.git" "$T/ssh.log"
check "ssh:// form argv with port" grep -qx -- "-p 2222 git@fakehost git-upload-pack $T/remote.git" "$T/ssh.log"

echo "# rejection"
check_not "invalid alias rejected" git ls-remote "anon::../etc"
check_not "unknown alias rejected" git ls-remote anon::nope
echo "evil git@h:x;touch\$IFS$T/pwned" >> "$GIT_ANON_MAP"
check_not "metacharacters in URL rejected" git ls-remote anon::evil
check_not "injection did not execute" test -e "$T/pwned"
check_not "duplicate alias with other URL rejected" sh -c "cd '$W' && git remote add o2 /x && git anon add named o2"
check_not "init outside repo fails" sh -c "cd '$T' && git anon init"
check "list without map succeeds" env GIT_ANON_MAP="$T/none" git anon list

echo "# install.sh"
check "install from checkout" env BINDIR="$T/inst" sh "$ROOT/install.sh"
check "installed executables" test -x "$T/inst/git-anon" -a -x "$T/inst/git-remote-anon"
check "uninstall" sh -c "BINDIR='$T/inst' sh '$ROOT/install.sh' --uninstall && ! test -e '$T/inst/git-anon'"

echo
echo "passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
