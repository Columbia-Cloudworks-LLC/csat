# Contributing to CSAT

Thanks for considering a contribution. CSAT is a working tool used in the field, so we keep the bar simple and high.

## Principles

1. **No external runtime dependencies on collectors.** A Windows admin should be able to copy `csat-collect.ps1` into a session and run it on Server 2012 R2 with no module installs. Same constraint on Linux: bash + standard userspace.
2. **No credentials, secrets, or password hashes are ever collected.** Ever.
3. **Failures are warnings, not crashes.** Wrap every collection block in error handling and append to `collection_warnings`.
4. **Schema is contract.** If you add a field, update `docs/SCHEMA.md`. If the change is breaking, bump `schema_version`.

## Repo layout

```
collectors/        Single-file collector scripts, one per platform.
aggregator/        Python CLI that turns snapshots into a matrix.
docs/              Schema + roadmap.
samples/           Synthetic snapshots and a generator for testing.
tests/             Place for future automated tests.
```

## Running the aggregator

```bash
pip install -r aggregator/requirements.txt
python aggregator/csat build samples/snapshots -o /tmp/matrix.xlsx
```

## Adding a field to the schema

1. Add it to both collectors with safe defaults.
2. Update `docs/SCHEMA.md`.
3. If it should appear in the matrix, add it to the appropriate row builder in `aggregator/csat`.
4. Add a value to one of the synthetic samples in `samples/generate_samples.py`.

## Style

- PowerShell: PS 5.1 compatible. No `#Requires -Modules`. Use `Get-CimInstance`, not `Get-WmiObject`.
- Bash: `set -u`. Quote everything. Test on Debian + RHEL families.
- Python: 3.8+. stdlib only except `openpyxl`. Type hints on public functions.

## Issues

Bug reports should include:

- Platform + version
- Whether the collector was run elevated
- The `collection_warnings` array from the snapshot
- A redacted snippet showing the failure

## License

By contributing, you agree your contributions are licensed under MIT.
