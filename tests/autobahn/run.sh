#!/bin/sh
# The Autobahn lane (M5, decision 0008), run by `make autobahn`.
#
# Starts tests/autobahn/echo.sps on this host in an environment of its own,
# runs Autobahn|Testsuite's fuzzing client from $IMAGE against it, stops the
# echo server, and gates the run's index.json against
# tests/autobahn/verdicts.txt.  Exit status: the gate's (0 every verdict as
# the ratchet holds it, 1 a difference, 2 a file it cannot read), or 2 when
# the echo server or Docker could not run.
#
# The container reaches the echo server on this host's network, as on Linux.
# Docker Desktop has no such network, so on macOS it goes through
# host.docker.internal, which Docker Desktop forwards to this host: there
# runs have stopped short (decision 0008), and the gate says so.
#
# Environment, from the Makefile: CHEZ, LIBDIRS, IMAGE, PORT, OUT.
set -u
: "${CHEZ:?}" "${LIBDIRS:?}" "${IMAGE:?}" "${PORT:?}" "${OUT:?}"

spec=tests/autobahn/fuzzingclient.json
case "$(uname -s)" in
  Darwin) host=host.docker.internal; network=bridge ;;
  *) host=127.0.0.1; network=host ;;
esac

# A run that writes no index must not be gated on the last one's: that file
# alone goes; the per-case reports a run writes replace the last run's.
mkdir -p "$OUT/config" "$OUT/reports" &&
  out=$(cd "$OUT" && pwd) &&
  rm -f "$out/reports/index.json" &&
  sed "s#ws://127.0.0.1:9001#ws://$host:$PORT#" "$spec" > "$out/config/fuzzingclient.json" ||
  exit 2

# The echo server's environment is the lane's alone, so no CHEZ_HTTP_ or
# CHEZ_WS_ variable of the caller's changes what the cases see.
env -i PATH="$PATH" HOME="${HOME:-/}" CHEZSCHEMELIBDIRS="$LIBDIRS" \
  CHEZ_HTTP_HOST=127.0.0.1 CHEZ_HTTP_PORT="$PORT" CHEZ_WS_MAX_MESSAGE_BYTES=16777216 \
  "$CHEZ" --program tests/autobahn/echo.sps > "$out/server.log" 2>&1 &
echo_pid=$!
trap 'kill "$echo_pid" 2>/dev/null' EXIT INT TERM

i=0
until grep -q '^listening ' "$out/server.log"; do
  if ! kill -0 "$echo_pid" 2>/dev/null; then
    echo "autobahn: the echo server ended before it listened:" >&2
    cat "$out/server.log" >&2
    exit 2
  fi
  i=$((i + 1))
  if [ "$i" -gt 600 ]; then echo "autobahn: the echo server did not listen within 60 s" >&2; exit 2; fi
  sleep 0.1
done

docker run --rm --network "$network" --user "$(id -u):$(id -g)" \
  -v "$out/config:/config:ro" -v "$out/reports:/reports" \
  "$IMAGE" wstest -m fuzzingclient -s /config/fuzzingclient.json > "$out/wstest.log" 2>&1
docker_status=$?

# SIGTERM drains the server (chez-http-server's docs/handlers.org): it says
# `stopped` as it returns.
kill -TERM "$echo_pid"
i=0
while kill -0 "$echo_pid" 2>/dev/null; do
  i=$((i + 1))
  if [ "$i" -gt 300 ]; then echo "autobahn: the echo server did not stop within 30 s" >&2; exit 2; fi
  sleep 0.1
done
trap - EXIT INT TERM
if ! grep -q '^stopped' "$out/server.log"; then
  echo "autobahn: the echo server ended without stopping:" >&2
  tail -5 "$out/server.log" >&2
  exit 2
fi

if [ "$docker_status" -ne 0 ]; then
  echo "autobahn: docker run exited $docker_status:" >&2
  tail -5 "$out/wstest.log" >&2
  exit 2
fi

CHEZSCHEMELIBDIRS="$LIBDIRS" "$CHEZ" --program tests/autobahn/gate.sps \
  "$spec" tests/autobahn/verdicts.txt "$out/reports/index.json"
