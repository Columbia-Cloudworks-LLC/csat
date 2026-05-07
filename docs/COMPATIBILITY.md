# CSAT Compatibility Matrix

This is the live tested-platform matrix. Status reflects what the maintainer (or a contributor) has actually exercised — not what *should* work in theory.

| Status | Meaning |
|---|---|
| ✅ Tested | Run on a real install; output validated against the schema |
| 🟡 Expected | Should work based on the runtime in use, but not yet verified |
| 🔴 Not yet | On the roadmap; collector does not target this platform yet |
| ⚫ Out of scope | Not on the roadmap (see [`ROADMAP.md`](ROADMAP.md)) |

## Windows

| Platform                                   | PS / runtime           | Collector              | v1.0 | v1.1 | v1.2 |
|--------------------------------------------|------------------------|------------------------|------|------|------|
| Windows Server 2025                        | PowerShell 5.1 / 7+    | `csat-collect.ps1`     | 🟡   |      |      |
| Windows Server 2022                        | PowerShell 5.1         | `csat-collect.ps1`     | 🟡   |      |      |
| Windows Server 2019                        | PowerShell 5.1         | `csat-collect.ps1`     | 🟡   |      |      |
| Windows Server 2016                        | PowerShell 5.1         | `csat-collect.ps1`     | 🟡   |      |      |
| Windows Server 2012 R2                     | PowerShell 4.0 → 5.1   | `csat-collect.ps1`     | 🟡   |      |      |
| Windows 11                                 | PowerShell 5.1 / 7+    | `csat-collect.ps1`     | 🟡   |      |      |
| Windows 10                                 | PowerShell 5.1         | `csat-collect.ps1`     | 🟡   |      |      |
| Windows Server 2012                        | PowerShell 3.0         |                        | 🔴   | 🟡   |      |
| Windows Server 2008 R2 SP1                 | PowerShell 2.0 → 4.0   | `legacy/csat-collect-ps2.ps1` | 🔴 | 🟡 |      |
| Windows Server 2008 SP2                    | PowerShell 2.0         | `legacy/csat-collect-ps2.ps1` | 🔴 | 🟡 |      |
| Windows Server 2003 R2 SP2                 | VBScript / WSH 5.7     | `legacy/csat-collect.cmd` + `.vbs` | 🔴 |    | 🟡  |
| Windows Server 2003 SP2                    | VBScript / WSH 5.7     | `legacy/csat-collect.cmd` + `.vbs` | 🔴 |    | 🟡  |
| Windows 2000 Server SP4                    | VBScript / WSH 5.6     | `legacy/csat-collect.cmd` + `.vbs` | 🔴 |    | 🟡  |
| Windows NT 4.0                             | WSH 1.0 (limited WMI)  | (contributor only)     | ⚫   | ⚫   | ⚫   |

The maintainer runs all Windows targets as VMs on consumer Windows hardware. CI's `windows-latest` runner only validates that the v1.0 PowerShell collector parses cleanly — actual execution on legacy targets is verified locally and reported in PR descriptions.

## Linux

| Platform                                   | Init system     | Bash      | Collector            | v1.0 | v1.3 |
|--------------------------------------------|-----------------|-----------|----------------------|------|------|
| Ubuntu 24.04 LTS                           | systemd         | bash 5.x  | `csat-collect.sh`    | ✅   |      |
| Ubuntu 22.04 LTS                           | systemd         | bash 5.x  | `csat-collect.sh`    | 🟡   |      |
| Ubuntu 20.04 LTS                           | systemd         | bash 5.x  | `csat-collect.sh`    | 🟡   |      |
| Debian 13 (trixie)                         | systemd         | bash 5.x  | `csat-collect.sh`    | ✅   |      |
| Debian 12 / 11                             | systemd         | bash 5.x  | `csat-collect.sh`    | 🟡   |      |
| RHEL / Rocky / Alma 9                      | systemd         | bash 5.x  | `csat-collect.sh`    | 🟡   |      |
| RHEL / Rocky / CentOS 8                    | systemd         | bash 4.x  | `csat-collect.sh`    | 🟡   |      |
| RHEL / CentOS 7                            | systemd         | bash 4.x  | `csat-collect.sh`    | 🟡   |      |
| openSUSE Leap 15                           | systemd         | bash 4.x  | `csat-collect.sh`    | 🟡   |      |
| RHEL / CentOS 6                            | SysV / Upstart  | bash 4.x  | `csat-collect.sh` (degraded) | 🔴 | 🟡 |
| Ubuntu 12.04 / 14.04                       | Upstart         | bash 4.x  | `csat-collect.sh` (degraded) | 🔴 | 🟡 |
| Debian 7 / 8                               | SysV → systemd  | bash 4.x  | `csat-collect.sh` (degraded) | 🔴 | 🟡 |
| RHEL / CentOS 5                            | SysV            | bash 3.x  | (contributor)        | 🔴   | 🟡   |

## Other platforms

Out of scope for the maintainer's roadmap; **contributions welcome.** See "How to help" in [`ROADMAP.md`](ROADMAP.md).

| Platform                | Notes                                                          | Status |
|-------------------------|----------------------------------------------------------------|--------|
| ESXi 7+ (standalone)    | esxcli / shell — useful when inheriting hosts without vCenter  | ⚫     |
| macOS (sysadmin / endpoint) | bash/zsh + `system_profiler` + `sw_vers`                   | ⚫     |
| FreeBSD / OpenBSD       | sh + `sysctl` + `pkg info`                                     | ⚫     |
| Solaris 10/11           | ksh + `prtconf` + `psrinfo`                                    | ⚫     |
| AIX                     | ksh + `lsattr` + `lparstat`                                    | ⚫     |
| IBM i (AS/400)          | DSPSYSSTS / WRKACTJOB — likely needs PASE bash + db2 queries   | ⚫     |
| z/OS USS                | shell + RACF queries                                           | ⚫     |

## How to update this matrix

When you successfully run a collector on a platform:

1. Open a PR moving that row from 🟡 → ✅
2. In the PR description, paste:
   - Output of `collector.platform` and `csat_version` from the snapshot
   - The full `collection_warnings` array
   - Anything you had to install or work around to get it running
3. The maintainer will merge after sanity-checking the schema conformance of an attached (redacted) snapshot.
