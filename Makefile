# chez-websocket — canonical entry points.
#
# One dependency, pinned by gitlink at a release tag: chez-http-server, under
# vendor/ (global-constraints).  It carries its own pins, and this project
# uses them through it: chez-libuv, chez-httparse with byte-machine under it,
# uriparse, and chez-srfi for the SRFI-64 test framework.  `make submodules`
# clones those, and not the server's test clients.  `make check-pins` holds
# the server at SERVER_PIN, and each pin it carries at the commit its parent
# records, so a server pin that moves brings them along; it refuses a
# checkout with local edits.  `make build` builds chez-libuv's shim and
# assembles one library path.

CHEZ ?= chez

# --- the pin -----------------------------------------------------------------
SERVER_DIR := vendor/chez-http-server
SERVER_PIN := 02ef95d39b307696064a344950ee10daa0a08640  # v0.5.0

# --- the pins it carries ------------------------------------------------------
LIBUV_DIR        := $(SERVER_DIR)/vendor/chez-libuv
HTTPARSE_DIR     := $(SERVER_DIR)/vendor/chez-httparse
BYTE_MACHINE_DIR := $(HTTPARSE_DIR)/vendor/byte-machine
URIPARSE_DIR     := $(SERVER_DIR)/vendor/uriparse
SRFI_DIR         := $(SERVER_DIR)/vendor/chez-srfi

# --- one library path ---------------------------------------------------------
# The server's, behind this project's own src/ and tests/.  chez-libuv locates
# its C shim by an absolute path baked into a config.sls it generates at its
# build, so only its src/ is needed here.  build/scheme-libs carries
# (srfi :64).
BUILD_DIR := build
SRFI_LIBS := $(BUILD_DIR)/scheme-libs
EMPTY :=
SPACE := $(EMPTY) $(EMPTY)
LIBDIR_LIST := src tests \
  $(SERVER_DIR)/src \
  $(LIBUV_DIR)/src \
  $(HTTPARSE_DIR)/src $(BYTE_MACHINE_DIR)/src \
  $(URIPARSE_DIR)/src \
  $(SRFI_LIBS)
LIBDIRS := $(subst $(SPACE),:,$(strip $(LIBDIR_LIST)))

# --- the suites' path ---------------------------------------------------------
# The suites run on LIBDIRS and then the test code they borrow, last, so the
# directories before it win any name it shares with them (the driver suite
# checks that none does): the server's tests/, whose (fake-shell) is the
# binding's test driver (decision 0004) and whose (shell-testing) runs clients
# on the libuv shell's loop for the socket suite; chez-httparse's test
# harness, on which the server's (response-reader) reads a response as a
# client would; and chez-libuv's tests/, whose (uv-testing) (shell-testing)
# is built on.  Test code stays off LIBDIRS, the path `make run` and `make
# dev` use, and `make test` refuses to run if it is there.
TEST_ONLY_DIRS := $(SERVER_DIR)/tests $(HTTPARSE_DIR)/test/support/harness $(LIBUV_DIR)/tests
TEST_LIBDIRS := $(LIBDIRS):$(subst $(SPACE),:,$(strip $(TEST_ONLY_DIRS)))

# Each tests/test-*.sps is its own process with its own (exit ...) status.
TESTS := $(wildcard tests/test-*.sps)

# The suites run with none of the binding's variables set: it reads them as a
# program starts, and the suites' numbers are the defaults' (design §7).  The
# binding suite refuses to run if one is set, so a variable added to (websocket
# limits) and not here stops it.
WS_ENV_VARS := CHEZ_WS_MAX_MESSAGE_BYTES CHEZ_WS_MAX_QUEUE CHEZ_WS_PING_INTERVAL \
  CHEZ_WS_PING_TIMEOUT CHEZ_WS_CLOSE_TIMEOUT CHEZ_WS_WRITE_HIGH_WATER CHEZ_WS_WRITE_LOW_WATER \
  CHEZ_WS_WRITE_TIMEOUT

# timeout(1) is GNU coreutils; macOS installs it as gtimeout. Absent both, a
# hung suite is not capped but the run is otherwise identical.
TIMEOUT_BIN := $(shell command -v timeout 2>/dev/null || command -v gtimeout 2>/dev/null)
SUITE_TIMEOUT ?= 120

# --- the Autobahn lane (M5, decision 0008) -----------------------------------
# Autobahn|Testsuite's fuzzing client, from its image pinned by digest (built
# for linux/amd64 alone, so Docker emulates it elsewhere), against
# tests/autobahn/echo.sps, gated on tests/autobahn/verdicts.txt.  The echo
# server runs on this host on Linux, and on Docker Desktop (macOS, Windows),
# which has no host network, in the image `make echo-image` builds;
# AUTOBAHN_ECHO=host or AUTOBAHN_ECHO=container says otherwise.  The image's
# Chez is CI's floor, read from the workflow so it is written once.
AUTOBAHN_IMAGE := crossbario/autobahn-testsuite:25.10.1@sha256:519915fb568b04c9383f70a1c405ae3ff44ab9e35835b085239c258b6fac3074
AUTOBAHN_ECHO ?= $(if $(filter Linux,$(shell uname -s)),host,container)
AUTOBAHN_ECHO_IMAGE := chez-websocket-autobahn-echo:local
CHEZ_FLOOR_VERSION := $(shell sed -n 's/^  CHEZ_FLOOR_VERSION: "\(.*\)"$$/\1/p' .github/workflows/ci.yml)

.PHONY: help check-help submodules check-pins check-imports deps build dev run test prod autobahn echo-image docker-smoke clean
.DEFAULT_GOAL := help

help: ## Show this help message
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z0-9_.-]+:.*?## / { printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

check-help: ## Fail if any .PHONY target is undocumented in `make help`
	@missing=0; \
	targets=$$(awk '/^\.PHONY:/ { $$1=""; print }' Makefile); \
	for t in $$targets; do \
	  grep -qE "^$$t:.*## " Makefile || { echo "check-help: '$$t' has no '## ' description" >&2; missing=1; }; \
	done; \
	exit $$missing

# Targeted, so neither chez-libuv's own vendored libuv nor the server's test
# clients (vtest2) are cloned here: the shim links the system libuv when it
# meets chez-libuv's floor, and chez-libuv's build clones and builds its own
# when it does not.
submodules: ## Clone the pinned server and the pins it carries
	git submodule update --init $(SERVER_DIR)
	git -C $(SERVER_DIR) submodule update --init vendor/chez-libuv vendor/uriparse vendor/chez-srfi
	git -C $(SERVER_DIR) submodule update --init --recursive vendor/chez-httparse

# check-pins asks each checkout for its own .git first: in a submodule that
# was never cloned, `git -C` would climb to the repository around it and
# answer that one's commit.
check-pins: ## Verify the server sits at its pin, and each pin it carries where its parent records
	@fail=0; \
	check_pin() { \
	  got=; [ -e "$$1/.git" ] && got=$$(git -C "$$1" rev-parse HEAD 2>/dev/null); \
	  if [ -z "$$2" ] || [ "$$got" != "$$2" ]; then \
	    echo "PIN MISMATCH: $$1 at $${got:-<absent>}, expected $${2:-<no gitlink recorded>}" >&2; fail=1; \
	  else echo "pin ok: $$1 $$2"; fi; }; \
	recorded() { git -C "$$1" rev-parse --verify --quiet "HEAD:$$2"; }; \
	check_pin $(SERVER_DIR) $(strip $(SERVER_PIN)); \
	for d in chez-libuv chez-httparse uriparse chez-srfi; do \
	  check_pin $(SERVER_DIR)/vendor/$$d "$$(recorded $(SERVER_DIR) vendor/$$d)"; \
	done; \
	check_pin $(BYTE_MACHINE_DIR) "$$(recorded $(HTTPARSE_DIR) vendor/byte-machine)"; \
	for d in $(SERVER_DIR) $(LIBUV_DIR) $(HTTPARSE_DIR) $(BYTE_MACHINE_DIR) $(URIPARSE_DIR) $(SRFI_DIR); do \
	  if [ -e "$$d/.git" ] && [ -n "$$(git -C $$d status --porcelain --untracked-files=no 2>/dev/null)" ]; then \
	    echo "PIN DIRTY: $$d has local edits to tracked files" >&2; fail=1; fi; \
	done; \
	exit $$fail

# The import audit is a suite, tests/test-imports.sps, which `make test` runs
# with the others: it reads each library under src/ with Chez's own reader
# and holds its imports to the pure ones (design §2).  This target runs it
# alone.
check-imports: build ## Check each library under src/ imports only (rnrs ...) and pure (websocket ...) ones
	CHEZSCHEMELIBDIRS=$(LIBDIRS) $(CHEZ) --program tests/test-imports.sps

deps: submodules ## Build chez-libuv's shim and link SRFI-64 onto the path
	$(MAKE) -C $(LIBUV_DIR) build
	@mkdir -p $(SRFI_LIBS)/srfi
	@src=$(abspath $(SRFI_DIR)); dst=$(abspath $(SRFI_LIBS))/srfi; \
	for f in $$src/*; do \
	  b=$$(basename "$$f"); \
	  ln -sfn "$$f" "$$dst/$$b"; \
	  d=$$(printf '%s' "$$b" | sed 's/%3a/:/g'); \
	  [ "$$d" = "$$b" ] || ln -sfn "$$f" "$$dst/$$d"; \
	done

build: deps ## Build dependencies and assemble the one library path
	@echo "build: chez-libuv shim built; library path = $(LIBDIRS); the suites' adds $(TEST_ONLY_DIRS)"

dev: build ## Start a REPL with everything on the library path
	CHEZSCHEMELIBDIRS=$(LIBDIRS) $(CHEZ)

run: build ## Run a program on the library path: make run PROGRAM=echo.sps
	@test -n "$(PROGRAM)" || { echo "run: set PROGRAM=path/to/program.sps" >&2; exit 2; }
	CHEZSCHEMELIBDIRS=$(LIBDIRS) $(CHEZ) --program $(PROGRAM)

test: build check-pins ## Run every tests/test-*.sps (status 0/1/2/3, keep-going)
	@test -n "$(TESTS)" || { echo "test: empty selection — no tests/test-*.sps (failure)" >&2; exit 2; }
	@test -n "$(TIMEOUT_BIN)" || echo "note: no timeout(1) on PATH; a hung suite will not be capped"
	@for d in $(TEST_ONLY_DIRS); do \
	  case ":$(LIBDIRS):" in *":$$d:"*) \
	    echo "test: $$d is test code on LIBDIRS, the path make run and make dev use; it belongs on TEST_LIBDIRS alone (decision 0004)" >&2; exit 2;; \
	  esac; \
	done
	@fail=0; \
	for t in $(TESTS); do \
	  echo "=== $$t ==="; \
	  env $(foreach v,$(WS_ENV_VARS),-u $(v)) CHEZSCHEMELIBDIRS=$(TEST_LIBDIRS) $(TIMEOUT_BIN) $(if $(TIMEOUT_BIN),$(SUITE_TIMEOUT),) $(CHEZ) --program $$t; \
	  rc=$$?; \
	  if [ $$rc -eq 124 ] && [ -n "$(TIMEOUT_BIN)" ]; then \
	    echo "HUNG: $$t exceeded $(SUITE_TIMEOUT)s and was killed" >&2; fail=1; \
	  elif [ $$rc -ne 0 ]; then echo "suite $$t exited $$rc" >&2; fail=1; fi; \
	done; \
	if [ $$fail -eq 0 ]; then echo "ALL SUITES PASSED"; else echo "SUITE FAILED"; fi; \
	exit $$fail

# chez-libuv builds its shim dev (debug counters, -O0) unless FLAVOR=prod, and
# relinks it whenever a build asks for the other flavor. So the suite runs with
# FLAVOR=prod, which make hands down to chez-libuv's build; and since check-prod
# reads whatever shim the last build left, the second one proves the suite ran
# on the prod shim, not on a dev one rebuilt under it. The first line enters
# chez-libuv, inside the server's checkout, before test's build would clone
# either, so prod names submodules itself.
prod: submodules ## Rebuild chez-libuv's shim optimized, run the suite on it, and check it is still the prod one
	$(MAKE) -C $(LIBUV_DIR) prod
	$(MAKE) test FLAVOR=prod
	$(MAKE) -C $(LIBUV_DIR) check-prod

autobahn: build check-pins $(if $(filter container,$(AUTOBAHN_ECHO)),echo-image) ## Run Autobahn's fuzzing client in Docker against tests/autobahn/echo.sps, gated on its verdicts
	@CHEZ=$(CHEZ) LIBDIRS=$(LIBDIRS) IMAGE=$(AUTOBAHN_IMAGE) OUT=$(BUILD_DIR)/autobahn \
	  ECHO_AT=$(AUTOBAHN_ECHO) ECHO_IMAGE=$(AUTOBAHN_ECHO_IMAGE) sh tests/autobahn/run.sh

echo-image: submodules ## Build the Autobahn lane's echo server image, tests/autobahn/echo.Dockerfile
	@test -n "$(CHEZ_FLOOR_VERSION)" || { echo "echo-image: no CHEZ_FLOOR_VERSION in .github/workflows/ci.yml" >&2; exit 2; }
	docker build -q -f tests/autobahn/echo.Dockerfile --build-arg CHEZ_VERSION=$(CHEZ_FLOOR_VERSION) \
	  --build-arg LIBDIRS=$(LIBDIRS) -t $(AUTOBAHN_ECHO_IMAGE) .

docker-smoke: echo-image ## Start the echo image, wait until its HEALTHCHECK says ready, and check it stops cleanly
	@ECHO_IMAGE=$(AUTOBAHN_ECHO_IMAGE) sh tests/autobahn/docker-smoke.sh

clean: ## Remove our build artifacts and the vendored shim
	rm -rf $(BUILD_DIR)
	-$(MAKE) -C $(LIBUV_DIR) clean
