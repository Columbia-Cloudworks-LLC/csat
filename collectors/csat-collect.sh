#!/usr/bin/env bash
# CSAT - Computer Situational Awareness Tool. Linux collector.
#
# Collects normalized inventory from a Linux host into a JSON snapshot
# plus a human-readable text brief. No external dependencies beyond
# coreutils + procps + iproute2 + (optionally) systemd. Bash 4+.
#
# Run as root (or via sudo). The collector reads metadata only.
# It does NOT collect credentials, secrets, or password hashes.
#
# Usage:  sudo ./csat-collect.sh [-o OUTPUT_DIR] [-y]
#
# Project: CSAT - Computer Situational Awareness Tool
# Owner:   Columbia Cloudworks LLC
# License: MIT
# Schema:  v1

set -u

CSAT_VERSION="1.0"
SCHEMA_VERSION=1
OUTPUT_PATH="$(pwd)"
ASSUME_YES=0
WARNINGS=()

usage() {
    cat <<EOF
CSAT Linux Collector v${CSAT_VERSION}

Usage: sudo $0 [-o OUTPUT_DIR] [-y]

  -o DIR    Directory to write output files (default: cwd)
  -y        Skip the consent prompt (unattended mode)
  -h        Show this help

EOF
}

while getopts ":o:yh" opt; do
    case $opt in
        o) OUTPUT_PATH="$OPTARG" ;;
        y) ASSUME_YES=1 ;;
        h) usage; exit 0 ;;
        \?) echo "Invalid option: -$OPTARG" >&2; usage; exit 2 ;;
    esac
done

warn() { WARNINGS+=("$1"); }
have() { command -v "$1" >/dev/null 2>&1; }

# JSON helpers - no jq dependency.
json_escape() {
    # Escape for JSON string content. Reads stdin or $1.
    local s
    if [ $# -gt 0 ]; then s="$1"; else s="$(cat)"; fi
    # Order matters: backslash first.
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    # Strip remaining control chars
    s="$(printf '%s' "$s" | tr -d '\000-\010\013\014\016-\037')"
    printf '%s' "$s"
}

json_str() { printf '"%s"' "$(json_escape "${1-}")"; }
json_bool() { if [ "${1:-0}" = "1" ] || [ "${1:-}" = "true" ]; then printf 'true'; else printf 'false'; fi; }
json_num() { local n="${1:-0}"; if [[ "$n" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then printf '%s' "$n"; else printf '0'; fi; }

# Build a JSON array of strings from arguments.
json_str_array() {
    local first=1 out="["
    for v in "$@"; do
        if [ $first -eq 1 ]; then first=0; else out+=","; fi
        out+="$(json_str "$v")"
    done
    out+="]"
    printf '%s' "$out"
}

show_banner() {
    cat <<'EOF'

================================================================
 CSAT - Computer Situational Awareness Tool (Linux)
 Columbia Cloudworks LLC  |  MIT License
================================================================
 This tool collects host inventory metadata only:
   - Identity, hardware, OS, storage, network
   - Detected services (systemd units), cron + systemd timers
   - Local accounts and sudo/wheel membership
   - NFS/Samba exports and patch state

 It does NOT collect credentials, secrets, or password hashes.
 Output is written to a JSON file and a human-readable .txt brief.
================================================================
EOF
}

# ---------- Collection ----------

iso_now() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
iso_from_epoch() {
    local e="${1:-0}"
    if [ "$e" -gt 0 ] 2>/dev/null; then date -u -d "@$e" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo ""; else echo ""; fi
}

collect_identity() {
    local hostname fqdn domain os_name os_version os_build kernel install_date last_boot uptime tz machine_guid

    hostname="$(hostname -s 2>/dev/null || echo "$HOSTNAME")"
    fqdn="$(hostname -f 2>/dev/null || echo "$hostname")"
    domain="$(hostname -d 2>/dev/null || echo "")"
    [ -z "$domain" ] && domain="workgroup"

    if [ -r /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        os_name="${PRETTY_NAME:-$NAME}"
        os_version="${VERSION_ID:-}"
        os_build="${BUILD_ID:-${VERSION:-}}"
    else
        os_name="$(uname -s)"
        os_version="$(uname -r)"
        os_build=""
        warn "identity: /etc/os-release missing"
    fi

    kernel="$(uname -r)"

    if [ -r /etc/machine-id ]; then
        machine_guid="$(cat /etc/machine-id)"
    elif [ -r /var/lib/dbus/machine-id ]; then
        machine_guid="$(cat /var/lib/dbus/machine-id)"
    else
        machine_guid=""
        warn "identity: machine-id not readable"
    fi

    # Install date best-effort: rootfs creation time, or earliest of /etc/hostname.
    if have stat; then
        local cd
        cd="$(stat -c %W / 2>/dev/null || echo 0)"
        if [ "$cd" -gt 0 ] 2>/dev/null; then
            install_date="$(iso_from_epoch "$cd")"
        else
            install_date="$(stat -c %y /etc/hostname 2>/dev/null | cut -d. -f1 | tr ' ' 'T' | sed 's/$/Z/' || echo "")"
        fi
    else
        install_date=""
    fi

    if have uptime; then
        uptime="$(awk '{print int($1)}' /proc/uptime 2>/dev/null || echo 0)"
    else
        uptime=0
    fi

    if [ "$uptime" -gt 0 ]; then
        local now boot_epoch
        now="$(date -u +%s)"
        boot_epoch=$((now - uptime))
        last_boot="$(iso_from_epoch "$boot_epoch")"
    else
        last_boot=""
    fi

    if [ -r /etc/timezone ]; then
        tz="$(cat /etc/timezone)"
    elif have timedatectl; then
        tz="$(timedatectl show --property=Timezone --value 2>/dev/null || echo "")"
    else
        tz=""
    fi

    cat <<EOF
"identity":{"hostname":$(json_str "$hostname"),"fqdn":$(json_str "$fqdn"),"domain_or_workgroup":$(json_str "$domain"),"machine_guid":$(json_str "$machine_guid"),"os_name":$(json_str "$os_name"),"os_version":$(json_str "$os_version"),"os_build":$(json_str "$os_build"),"kernel":$(json_str "$kernel"),"install_date":$(json_str "$install_date"),"last_boot_utc":$(json_str "$last_boot"),"uptime_seconds":$(json_num "$uptime"),"timezone":$(json_str "$tz")}
EOF
}

collect_hardware() {
    local manuf="" model="" serial="" bios="" cpu_model="" sockets=0 cores=0 logical=0 mem_gb=0 is_virtual="false" hypervisor=""

    if [ -r /sys/class/dmi/id/sys_vendor ]; then manuf="$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null)"; fi
    if [ -r /sys/class/dmi/id/product_name ]; then model="$(cat /sys/class/dmi/id/product_name 2>/dev/null)"; fi
    if [ -r /sys/class/dmi/id/product_serial ]; then serial="$(cat /sys/class/dmi/id/product_serial 2>/dev/null)"; fi
    if [ -r /sys/class/dmi/id/bios_version ]; then bios="$(cat /sys/class/dmi/id/bios_version 2>/dev/null)"; fi

    if [ -r /proc/cpuinfo ]; then
        cpu_model="$(awk -F: '/^model name/ {print $2; exit}' /proc/cpuinfo | sed 's/^ //')"
        [ -z "$cpu_model" ] && cpu_model="$(awk -F: '/^Model/ {print $2; exit}' /proc/cpuinfo | sed 's/^ //')"
        logical="$(grep -c '^processor' /proc/cpuinfo)"
        sockets="$(awk -F: '/^physical id/ {print $2}' /proc/cpuinfo | sort -u | wc -l)"
        [ "$sockets" -eq 0 ] && sockets=1
        cores="$(awk -F: '/^cpu cores/ {print $2; exit}' /proc/cpuinfo | tr -d ' ')"
        [ -z "$cores" ] && cores="$logical"
        cores=$((cores * sockets))
    fi

    if [ -r /proc/meminfo ]; then
        local kb
        kb="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)"
        mem_gb="$(awk -v kb="$kb" 'BEGIN{printf "%.2f", kb/1024/1024}')"
    fi

    if have systemd-detect-virt; then
        local v
        v="$(systemd-detect-virt 2>/dev/null || echo none)"
        if [ "$v" != "none" ] && [ -n "$v" ]; then
            is_virtual="true"
            case "$v" in
                vmware) hypervisor="VMware" ;;
                kvm)    hypervisor="KVM" ;;
                microsoft) hypervisor="Hyper-V" ;;
                xen) hypervisor="Xen" ;;
                oracle) hypervisor="VirtualBox" ;;
                *) hypervisor="$v" ;;
            esac
        fi
    fi

    cat <<EOF
"hardware":{"manufacturer":$(json_str "$manuf"),"model":$(json_str "$model"),"serial":$(json_str "$serial"),"bios_version":$(json_str "$bios"),"cpu_model":$(json_str "$cpu_model"),"cpu_sockets":$(json_num "$sockets"),"cpu_cores":$(json_num "$cores"),"cpu_logical":$(json_num "$logical"),"memory_gb":$(json_num "$mem_gb"),"is_virtual":$is_virtual,"hypervisor":$(json_str "$hypervisor")}
EOF
}

collect_storage() {
    local first=1 out="["
    if have df; then
        # POSIX block-size 1K, skip pseudo filesystems
        while IFS= read -r line; do
            local fs size used avail pct mount
            fs="$(echo "$line"   | awk '{print $1}')"
            size="$(echo "$line" | awk '{print $2}')"
            used="$(echo "$line" | awk '{print $3}')"
            avail="$(echo "$line" | awk '{print $4}')"
            mount="$(echo "$line" | awk '{print $6}')"
            local fstype
            fstype="$(echo "$line" | awk '{print $5}')"

            local size_gb avail_gb pct_free
            size_gb="$(awk -v k="$size" 'BEGIN{printf "%.2f", k/1024/1024}')"
            avail_gb="$(awk -v k="$avail" 'BEGIN{printf "%.2f", k/1024/1024}')"
            if [ "$size" -gt 0 ] 2>/dev/null; then
                pct_free="$(awk -v a="$avail" -v s="$size" 'BEGIN{printf "%.2f", (a/s)*100}')"
            else
                pct_free="0"
            fi

            if [ $first -eq 1 ]; then first=0; else out+=","; fi
            out+="{\"device\":$(json_str "$fs"),\"mount_or_letter\":$(json_str "$mount"),\"filesystem\":$(json_str "$fstype"),\"size_gb\":$(json_num "$size_gb"),\"free_gb\":$(json_num "$avail_gb"),\"percent_free\":$(json_num "$pct_free")}"
        done < <(df -PT -x tmpfs -x devtmpfs -x squashfs -x overlay -x proc -x sysfs 2>/dev/null | awk 'NR>1 {print $1, $3, $4, $5, $2, $7}')
    else
        warn "storage: df not available"
    fi
    out+="]"
    printf '"storage":%s' "$out"
}

collect_network() {
    local first=1 out="["
    if have ip; then
        # iterate interfaces (skip loopback)
        local iface
        while IFS= read -r iface; do
            [ "$iface" = "lo" ] && continue
            local mac="" speed=0 dhcp="false"
            if [ -r "/sys/class/net/$iface/address" ]; then mac="$(cat "/sys/class/net/$iface/address")"; fi
            if [ -r "/sys/class/net/$iface/speed" ]; then
                local sp; sp="$(cat "/sys/class/net/$iface/speed" 2>/dev/null)"
                if [[ "$sp" =~ ^[0-9]+$ ]] && [ "$sp" -gt 0 ]; then speed="$sp"; fi
            fi

            # IPs
            local ipv4_arr=() ipv6_arr=() subnet_arr=()
            while IFS= read -r addr; do
                [ -z "$addr" ] && continue
                if [[ "$addr" == *:* ]]; then
                    ipv6_arr+=("$(echo "$addr" | cut -d/ -f1)")
                else
                    ipv4_arr+=("$(echo "$addr" | cut -d/ -f1)")
                    subnet_arr+=("$addr")
                fi
            done < <(ip -o addr show dev "$iface" 2>/dev/null | awk '{print $4}')

            # Default gateway via this iface
            local gw_arr=()
            while IFS= read -r gw; do
                [ -n "$gw" ] && gw_arr+=("$gw")
            done < <(ip route show default 2>/dev/null | awk -v i="$iface" '$5==i {print $3}')

            # DNS
            local dns_arr=()
            if [ -r /etc/resolv.conf ]; then
                while IFS= read -r ns; do
                    dns_arr+=("$ns")
                done < <(awk '/^nameserver/ {print $2}' /etc/resolv.conf)
            fi

            # DHCP heuristic
            if pgrep -f "dhclient.*$iface" >/dev/null 2>&1; then dhcp="true"; fi
            if have nmcli; then
                local m; m="$(nmcli -g IP4.METHOD device show "$iface" 2>/dev/null || echo "")"
                if [ "$m" = "auto" ]; then dhcp="true"; fi
            fi

            if [ $first -eq 1 ]; then first=0; else out+=","; fi
            out+="{\"interface\":$(json_str "$iface"),\"mac\":$(json_str "$mac"),\"ipv4\":$(json_str_array "${ipv4_arr[@]}"),\"ipv6\":$(json_str_array "${ipv6_arr[@]}"),\"subnet\":$(json_str_array "${subnet_arr[@]}"),\"gateway\":$(json_str_array "${gw_arr[@]}"),\"dns_servers\":$(json_str_array "${dns_arr[@]}"),\"dhcp_enabled\":$dhcp,\"link_speed_mbps\":$(json_num "$speed")}"
        done < <(ls /sys/class/net 2>/dev/null)
    else
        warn "network: 'ip' not available"
    fi
    out+="]"
    printf '"network":%s' "$out"
}

collect_roles() {
    local roles=()
    # Detect known service roles by listening port + binary presence
    if have ss; then
        local listening
        listening="$(ss -tlnp 2>/dev/null || true)"
        echo "$listening" | grep -q ':80\b'   && roles+=("role:http")
        echo "$listening" | grep -q ':443\b'  && roles+=("role:https")
        echo "$listening" | grep -q ':22\b'   && roles+=("role:ssh")
        echo "$listening" | grep -q ':25\b'   && roles+=("role:smtp")
        echo "$listening" | grep -q ':53\b'   && roles+=("role:dns")
        echo "$listening" | grep -q ':3306\b' && roles+=("role:mysql")
        echo "$listening" | grep -q ':5432\b' && roles+=("role:postgres")
        echo "$listening" | grep -q ':6379\b' && roles+=("role:redis")
        echo "$listening" | grep -q ':27017\b' && roles+=("role:mongodb")
        echo "$listening" | grep -q ':445\b'  && roles+=("role:smb")
        echo "$listening" | grep -q ':389\b'  && roles+=("role:ldap")
        echo "$listening" | grep -q ':636\b'  && roles+=("role:ldaps")
        echo "$listening" | grep -q ':2049\b' && roles+=("role:nfs")
    else
        warn "roles: ss not available"
    fi
    # systemd-known well-known services (running)
    if have systemctl; then
        for u in nginx apache2 httpd mariadb mysql postgresql redis-server redis docker containerd kubelet sshd named bind9 dnsmasq smbd nfs-server vsftpd; do
            if systemctl is-active --quiet "$u" 2>/dev/null; then
                roles+=("svc:$u")
            fi
        done
    fi
    # Unique
    local uniq
    uniq="$(printf '%s\n' "${roles[@]:-}" | awk 'NF' | sort -u)"
    local arr=() line
    while IFS= read -r line; do [ -n "$line" ] && arr+=("$line"); done <<< "$uniq"
    printf '"roles_features":%s' "$(json_str_array "${arr[@]}")"
}

collect_services() {
    local first=1 out="["
    if have systemctl; then
        # list-unit-files gives us start_mode (enabled/disabled/static); list-units gives state
        # Build a map of name -> state from list-units.
        local states
        states="$(systemctl list-units --type=service --all --no-legend --no-pager 2>/dev/null \
            | awk '{name=$1; load=$2; active=$3; sub(/\.service$/, "", name); print name"\t"active}')"
        local files
        files="$(systemctl list-unit-files --type=service --no-legend --no-pager 2>/dev/null \
            | awk '{name=$1; mode=$2; sub(/\.service$/, "", name); print name"\t"mode}')"

        declare -A STATE
        while IFS=$'\t' read -r n s; do
            [ -n "$n" ] && STATE["$n"]="$s"
        done <<< "$states"

        while IFS=$'\t' read -r name mode; do
            [ -z "$name" ] && continue
            local active="${STATE[$name]:-unknown}"
            local account=""
            account="$(systemctl show -p User --value "$name" 2>/dev/null || true)"
            [ -z "$account" ] && account="root"
            local display
            display="$(systemctl show -p Description --value "$name" 2>/dev/null || true)"
            if [ $first -eq 1 ]; then first=0; else out+=","; fi
            out+="{\"name\":$(json_str "$name"),\"display_name\":$(json_str "$display"),\"state\":$(json_str "$active"),\"start_mode\":$(json_str "$mode"),\"account\":$(json_str "$account")}"
        done <<< "$files"
    else
        warn "services: systemctl not available"
    fi
    out+="]"
    printf '"services":%s' "$out"
}

collect_scheduled() {
    local first=1 out="["
    # systemd timers
    if have systemctl; then
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            local name last next state run_as action
            name="$(echo "$line" | awk '{print $NF}')"
            # systemctl list-timers columns: NEXT LEFT LAST PASSED UNIT ACTIVATES
            next="$(echo "$line"  | awk '{print $1" "$2" "$3}')"
            last="$(echo "$line"  | awk '{print $5" "$6" "$7}')"
            state="enabled"
            run_as="root"
            action="$name"
            if [ $first -eq 1 ]; then first=0; else out+=","; fi
            out+="{\"name\":$(json_str "$name"),\"path\":$(json_str "/systemd/timers"),\"state\":$(json_str "$state"),\"last_run\":$(json_str "$last"),\"next_run\":$(json_str "$next"),\"run_as\":$(json_str "$run_as"),\"action\":$(json_str "$action")}"
        done < <(systemctl list-timers --all --no-legend --no-pager 2>/dev/null)
    fi
    # crontabs - system + per-user
    local crons=()
    [ -r /etc/crontab ] && crons+=("/etc/crontab")
    for f in /etc/cron.d/*; do [ -r "$f" ] && crons+=("$f"); done
    if [ -d /var/spool/cron ]; then
        for f in /var/spool/cron/* /var/spool/cron/crontabs/*; do
            [ -r "$f" ] && crons+=("$f")
        done
    fi
    for cf in "${crons[@]:-}"; do
        [ -z "$cf" ] && continue
        local user="root"
        case "$cf" in
            /var/spool/cron/crontabs/*) user="$(basename "$cf")" ;;
            /var/spool/cron/*)          user="$(basename "$cf")" ;;
        esac
        local lineno=0
        while IFS= read -r cline; do
            lineno=$((lineno+1))
            # skip blanks + comments
            [[ -z "$cline" || "$cline" =~ ^[[:space:]]*# ]] && continue
            # skip env assignments
            [[ "$cline" =~ ^[A-Z_]+= ]] && continue
            if [ $first -eq 1 ]; then first=0; else out+=","; fi
            out+="{\"name\":$(json_str "$(basename "$cf"):$lineno"),\"path\":$(json_str "$cf"),\"state\":$(json_str "enabled"),\"last_run\":$(json_str ""),\"next_run\":$(json_str ""),\"run_as\":$(json_str "$user"),\"action\":$(json_str "$cline")}"
        done < "$cf"
    done
    out+="]"
    printf '"scheduled_tasks":%s' "$out"
}

collect_accounts() {
    local first=1 out="[" admins=()
    # Build admin set: members of sudo, wheel, admin
    for grp in sudo wheel admin; do
        if getent group "$grp" >/dev/null 2>&1; then
            local members
            members="$(getent group "$grp" | awk -F: '{print $4}')"
            IFS=',' read -ra arr <<< "$members"
            for m in "${arr[@]}"; do [ -n "$m" ] && admins+=("$m"); done
        fi
    done

    # users with shell, UID >= 1000 OR root
    while IFS=: read -r name _ uid _ _ _ shell; do
        if [ "$uid" -lt 1000 ] && [ "$name" != "root" ]; then continue; fi
        if [[ "$shell" =~ (nologin|false)$ ]] && [ "$name" != "root" ]; then continue; fi

        local enabled="true" is_admin="false" pwage=-1 last=""
        if have passwd; then
            local locked
            locked="$(passwd -S "$name" 2>/dev/null | awk '{print $2}')"
            case "$locked" in
                L|LK) enabled="false" ;;
            esac
        fi
        for a in "${admins[@]:-}"; do
            if [ "$a" = "$name" ]; then is_admin="true"; break; fi
        done
        if [ "$name" = "root" ]; then is_admin="true"; fi

        if have chage; then
            local pwlast
            pwlast="$(chage -l "$name" 2>/dev/null | awk -F: '/Last password change/ {gsub(/^ +| +$/,"",$2); print $2}')"
            if [ -n "$pwlast" ] && [ "$pwlast" != "never" ]; then
                local pw_epoch now_epoch
                pw_epoch="$(date -d "$pwlast" +%s 2>/dev/null || echo 0)"
                now_epoch="$(date +%s)"
                if [ "$pw_epoch" -gt 0 ]; then pwage=$(( (now_epoch - pw_epoch) / 86400 )); fi
            fi
        fi

        if have lastlog; then
            local ll
            ll="$(lastlog -u "$name" 2>/dev/null | tail -n +2 | awk '{$1=$2=""; print $0}' | sed 's/^ *//')"
            if [ -n "$ll" ] && [[ "$ll" != *"Never logged in"* ]]; then
                local le
                le="$(date -u -d "$ll" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "")"
                last="$le"
            fi
        fi

        if [ $first -eq 1 ]; then first=0; else out+=","; fi
        out+="{\"name\":$(json_str "$name"),\"enabled\":$enabled,\"is_admin\":$is_admin,\"last_logon\":$(json_str "$last"),\"password_age_days\":$(json_num "$pwage")}"
    done < /etc/passwd
    out+="]"

    # Dedup admins
    local admin_uniq=()
    if [ ${#admins[@]} -gt 0 ]; then
        local sorted
        sorted="$(printf '%s\n' "${admins[@]}" | sort -u)"
        while IFS= read -r a; do [ -n "$a" ] && admin_uniq+=("$a"); done <<< "$sorted"
    fi
    # Always include root
    admin_uniq+=("root")
    local sorted
    sorted="$(printf '%s\n' "${admin_uniq[@]}" | sort -u)"
    local final=()
    while IFS= read -r a; do [ -n "$a" ] && final+=("$a"); done <<< "$sorted"

    printf '"local_accounts":%s,"admin_group_members":%s' "$out" "$(json_str_array "${final[@]}")"
}

collect_shares() {
    local first=1 out="["
    if [ -r /etc/exports ]; then
        while IFS= read -r ln; do
            [[ -z "$ln" || "$ln" =~ ^[[:space:]]*# ]] && continue
            local p
            p="$(echo "$ln" | awk '{print $1}')"
            [ -z "$p" ] && continue
            if [ $first -eq 1 ]; then first=0; else out+=","; fi
            out+="{\"name\":$(json_str "nfs:$p"),\"path\":$(json_str "$p"),\"description\":$(json_str "NFS export")}"
        done < /etc/exports
    fi
    if [ -r /etc/samba/smb.conf ]; then
        local section=""
        while IFS= read -r ln; do
            if [[ "$ln" =~ ^\[(.+)\]$ ]]; then
                section="${BASH_REMATCH[1]}"
                continue
            fi
            if [[ "$ln" =~ ^[[:space:]]*path[[:space:]]*=[[:space:]]*(.+)$ ]] && [ -n "$section" ] && [ "$section" != "global" ]; then
                local pth="${BASH_REMATCH[1]}"
                if [ $first -eq 1 ]; then first=0; else out+=","; fi
                out+="{\"name\":$(json_str "smb:$section"),\"path\":$(json_str "$pth"),\"description\":$(json_str "Samba share")}"
            fi
        done < /etc/samba/smb.conf
    fi
    out+="]"
    printf '"shares":%s' "$out"
}

collect_patches() {
    local last="" pending="false" pkgs=()
    if [ -f /var/run/reboot-required ]; then pending="true"; fi
    if [ -f /var/run/reboot-required.pkgs ]; then pending="true"; fi

    if have dpkg-query; then
        # Most recently configured 10 packages; dpkg log has install dates
        if [ -r /var/log/dpkg.log ]; then
            last="$(awk '/ status installed / {print $1"T"$2"Z"; }' /var/log/dpkg.log | tail -n 1 || echo "")"
            mapfile -t pkgs < <(awk '/ status installed / {print $4}' /var/log/dpkg.log | tail -n 10)
        fi
    elif have rpm; then
        last="$(rpm -qa --last 2>/dev/null | head -n1 | awk '{print $2,$3,$4,$5,$6}' || echo "")"
        mapfile -t pkgs < <(rpm -qa --last 2>/dev/null | head -n10 | awk '{print $1}')
    else
        warn "patches: no supported package manager (dpkg/rpm)"
    fi

    printf '"patches":{"last_update_utc":%s,"pending_reboot":%s,"recent_kbs_or_packages":%s}' \
        "$(json_str "$last")" "$pending" "$(json_str_array "${pkgs[@]:-}")"
}

write_brief() {
    local snapshot_file="$1" txt_file="$2"
    # Keep brief simple - parse selected fields using grep/python if available; else basic shell
    {
        echo "CSAT Snapshot - $HOSTNAME"
        echo "Collected: $(iso_now)  |  Schema v${SCHEMA_VERSION}  |  CSAT v${CSAT_VERSION}"
        echo "========================================================================"
        echo "IDENTITY"
        echo "  Host:        $HOSTNAME ($(hostname -f 2>/dev/null || echo "$HOSTNAME"))"
        if [ -r /etc/os-release ]; then
            # shellcheck disable=SC1091
            . /etc/os-release
            echo "  OS:          ${PRETTY_NAME:-$NAME} (${VERSION_ID:-})"
        fi
        echo "  Kernel:      $(uname -r)"
        echo "  Uptime:      $(awk '{print int($1/3600)}' /proc/uptime 2>/dev/null) h"
        echo ""
        echo "HARDWARE"
        [ -r /sys/class/dmi/id/sys_vendor ]   && echo "  Vendor:      $(cat /sys/class/dmi/id/sys_vendor)"
        [ -r /sys/class/dmi/id/product_name ] && echo "  Model:       $(cat /sys/class/dmi/id/product_name)"
        [ -r /sys/class/dmi/id/product_serial ] && echo "  Serial:      $(cat /sys/class/dmi/id/product_serial)"
        echo "  CPU:         $(awk -F: '/^model name/ {print $2; exit}' /proc/cpuinfo | sed 's/^ //')"
        echo "  Cores/Threads: $(grep -c '^processor' /proc/cpuinfo) logical"
        echo "  Memory:      $(awk '/^MemTotal:/ {printf "%.2f GB", $2/1024/1024}' /proc/meminfo)"
        echo ""
        echo "STORAGE"
        df -hPT -x tmpfs -x devtmpfs -x squashfs -x overlay 2>/dev/null | awk 'NR>1 {printf "  %-20s %-6s %6s total %6s free\n", $7, $2, $3, $5}'
        echo ""
        echo "NETWORK"
        if have ip; then
            for iface in $(ls /sys/class/net 2>/dev/null); do
                [ "$iface" = "lo" ] && continue
                ips="$(ip -o -4 addr show dev "$iface" 2>/dev/null | awk '{print $4}' | tr '\n' ' ')"
                mac="$(cat "/sys/class/net/$iface/address" 2>/dev/null)"
                printf "  %-12s MAC %s  IP %s\n" "$iface" "$mac" "$ips"
            done
        fi
        echo ""
        echo "ADMIN GROUP MEMBERS"
        for grp in sudo wheel admin; do
            getent group "$grp" 2>/dev/null | awk -F: -v g="$grp" '{print "  ["g"] "$4}'
        done
        echo ""
        echo "RECENT WARNINGS"
        if [ ${#WARNINGS[@]} -gt 0 ]; then
            for w in "${WARNINGS[@]}"; do echo "  ! $w"; done
        else
            echo "  (none)"
        fi
    } > "$txt_file"
}

# ---------- Main ----------

show_banner

if [ "$ASSUME_YES" -ne 1 ]; then
    read -r -p "Proceed with collection? [y/N] " resp
    case "$resp" in
        y|Y|yes|YES) ;;
        *) echo "Aborted."; exit 1 ;;
    esac
fi

elevated="false"
if [ "$(id -u)" -eq 0 ]; then
    elevated="true"
else
    warn "Process is NOT running as root. Some sections will be incomplete."
    echo "WARNING: not running as root. Output will be incomplete." >&2
fi

mkdir -p "$OUTPUT_PATH"

echo "Collecting..."

IDENTITY="$(collect_identity)"
HARDWARE="$(collect_hardware)"
STORAGE="$(collect_storage)"
NETWORK="$(collect_network)"
ROLES="$(collect_roles)"
SERVICES="$(collect_services)"
TASKS="$(collect_scheduled)"
ACCOUNTS="$(collect_accounts)"
SHARES="$(collect_shares)"
PATCHES="$(collect_patches)"

# Build warnings array
warn_json="["
first=1
for w in "${WARNINGS[@]:-}"; do
    [ -z "$w" ] && continue
    if [ $first -eq 1 ]; then first=0; else warn_json+=","; fi
    warn_json+="$(json_str "$w")"
done
warn_json+="]"

run_as="$(id -un 2>/dev/null || echo "$USER")"

snapshot=$(cat <<EOF
{"csat_version":$(json_str "$CSAT_VERSION"),"schema_version":$SCHEMA_VERSION,"collected_at_utc":$(json_str "$(iso_now)"),"collector":{"platform":"linux","script_version":$(json_str "$CSAT_VERSION"),"run_as":$(json_str "$run_as"),"elevated":$elevated},$IDENTITY,$HARDWARE,$STORAGE,$NETWORK,$ROLES,$SERVICES,$TASKS,$ACCOUNTS,$SHARES,$PATCHES,"collection_warnings":$warn_json}
EOF
)

stamp="$(date -u +"%Y-%m-%dT%H%MZ")"
hostname_short="$(hostname -s 2>/dev/null || echo "$HOSTNAME")"
base="${OUTPUT_PATH%/}/${hostname_short}_${stamp}"
json_path="${base}.json"
txt_path="${base}.txt"

# Pretty-print if python3 is available; otherwise dump compact.
if have python3; then
    echo "$snapshot" | python3 -c 'import sys,json; print(json.dumps(json.loads(sys.stdin.read()), indent=2))' > "$json_path"
else
    printf '%s\n' "$snapshot" > "$json_path"
fi

write_brief "$json_path" "$txt_path"

echo ""
echo "Snapshot written:"
echo "  $json_path"
echo "  $txt_path"
if [ ${#WARNINGS[@]} -gt 0 ]; then
    echo ""
    echo "Warnings (${#WARNINGS[@]}):"
    for w in "${WARNINGS[@]}"; do echo "  ! $w"; done
fi
exit 0
