# The Autobahn lane's echo server in a Linux container, for Docker Desktop
# hosts (macOS, Windows), which have no host network for the fuzzing client to
# reach a server on.  `make echo-image` builds it from the repository, whose
# .dockerignore keeps the host's own build outputs out.
#
# CHEZ_VERSION is CI's floor, which the Makefile reads from the workflow;
# LIBDIRS is the Makefile's library path, relative to /app.

# --- Chez Scheme, from its release, threaded, as CI builds it ----------------
FROM ubuntu:24.04 AS chez
ARG CHEZ_VERSION
RUN test -n "$CHEZ_VERSION" || (echo "build-arg CHEZ_VERSION is required" >&2; exit 1)
# hadolint ignore=DL3008
RUN apt-get update -qq && apt-get install -y --no-install-recommends \
      build-essential curl ca-certificates uuid-dev \
 && rm -rf /var/lib/apt/lists/*
# --disable-x11 --disable-curses: the expeditor wants headers this image
# lacks. One layer, so the source tree never lands in the image.
# hadolint ignore=DL3003
RUN curl -fsSL -o /tmp/chez.tar.gz \
      "https://github.com/cisco/ChezScheme/releases/download/v${CHEZ_VERSION}/csv${CHEZ_VERSION}.tar.gz" \
 && tar xzf /tmp/chez.tar.gz -C /tmp \
 && cd "/tmp/csv${CHEZ_VERSION}" \
 && ./configure --threads --disable-x11 --disable-curses --installprefix=/opt/chez \
 && make && make install \
 && rm -rf "/tmp/csv${CHEZ_VERSION}" /tmp/chez.tar.gz

# --- chez-libuv's shim, against the system libuv -----------------------------
FROM ubuntu:24.04 AS build
# hadolint ignore=DL3008
RUN apt-get update -qq && apt-get install -y --no-install-recommends \
      build-essential pkg-config libuv1-dev make \
 && rm -rf /var/lib/apt/lists/*
COPY --from=chez /opt/chez /opt/chez
ENV PATH=/opt/chez/bin:$PATH
COPY . /app
WORKDIR /app
RUN make -s -C vendor/chez-http-server/vendor/chez-libuv build CHEZ=scheme FLAVOR=prod

# --- the server, as a user of its own ------------------------------------------
FROM ubuntu:24.04
ARG LIBDIRS
RUN test -n "$LIBDIRS" || (echo "build-arg LIBDIRS is required" >&2; exit 1)
# libuv1-dev, not libuv1: the shim's config names libuv.so, the development
# link, as chez-libuv found it at build time. curl is the HEALTHCHECK's.
# hadolint ignore=DL3008
RUN apt-get update -qq && apt-get install -y --no-install-recommends libuv1-dev curl ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --create-home --uid 1001 echo
COPY --from=chez /opt/chez /opt/chez
COPY --from=build /app /app
ENV PATH=/opt/chez/bin:$PATH CHEZSCHEMELIBDIRS=$LIBDIRS
WORKDIR /app
USER echo
HEALTHCHECK --interval=2s --timeout=2s --start-period=20s --retries=3 \
  CMD curl -fsS "http://127.0.0.1:${CHEZ_HTTP_PORT:-8080}/health/ready" || exit 1
CMD ["scheme", "--program", "tests/autobahn/echo.sps"]
