## Summary

<!-- One or two sentences. What changed and why? -->

## Component

- [ ] Windows collector
- [ ] Linux collector
- [ ] Aggregator
- [ ] Schema
- [ ] Docs / samples / CI

## Schema impact

- [ ] No schema change
- [ ] Additive (new optional field) — `docs/SCHEMA.md` updated
- [ ] Breaking — `schema_version` bumped, `docs/SCHEMA.md` updated, both collectors emit the new shape

## Checklist

- [ ] Collectors still run with no external dependencies (no new modules / packages required at runtime on the target host)
- [ ] Failures wrapped in error handling — anything that can break is reported as a `collection_warning`, not a crash
- [ ] No credentials, secrets, or password hashes are collected
- [ ] If a new field is added, it is also represented in at least one synthetic sample under `samples/`
- [ ] Tested on a real host: `_______________` <!-- e.g. "Windows Server 2019, elevated" -->

## Notes for the reviewer

<!-- Anything tricky, surprising, or worth flagging -->
