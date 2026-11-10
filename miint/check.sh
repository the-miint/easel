#!/usr/bin/env bash
# miint/check.sh: environment checks for the miint Easel patches.
#
# Unit tests live in Easel's own test drivers and run with `make check`.
# These checks need something a test driver can't arrange for itself:
# a PID-1 parent, a look at what configure generated, or another
# compiler.
#
# Usage:  miint/check.sh          (from any directory)
# Builds in <repo>/build-miint-native (gitignored by /build-*/).
# Prints PASS / FAIL / SKIP per check; exits 1 if any check failed.
# A SKIP means a tool this host lacks; it is listed again at the end.

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
NATIVE="$ROOT/build-miint-native"

npass=0; nfail=0; skipped=()
pass() { echo "PASS  $1"; npass=$((npass+1)); }
fail() { echo "FAIL  $1: $2"; nfail=$((nfail+1)); }
skip() { echo "SKIP  $1: $2"; skipped+=("$1 ($2)"); }

# Run a build step, logging to $log; on failure show the log's tail.
step() { # log cmd...
  local log=$1; shift
  if "$@" > "$log" 2>&1; then return 0; fi
  echo "      command failed: $*  (log: $log)"; tail -n 15 "$log" | sed 's/^/      | /'
  return 1
}

# --- native build: libeasel.a with the host compiler -------------------
native_ok=0
mkdir -p "$NATIVE"
if step "$NATIVE/autoconf.log" bash -c "cd '$ROOT' && autoconf" &&
   step "$NATIVE/configure.log" bash -c "cd '$NATIVE' && '$ROOT/configure'" &&
   step "$NATIVE/make.log" make -C "$NATIVE" -j8 libeasel.a
then native_ok=1; pass "native-build"
else fail "native-build" "autoconf/configure/make libeasel.a failed"
fi

# --- errmsg-pid1: messages reach the caller under a PID-1 parent -------
# esl_fail() must fill the caller's buffer; esl_exception() and
# esl_fatal() must print to stderr. Each runs once as a control and once
# under a PID-1 parent (`sh` as PID 1 of a new PID namespace; the
# trailing `true` stops sh from exec'ing the driver in its place).
check_errmsg() {
  local bin="$NATIVE/errmsg_check" out mode bad=""
  if ! step "$NATIVE/errmsg_check.log" ${CC:-cc} -I"$NATIVE" -I"$ROOT" \
         -o "$bin" "$ROOT/miint/errmsg_check.c" "$NATIVE/libeasel.a" -lm; then
    fail "errmsg-pid1" "could not build miint/errmsg_check.c"; return
  fi
  if ! unshare -rpf --mount-proc true > /dev/null 2>&1; then
    skip "errmsg-pid1" "unshare -rpf unavailable (needs unprivileged user namespaces)"; return
  fi
  out=$(unshare -rpf --mount-proc sh -c '"$1" ppid; true' sh "$bin" 2>&1)
  if [ "$out" != "1" ]; then
    fail "errmsg-pid1" "premise not met: the driver's parent is '$out', not PID 1"; return
  fi
  for mode in fail exception fatal; do
    out=$("$bin" "$mode" 2>&1)
    case $out in *"miint-errmsg-check $mode"*) ;; *) bad="$bad $mode(control)";; esac
    out=$(unshare -rpf --mount-proc sh -c '"$1" "$2"; true' sh "$bin" "$mode" 2>&1)
    case $out in *"miint-errmsg-check $mode"*) ;; *) bad="$bad $mode(pid1)";; esac
  done
  if [ -z "$bad" ]; then pass "errmsg-pid1"; else fail "errmsg-pid1" "message lost:$bad"; fi
}
if [ $native_ok = 1 ]; then check_errmsg; else fail "errmsg-pid1" "no native build"; fi

# --- summary ------------------------------------------------------------
echo "----"
echo "$npass passed, $nfail failed, ${#skipped[@]} skipped"
for s in "${skipped[@]+"${skipped[@]}"}"; do echo "  skipped: $s"; done
[ $nfail = 0 ]
