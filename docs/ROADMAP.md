# CSAT Roadmap

## Philosophy

CSAT exists for the boxes nobody else helps you with: the inherited server with no documentation, no support contract, and no modern agent that runs on it. **Legacy support is a first-class feature, not an afterthought.** Modern tools have abandoned the long tail. CSAT will not.

## Tested platforms (current)

See [`COMPATIBILITY.md`](COMPATIBILITY.md) for the live matrix. The maintainer tests on VMs running on consumer-grade Windows hardware (no enterprise lab). Contributors with access to more platforms are welcome to expand the matrix — see "How to help" below.

## v1.0 — Modern PowerShell baseline (current)

**Status:** released

- Windows collector running on PowerShell 5.1+ (Server 2012 R2 through 2025; Win10/11)
- Linux collector running on bash 4+ (Debian/Ubuntu/RHEL families with systemd)
- Identical `csat-schema v1` JSON output across both platforms
- Python aggregator: `build` / `diff` / `info`

**Known not-yet-supported:** anything older than PowerShell 5.1 on Windows, anything pre-systemd on Linux.

## v1.1 — Legacy Windows: PowerShell 2.0 collector

**Goal:** support Windows Server 2008 R2 through 2012 (PowerShell 2.0 era) without raising the dependency floor for v1.0 users.

- New collector: `collectors/legacy/csat-collect-ps2.ps1`
- PowerShell 2.0 syntax compatible — no advanced parameter binding, no `[ordered]`, no `ConvertTo-Json -Depth`, hand-rolled JSON emitter
- Uses `Get-WmiObject` instead of `Get-CimInstance` (CIM cmdlets land in PS 3.0)
- Detects PS version on launch and self-routes — admin runs the same `.ps1`, gets the right code path
- Same `csat-schema v1` output

**Test targets (VMs on maintainer hardware):**

- Windows Server 2008 R2 SP1 (PS 2.0 default; can be upgraded to 4.0 via WMF)
- Windows Server 2012 (PS 3.0 default)

## v1.2 — Pre-PowerShell Windows: VBScript / batch collector

**Goal:** support Windows 2000, Server 2003, and Server 2003 R2. These boxes predate PowerShell entirely.

- New collector: `collectors/legacy/csat-collect.cmd` — a batch wrapper that calls `csat-collect.vbs`
- VBScript using WMI via `winmgmts:` moniker — works back to Windows 2000
- Hand-rolled JSON emitter in VBScript (no native JSON support in WSH)
- Reduced field set where the OS truly cannot provide the data — fields are emitted as empty strings with a corresponding `collection_warnings` entry, never omitted (the schema stays stable)
- One-line invocation: `cscript //nologo csat-collect.vbs C:\Temp`

**Test targets (VMs on maintainer hardware):**

- Windows 2000 Server SP4
- Windows Server 2003 SP2
- Windows Server 2003 R2 SP2

**Schema impact:** none. Pre-2008 hosts will set `collector.platform = "windows-legacy"` and populate `collector.script_version` accordingly so the aggregator can flag them in the matrix.

## v1.3 — Legacy Linux: pre-systemd

**Goal:** support RHEL/CentOS 5 + 6, Debian 6/7, Ubuntu 10.04/12.04, and other SysV-init era distros.

- Existing `csat-collect.sh` already degrades when systemd is missing; v1.3 hardens this path
- Service enumeration via `chkconfig --list` (RHEL/CentOS 5/6) and `service --status-all` (Debian/Ubuntu pre-systemd)
- Cron-only scheduled task collection (no systemd timers)
- Bash 3.x compatibility audit (macOS-style bash limits, no associative arrays)

**Test targets:** CentOS 6, Ubuntu 12.04, Debian 7 VMs on maintainer hardware.

## v1.4 — Quality of life

- Windows collector signed with a Columbia Cloudworks code-signing cert (release artifacts)
- `--exclude` flags on collectors to skip slow sections (e.g. `--no-services`, `--no-tasks`)
- Aggregator `--history` mode keeping all snapshots per host (already implemented as a flag; needs UI polish)
- Aggregator HTML report option
- Optional output encryption: AES-256 bundle with passphrase, for safe email/transfer of snapshots between teams

## v2.0 — Role-aware deep dive

Adds depth to the collection. All platforms supported by v1.x continue to work; new fields are additive (`schema_version` bumps to 2 only for breaking changes).

- Active Directory Domain Services health (if DC)
- DHCP scopes and reservations
- DNS zones and forwarders
- IIS sites, app pools, bindings, and host headers
- SQL Server instances and databases
- File share NTFS permissions (top N levels)
- Certificate inventory (computer + user stores)
- Windows Firewall rule export
- WSUS / SCCM client state
- Linux: systemd unit deep inspection, package repository config, sudoers parsing

## v3.0 — Dependency mapping

The "what does this server actually do for the rest of the network" layer.

- Established TCP connections with owning process (`netstat -anob` / `ss -tnp`)
- Listening ports → service mapping
- Scheduled task → script path resolution and content hashing
- Service account inventory across hosts (which boxes use which AD service account)
- Applied GPO set (`gpresult /h`)
- Cross-host correlation in the aggregator (this server depends on that one)

## Out of scope (please do not file issues for these)

- Continuous monitoring — use an RMM
- Configuration management — use Ansible / DSC / Puppet
- Vulnerability scanning — use a scanner
- Phoning home, telemetry, or cloud sync — never. CSAT is offline by design.
- Platforms the maintainer cannot test on consumer hardware (mainframe, AS/400, ESXi clusters, Solaris, AIX, HP-UX, NetWare). **Contributors with access to those platforms are welcome to add support — see "How to help."**

## How to help

If you have access to a platform CSAT does not yet support and want to contribute a collector:

1. Open a feature request issue tagged `platform:<name>` describing the OS, scripting environments available, and what you can test against
2. Implement a collector that emits the existing `csat-schema v1` JSON shape — additive only, no breaking changes
3. Add at least one synthetic sample to `samples/` so CI can exercise the aggregator path
4. Document the platform under `docs/COMPATIBILITY.md`

Platforms the maintainer would love to see contributed but cannot personally test:

- ESXi shell collection (standalone hosts inherited without vCenter)
- macOS server / endpoint
- FreeBSD / OpenBSD
- Solaris 10/11
- AIX
- IBM i (AS/400)
- z/OS USS
