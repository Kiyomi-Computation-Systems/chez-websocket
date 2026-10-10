#!/bin/sh
# The Autobahn lane (M5, decision 0008), run by `make autobahn`.
#
# Starts the echo server, tests/autobahn/echo.sps, runs Autobahn|Testsuite's
# fuzzing client from $IMAGE against it, stops the server, and gates the run's
# index.json against tests/autobahn/verdicts.txt.  Exit status: the gate's (0
# every verdict as the ratchet holds it, 1 a difference, 2 a file it cannot
# read), or 2 when the echo server or Docker could not run.
#
# Where the echo server runs, ECHO_AT (the Makefile's AUTOBAHN_ECHO):
#   host       on this host, on a port of its own, which the fuzzing client
#              reaches on the host's network: Linux's, and CI's.
#   container  in ECHO_IMAGE, the image tests/autobahn/echo.Dockerfile builds
#              (`make echo-image`), on a Docker network of its own beside the
#              fuzzing client: Docker Desktop's (macOS, Windows), which has no
#              host network (0008's review, by form: "Container on Docker
#              Desktop").
#
# Environment, from the Makefile: CHEZ, LIBDIRS, IMAGE, OUT, ECHO_AT, and for
# the container ECHO_IMAGE.
set -u
: "${CHEZ:?}" "${LIBDIRS:?}" "${IMAGE:?}" "${OUT:?}" "${ECHO_AT:?}"

spec=tests/autobahn/fuzzingclient.json

# A run that writes no index must not be gated on the last one's: that file
# alone goes; the per-case reports a run writes replace the last run's.
mkdir -p "$OUT/config" "$OUT/reports" &&
  out=$(cd "$OUT" && pwd) &&
  rm -f "$out/reports/index.json" ||
  exit 2

# wait_listening LOG: until LOG says `listening`, while the echo server lives;
# its port, from that line, on stdout.
wait_listening() {
  i=0
  until grep -q '^listening ' "$1"; do
    if ! echo_alive; then
      echo "autobahn: the echo server ended before it listened:" >&2
      cat "$1" >&2
      return 1
    fi
    i=$((i + 1))
    if [ "$i" -gt 600 ]; then echo "autobahn: the echo server did not listen within 60 s" >&2; return 1; fi
    sleep 0.1
  done
  sed -n 's/^listening [^ ]* \([0-9][0-9]*\)$/\1/p' "$1" | head -1
}

case "$ECHO_AT" in
  host)
    # The echo server's environment is the lane's alone, so no CHEZ_HTTP_ or
    # CHEZ_WS_ variable of the caller's changes what the cases see.  Port 0
    # takes any free one.
    env -i PATH="$PATH" HOME="${HOME:-/}" CHEZSCHEMELIBDIRS="$LIBDIRS" \
      CHEZ_HTTP_HOST=127.0.0.1 CHEZ_HTTP_PORT=0 CHEZ_WS_MAX_MESSAGE_BYTES=16777216 \
      "$CHEZ" --program tests/autobahn/echo.sps > "$out/server.log" 2>&1 &
    echo_pid=$!
    echo "$echo_pid" > "$out/echo.pid"
    # Alive and not a zombie. A server that has exited stays one until this
    # shell reaps it, which a subshell cannot do, such as wait_listening's
    # command substitution, and dash's kill -0 answers for a zombie too.
    echo_alive() {
      [ -n "$echo_pid" ] || return 1
      case "$(ps -o stat= -p "$echo_pid" 2>/dev/null | tr -d ' ')" in
        '' | Z*) return 1 ;;
        *) return 0 ;;
      esac
    }
    # SIGTERM drains the server (chez-http-server's docs/handlers.org): it
    # says `stopped` as it returns.  Once it has, its pid is forgotten, so
    # nothing signals a process that may have reused it.
    echo_stop() {
      [ -n "$echo_pid" ] || return 0
      kill -TERM "$echo_pid" 2>/dev/null
      i=0
      while echo_alive; do
        i=$((i + 1))
        if [ "$i" -gt 300 ]; then echo "autobahn: the echo server did not stop within 30 s" >&2; return 1; fi
        sleep 0.1
      done
      echo_pid=
    }
    cleanup() { echo_stop > /dev/null 2>&1; }
    # Whatever ends the run, a signal or an error, the echo server goes with
    # it: a signal exits, and the exit stops the server.
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    port=$(wait_listening "$out/server.log") || exit 2
    url="ws://127.0.0.1:$port"
    network=host
    ;;
  container)
    : "${ECHO_IMAGE:?}"
    name="chez-websocket-autobahn-$$"
    docker network create "$name" > /dev/null || exit 2
    cleanup() { docker rm -f "$name" > /dev/null 2>&1; docker network rm "$name" > /dev/null 2>&1; }
    docker run -d --name "$name" --network "$name" -e CHEZ_HTTP_HOST=0.0.0.0 -e CHEZ_HTTP_PORT=9001 \
      -e CHEZ_WS_MAX_MESSAGE_BYTES=16777216 "$ECHO_IMAGE" > /dev/null || exit 2
    echo_alive() {
      docker logs "$name" > "$out/server.log" 2>&1
      [ "$(docker inspect -f '{{.State.Running}}' "$name" 2>/dev/null)" = true ]
    }
    # docker stop sends SIGTERM and waits; the logs are read after.
    echo_stop() {
      docker stop --time 30 "$name" > /dev/null
      docker logs "$name" > "$out/server.log" 2>&1
    }
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    port=$(wait_listening "$out/server.log") || exit 2
    url="ws://$name:$port"
    network=$name
    ;;
  *) echo "autobahn: ECHO_AT is host or container, not $ECHO_AT" >&2; exit 2 ;;
esac

sed "s#ws://127.0.0.1:9001#$url#" "$spec" > "$out/config/fuzzingclient.json" || exit 2

docker run --rm --network "$network" --user "$(id -u):$(id -g)" \
  -v "$out/config:/config:ro" -v "$out/reports:/reports" \
  "$IMAGE" wstest -m fuzzingclient -s /config/fuzzingclient.json > "$out/wstest.log" 2>&1
docker_status=$?

echo_stop || exit 2
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
