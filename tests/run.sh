#!/bin/sh
# End-to-end tests for git-anon. Offline: uses local bare repos and a fake ssh.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/git-anon-test.XXXXXX")
trap 'rm -rf "$T"' EXIT

# Git for Windows: use C:/... paths everywhere so git stores exactly the
# strings the tests compare against (MSYS would rewrite /tmp/... arguments).
WINDOWS=
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) WINDOWS=1; T=$(cygpath -m "$T") ;;
esac
TP=$T
[ -z "$WINDOWS" ] || TP=$(cygpath -u "$T")   # for PATH, which is ':'-separated

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
while [ "\$1" = "-p" ] || [ "\$1" = "-o" ]; do shift 2; done
shift
# Play the server side: on Windows, ssh://host/C:/x means the local path C:/x.
exec sh -c "\$(printf '%s' "\$*" | sed "s#'/\\([A-Za-z]:\\)#'\\1#")"
EOF
chmod +x "$T/fakebin/ssh"
PATH="$ROOT/bin:$TP/fakebin:$PATH"
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

# with_timeout <secs> cmd...: run cmd, kill it after <secs>; touches $T/timed-out on kill.
with_timeout() {
  secs=$1; shift
  rm -f "$T/timed-out"
  "$@" &
  pid=$!
  ( sleep "$secs"; kill -9 "$pid" 2>/dev/null && touch "$T/timed-out" ) &
  watchdog=$!
  rc=0; wait "$pid" || rc=$?
  kill "$watchdog" 2>/dev/null || true
  wait "$watchdog" 2>/dev/null || true
  return "$rc"
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
if [ -z "$WINDOWS" ]; then  # no POSIX modes on Windows
  check "map is mode 600" sh -c "ls -l '$GIT_ANON_MAP' | grep -q '^-rw-------'"
  check "map dir is mode 700" sh -c "ls -ld '$(dirname "$GIT_ANON_MAP")' | grep -q '^drwx------'"
fi
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
# ssh:// paths always start with "/" (on Windows: /C:/..., see fake ssh)
printf 'scp1 git@fakehost:%s\nurl1 ssh://git@fakehost:2222/%s\n' "$T/remote.git" "${T#/}/remote.git" >> "$GIT_ANON_MAP"
for a in scp1 url1; do
  git -C "$W" remote set-url origin "anon::$a"
  commit "$W" "$a"
  check "$a: push" git -C "$W" push -q origin main
  check "$a: clone" git clone -q "anon::$a" "$T/clone-$a"
done
check "scp form argv" grep -qxF "git@fakehost git-receive-pack '$T/remote.git'" "$T/ssh.log"
check "ssh:// form argv with port" grep -qxF -- "-p 2222 git@fakehost git-upload-pack '/${T#/}/remote.git'" "$T/ssh.log"
: > "$T/ssh.log"
check "GIT_SSH_COMMAND honored" env GIT_SSH_COMMAND="ssh -o X=1" git ls-remote anon::scp1
check "GIT_SSH_COMMAND argv" grep -qxF -- "-o X=1 git@fakehost git-upload-pack '$T/remote.git'" "$T/ssh.log"

echo "# failures exit instead of hanging"
printf 'gone %s\nsshgone git@fakehost:%s\n' "$T/missing.git" "$T/missing.git" >> "$GIT_ANON_MAP"
check_not "missing local repo: ls-remote fails" with_timeout 20 git ls-remote anon::gone
check "missing local repo: did not time out" test ! -e "$T/timed-out"
check_not "missing ssh repo: fetch fails" with_timeout 20 git -C "$W" fetch anon::sshgone
check "missing ssh repo: did not time out" test ! -e "$T/timed-out"
check_not "missing local repo: clone fails" with_timeout 20 git clone -q anon::gone "$T/clone-gone"
check "missing local repo clone: did not time out" test ! -e "$T/timed-out"

echo "# submodules"
# super ── abs (absolute URL)
#       └─ rel (relative ../sub-rel.git) ── nested (relative ../nested.git)
git config --global protocol.file.allow always   # plain git needs it for local submodules
S=$T/srv
mkdir -p "$S"
for r in super sub-abs sub-rel nested; do
  git init -q --bare "$S/$r.git"
  git clone -q "$S/$r.git" "$T/seed-$r" 2>/dev/null
  commit "$T/seed-$r" "$r"
done
git -C "$T/seed-nested" push -q origin main
git -C "$T/seed-sub-abs" push -q origin main
(cd "$T/seed-sub-rel" && git submodule add -q ../nested.git nested && git commit -qm sub && git push -q origin main)
(cd "$T/seed-super" && git submodule add -q "$S/sub-abs.git" abs && git submodule add -q ../sub-rel.git rel \
  && git commit -qm subs && git push -q origin main)
leaks() {  # repo dir: list config files that still contain a real server path
  [ -d "$1/.git" ] || { echo "missing $1"; return 0; }
  find "$1/.git" -name config -type f -exec grep -l "$S" {} + 2>/dev/null || true
}

git clone -q --recurse-submodules "$S/super.git" "$T/sm1" 2>/dev/null
check "submodules: precondition, real URLs present" sh -c "[ -n \"\$(find '$T/sm1/.git' -name config -exec grep -l '$S' {} +)\" ]"
(cd "$T/sm1" && git anon init) > "$T/sm1.out"
check "submodules: no real URL left in any .git config" test -z "$(leaks "$T/sm1")"
check "submodules: nested submodule remote anonymized" sh -c "git -C '$T/sm1/rel/nested' remote get-url origin | grep -q '^anon::'"
check "submodules: protocol.anon.allow set globally" sh -c "[ \"\$(git config --global protocol.anon.allow)\" = always ]"
check "submodules: .gitmodules note printed" grep -q "^note: .gitmodules" "$T/sm1.out"
check "submodules: status all anonymized" sh -c "cd '$T/sm1' && ! git anon status | grep -q NOT"
check "submodules: status shows nested" sh -c "cd '$T/sm1' && git anon status | grep -q '^rel/submodule nested: anonymized'"
check "submodules: recursive fetch" git -C "$T/sm1" fetch -q --recurse-submodules=yes
commit "$T/sm1/rel/nested" nested2
check "submodules: push from nested submodule" git -C "$T/sm1/rel/nested" push -q origin HEAD:main
check "submodules: init is idempotent" sh -c "cd '$T/sm1' && git anon init | grep -q 'submodule.rel.url already anonymized'"
(cd "$T/sm1" && git anon off) >/dev/null
check "submodules: off leaves no anon:: anywhere" sh -c "! find '$T/sm1/.git' -name config -exec grep -l 'anon::' {} + | grep -q ."
check "submodules: off restores relative-resolved URL" sh -c "[ \"\$(git -C '$T/sm1' config submodule.rel.url)\" = '$S/sub-rel.git' ]"

git clone -q "$S/super.git" "$T/sm2"
(cd "$T/sm2" && git anon init) >/dev/null
check "uninitialized: stays inactive" sh -c "git -C '$T/sm2' submodule status | grep -q '^-'"
check "uninitialized: relative URL pre-resolved" sh -c "git -C '$T/sm2' config submodule.rel.url | grep -q '^anon::'"
check "uninitialized: plain submodule update --init works" git -C "$T/sm2" submodule --quiet update --init
check "uninitialized: first level cloned via alias" sh -c "git -C '$T/sm2/rel' remote get-url origin | grep -q '^anon::'"
check "git anon update clones nested level" sh -c "cd '$T/sm2' && git anon update"
check "git anon update: nested checked out" test -f "$T/sm2/rel/nested/f.txt"
check "git anon update: no real URL left" test -z "$(leaks "$T/sm2")"

git clone -q "$S/super.git" "$T/sm3"
(cd "$T/sm3" && git anon init && git anon off) >/dev/null
check "off on never-initialized submodules restores pristine state" \
  sh -c "! git -C '$T/sm3' config --get-regexp '^submodule\.' >/dev/null"

(cd "$T/sm1" && git anon init) >/dev/null
salias=$(git -C "$T/sm1" config remote.origin.url | sed 's/^anon:://')
check "clone --recurse-submodules through alias" git anon clone --recurse-submodules "$salias" "$T/sm4"
check "clone --recurse-submodules: nested checked out" test -f "$T/sm4/rel/nested/f.txt"
check "clone --recurse-submodules: no real URL left" test -z "$(leaks "$T/sm4")"

echo "# reflog / FETCH_HEAD (opt-in: --scrub-reflog)"
git clone -q "$S/super.git" "$T/tr0"
(cd "$T/tr0" && git anon init) > "$T/tr0.out" 2>&1
check "default: reflog left untouched" grep -rqF "$S/super.git" "$T/tr0/.git/logs"
check "default: note about --scrub-reflog printed" grep -q -- "--scrub-reflog" "$T/tr0.out"
check "default: no scrub warning" sh -c "! grep -q '^warning:' '$T/tr0.out'"

git clone -q "$S/super.git" "$T/tr1"
git -C "$T/tr1" fetch -q origin
check "precondition: reflog records clone URL" grep -rqF "$S/super.git" "$T/tr1/.git/logs"
(cd "$T/tr1" && git anon init --scrub-reflog) > "$T/tr1.out" 2>&1
check "--scrub-reflog warns it can be slow" grep -q "^warning: --scrub-reflog" "$T/tr1.out"
check "reflog and FETCH_HEAD scrubbed" sh -c "! grep -rqF '$S/super.git' '$T/tr1/.git/logs' '$T/tr1/.git/FETCH_HEAD'"
check "reflog still readable" sh -c "git -C '$T/tr1' reflog -1 | grep -q 'clone: from anon::'"
check "no lock or temp files left" sh -c "! find '$T/tr1/.git' -name '*.lock' -o -name '*.anon-tmp.*' | grep -q ."

git clone -q "$S/super.git" "$T/tr2"
(cd "$T/tr2" && git anon init --scrub-reflog >/dev/null 2>&1 && git anon init --scrub-reflog) > "$T/tr2.out" 2>&1
check "rerun on already-scrubbed repo is clean" sh -c "! grep -rqF '$S' '$T/tr2/.git/logs'"
check "nothing printed about scrubbing on clean rerun" sh -c "! grep -q scrubbed '$T/tr2.out'"

git clone -q "$S/super.git" "$T/tr3"
(cd "$T/tr3" && git anon init) >/dev/null 2>&1
(cd "$T/tr3" && git anon init --scrub-reflog) > "$T/tr3.out" 2>&1
check "already-anonymized repo scrubbed on request" sh -c "! grep -rqF '$S' '$T/tr3/.git/logs' && grep -q scrubbed '$T/tr3.out'"

git clone -q "git@fakehost:$S/super.git" "$T/tr4"
check "precondition: reflog records URL without user" grep -rqF "clone: from fakehost:$S/super.git" "$T/tr4/.git/logs"
(cd "$T/tr4" && git anon init --scrub-reflog) >/dev/null 2>&1
check "scp-style URL scrubbed in user-less form too" sh -c "! grep -rqF 'fakehost' '$T/tr4/.git/logs'"

git clone -q "$S/super.git" "$T/tr5"
: > "$T/tr5/.git/HEAD.lock"
(cd "$T/tr5" && git anon init --scrub-reflog) > "$T/tr5.out" 2>&1
check "locked ref: skipped with a warning" grep -q "HEAD.lock is locked" "$T/tr5.out"
check "locked ref: its reflog left intact" grep -qF "$S/super.git" "$T/tr5/.git/logs/HEAD"
check "locked ref: foreign lock not removed" test -e "$T/tr5/.git/HEAD.lock"
check "locked ref: other reflogs still scrubbed" sh -c "! grep -qF '$S/super.git' '$T/tr5/.git/logs/refs/heads/main'"
rm -f "$T/tr5/.git/HEAD.lock"

git clone -q "$S/super.git" "$T/tr6"
git -C "$T/tr6" worktree add -q "$T/tr6-wt" -b wt 2>/dev/null
printf '%s\n' "0000000000000000000000000000000000000000 $(git -C "$T/tr6" rev-parse HEAD) t <t@t> 1700000000 +0000	pull $S/super.git: note" >> "$T/tr6/.git/worktrees/tr6-wt/logs/HEAD"
(cd "$T/tr6" && git anon init --scrub-reflog) >/dev/null 2>&1
check "linked worktree reflog scrubbed" sh -c "! grep -qF '$S' '$T/tr6/.git/worktrees/tr6-wt/logs/HEAD'"

(cd "$T/sm1" && git anon off && git anon init --scrub-reflog) >/dev/null 2>&1
check "submodule reflogs scrubbed" sh -c "! grep -rqF '$S' \$(find '$T/sm1/.git/modules' -type d -name logs)"

echo "# performance: 10000 reflog files"
git clone -q "$S/super.git" "$T/perf"
h=$(git -C "$T/perf" rev-parse HEAD)
mkdir -p "$T/perf/.git/logs/refs/remotes/origin/many"
i=0
while [ $i -lt 10000 ]; do
  i=$((i + 1))
  printf '%s %s t <t@t> 1700000000 +0000\tfetch: storing head\n' 0000000000000000000000000000000000000000 "$h"
done | awk -v d="$T/perf/.git/logs/refs/remotes/origin/many" '{ f = d "/b" NR; print > f; close(f) }'
start=$(date +%s)
(cd "$T/perf" && git anon init --scrub-reflog) >/dev/null 2>&1
secs=$(( $(date +%s) - start ))
echo "     (init --scrub-reflog with 10000 reflog files: ${secs}s)"
check "10000 reflog files scrubbed in under 60s" test "$secs" -lt 60
check "10000 reflog files: real URL gone" sh -c "! grep -rqF '$S/super.git' '$T/perf/.git/logs'"

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
