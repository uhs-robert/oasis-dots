#!/usr/bin/env bash
# Runs resolve-thread.sh against the fake gh, which logs each call to $GH_LOG.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
script=${1:-$here/../resolve-thread.sh}
pass=0 fail=0
check() { if eval "$2"; then
  echo "ok   $1"
  pass=$((pass + 1))
else
  echo "FAIL $1"
  fail=$((fail + 1))
fi; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir "$work/bin"
cp "$here/gh" "$work/bin/gh"
export PATH=$work/bin:$PATH GH_LOG=$work/log FAKE_THREADS=$work/threads.json FAKE_THREADS_2=$work/threads2.json
# shellcheck disable=SC2034 # out, code and err are read by the eval in check
run() {
  : >"$GH_LOG"
  out=$("$script" "$@" 2>"$work/err")
  code=$?
  err=$(<"$work/err")
}
long=$(printf 'x%.0s' {1..120})
cat >"$FAKE_THREADS" <<JSON
{"data":{"repository":{"pullRequest":{"reviewThreads":{"pageInfo":{"hasNextPage":false},"nodes":[
{"id":"PRRT_open1","isResolved":false,"path":"a.sh","line":7,"comments":{"nodes":[{"author":{"login":"bot"},"body":"first line\nsecond line"}]}},
{"id":"PRRT_done","isResolved":true,"path":"b.sh","line":1,"comments":{"nodes":[{"author":{"login":"bot"},"body":"already handled"}]}},
{"id":"PRRT_open2","isResolved":false,"path":"c.sh","line":null,"comments":{"nodes":[{"author":{"login":"me"},"body":"$long"}]}}
]}}}}}
JSON

echo "== reply and resolve"
run PRRT_abc-1_x "fixed in abc"
check "exits 0 and reports both" "[[ \$code == 0 && \$out == 'replied+resolved PRRT_abc-1_x' ]]"
check "replies before it resolves" "[[ \$(grep -n -e addPullRequestReviewThreadReply -e 'resolveReviewThread(' '$GH_LOG' | cut -d: -f1 | paste -sd,) == 2,3 ]]"
check "sends the body literally" "grep -q -- '-f body=fixed in abc' '$GH_LOG'"

echo "== reply fails"
FAKE_REPLY_FAIL=1 run PRRT_abc "x"
check "exits 1" "[[ \$code == 1 ]]"
check "names the thread on stderr" "[[ \$err == *'resolve-thread: cannot reply to PRRT_abc' ]]"
check "never resolves" "! grep -q 'resolveReviewThread(' '$GH_LOG'"

echo "== bad input"
for bad in "PRRT" "PRRT_" "PRRT_x; rm" "abc" "PRRT_a b"; do
  run "$bad" "text"
  check "refuses id '$bad' without calling gh" "[[ \$code == 1 && ! -s '$GH_LOG' ]]"
done
run PRRT_abc ""
check "refuses an empty body without calling gh" "[[ \$code == 1 && ! -s '$GH_LOG' ]]"
run PRRT_abc "   "
check "refuses a blank body without calling gh" "[[ \$code == 1 && ! -s '$GH_LOG' ]]"
run PRRT_abc
check "refuses a missing body" "[[ \$code == 1 && ! -s '$GH_LOG' ]]"

echo "== body from stdin"
: >"$GH_LOG"
printf 'line one\nline two\n' | "$script" PRRT_abc - >/dev/null 2>&1
check "replies with the stdin body" "[[ \$? == 0 ]] && grep -q 'line one line two' '$GH_LOG'"
: >"$GH_LOG"
printf '' | "$script" PRRT_abc - >/dev/null 2>&1
check "refuses an empty stdin without calling gh" "[[ \$? == 1 && ! -s '$GH_LOG' ]]"

echo "== already resolved"
FAKE_RESOLVED=true run PRRT_abc "late note"
check "exits 0 with a note" "[[ \$code == 0 && \$out == 'replied PRRT_abc (already resolved)' ]]"
check "replies" "grep -q addPullRequestReviewThreadReply '$GH_LOG'"
check "does not resolve again" "! grep -q 'resolveReviewThread(' '$GH_LOG'"

echo "== --list"
run --list 12
check "exits 0" "[[ \$code == 0 ]]"
check "lists the unresolved threads only" "[[ \$(cut -f1 <<<\"\$out\" | paste -sd,) == PRRT_open1,PRRT_open2 ]]"
check "prints id path line author first line" "[[ \$(head -1 <<<\"\$out\") == \$'PRRT_open1\ta.sh\t7\tbot\tfirst line' ]]"
check "cuts a long first line to 80 characters" "[[ \$(tail -1 <<<\"\$out\" | cut -f5 | wc -c) == 81 ]]"
check "shows a missing line as -" "[[ \$(tail -1 <<<\"\$out\" | cut -f3) == - ]]"
check "issues no mutation" "! grep -q mutation '$GH_LOG'"
run --list x
check "refuses a non-numeric pr" "[[ \$code == 1 ]]"
sed -i 's/"hasNextPage":false/"hasNextPage":true,"endCursor":"C1"/' "$FAKE_THREADS"
cat >"$FAKE_THREADS_2" <<'JSON'
{"data":{"repository":{"pullRequest":{"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":"C2"},"nodes":[
{"id":"PRRT_page2","isResolved":false,"path":"d.sh","line":3,"comments":{"nodes":[{"author":{"login":"bot"},"body":"on page two"}]}}
]}}}}}
JSON
run --list 12
check "follows the cursor to the next page" "[[ \$(cut -f1 <<<\"\$out\" | paste -sd,) == PRRT_open1,PRRT_open2,PRRT_page2 ]]"
check "sends the cursor on the second call only" "[[ \$(grep -c ' after=C1' '$GH_LOG') == 1 && \$(grep -c 'reviewThreads' '$GH_LOG') == 2 ]]"
check "no longer notes a truncated list" "[[ -z \$err ]]"
sed -i 's/,"endCursor":"C1"//' "$FAKE_THREADS"
run --list 12
check "refuses a next page without a cursor" "[[ \$code == 1 && \$err == *'no cursor'* ]]"

sed -i 's/"pageInfo":{[^}]*}/"pageInfo":{"hasNextPage":true,"endCursor":"C1"}/' "$FAKE_THREADS" "$FAKE_THREADS_2"
run --list 12
check "refuses a page that repeats the cursor" "[[ \$code == 1 && \$err == *'repeats cursor C1'* ]]"

echo "$pass passed, $fail failed"
((fail == 0))
