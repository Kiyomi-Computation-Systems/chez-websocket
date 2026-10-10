#!/bin/sh
# `make docker-smoke`: the echo image (built by make echo-image) started, ready
# by its HEALTHCHECK on /health/ready, and stopped as the server stops, saying
# `stopped`.  Exit 0, or 1 with what went wrong.
set -u
: "${ECHO_IMAGE:?}"
name="chez-websocket-smoke-$$"
trap 'docker rm -f "$name" > /dev/null 2>&1' EXIT INT TERM
docker run -d --name "$name" -e CHEZ_HTTP_HOST=0.0.0.0 -e CHEZ_HTTP_PORT=9001 "$ECHO_IMAGE" > /dev/null || exit 1
i=0
until [ "$(docker inspect -f '{{.State.Health.Status}}' "$name" 2>/dev/null)" = healthy ]; do
  i=$((i + 1))
  if [ "$i" -gt 60 ]; then
    echo "docker-smoke: not healthy within 60 s:" >&2
    docker logs "$name" >&2
    exit 1
  fi
  sleep 1
done
docker stop --time 30 "$name" > /dev/null
if docker logs "$name" 2>&1 | grep -q '^stopped'; then
  echo "docker-smoke: $ECHO_IMAGE built, ready, and stopped"
else
  echo "docker-smoke: $ECHO_IMAGE did not stop as the server stops:" >&2
  docker logs "$name" 2>&1 | tail -5 >&2
  exit 1
fi
