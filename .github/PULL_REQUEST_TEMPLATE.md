## What

<!-- One or two sentences: what changes, and why. Link the issue if there is one. -->

## Tested on

<!-- CI runs Linux x86-64 only. Say where else you ran `make test`: macOS, arm64. -->

## Checklist

- [ ] `make test` passes locally (`ALL SUITES PASSED`)
- [ ] A behavior change comes with a test I watched fail without it
- [ ] The title is a Conventional Commit (`feat:`, `fix:`, `docs:`, …)
- [ ] `README.org` and `docs/` match, if what users see changed (`make check-site`)
- [ ] `CHANGELOG.md` has an entry under `[Unreleased]`, if users can see the change
- [ ] A verdict that moved is updated in `tests/autobahn/verdicts.txt`, with the reason above (`make autobahn`)
- [ ] A moved server pin is on a commit of its own, with `SERVER_PIN` (`make check-pins`)
