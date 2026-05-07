<#
.SYNOPSIS
    CSAT - Computer Situational Awareness Tool. Windows collector.

.DESCRIPTION
    Collects normalized inventory from a Windows host into a JSON snapshot
    plus a human-readable text brief. No external dependencies. PowerShell 5.1+.

    Run with the highest privilege you have in the environment - typically
    a Domain Admin or local Administrator. The collector reads metadata only.
    It does NOT collect credentials, secrets, or password hashes.

.PARAMETER OutputPath
    Directory to write output files. Defaults to current directory.

.PARAMETER Yes
    Skip the consent prompt. Required for unattended runs.

.EXAMPLE
    .\csat-collect.ps1 -OutputPath C:\Temp -Yes

.NOTES
    Project: CSAT - Computer Situational Awareness Tool
    Owner:   Columbia Cloudworks LLC
    License: MIT
    Schema:  v1
#>

[CmdletBinding()]
param(
    [string]$OutputPath = (Get-Location).Path,
    [switch]$Yes
)

$ErrorActionPreference = 'Continue'
$script:CsatVersion    = '1.0'
$script:SchemaVersion  = 1
$script:Warnings       = New-Object System.Collections.Generic.List[string]

function Add-Warn([string]$msg) { $script:Warnings.Add($msg) | Out-Null }

function Try-Get {
    param([scriptblock]$Block, [string]$Label, $Default = $null)
    try { & $Block }
    catch {
        Add-Warn ("{0}: {1}" -f $Label, $_.Exception.Message)
        return $Default
    }
}

function Test-Elevated {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $p  = New-Object Security.Principal.WindowsPrincipal($id)
        return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

function To-Iso([datetime]$dt) {
    if (-not $dt) { return '' }
    return $dt.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
}

function Show-Banner {
    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host " CSAT - Computer Situational Awareness Tool (Windows)" -ForegroundColor Cyan
    Write-Host " Columbia Cloudworks LLC  |  MIT License  |  v$($script:CsatVersion)" -ForegroundColor Cyan
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host " This tool collects host inventory metadata only:"
    Write-Host "   - Identity, hardware, OS, storage, network"
    Write-Host "   - Roles/features, services, scheduled tasks"
    Write-Host "   - Local accounts and admin group membership"
    Write-Host "   - Shares and patch state"
    Write-Host ""
    Write-Host " It does NOT collect credentials, secrets, or password hashes." -ForegroundColor Yellow
    Write-Host " Output is written to a JSON file and a human-readable .txt brief."
    Write-Host "================================================================" -ForegroundColor Cyan
}

# ---------- Collection sections ----------

function Get-IdentityInfo {
    $cs  = Try-Get { Get-CimInstance Win32_ComputerSystem }       'identity.cs'
    $os  = Try-Get { Get-CimInstance Win32_OperatingSystem }      'identity.os'
    $tz  = Try-Get { Get-CimInstance Win32_TimeZone }             'identity.tz'
    $guid = Try-Get { (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name MachineGuid -EA Stop).MachineGuid } 'identity.guid' ''

    $hostname = $env:COMPUTERNAME
    $fqdn = $hostname
    if ($cs -and $cs.Domain -and $cs.PartOfDomain) { $fqdn = "$hostname.$($cs.Domain)" }

    $lastBoot = $null
    $uptime = 0
    if ($os) {
        $lastBoot = $os.LastBootUpTime
        if ($lastBoot) { $uptime = [int]((Get-Date) - $lastBoot).TotalSeconds }
    }

    return [ordered]@{
        hostname            = $hostname
        fqdn                = $fqdn
        domain_or_workgroup = if ($cs) { $cs.Domain } else { '' }
        machine_guid        = $guid
        os_name             = if ($os) { $os.Caption } else { '' }
        os_version          = if ($os) { $os.Version } else { '' }
        os_build            = if ($os) { $os.BuildNumber } else { '' }
        kernel              = ''
        install_date        = if ($os -and $os.InstallDate) { To-Iso $os.InstallDate } else { '' }
        last_boot_utc       = if ($lastBoot) { To-Iso $lastBoot } else { '' }
        uptime_seconds      = $uptime
        timezone            = if ($tz) { $tz.StandardName } else { '' }
    }
}

function Get-HardwareInfo {
    $cs   = Try-Get { Get-CimInstance Win32_ComputerSystem } 'hw.cs'
    $bios = Try-Get { Get-CimInstance Win32_BIOS }           'hw.bios'
    $cpus = Try-Get { @(Get-CimInstance Win32_Processor) }   'hw.cpu' @()

    $cores   = 0; $logical = 0; $cpuModel = ''
    foreach ($c in $cpus) {
        $cores   += [int]$c.NumberOfCores
        $logical += [int]$c.NumberOfLogicalProcessors
        if (-not $cpuModel) { $cpuModel = $c.Name }
    }

    $memGb = 0.0
    if ($cs -and $cs.TotalPhysicalMemory) {
        $memGb = [math]::Round($cs.TotalPhysicalMemory / 1GB, 2)
    }

    $isVirtual = $false; $hypervisor = ''
    if ($cs) {
        $model = "$($cs.Model)"
        $manuf = "$($cs.Manufacturer)"
        if ($model -match 'Virtual|VMware|VirtualBox' -or $manuf -match 'VMware|Microsoft Corporation|innotek|QEMU|Xen') {
            $isVirtual = $true
            if ($model -match 'VMware' -or $manuf -match 'VMware') { $hypervisor = 'VMware' }
            elseif ($model -match 'Virtual Machine' -and $manuf -match 'Microsoft') { $hypervisor = 'Hyper-V' }
            elseif ($manuf -match 'innotek') { $hypervisor = 'VirtualBox' }
            elseif ($manuf -match 'QEMU') { $hypervisor = 'KVM' }
            elseif ($manuf -match 'Xen') { $hypervisor = 'Xen' }
        }
    }

    return [ordered]@{
        manufacturer = if ($cs) { $cs.Manufacturer } else { '' }
        model        = if ($cs) { $cs.Model } else { '' }
        serial       = if ($bios) { $bios.SerialNumber } else { '' }
        bios_version = if ($bios) { ($bios.SMBIOSBIOSVersion) } else { '' }
        cpu_model    = $cpuModel
        cpu_sockets  = $cpus.Count
        cpu_cores    = $cores
        cpu_logical  = $logical
        memory_gb    = $memGb
        is_virtual   = $isVirtual
        hypervisor   = $hypervisor
    }
}

function Get-StorageInfo {
    $disks = Try-Get { @(Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3") } 'storage' @()
    $out = @()
    foreach ($d in $disks) {
        $size = if ($d.Size) { [math]::Round($d.Size / 1GB, 2) } else { 0 }
        $free = if ($d.FreeSpace) { [math]::Round($d.FreeSpace / 1GB, 2) } else { 0 }
        $pct  = if ($size -gt 0) { [math]::Round(($free / $size) * 100, 2) } else { 0 }
        $out += [ordered]@{
            device          = $d.DeviceID
            mount_or_letter = $d.DeviceID
            filesystem      = $d.FileSystem
            size_gb         = $size
            free_gb         = $free
            percent_free    = $pct
        }
    }
    return ,$out
}

function Get-NetworkInfo {
    $adapters = Try-Get { @(Get-CimInstance Win32_NetworkAdapterConfiguration -Filter "IPEnabled=true") } 'network.cfg' @()
    $nics     = Try-Get { @(Get-CimInstance Win32_NetworkAdapter -Filter "NetEnabled=true") } 'network.adapters' @()
    $out = @()
    foreach ($a in $adapters) {
        $nic = $nics | Where-Object { $_.DeviceID -eq $a.Index } | Select-Object -First 1
        $speed = 0
        if ($nic -and $nic.Speed) { $speed = [int]([int64]$nic.Speed / 1000000) }

        $ipv4 = @(); $ipv6 = @(); $subnet = @()
        if ($a.IPAddress) {
            foreach ($ip in $a.IPAddress) {
                if ($ip -match ':') { $ipv6 += $ip } else { $ipv4 += $ip }
            }
        }
        if ($a.IPSubnet) { $subnet = @($a.IPSubnet) }

        $out += [ordered]@{
            interface       = $a.Description
            mac             = $a.MACAddress
            ipv4            = $ipv4
            ipv6            = $ipv6
            subnet          = $subnet
            gateway         = if ($a.DefaultIPGateway) { @($a.DefaultIPGateway) } else { @() }
            dns_servers     = if ($a.DNSServerSearchOrder) { @($a.DNSServerSearchOrder) } else { @() }
            dhcp_enabled    = [bool]$a.DHCPEnabled
            link_speed_mbps = $speed
        }
    }
    return ,$out
}

function Get-RolesFeatures {
    $out = New-Object System.Collections.Generic.List[string]
    # Server SKUs
    $sku = Try-Get { (Get-CimInstance Win32_OperatingSystem).ProductType } 'roles.sku' 1
    if ($sku -ne 1) {
        Try-Get {
            if (Get-Command Get-WindowsFeature -ErrorAction SilentlyContinue) {
                Get-WindowsFeature | Where-Object { $_.Installed } | ForEach-Object {
                    $out.Add($_.Name) | Out-Null
                }
            }
        } 'roles.windowsfeature' | Out-Null
    }
    # Optional features (works on client + server)
    Try-Get {
        if (Get-Command Get-WindowsOptionalFeature -ErrorAction SilentlyContinue) {
            Get-WindowsOptionalFeature -Online -ErrorAction Stop |
                Where-Object { $_.State -eq 'Enabled' } |
                ForEach-Object { $out.Add("optional:$($_.FeatureName)") | Out-Null }
        }
    } 'roles.optional' | Out-Null
    return ,@($out | Select-Object -Unique)
}

function Get-ServicesInfo {
    $svcs = Try-Get { @(Get-CimInstance Win32_Service) } 'services' @()
    $out = @()
    foreach ($s in $svcs) {
        $out += [ordered]@{
            name         = $s.Name
            display_name = $s.DisplayName
            state        = ($s.State + '').ToLower()
            start_mode   = ($s.StartMode + '').ToLower()
            account      = $s.StartName
        }
    }
    return ,$out
}

function Get-ScheduledTasksInfo {
    $out = @()
    if (-not (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue)) {
        Add-Warn 'scheduled_tasks: Get-ScheduledTask not available'
        return ,$out
    }
    $tasks = Try-Get { @(Get-ScheduledTask) } 'tasks.list' @()
    foreach ($t in $tasks) {
        $info = Try-Get { $t | Get-ScheduledTaskInfo } 'tasks.info'
        $action = ''
        if ($t.Actions -and $t.Actions.Count -gt 0) {
            $a = $t.Actions[0]
            if ($a.Execute) { $action = $a.Execute }
            if ($a.Arguments) { $action = "$action $($a.Arguments)".Trim() }
        }
        $runAs = ''
        if ($t.Principal) { $runAs = $t.Principal.UserId }

        $last = ''; $next = ''
        if ($info) {
            if ($info.LastRunTime -and $info.LastRunTime.Year -gt 1900) { $last = To-Iso $info.LastRunTime }
            if ($info.NextRunTime -and $info.NextRunTime.Year -gt 1900) { $next = To-Iso $info.NextRunTime }
        }

        $out += [ordered]@{
            name      = $t.TaskName
            path      = $t.TaskPath
            state     = "$($t.State)".ToLower()
            last_run  = $last
            next_run  = $next
            run_as    = $runAs
            action    = $action
        }
    }
    return ,$out
}

function Get-LocalAccountsInfo {
    $out = @()
    $admins = New-Object System.Collections.Generic.List[string]

    if (Get-Command Get-LocalUser -ErrorAction SilentlyContinue) {
        $users = Try-Get { @(Get-LocalUser) } 'accounts.users' @()
        $adminMembers = Try-Get { @(Get-LocalGroupMember -Group 'Administrators' -ErrorAction Stop) } 'accounts.adminmembers' @()
        $adminNames = $adminMembers | ForEach-Object { ($_.Name -split '\\')[-1] }
        foreach ($n in $adminMembers) { $admins.Add($n.Name) | Out-Null }

        foreach ($u in $users) {
            $isAdmin = $adminNames -contains $u.Name
            $pwAge = -1
            if ($u.PasswordLastSet) { $pwAge = [int]((Get-Date) - $u.PasswordLastSet).TotalDays }
            $last = ''
            if ($u.LastLogon -and $u.LastLogon.Year -gt 1900) { $last = To-Iso $u.LastLogon }
            $out += [ordered]@{
                name              = $u.Name
                enabled           = [bool]$u.Enabled
                is_admin          = $isAdmin
                last_logon        = $last
                password_age_days = $pwAge
            }
        }
    } else {
        # Fallback: WMI
        $users = Try-Get { @(Get-CimInstance Win32_UserAccount -Filter "LocalAccount=true") } 'accounts.wmi' @()
        foreach ($u in $users) {
            $out += [ordered]@{
                name              = $u.Name
                enabled           = -not [bool]$u.Disabled
                is_admin          = $false
                last_logon        = ''
                password_age_days = -1
            }
        }
        Add-Warn 'accounts: Get-LocalUser unavailable, used WMI fallback (is_admin not resolved).'
    }

    return @{ accounts = ,$out; admins = ,@($admins | Select-Object -Unique) }
}

function Get-SharesInfo {
    $shares = Try-Get { @(Get-CimInstance Win32_Share) } 'shares' @()
    $out = @()
    foreach ($s in $shares) {
        # Skip default admin shares from the headline list - they are noise
        if ($s.Name -match '\$$' -and $s.Name -ne 'IPC$') { continue }
        $out += [ordered]@{
            name        = $s.Name
            path        = $s.Path
            description = $s.Description
        }
    }
    return ,$out
}

function Get-PatchesInfo {
    $hotfixes = Try-Get { @(Get-CimInstance Win32_QuickFixEngineering) } 'patches.qfe' @()
    $sorted = $hotfixes | Where-Object { $_.InstalledOn } | Sort-Object InstalledOn -Descending
    $recent = @()
    $last = ''
    if ($sorted.Count -gt 0) {
        $last = To-Iso ([datetime]$sorted[0].InstalledOn)
        $recent = $sorted | Select-Object -First 10 | ForEach-Object { "$($_.HotFixID) ($([datetime]$_.InstalledOn | Get-Date -Format 'yyyy-MM-dd'))" }
    }

    $pending = $false
    Try-Get {
        $keys = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
        )
        foreach ($k in $keys) {
            if (Test-Path $k) { $pending = $true }
        }
    } 'patches.pending' | Out-Null

    return [ordered]@{
        last_update_utc          = $last
        pending_reboot           = $pending
        recent_kbs_or_packages   = ,@($recent)
    }
}

# ---------- Human-readable brief ----------

function Write-Brief {
    param($Snapshot, [string]$Path)
    $i = $Snapshot.identity
    $h = $Snapshot.hardware
    $sb = New-Object System.Text.StringBuilder
    $null = $sb.AppendLine("CSAT Snapshot - $($i.hostname)")
    $null = $sb.AppendLine("Collected: $($Snapshot.collected_at_utc)  |  Schema v$($Snapshot.schema_version)  |  CSAT v$($Snapshot.csat_version)")
    $null = $sb.AppendLine(("=" * 72))
    $null = $sb.AppendLine("IDENTITY")
    $null = $sb.AppendLine("  FQDN:        $($i.fqdn)")
    $null = $sb.AppendLine("  Domain:      $($i.domain_or_workgroup)")
    $null = $sb.AppendLine("  OS:          $($i.os_name) ($($i.os_version) build $($i.os_build))")
    $null = $sb.AppendLine("  Installed:   $($i.install_date)")
    $null = $sb.AppendLine("  Last boot:   $($i.last_boot_utc)  (uptime $([int]($i.uptime_seconds/3600)) h)")
    $null = $sb.AppendLine("  Timezone:    $($i.timezone)")
    $null = $sb.AppendLine("")
    $null = $sb.AppendLine("HARDWARE")
    $null = $sb.AppendLine("  Vendor:      $($h.manufacturer) / $($h.model)")
    $null = $sb.AppendLine("  Serial:      $($h.serial)")
    $null = $sb.AppendLine("  CPU:         $($h.cpu_model)  ($($h.cpu_sockets) sockets / $($h.cpu_cores) cores / $($h.cpu_logical) logical)")
    $null = $sb.AppendLine("  Memory:      $($h.memory_gb) GB")
    $null = $sb.AppendLine("  Virtual:     $($h.is_virtual)  $($h.hypervisor)")
    $null = $sb.AppendLine("")
    $null = $sb.AppendLine("STORAGE")
    foreach ($d in $Snapshot.storage) {
        $null = $sb.AppendLine(("  {0,-6} {1,-6} {2,8} GB total  {3,8} GB free  ({4}% free)" -f $d.mount_or_letter, $d.filesystem, $d.size_gb, $d.free_gb, $d.percent_free))
    }
    $null = $sb.AppendLine("")
    $null = $sb.AppendLine("NETWORK")
    foreach ($n in $Snapshot.network) {
        $ipline = ($n.ipv4 -join ', ')
        $null = $sb.AppendLine(("  {0}  MAC {1}  IP {2}  GW {3}  DHCP {4}" -f $n.interface, $n.mac, $ipline, ($n.gateway -join ','), $n.dhcp_enabled))
    }
    $null = $sb.AppendLine("")
    $null = $sb.AppendLine("ROLES / FEATURES (top 20)")
    $rolesSubset = @($Snapshot.roles_features | Select-Object -First 20)
    foreach ($r in $rolesSubset) { $null = $sb.AppendLine("  - $r") }
    $null = $sb.AppendLine("")
    $null = $sb.AppendLine("LOCAL ADMINISTRATORS")
    foreach ($a in $Snapshot.admin_group_members) { $null = $sb.AppendLine("  - $a") }
    $null = $sb.AppendLine("")
    $null = $sb.AppendLine("SHARES")
    foreach ($s in $Snapshot.shares) { $null = $sb.AppendLine(("  {0,-20} {1}" -f $s.name, $s.path)) }
    $null = $sb.AppendLine("")
    $null = $sb.AppendLine("PATCHES")
    $null = $sb.AppendLine("  Last update:    $($Snapshot.patches.last_update_utc)")
    $null = $sb.AppendLine("  Pending reboot: $($Snapshot.patches.pending_reboot)")
    $null = $sb.AppendLine("")
    if ($Snapshot.collection_warnings.Count -gt 0) {
        $null = $sb.AppendLine("WARNINGS")
        foreach ($w in $Snapshot.collection_warnings) { $null = $sb.AppendLine("  ! $w") }
    }

    [System.IO.File]::WriteAllText($Path, $sb.ToString(), [System.Text.UTF8Encoding]::new($false))
}

# ---------- Main ----------

Show-Banner

if (-not $Yes) {
    $resp = Read-Host "Proceed with collection? [y/N]"
    if ($resp -notmatch '^(y|Y)') { Write-Host "Aborted."; exit 1 }
}

$elevated = Test-Elevated
if (-not $elevated) {
    Add-Warn 'Process is NOT elevated. Some sections will be incomplete.'
    Write-Host "WARNING: not running as Administrator. Output will be incomplete." -ForegroundColor Yellow
}

if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

Write-Host "Collecting..." -ForegroundColor Green

$identity = Get-IdentityInfo
$hardware = Get-HardwareInfo
$storage  = Get-StorageInfo
$network  = Get-NetworkInfo
$roles    = Get-RolesFeatures
$services = Get-ServicesInfo
$tasks    = Get-ScheduledTasksInfo
$accInfo  = Get-LocalAccountsInfo
$shares   = Get-SharesInfo
$patches  = Get-PatchesInfo

$snapshot = [ordered]@{
    csat_version         = $script:CsatVersion
    schema_version       = $script:SchemaVersion
    collected_at_utc     = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    collector            = [ordered]@{
        platform        = 'windows'
        script_version  = $script:CsatVersion
        run_as          = "$env:USERDOMAIN\$env:USERNAME"
        elevated        = $elevated
    }
    identity             = $identity
    hardware             = $hardware
    storage              = $storage
    network              = $network
    roles_features       = $roles
    services             = $services
    scheduled_tasks      = $tasks
    local_accounts       = $accInfo.accounts
    admin_group_members  = $accInfo.admins
    shares               = $shares
    patches              = $patches
    collection_warnings  = ,@($script:Warnings)
}

$stamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHHmmZ")
$base  = Join-Path $OutputPath ("{0}_{1}" -f $identity.hostname, $stamp)
$jsonPath = "$base.json"
$txtPath  = "$base.txt"

# ConvertTo-Json default depth is 2 - we need much more
$json = $snapshot | ConvertTo-Json -Depth 10
[System.IO.File]::WriteAllText($jsonPath, $json, [System.Text.UTF8Encoding]::new($false))

Write-Brief -Snapshot $snapshot -Path $txtPath

Write-Host ""
Write-Host "Snapshot written:" -ForegroundColor Green
Write-Host "  $jsonPath"
Write-Host "  $txtPath"
if ($script:Warnings.Count -gt 0) {
    Write-Host ""
    Write-Host "Warnings ($($script:Warnings.Count)):" -ForegroundColor Yellow
    $script:Warnings | ForEach-Object { Write-Host "  ! $_" -ForegroundColor Yellow }
}
exit 0
