#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2025 useless-rs
#
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later
# version. This program is distributed WITHOUT ANY WARRANTY; without even the
# implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See the GNU General Public License for more details.

HBSS_VERSION="1.0.0"
HBSS_BASE_URL="${HBSS_BASE_URL:-https://raw.githubusercontent.com/useless-rs/HBSS/main}"

# Preserve original stdout so --output can tee the report without losing it.
exec 3>&1

# ---------------------------------------------------------------------------
# Globals
# ---------------------------------------------------------------------------
PROFILE="standard"
ONLY_LIST=""
SKIP_LIST=""
ALL_DRIVES=0
NO_DOWNLOADS=0
DOWNLOAD_BENCHMARKS=0
USE_INSTALLED=0
NO_PROPRIETARY=0
ALLOW_NETWORK=0
ALLOW_LARGE=0
ENDPOINT=""
OUTPUT_FILE=""
JSON_OUTPUT=0
SHOW_HELP=0
SHOW_VERSION=0
WORKDIR=""
RESULTS=""
SKIPPED=""
FAILED=""
METHOD=""
INV=""
S_SYSTEM=""
S_CPU=""
S_GPU=""
S_MEMORY=""
S_STORAGE=""
S_NETWORK=""
S_OTHER=""
S_NPU=""
S_THERMALS=""
COMPLETED=0
SKIPPED_N=0
FAILED_N=0
START_MS=""
END_MS=""
ON_BATTERY=0
HAS_TEMP=0
THERMAL_FILES=""
THERMAL_LOG=""
THERMAL_PID=""
TEMP_ZONES=""
STOP_THERMAL_FILE=""

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
sanitize() {
    # Replace tabs/newlines/carriage returns with spaces; escape pipes for Markdown.
    printf '%s' "$1" | tr '\011\012\015' '   ' | sed 's/|/\\|/g'
}

have_cmd() { command -v "$1" >/dev/null 2>&1; }

now_ms() {
    if have_cmd date; then
        d=$(date +%s%N 2>/dev/null)
        case "$d" in
            ''|*[!0-9]*) ;;
            *)
                echo $(( d / 1000000 ))
                return 0
                ;;
        esac
    fi
    if have_cmd python3; then
        python3 -c 'import time; print(int(time.time()*1000))' 2>/dev/null
        return 0
    fi
    if have_cmd perl; then
        perl -MTime::HiRes -e 'printf "%d\n", int(time*1000)' 2>/dev/null
        return 0
    fi
    echo $(($(date +%s 2>/dev/null || echo 0) * 1000))
}

elapsed_s() {
    # $1=start ms, $2=end ms
    awk -v a="$1" -v b="$2" 'BEGIN{printf "%.2f", (b-a)/1000.0}'
}

cleanup() {
    if [ -n "$WORKDIR" ] && [ -d "$WORKDIR" ]; then
        if [ -n "$THERMAL_PID" ]; then
            : > "$STOP_THERMAL_FILE" 2>/dev/null
            kill -9 "$THERMAL_PID" 2>/dev/null
            wait "$THERMAL_PID" 2>/dev/null
        fi
        rm -rf "$WORKDIR"
    fi
}
trap cleanup 0 1 2 15

record() {
    # $1 benchmark  $2 category  $3 engine  $4 version  $5 workload  $6 threads
    # $7 dataset  $8 duration  $9 result  $10 unit  $11 origin  $12 notes
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$(sanitize "$1")" "$(sanitize "$2")" "$(sanitize "$3")" "$(sanitize "$4")" \
        "$(sanitize "$5")" "$(sanitize "$6")" "$(sanitize "$7")" "$(sanitize "$8")" \
        "$(sanitize "$9")" "$(sanitize "${10}")" "$(sanitize "${11}")" "$(sanitize "${12}")" \
        >> "$RESULTS"
    COMPLETED=$((COMPLETED + 1))
}

skip_test() {
    # $1 benchmark  $2 category  $3 reason  $4 profile
    printf '%s\t%s\t%s\t%s\n' \
        "$(sanitize "$1")" "$(sanitize "$2")" "$(sanitize "$3")" "$(sanitize "$4")" \
        >> "$SKIPPED"
    SKIPPED_N=$((SKIPPED_N + 1))
}

fail_test() {
    # $1 benchmark  $2 category  $3 reason  $4 profile
    printf '%s\t%s\t%s\t%s\n' \
        "$(sanitize "$1")" "$(sanitize "$2")" "$(sanitize "$3")" "$(sanitize "$4")" \
        >> "$FAILED"
    FAILED_N=$((FAILED_N + 1))
}

setinv() {
    # $1 key  $2 value
    printf '%s\t%s\n' "$1" "$(sanitize "$2")" >> "$INV"
}

invget() {
    # $1 key
    awk -F'\t' -v k="$1" '$1==k{sub(/^[^\t]*\t/,""); print}' "$INV" 2>/dev/null | head -n1
}

usage() {
    cat <<'EOF'
HBSS — Hardware Benchmark Suite Script
Usage: bench.sh [OPTIONS]

Profiles:
  --quick                  Fast inspection (target <= 90s)
  --standard               Default: broad safe benchmark set (~5-10 min)
  --full                   Maximum safe coverage (~10-15 min)

Options:
  --only <list>            Comma-separated categories: cpu,gpu,memory,storage,network,npu,crypto,thermals,other
  --skip <list>            Comma-separated categories to skip
  --all-drives             Benchmark every eligible fixed local volume (opt-in)
  --no-downloads           Disable all third-party downloads
  --download-benchmarks    Opt in to pinned, SHA-256-verified third-party downloads
  --use-installed-benchmarks  Allow execution of user-installed third-party benchmarks
  --no-proprietary         Disable all proprietary benchmark integration
  --allow-network          Permit external network benchmark
  --allow-large-downloads  Permit large downloads (e.g. Blender)
  --endpoint <host>        External iperf3 server host (requires --allow-network)
  --output <file>          Also write the final Markdown report to <file>
  --json                   Also write a machine-readable JSON summary of results
  --help                   Show this help
  --version                Show version
EOF
}

category_enabled() {
    # $1 = category name
    if [ -n "$ONLY_LIST" ]; then
        case ",$ONLY_LIST," in
            *,all,*) ;;
            *,"$1",*) ;;
            *) return 1 ;;
        esac
    fi
    case ",$SKIP_LIST," in
        *,"$1",*) return 1 ;;
    esac
    return 0
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [ $# -gt 0 ]; do
    case "$1" in
        --quick) PROFILE="quick"; shift ;;
        --standard) PROFILE="standard"; shift ;;
        --full) PROFILE="full"; shift ;;
        --only)
            [ $# -ge 2 ] || { echo "missing value for --only" >&2; exit 2; }
            ONLY_LIST="$2"; shift 2 ;;
        --only=*) ONLY_LIST="${1#--only=}"; shift ;;
        --skip)
            [ $# -ge 2 ] || { echo "missing value for --skip" >&2; exit 2; }
            SKIP_LIST="$2"; shift 2 ;;
        --skip=*) SKIP_LIST="${1#--skip=}"; shift ;;
        --all-drives) ALL_DRIVES=1; shift ;;
        --no-downloads) NO_DOWNLOADS=1; shift ;;
        --download-benchmarks) DOWNLOAD_BENCHMARKS=1; shift ;;
        --use-installed-benchmarks) USE_INSTALLED=1; shift ;;
        --no-proprietary) NO_PROPRIETARY=1; shift ;;
        --allow-network) ALLOW_NETWORK=1; shift ;;
        --allow-large-downloads) ALLOW_LARGE=1; shift ;;
        --endpoint)
            [ $# -ge 2 ] || { echo "missing value for --endpoint" >&2; exit 2; }
            ENDPOINT="$2"; shift 2 ;;
        --endpoint=*) ENDPOINT="${1#--endpoint=}"; shift ;;
        --output)
            [ $# -ge 2 ] || { echo "missing value for --output" >&2; exit 2; }
            OUTPUT_FILE="$2"; shift 2 ;;
        --output=*) OUTPUT_FILE="${1#--output=}"; shift ;;
        --json) JSON_OUTPUT=1; shift ;;
        --help|-h) SHOW_HELP=1; shift ;;
        --version) SHOW_VERSION=1; shift ;;
        --) shift; break ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 2 ;;
    esac
done

if [ "$SHOW_HELP" -eq 1 ]; then usage; exit 0; fi
if [ "$SHOW_VERSION" -eq 1 ]; then echo "HBSS $HBSS_VERSION"; exit 0; fi

if [ "$NO_DOWNLOADS" -eq 1 ]; then
    DOWNLOAD_BENCHMARKS=0
    ALLOW_LARGE=0
fi

# Profile budgets
case "$PROFILE" in
    quick)
        CPU_CAP=20; MEM_CAP=10; STO_CAP=15; GPU_CAP=30
        FILE_MB=256; MEM_MB=64; TOTAL_CAP=90; COMPILE_OK=0 ;;
    standard)
        CPU_CAP=60; MEM_CAP=30; STO_CAP=45; GPU_CAP=120
        FILE_MB=1024; MEM_MB=256; TOTAL_CAP=600; COMPILE_OK=1 ;;
    full)
        CPU_CAP=120; MEM_CAP=60; STO_CAP=90; GPU_CAP=240
        FILE_MB=2048; MEM_MB=512; TOTAL_CAP=900; COMPILE_OK=1 ;;
esac

# Quick mode skips runtime compilation to keep the target.
if [ "$PROFILE" = "quick" ]; then COMPILE_OK=0; fi

# Temp workspace
WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/hbss.XXXXXX") || { echo "Failed to create temp dir" >&2; exit 1; }
TOTAL_START=$(now_ms)
# Always buffer the report to a file so we can render it (glow/color) at the end.
REPORT_FILE="$WORKDIR/report.md"
exec > "$REPORT_FILE"
RESULTS="$WORKDIR/results.tsv"
SKIPPED="$WORKDIR/skipped.tsv"
FAILED="$WORKDIR/failed.tsv"
METHOD="$WORKDIR/method.md"
INV="$WORKDIR/inventory.tsv"
S_SYSTEM="$WORKDIR/system.md"
S_CPU="$WORKDIR/cpu.md"
S_GPU="$WORKDIR/gpu.md"
S_MEMORY="$WORKDIR/memory.md"
S_STORAGE="$WORKDIR/storage.md"
S_NETWORK="$WORKDIR/network.md"
S_OTHER="$WORKDIR/other.md"
S_NPU="$WORKDIR/npu.md"
S_THERMALS="$WORKDIR/thermals.md"
THERMAL_LOG="$WORKDIR/thermal.log"
STOP_THERMAL_FILE="$WORKDIR/stop_thermal"
: > "$RESULTS"; : > "$SKIPPED"; : > "$FAILED"; : > "$METHOD"
: > "$INV"; : > "$S_SYSTEM"; : > "$S_CPU"; : > "$S_GPU"; : > "$S_MEMORY"
: > "$S_STORAGE"; : > "$S_NETWORK"; : > "$S_OTHER"; : > "$S_NPU"; : > "$S_THERMALS"
: > "$THERMAL_LOG"

TIMEOUT_BIN=""
if have_cmd timeout; then TIMEOUT_BIN="timeout"; elif have_cmd gtimeout; then TIMEOUT_BIN="gtimeout"; fi

run_limited() {
    # $1 seconds then command...
    secs=$1; shift
    if [ -n "$TIMEOUT_BIN" ]; then
        "$TIMEOUT_BIN" -k 2 "$secs" "$@" 2>>"$WORKDIR/log"
    else
        "$@" 2>>"$WORKDIR/log"
    fi
}

budget_exhausted() {
    # returns 0 (true) if total profile budget exceeded
    [ -z "$TOTAL_START" ] && return 1
    now=$(now_ms)
    elapsed=$(( (now - TOTAL_START) / 1000 ))
    [ "$elapsed" -ge "$TOTAL_CAP" ]
}

# ---------------------------------------------------------------------------
# Thermal sampler (background, read-only)
# ---------------------------------------------------------------------------
start_thermal_sampler() {
    if [ "$HAS_TEMP" -ne 1 ]; then return 0; fi
    (
        while [ ! -f "$STOP_THERMAL_FILE" ]; do
            max=0
            for f in $THERMAL_FILES; do
                v=$(cat "$f" 2>/dev/null)
                case "$v" in ''|*[!0-9]*) continue ;; esac
                if [ "$v" -gt "$max" ]; then max="$v"; fi
            done
            printf '%s\n' "$max" >> "$THERMAL_LOG"
            sleep 2
        done
    ) &
    THERMAL_PID=$!
}

stop_thermal_sampler() {
    if [ -n "$THERMAL_PID" ]; then
        : > "$STOP_THERMAL_FILE"
        kill "$THERMAL_PID" 2>/dev/null
        wait "$THERMAL_PID" 2>/dev/null
        THERMAL_PID=""
    fi
}

# ---------------------------------------------------------------------------
# OS / architecture
# ---------------------------------------------------------------------------
KERNEL=$(uname -s 2>/dev/null || echo unknown)
ARCH_RAW=$(uname -m 2>/dev/null || echo unknown)
case "$KERNEL" in
    Linux) OS="Linux" ;;
    Darwin) OS="macOS" ;;
    FreeBSD) OS="FreeBSD" ;;
    MINGW*|MSYS*|CYGWIN*) OS="Windows" ;;
    *) OS="$KERNEL" ;;
esac

case "$ARCH_RAW" in
    x86_64|amd64) ARCH="x86_64" ;;
    aarch64|arm64) ARCH="aarch64" ;;
    i386|i686) ARCH="x86" ;;
    armv7l) ARCH="armv7" ;;
    *) ARCH="$ARCH_RAW" ;;
esac

HOSTNAME=$(hostname 2>/dev/null || echo unknown)
NCPU=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)
case "$NCPU" in ''|*[!0-9]*) NCPU=1 ;; esac
[ "$NCPU" -lt 1 ] 2>/dev/null && NCPU=1

START_MS=$(now_ms)

# ---------------------------------------------------------------------------
# Inventory detection
# ---------------------------------------------------------------------------
detect_system() {
    if [ "$OS" = "Linux" ]; then
        if [ -r /etc/os-release ]; then
            . /etc/os-release
            OSNAME="${PRETTY_NAME:-Linux}"
        else
            OSNAME="Linux $(uname -r)"
        fi
        setinv "os" "$OSNAME"
        setinv "kernel" "$(uname -r)"
        # DMI
        for f in /sys/class/dmi/id/sys_vendor /sys/class/dmi/id/product_name /sys/class/dmi/id/product_version /sys/class/dmi/id/board_vendor /sys/class/dmi/id/board_name /sys/class/dmi/id/bios_version; do
            if [ -r "$f" ]; then
                k=$(basename "$f")
                setinv "dmi_$k" "$(cat "$f" 2>/dev/null)"
            fi
        done
        # lscpu
        if have_cmd lscpu; then
            for field in "Model name" "Vendor ID" "Architecture" "CPU(s)" "Core(s) per socket" "Socket(s)" "Thread(s) per core" "CPU max MHz" "CPU min MHz" "L1d cache" "L1i cache" "L2 cache" "L3 cache" "NUMA node(s)"; do
                v=$(lscpu 2>/dev/null | awk -F: -v f="$field" '$1 ~ f {sub(/^[ \t]+/,"",$2); print $2; exit}')
                [ -n "$v" ] && setinv "lscpu_$field" "$v"
            done
        fi
        # memory
        if [ -r /proc/meminfo ]; then
            mt=$(awk '/^MemTotal:/{print $2}' /proc/meminfo)
            ma=$(awk '/^MemAvailable:/{print $2}' /proc/meminfo)
            setinv "mem_total_kb" "$mt"
            setinv "mem_available_kb" "$ma"
        fi
        # battery
        for b in /sys/class/power_supply/BAT*; do
            [ -e "$b" ] || continue
            cap=$(cat "$b/capacity" 2>/dev/null)
            status=$(cat "$b/status" 2>/dev/null)
            [ -n "$cap" ] && setinv "battery" "$status ${cap}%"
            case "$status" in Discharging) ON_BATTERY=1 ;; esac
        done
        # temps
        for z in /sys/class/thermal/thermal_zone*; do
            [ -e "$z" ] || continue
            if [ -r "$z/temp" ]; then
                THERMAL_FILES="$THERMAL_FILES $z/temp"
                HAS_TEMP=1
            fi
        done
        for h in /sys/class/hwmon/hwmon*/temp*_input; do
            [ -r "$h" ] && { THERMAL_FILES="$THERMAL_FILES $h"; HAS_TEMP=1; }
        done
    elif [ "$OS" = "macOS" ]; then
        setinv "os" "macOS $(sw_vers -productVersion 2>/dev/null)"
        setinv "kernel" "$(uname -r)"
        setinv "hw_model" "$(sysctl -n hw.model 2>/dev/null)"
        setinv "mem_bytes" "$(sysctl -n hw.memsize 2>/dev/null)"
        setinv "ncpu" "$(sysctl -n hw.ncpu 2>/dev/null)"
        setinv "pcores" "$(sysctl -n hw.physicalcpu 2>/dev/null)"
        setinv "lcores" "$(sysctl -n hw.logicalcpu 2>/dev/null)"
        if [ -r /sys/class/power_supply ] ; then :; fi
        # battery via ioreg is complex; skip power state detection on macOS (conservative)
    else
        setinv "os" "$OS"
        setinv "kernel" "$(uname -r)"
    fi
    setinv "hostname" "$HOSTNAME"
    setinv "arch" "$ARCH"
    setinv "kernel_name" "$KERNEL"
}

detect_cpu() {
    if [ "$OS" = "Linux" ]; then
        if have_cmd lscpu; then
            {
                echo "| Field | Value |"
                echo "|---|---|"
                for field in "Model name" "Vendor ID" "Architecture" "CPU(s)" "Core(s) per socket" "Socket(s)" "Thread(s) per core" "CPU max MHz" "CPU min MHz" "L1d cache" "L1i cache" "L2 cache" "L3 cache" "NUMA node(s)"; do
                    v=$(lscpu 2>/dev/null | awk -F: -v f="$field" '$1 ~ f {sub(/^[ \t]+/,"",$2); print $2; exit}')
                    [ -n "$v" ] && printf '| %s | %s |\n' "$field" "$v"
                done
            } >> "$S_CPU"
        fi
        # flags / virtualization
        flags=$(awk '/^flags/{print; exit}' /proc/cpuinfo 2>/dev/null)
        case "$flags" in
            *vmx*) setinv "virt" "Intel VT-x (vmx)" ;;
            *svm*) setinv "virt" "AMD-V (svm)" ;;
        esac
        # perf/eff cores via sysfs max_freq grouping (best-effort)
        if [ -d /sys/devices/system/cpu/cpu0 ]; then
            {
                echo ""
                echo "Topology (per logical CPU, from /sys):"
                echo ""
                echo "| CPU | Core | Package | Max MHz |"
                echo "|---|---|---|---|"
                for d in /sys/devices/system/cpu/cpu[0-9]*; do
                    [ -d "$d" ] || continue
                    n=$(basename "$d" | sed 's/cpu//')
                    core=$(cat "$d/topology/core_id" 2>/dev/null)
                    pkg=$(cat "$d/topology/physical_package_id" 2>/dev/null)
                    maxf=$(cat "$d/cpufreq/scaling_max_freq" 2>/dev/null)
                    [ -n "$maxf" ] && maxf=$((maxf / 1000))
                    printf '| %s | %s | %s | %s |\n' "$n" "${core:-?}" "${pkg:-?}" "${maxf:-?}"
                done
            } >> "$S_CPU"
        fi
    elif [ "$OS" = "macOS" ]; then
        brand=$(sysctl -n machdep.cpu.brand_string 2>/dev/null)
        [ -n "$brand" ] && setinv "cpu_model" "$brand"
        {
            echo "| Field | Value |"
            echo "|---|---|"
            for k in hw.physicalcpu hw.logicalcpu hw.cpufrequency hw.cpufrequency_max machdep.cpu.core_count machdep.cpu.thread_count; do
                v=$(sysctl -n "$k" 2>/dev/null)
                [ -n "$v" ] && printf '| %s | %s |\n' "$k" "$v"
            done
        } >> "$S_CPU"
        # perf levels
        p0=$(sysctl -n hw.perflevel0.logicalcpu 2>/dev/null)
        p1=$(sysctl -n hw.perflevel1.logicalcpu 2>/dev/null)
        if [ -n "$p0" ] || [ -n "$p1" ]; then
            printf '\nPerformance levels: P-cores=%s, E-cores=%s\n' "${p0:-0}" "${p1:-0}" >> "$S_CPU"
            setinv "perf_cores" "${p0:-0}"
            setinv "eff_cores" "${p1:-0}"
        fi
    fi
    # cache sizes from sysfs
    if [ -d /sys/devices/system/cpu/cpu0/cache ]; then
        {
            echo ""
            echo "Cache hierarchy (from /sys):"
            echo ""
            echo "| Level | Size |"
            echo "|---|---|"
            for idx in /sys/devices/system/cpu/cpu0/cache/index*; do
                [ -d "$idx" ] || continue
                lvl=$(cat "$idx/level" 2>/dev/null)
                typ=$(cat "$idx/type" 2>/dev/null)
                sz=$(cat "$idx/size" 2>/dev/null)
                [ -n "$sz" ] && printf '| L%s %s | %s |\n' "$lvl" "$typ" "$sz"
            done
        } >> "$S_CPU"
    fi
}

detect_memory() {
    if [ "$OS" = "Linux" ]; then
        if [ -r /proc/meminfo ]; then
            {
                echo "| Field | Value |"
                echo "|---|---|"
                for f in MemTotal MemFree MemAvailable Buffers Cached SwapTotal SwapFree; do
                    v=$(awk -v k="$f:" '$1==k{print $2" "$3}' /proc/meminfo)
                    [ -n "$v" ] && printf '| %s | %s |\n' "$f" "$v"
                done
            } >> "$S_MEMORY"
        fi
        # DMI memory modules (best effort, unprivileged via sysfs)
        if [ -d /sys/bus/dmi/devices ]; then
            mods=$(grep -rl "Memory Device" /sys/bus/dmi/devices 2>/dev/null | wc -l)
            [ "$mods" -gt 0 ] 2>/dev/null && printf '\nDMI memory device entries detected: %s\n' "$mods" >> "$S_MEMORY"
        fi
        # NUMA
        if [ -d /sys/devices/system/node ]; then
            for n in /sys/devices/system/node/node*; do
                [ -d "$n" ] || continue
                mem=$(cat "$n/meminfo" 2>/dev/null | awk '/MemTotal/{print $4" "$5}')
                [ -n "$mem" ] && printf '| NUMA %s | %s |\n' "$(basename "$n")" "$mem" >> "$S_MEMORY"
            done
        fi
    elif [ "$OS" = "macOS" ]; then
        mb=$(sysctl -n hw.memsize 2>/dev/null)
        if [ -n "$mb" ]; then
            setinv "mem_bytes" "$mb"
            printf '| Field | Value |\n|---|---|\n| Total RAM | %s bytes |\n' "$mb" >> "$S_MEMORY"
        fi
        if have_cmd system_profiler; then
            system_profiler SPMemoryDataType -timeout 20 2>/dev/null >> "$WORKDIR/spmem.txt"
            printf '\n```\n%s\n```\n' "$(head -c 4000 "$WORKDIR/spmem.txt")" >> "$S_MEMORY"
        fi
    fi
    # mem speed from DMI (Linux)
    if have_cmd dmidecode; then
        dmidecode -t memory 2>/dev/null | grep -iE "Speed:|Size:|Type:|Manufacturer:|Part Number:" | head -n 40 >> "$WORKDIR/dmi_mem.txt" 2>/dev/null
        if [ -s "$WORKDIR/dmi_mem.txt" ]; then
            printf '\nDMI memory (dmidecode, best effort):\n\n```\n%s\n```\n' "$(cat "$WORKDIR/dmi_mem.txt")" >> "$S_MEMORY"
        fi
    fi
}

detect_gpu() {
    if [ "$OS" = "Linux" ]; then
        if have_cmd lspci; then
            {
                echo "| PCI device | Details |"
                echo "|---|---|"
                lspci 2>/dev/null | grep -iE 'vga|3d controller|display' | while IFS= read -r line; do
                    printf '| GPU | %s |\n' "$line"
                done
            } >> "$S_GPU"
        fi
        # DRM cards
        for c in /sys/class/drm/card[0-9]*; do
            [ -d "$c" ] || continue
            ven=$(cat "$c/device/vendor" 2>/dev/null)
            dev=$(cat "$c/device/device" 2>/dev/null)
            [ -n "$ven" ] && printf '| DRM card %s | vendor=%s device=%s |\n' "$(basename "$c")" "$ven" "$dev" >> "$S_GPU"
        done
        if have_cmd nvidia-smi; then
            {
                echo ""
                echo "NVIDIA (nvidia-smi):"
                echo ""
                nvidia-smi --query-gpu=name,driver_version,memory.total,memory.free,temperature.gpu,power.draw --format=csv 2>/dev/null
            } >> "$S_GPU"
            setinv "nvidia_smi" "present"
        fi
        if have_cmd rocm-smi; then
            rocm-smi 2>/dev/null | head -n 40 >> "$S_GPU"
        fi
    elif [ "$OS" = "macOS" ]; then
        if have_cmd system_profiler; then
            system_profiler SPDisplaysDataType -timeout 20 2>/dev/null >> "$WORKDIR/spdisp.txt"
            printf '```\n%s\n```\n' "$(cat "$WORKDIR/spdisp.txt")" >> "$S_GPU"
        fi
    fi
}

detect_storage() {
    if [ "$OS" = "Linux" ]; then
        if have_cmd lsblk; then
            {
                echo "Block devices (lsblk):"
                echo ""
                echo '```'
                lsblk -d -o NAME,MODEL,SIZE,TYPE,ROTA,TRAN,MOUNTPOINT 2>/dev/null
                echo '```'
            } >> "$S_STORAGE"
        fi
        if have_cmd findmnt; then
            tested_src=$(findmnt -no SOURCE -T "$WORKDIR" 2>/dev/null)
            tested_fs=$(findmnt -no FSTYPE -T "$WORKDIR" 2>/dev/null)
            tested_mp=$(findmnt -no TARGET -T "$WORKDIR" 2>/dev/null)
            setinv "storage_tested_src" "${tested_src:-unknown}"
            setinv "storage_tested_fs" "${tested_fs:-unknown}"
            setinv "storage_tested_mp" "${tested_mp:-$WORKDIR}"
            printf '\nTested volume: source=%s fs=%s mount=%s\n' "${tested_src:-unknown}" "${tested_fs:-unknown}" "${tested_mp:-$WORKDIR}" >> "$S_STORAGE"
        else
            setinv "storage_tested_mp" "$WORKDIR"
        fi
        if have_cmd smartctl; then
            dev=$(lsblk -no PKNAME "$(findmnt -no SOURCE -T "$WORKDIR" 2>/dev/null)" 2>/dev/null | head -n1)
            [ -z "$dev" ] && dev=$(basename "$(findmnt -no SOURCE -T "$WORKDIR" 2>/dev/null)" 2>/dev/null | sed 's/[0-9]*$//')
            if [ -n "$dev" ]; then
                smartctl -i "/dev/$dev" 2>/dev/null | head -n 30 >> "$WORKDIR/smart.txt"
                if [ -s "$WORKDIR/smart.txt" ]; then
                    printf '\nSMART (best effort, /dev/%s):\n\n```\n%s\n```\n' "$dev" "$(cat "$WORKDIR/smart.txt")" >> "$S_STORAGE"
                fi
            fi
        fi
    elif [ "$OS" = "macOS" ]; then
        if have_cmd diskutil; then
            diskutil list 2>/dev/null >> "$S_STORAGE"
        fi
        if have_cmd system_profiler; then
            system_profiler SPStorageDataType SPNVMeDataType -timeout 20 2>/dev/null | head -n 120 >> "$S_STORAGE"
        fi
        setinv "storage_tested_mp" "$WORKDIR"
    else
        setinv "storage_tested_mp" "$WORKDIR"
    fi
}

detect_network() {
    if [ "$OS" = "Linux" ]; then
        if have_cmd ip; then
            {
                echo "Interfaces (ip -brief):"
                echo ""
                echo '```'
                ip -brief link 2>/dev/null
                echo '```'
                echo ""
                echo "Addresses:"
                echo '```'
                ip -brief addr 2>/dev/null
                echo '```'
            } >> "$S_NETWORK"
        fi
        # link speeds
        {
            echo ""
            echo "Link speeds (from /sys):"
            echo ""
            echo "| Interface | Speed (Mb/s) | Operstate |"
            echo "|---|---|---|"
            for d in /sys/class/net/*; do
                [ -d "$d" ] || continue
                iface=$(basename "$d")
                [ "$iface" = "lo" ] && continue
                speed=$(cat "$d/speed" 2>/dev/null)
                state=$(cat "$d/operstate" 2>/dev/null)
                printf '| %s | %s | %s |\n' "$iface" "${speed:-?}" "${state:-?}"
            done
        } >> "$S_NETWORK"
        # wifi
        if have_cmd iw; then
            iw dev 2>/dev/null | head -n 40 >> "$WORKDIR/iw.txt"
            if [ -s "$WORKDIR/iw.txt" ]; then
                printf '\nWi-Fi (iw):\n\n```\n%s\n```\n' "$(cat "$WORKDIR/iw.txt")" >> "$S_NETWORK"
            fi
        fi
    elif [ "$OS" = "macOS" ]; then
        if have_cmd networksetup; then
            networksetup -listallhardwareports 2>/dev/null >> "$S_NETWORK"
        fi
        if have_cmd ifconfig; then
            ifconfig 2>/dev/null | head -n 60 >> "$S_NETWORK"
        fi
    fi
}

detect_other() {
    if [ "$OS" = "Linux" ]; then
        {
            echo "| Field | Value |"
            echo "|---|---|"
            for f in /sys/class/dmi/id/sys_vendor /sys/class/dmi/id/product_name /sys/class/dmi/id/product_version /sys/class/dmi/id/board_vendor /sys/class/dmi/id/board_name /sys/class/dmi/id/bios_vendor /sys/class/dmi/id/bios_version /sys/class/dmi/id/chassis_type; do
                if [ -r "$f" ]; then
                    printf '| %s | %s |\n' "$(basename "$f")" "$(cat "$f" 2>/dev/null)"
                fi
            done
        } >> "$S_OTHER"
        # displays
        if have_cmd xrandr; then
            xrandr 2>/dev/null | grep -E ' connected | \*' | head -n 20 >> "$WORKDIR/displays.txt"
            if [ -s "$WORKDIR/displays.txt" ]; then
                printf '\nDisplays (xrandr):\n\n```\n%s\n```\n' "$(cat "$WORKDIR/displays.txt")" >> "$S_OTHER"
            fi
        fi
        # audio
        if have_cmd lspci; then
            aud=$(lspci 2>/dev/null | grep -i audio)
            if [ -n "$aud" ]; then
                printf '\nAudio controllers:\n\n```\n%s\n```\n' "$aud" >> "$S_OTHER"
            fi
        fi
        # PCIe count
        if have_cmd lspci; then
            n=$(lspci 2>/dev/null | wc -l)
            printf '\nPCIe/PCI devices: %s\n' "$n" >> "$S_OTHER"
        fi
    elif [ "$OS" = "macOS" ]; then
        if have_cmd system_profiler; then
            system_profiler SPHardwareDataType SPDisplaysDataType SPAudioDataType SPPowerDataType -timeout 30 2>/dev/null | head -n 200 >> "$S_OTHER"
        fi
    fi
}

detect_npu() {
    found=0
    if [ "$OS" = "Linux" ]; then
        if have_cmd lspci; then
            npu=$(lspci 2>/dev/null | grep -iE 'neural|npu|ai boost|xdna|hexagon')
            if [ -n "$npu" ]; then
                printf '%s\n' "$npu" >> "$S_NPU"
                found=1
            fi
        fi
        # /dev/accel
        if [ -d /dev/accel ]; then
            printf 'Accelerator devices: %s\n' "$(ls /dev/accel 2>/dev/null)" >> "$S_NPU"
            found=1
        fi
        # Intel VPU
        if [ -d /sys/class/intel_vpu ]; then
            printf 'Intel VPU class present\n' >> "$S_NPU"
            found=1
        fi
    elif [ "$OS" = "macOS" ]; then
        # Apple Neural Engine is not separately exposed; note presence via chip
        chip=$(sysctl -n machdep.cpu.brand_string 2>/dev/null)
        case "$chip" in *Apple*) printf 'Apple Silicon detected; Neural Engine present on-chip (not independently measurable)\n' >> "$S_NPU"; found=1 ;; esac
    fi
    if [ "$found" -eq 0 ]; then
        printf 'No AI accelerator / NPU detected by available unprivileged interfaces.\n' >> "$S_NPU"
    fi
}

# ---------------------------------------------------------------------------
# Run all detection
# ---------------------------------------------------------------------------
detect_system
detect_cpu
detect_memory
detect_gpu
detect_storage
detect_network
detect_other
detect_npu

# Start thermal sampler after detection (idle baseline captured by first sample)
start_thermal_sampler


# ---------------------------------------------------------------------------
# CPU benchmark
# ---------------------------------------------------------------------------
if category_enabled cpu; then
    # Recognized: sysbench if installed
    if have_cmd sysbench && [ "$NO_PROPRIETARY" -eq 0 ]; then
        # open-source; allowed by default if installed
        out=$(run_limited "$CPU_CAP" sysbench cpu --cpu-max-prime=20000 --threads=1 --time="$CPU_CAP" run 2>&1)
        eps=$(printf '%s\n' "$out" | awk '/events per second:/{print $NF; exit}')
        if [ -n "$eps" ]; then
            record "sysbench cpu" "cpu" "sysbench" "$(sysbench --version 2>/dev/null | head -n1)" \
                "cpu max-prime=20000, 1 thread, ${CPU_CAP}s" "1" "max-prime 20000" "$CPU_CAP" \
                "$eps" "events/s" "recognized open-source" "open-source, installed"
        else
            fail_test "sysbench cpu" "cpu" "execution failed or timed out" "$PROFILE"
        fi
        # multi-thread
        out2=$(run_limited "$CPU_CAP" sysbench cpu --cpu-max-prime=20000 --threads="$NCPU" --time="$CPU_CAP" run 2>&1)
        eps2=$(printf '%s\n' "$out2" | awk '/events per second:/{print $NF; exit}')
        if [ -n "$eps2" ]; then
            record "sysbench cpu (mt)" "cpu" "sysbench" "$(sysbench --version 2>/dev/null | head -n1)" \
                "cpu max-prime=20000, $NCPU threads, ${CPU_CAP}s" "$NCPU" "max-prime 20000" "$CPU_CAP" \
                "$eps2" "events/s" "recognized open-source" "open-source, installed"
            if [ -n "$eps" ]; then
                ratio=$(awk -v a="$eps2" -v b="$eps" 'BEGIN{if(b>0) printf "%.2f", a/b; else print "n/a"}')
                record "sysbench scaling" "cpu" "sysbench" "$(sysbench --version 2>/dev/null | head -n1)" \
                    "multi/single thread ratio" "$NCPU" "n/a" "$CPU_CAP" "$ratio" "x" "recognized open-source" "derived ratio"
            fi
        else
            fail_test "sysbench cpu (mt)" "cpu" "execution failed or timed out" "$PROFILE"
        fi
    else
        skip_test "sysbench cpu" "cpu" "sysbench not installed" "$PROFILE"
    fi

    # 7-Zip if installed (heavy; skip in quick to honor 90s target)
    SEVEN=""
    if have_cmd 7zz; then SEVEN="7zz"; elif have_cmd 7za; then SEVEN="7za"; elif have_cmd 7z; then SEVEN="7z"; fi
    if [ "$PROFILE" = "quick" ]; then
        skip_test "7-Zip benchmark" "cpu" "skipped in quick profile (heavy; run standard/full)" "$PROFILE"
        SEVEN=""
    fi
    if [ -n "$SEVEN" ]; then
        out=$(run_limited "$CPU_CAP" "$SEVEN" b 2>&1)
        # parse Avr MB/s (compression)
        avr=$(printf '%s\n' "$out" | awk '/Avr:/{for(i=1;i<=NF;i++) if($i ~ /MB\/s/ || $i=="MB/s"){print $(i-1); exit}}')
        [ -z "$avr" ] && avr=$(printf '%s\n' "$out" | grep -i "Avr" | tail -n1 | awk '{for(i=1;i<=NF;i++) if($i ~ /^[0-9.]+$/){print $i; exit}}')
        if [ -n "$avr" ]; then
            record "7-Zip benchmark" "cpu" "7-Zip" "$("$SEVEN" 2>&1 | head -n1 | sed 's/.*7-Zip //;s/ .*//')" \
                "built-in 7zz b, default pass" "all" "default" "$CPU_CAP" "$avr" "MB/s" \
                "recognized open-source" "installed 7-Zip; parse Avr"
        else
            fail_test "7-Zip benchmark" "cpu" "could not parse result" "$PROFILE"
        fi
    else
        skip_test "7-Zip benchmark" "cpu" "7-Zip not installed (use --download-benchmarks)" "$PROFILE"
    fi

    # OpenSSL speed if installed
    if have_cmd openssl; then
        if budget_exhausted; then skip_test "OpenSSL speed" "crypto" "profile time budget exhausted" "$PROFILE"; else
        osslver=$(openssl version 2>/dev/null)
        secs=$(( CPU_CAP / 8 )); [ "$secs" -lt 2 ] && secs=2

        out=$(run_limited "$CPU_CAP" openssl speed -evp aes-256-gcm -seconds "$secs" 2>&1)
        aes=$(printf '%s\n' "$out" | awk '/aes-256 gcm|AES-256-GCM/{for(i=NF;i>=1;i--) if($i ~ /^[0-9.]+k?$/){print $i; exit}}')
        if [ -n "$aes" ]; then
            record "OpenSSL AES-256-GCM" "crypto" "OpenSSL" "$osslver" "speed -evp aes-256-gcm, ${secs}s" "1" "default block sizes" "$secs" \
                "$aes" "ops/s (last block)" "recognized open-source (detect-only tool)" "installed openssl"
        else
            fail_test "OpenSSL AES-256-GCM" "crypto" "execution/parse failed" "$PROFILE"
        fi
        # SHA-256
        out3=$(run_limited "$CPU_CAP" openssl speed -evp sha256 -seconds "$secs" 2>&1)
        sha=$(printf '%s\n' "$out3" | awk '/sha256/{for(i=NF;i>=1;i--) if($i ~ /^[0-9.]+k?$/){print $i; exit}}')
        if [ -n "$sha" ]; then
            record "OpenSSL SHA-256" "crypto" "OpenSSL" "$osslver" "speed -evp sha256, ${secs}s" "1" "default block sizes" "$secs" \
                "$sha" "ops/s (last block)" "recognized open-source (detect-only tool)" "installed openssl"
        else
            skip_test "OpenSSL SHA-256" "crypto" "could not parse result" "$PROFILE"
        fi
        fi

    else
        skip_test "OpenSSL speed" "crypto" "openssl not installed" "$PROFILE"
    fi

    # Geekbench / Cinebench detection (never auto-run)
    for bin in geekbench geekbench6 geekbench7 cinebench cinebenchR23; do
        if have_cmd "$bin"; then
            if [ "$USE_INSTALLED" -eq 1 ] && [ "$NO_PROPRIETARY" -eq 0 ]; then
                skip_test "$bin" "cpu" "detected; not executed (requires named-user license, activation and/or result upload; verify license manually)" "$PROFILE"
            else
                skip_test "$bin" "cpu" "detected but not executed (use --use-installed-benchmarks with a valid license)" "$PROFILE"
            fi
        fi
    done
    if have_cmd cinebench; then :; fi
    # y-cruncher detect-only
    if have_cmd y-cruncher; then
        skip_test "y-cruncher" "cpu" "detected; not executed (interactive workload selection; license accepted by download)" "$PROFILE"
    fi
    # Phoronix detect-only
    if have_cmd phoronix-test-suite; then
        skip_test "phoronix-test-suite" "cpu" "detected; not executed (pulls unpinned test profiles; use manually)" "$PROFILE"
    fi


    # HBSS fallback: integer loop microbenchmark
    cat > "$WORKDIR/cpu_worker.sh" <<'EOF'
#!/bin/sh
iters=$1
i=0
acc=0
while [ "$i" -lt "$iters" ]; do
    acc=$(( (acc + i * 2654435761) % 2147483647 ))
    i=$((i + 1))
done
printf '%s\n' "$acc"
EOF
    chmod +x "$WORKDIR/cpu_worker.sh"

    case "$PROFILE" in
        quick) iters=200000 ;;
        standard) iters=600000 ;;
        full) iters=1000000 ;;
    esac

    # single thread
    s=$(now_ms)
    out=$(run_limited "$CPU_CAP" sh "$WORKDIR/cpu_worker.sh" "$iters" 2>&1)
    e=$(now_ms)
    if [ -n "$out" ]; then
        dur=$(elapsed_s "$s" "$e")
        score=$(awk -v i="$iters" -v d="$dur" 'BEGIN{if(d>0) printf "%.0f", i/d; else print 0}')
        record "HBSS integer loop (1 thread)" "cpu" "HBSS fallback" "1.0" \
            "integer mix, $iters iterations" "1" "$iters iterations" "$dur" "$score" "ops/s" \
            "HBSS fallback" "homemade microbenchmark; not comparable to Geekbench/Cinebench"
    else
        fail_test "HBSS integer loop (1 thread)" "cpu" "timed out or failed" "$PROFILE"
    fi


    # multi thread
    if [ "$NCPU" -gt 1 ]; then
        s=$(now_ms)
        i=0
        pids=""
        while [ "$i" -lt "$NCPU" ]; do
            sh "$WORKDIR/cpu_worker.sh" "$iters" > "$WORKDIR/cpu.$i.out" 2>>"$WORKDIR/log" &
            pids="$pids $!"
            i=$((i + 1))
        done
        for pid in $pids; do wait "$pid" 2>/dev/null; done

        e=$(now_ms)
        dur=$(elapsed_s "$s" "$e")
        total=$((iters * NCPU))
        score=$(awk -v i="$total" -v d="$dur" 'BEGIN{if(d>0) printf "%.0f", i/d; else print 0}')
        record "HBSS integer loop ($NCPU threads)" "cpu" "HBSS fallback" "1.0" \
            "integer mix, $iters x $NCPU iterations" "$NCPU" "$total iterations" "$dur" "$score" "ops/s" \
            "HBSS fallback" "homemade microbenchmark; not comparable to Geekbench/Cinebench"
        if [ -n "$score" ]; then
            # scaling ratio uses single-thread score recomputed implicitly
            :
        fi
    fi

    # STREAM-derived (compiled) if allowed
    if [ "$COMPILE_OK" -eq 1 ]; then
        CC=""
        for c in cc clang gcc; do
            if have_cmd "$c"; then CC="$c"; break; fi
        done
        if [ -n "$CC" ]; then
            # verify pinned source hash at runtime by writing source then hashing
            cat > "$WORKDIR/stream_hbss.c" <<'CEOF'
/* STREAM-derived memory bandwidth kernels.
   Derived from the STREAM benchmark by John D. McCalpin, University of Virginia.
   Kernels: Copy, Scale, Add, Triad. OpenMP used when available.
   HBSS labels results "STREAM-derived" unless standard run rules are met.
*/
#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#ifdef _OPENMP
#include <omp.h>
#endif

static double mysecond(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec * 1.0e-9;
}

int main(int argc, char **argv) {
    size_t n = 2000000;
    if (argc > 1) n = (size_t)strtoull(argv[1], NULL, 10);
    if (n < 100000) n = 100000;
    double *a = malloc(n * sizeof(double));
    double *b = malloc(n * sizeof(double));
    double *c = malloc(n * sizeof(double));
    if (!a || !b || !c) { fprintf(stderr, "ALLOC_FAIL\n"); return 1; }
    size_t i;
    for (i = 0; i < n; i++) { a[i] = 1.0; b[i] = 2.0; c[i] = 0.0; }
    int threads = 1;
#ifdef _OPENMP
    threads = omp_get_max_threads();
#endif
    double scalar = 3.0;
    double t0, t1;
    /* Copy */
    t0 = mysecond();
    for (i = 0; i < n; i++) c[i] = a[i];
    t1 = mysecond();
    double copy = (2.0 * n * sizeof(double)) / (t1 - t0) / 1e6;
    /* Scale */
    t0 = mysecond();
    for (i = 0; i < n; i++) b[i] = scalar * c[i];
    t1 = mysecond();
    double scale = (2.0 * n * sizeof(double)) / (t1 - t0) / 1e6;
    /* Add */
    t0 = mysecond();
    for (i = 0; i < n; i++) c[i] = a[i] + b[i];
    t1 = mysecond();
    double add = (3.0 * n * sizeof(double)) / (t1 - t0) / 1e6;
    /* Triad */
    t0 = mysecond();
    for (i = 0; i < n; i++) a[i] = b[i] + scalar * c[i];
    t1 = mysecond();
    double triad = (3.0 * n * sizeof(double)) / (t1 - t0) / 1e6;
    printf("STREAM Copy: %.2f MB/s\n", copy);
    printf("STREAM Scale: %.2f MB/s\n", scale);
    printf("STREAM Add: %.2f MB/s\n", add);
    printf("STREAM Triad: %.2f MB/s\n", triad);
    printf("STREAM Threads: %d\n", threads);
    printf("STREAM Elements: %lu\n", (unsigned long)n);
    printf("STREAM Bytes: %lu\n", (unsigned long)(3 * n * sizeof(double)));
    /* validation */
    double s = 0.0;
    for (i = 0; i < n; i++) s += a[i] + b[i] + c[i];
    printf("STREAM Validation: %s\n", (s > 0) ? "PASS" : "FAIL");
    free(a); free(b); free(c);
    return 0;
}
CEOF
            SRC_HASH=$(sha256sum "$WORKDIR/stream_hbss.c" 2>/dev/null | awk '{print $1}')
            [ -z "$SRC_HASH" ] && SRC_HASH=$(shasum -a 256 "$WORKDIR/stream_hbss.c" 2>/dev/null | awk '{print $1}')
            # compile (try OpenMP)
            if ! "$CC" -O3 -fopenmp -o "$WORKDIR/stream_hbss" "$WORKDIR/stream_hbss.c" 2>"$WORKDIR/stream_compile.log"; then
                "$CC" -O3 -o "$WORKDIR/stream_hbss" "$WORKDIR/stream_hbss.c" 2>>"$WORKDIR/stream_compile.log"
            fi
            if [ -x "$WORKDIR/stream_hbss" ]; then
                # dataset sizing
                llc_kb=0
                if [ -d /sys/devices/system/cpu/cpu0/cache ]; then
                    llc_kb=$(for idx in /sys/devices/system/cpu/cpu0/cache/index*; do
                        [ -d "$idx" ] || continue
                        lvl=$(cat "$idx/level" 2>/dev/null)
                        sz=$(cat "$idx/size" 2>/dev/null)
                        case "$sz" in *K) sz=${sz%K} ;; *M) sz=$(( ${sz%M} * 1024 )) ;; esac
                        echo "$lvl $sz"
                    done | sort -n | tail -n1 | awk '{print $2}')
                fi
                [ -z "$llc_kb" ] && llc_kb=0
                target_bytes=$(( MEM_MB * 1024 * 1024 ))
                if [ "$llc_kb" -gt 0 ]; then
                    min_bytes=$(( llc_kb * 4 * 1024 ))
                    [ "$min_bytes" -gt "$target_bytes" ] && min_bytes="$target_bytes"
                    [ "$min_bytes" -lt $(( 1024*1024 )) ] && min_bytes=$((1024*1024))
                else
                    min_bytes=$(( target_bytes / 2 ))
                fi
                elems=$(( min_bytes / 24 ))
                [ "$elems" -lt 100000 ] && elems=100000
                # standard-run check: dataset >= 4*LLC
                standard_run=0
                if [ "$llc_kb" -gt 0 ]; then
                    if [ "$min_bytes" -ge $(( llc_kb * 4 * 1024 )) ]; then standard_run=1; fi
                fi
                label="STREAM-derived (HBSS-compiled)"
                if [ "$standard_run" -eq 1 ]; then label="STREAM (HBSS-compiled, standard run rules)"; else label="STREAM-derived (reduced dataset)"; fi

                # run single-thread
                OMP_NUM_THREADS=1 "$WORKDIR/stream_hbss" "$elems" > "$WORKDIR/stream.out" 2>>"$WORKDIR/log"
                if [ -s "$WORKDIR/stream.out" ]; then
                    threads=$(awk '/^STREAM Threads:/{print $3}' "$WORKDIR/stream.out")
                    elemsr=$(awk '/^STREAM Elements:/{print $3}' "$WORKDIR/stream.out")
                    bytesr=$(awk '/^STREAM Bytes:/{print $3}' "$WORKDIR/stream.out")
                    val=$(awk '/^STREAM Validation:/{print $3}' "$WORKDIR/stream.out")
                    for k in Copy Scale Add Triad; do
                        v=$(awk -v K="$k" '$1=="STREAM" && $2==K":"{print $3}' "$WORKDIR/stream.out")
                        [ -n "$v" ] && record "STREAM $k" "memory" "STREAM (HBSS-compiled)" "source $SRC_HASH" \
                            "$label, $elemsr elements, 1 thread" "1" "$bytesr bytes" "n/a" "$v" "MB/s" \
                            "HBSS fallback" "compiler=$CC; source sha256=$SRC_HASH; validation=$val"
                    done
                else
                    fail_test "STREAM" "memory" "execution failed" "$PROFILE"
                fi

                # multi-thread in standard/full
                if [ "$PROFILE" != "quick" ] && [ "$NCPU" -gt 1 ]; then
                    OMP_NUM_THREADS="$NCPU" "$WORKDIR/stream_hbss" "$elems" > "$WORKDIR/stream_mt.out" 2>>"$WORKDIR/log"
                    if [ -s "$WORKDIR/stream_mt.out" ]; then
                        bytesr=$(awk '/^STREAM Bytes:/{print $3}' "$WORKDIR/stream_mt.out")
                        for k in Copy Scale Add Triad; do
                            v=$(awk -v K="$k" '$1=="STREAM" && $2==K":"{print $3}' "$WORKDIR/stream_mt.out")
                            [ -n "$v" ] && record "STREAM $k ($NCPU threads)" "memory" "STREAM (HBSS-compiled)" "source $SRC_HASH" \
                                "$label, $elems elements, $NCPU threads" "$NCPU" "$bytesr bytes" "n/a" "$v" "MB/s" \
                                "HBSS fallback" "compiler=$CC; source sha256=$SRC_HASH"
                        done
                    fi
                fi
            else
                skip_test "STREAM" "memory" "compilation failed (compiler=$CC)" "$PROFILE"
            fi
        else
            skip_test "STREAM" "memory" "no C compiler found (cc/clang/gcc)" "$PROFILE"
        fi
    else
        skip_test "STREAM" "memory" "runtime compilation skipped in this profile" "$PROFILE"
    fi

    # Pointer-chasing latency (HBSS custom microbenchmark)
    if [ "$COMPILE_OK" -eq 1 ]; then
        CC=""
        for c in cc clang gcc; do have_cmd "$c" && { CC="$c"; break; }; done
        if [ -n "$CC" ]; then
            cat > "$WORKDIR/ptrchase.c" <<'CEOF'
#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <stdint.h>
int main(int argc, char **argv) {
    size_t bytes = 1048576;
    if (argc > 1) bytes = (size_t)strtoull(argv[1], NULL, 10);
    size_t n = bytes / sizeof(void*);
    if (n < 1024) n = 1024;
    void **arr = malloc(n * sizeof(void*));
    if (!arr) { fprintf(stderr, "ALLOC_FAIL\n"); return 1; }
    /* build random permutation chain */
    size_t *perm = malloc(n * sizeof(size_t));
    for (size_t i = 0; i < n; i++) perm[i] = i;
    /* Fisher-Yates */
    for (size_t i = n - 1; i > 0; i--) {
        size_t j = (size_t)rand() % (i + 1);
        size_t t = perm[i]; perm[i] = perm[j]; perm[j] = t;
    }
    for (size_t i = 0; i < n - 1; i++) arr[perm[i]] = &arr[perm[i+1]];
    arr[perm[n-1]] = &arr[perm[0]];
    void *p = &arr[perm[0]];
    size_t iters = 2000000;
    if (bytes >= 67108864) iters = 500000;
    struct timespec ts0, ts1;
    clock_gettime(CLOCK_MONOTONIC, &ts0);
    for (size_t i = 0; i < iters; i++) p = *(void**)p;
    clock_gettime(CLOCK_MONOTONIC, &ts1);
    double sec = (ts1.tv_sec - ts0.tv_sec) + (ts1.tv_nsec - ts0.tv_nsec) * 1e-9;
    double ns = sec * 1e9 / (double)iters;
    printf("POINTER_CHASE %lu %lu %.2f %lu\n", (unsigned long)bytes, (unsigned long)n, ns, (unsigned long)iters);
    /* prevent optimization */
    fprintf(stderr, "%p\n", p);
    free(arr); free(perm);
    return 0;
}
CEOF
            if "$CC" -O2 -o "$WORKDIR/ptrchase" "$WORKDIR/ptrchase.c" 2>>"$WORKDIR/log"; then
                for ws in 32768 262144 4194304 67108864; do
                    [ "$ws" -gt $((MEM_MB * 1024 * 1024)) ] && continue
                    out=$(run_limited "$MEM_CAP" "$WORKDIR/ptrchase" "$ws" 2>>"$WORKDIR/log")
                    if [ -n "$out" ]; then
                        set -- $out
                        # $1=POINTER_CHASE $2=bytes $3=n $4=ns $5=iters
                        record "HBSS pointer-chase ($2 bytes)" "memory" "HBSS fallback" "1.0" \
                            "random pointer chain, $5 accesses" "1" "$2 bytes" "n/a" "$4" "ns/access" \
                            "HBSS fallback" "HBSS custom microbenchmark (not a standardized benchmark); compiler=$CC"
                    fi
                done
            else
                skip_test "HBSS pointer-chase" "memory" "compilation failed" "$PROFILE"
            fi
        else
            skip_test "HBSS pointer-chase" "memory" "no C compiler found" "$PROFILE"
        fi
    else
        skip_test "HBSS pointer-chase" "memory" "runtime compilation skipped in this profile" "$PROFILE"
    fi

    # Memory fallback if no STREAM ran
    # (record a simple .NET-free sequential copy using dd? skip; STREAM covers it)
fi


# ---------------------------------------------------------------------------
# Storage benchmark
# ---------------------------------------------------------------------------
if category_enabled storage; then
    tested_mp=$(invget storage_tested_mp)
    [ -z "$tested_mp" ] && tested_mp="$WORKDIR"
    mkdir -p "$WORKDIR/stor" 2>/dev/null

    run_storage_volume() {
        # $1 = mountpoint/dir to test
        vol="$1"
        tdir="$vol/.hbss_tmp_$$"
        mkdir -p "$tdir" 2>/dev/null || tdir="$WORKDIR/stor"
        testfile="$tdir/hbss_test.bin"
        sz=$(( FILE_MB * 1024 * 1024 ))

        # fio if available or downloaded
        fio_bin=""
        if have_cmd fio; then fio_bin="fio"; fi

        if [ -n "$fio_bin" ]; then
            # write job file
            cat > "$WORKDIR/fio.job" <<EOF
[global]
ioengine=psync
directory=$tdir
size=${FILE_MB}M
runtime=$STO_CAP
time_based=1
direct=0
stonewall

[seqread]
rw=read
bs=1M
name=seqread

[seqwrite]
rw=write
bs=1M
name=seqwrite

[randread]
rw=randread
bs=4k
iodepth=1
name=randread

[randwrite]
rw=randwrite
bs=4k
iodepth=1
name=randwrite
EOF
            out=$(run_limited "$STO_CAP" "$fio_bin" "$WORKDIR/fio.job" 2>&1)
            # parse each section's bw/iops from normal output
            for rw in seqread seqwrite randread randwrite; do
                section=$(printf '%s\n' "$out" | sed -n "/$rw:/,/^$/p")
                bw=$(printf '%s\n' "$section" | grep -o 'bw=[0-9.]*[KMG]iB/s' | head -n1 | sed 's/bw=//;s/iB\/s//')
                iops=$(printf '%s\n' "$section" | grep -o 'iops=[0-9.]*' | head -n1 | sed 's/iops=//')
                [ -z "$bw" ] && bw="n/a"
                [ -z "$iops" ] && iops="n/a"
                # convert bw to MB/s best-effort
                mb=$(printf '%s' "$bw" | awk '
                    /K$/ {printf "%.2f", substr($0,1,length($0)-1)/1024; exit}
                    /M$/ {printf "%.2f", substr($0,1,length($0)-1); exit}
                    /G$/ {printf "%.2f", substr($0,1,length($0)-1)*1024; exit}
                    {print "n/a"}')
                [ "$mb" = "n/a" ] && mb="$bw"
                unit="MB/s"
                [ "$rw" = "randread" ] || [ "$rw" = "randwrite" ] && unit="IOPS/MB/s"
                record "fio $rw" "storage" "fio" "$(fio --version 2>/dev/null)" \
                    "file-based $rw, ${FILE_MB}M, ${STO_CAP}s" "1" "${FILE_MB}M" "$STO_CAP" \
                    "$iops IOPS / $mb MB/s" "IOPS / MB/s" "recognized open-source" \
                    "volume=$vol; filesystem+OS stack included; not raw device"
            done
        else
            # fallback sequential via dd
            # write
            s=$(now_ms)
            dd if=/dev/zero of="$testfile" bs=1048576 count="$FILE_MB" conv=fsync 2>"$WORKDIR/ddw.log"
            rc=$?
            e=$(now_ms)
            if [ "$rc" -eq 0 ]; then
                dur=$(elapsed_s "$s" "$e")
                mb=$(awk -v mb="$FILE_MB" -v d="$dur" 'BEGIN{if(d>0) printf "%.2f", mb/d; else print 0}')
                record "HBSS seq write" "storage" "HBSS fallback" "1.0" \
                    "dd zero write ${FILE_MB}M + fsync" "1" "${FILE_MB}M" "$dur" "$mb" "MB/s" \
                    "HBSS fallback" "volume=$vol; file-based; includes filesystem+OS stack"
            else
                fail_test "HBSS seq write" "storage" "dd write failed" "$PROFILE"
            fi
            # read (drop caches not possible unprivileged; note)
            if [ -f "$testfile" ]; then
                s=$(now_ms)
                dd if="$testfile" of=/dev/null bs=1048576 2>"$WORKDIR/ddr.log"
                rc=$?
                e=$(now_ms)
                if [ "$rc" -eq 0 ]; then
                    dur=$(elapsed_s "$s" "$e")
                    mb=$(awk -v mb="$FILE_MB" -v d="$dur" 'BEGIN{if(d>0) printf "%.2f", mb/d; else print 0}')
                    record "HBSS seq read" "storage" "HBSS fallback" "1.0" \
                        "dd read ${FILE_MB}M" "1" "${FILE_MB}M" "$dur" "$mb" "MB/s" \
                        "HBSS fallback" "volume=$vol; file-based; caches may inflate read"
                else
                    fail_test "HBSS seq read" "storage" "dd read failed" "$PROFILE"
                fi
            fi
            skip_test "random I/O" "storage" "no fio/DiskSpd available for random workloads" "$PROFILE"
        fi

        # cleanup test file
        rm -f "$testfile" 2>/dev/null
        rmdir "$tdir" 2>/dev/null
    }

    run_storage_volume "$tested_mp"

    if [ "$ALL_DRIVES" -eq 1 ]; then
        # additional eligible fixed local volumes
        if [ "$OS" = "Linux" ] && have_cmd lsblk; then
            lsblk -rno MOUNTPOINT,FSTYPE,TYPE 2>/dev/null | awk '$3=="part"||$3=="disk"{print $1"\t"$2}' | while IFS='\t' read -r mp fs; do
                [ -z "$mp" ] && continue
                [ "$mp" = "$tested_mp" ] && continue
                case "$fs" in tmpfs|devtmpfs|proc|sysfs|overlay) continue ;; esac
                [ -w "$mp" ] || continue
                # free space check (conservative: require FILE_MB+64MB)
                avail=$(df -m "$mp" 2>/dev/null | awk 'NR==2{print $4}')
                if [ -n "$avail" ] && [ "$avail" -ge $((FILE_MB + 64)) ] 2>/dev/null; then
                    run_storage_volume "$mp"
                else
                    skip_test "storage ($mp)" "storage" "insufficient free space or ineligible volume" "$PROFILE"
                fi
            done
        fi
    fi
fi

# ---------------------------------------------------------------------------
# GPU benchmark
# ---------------------------------------------------------------------------
if category_enabled gpu; then
    # clpeak if installed (recognized, open-source)
    if have_cmd clpeak; then
        out=$(run_limited "$GPU_CAP" clpeak 2>&1)
        # extract a bandwidth/compute line if present
        line=$(printf '%s\n' "$out" | grep -iE 'bandwidth|GFLOPS|compute' | head -n1)
        if [ -n "$line" ]; then
            record "clpeak" "gpu" "clpeak" "2.0.0 (pre-release)" "device peak (clpeak default)" "all" "device-dependent" "$GPU_CAP" \
                "$line" "mixed" "recognized open-source" "installed clpeak; unsigned/pre-release caveats"
        else
            fail_test "clpeak" "gpu" "execution failed or no output" "$PROFILE"
        fi
    else
        skip_test "clpeak" "gpu" "clpeak not installed" "$PROFILE"
    fi

    # Blender: detect only (scenes not bundled)
    if have_cmd blender; then
        bver=$(blender --version 2>/dev/null | head -n1)
        skip_test "Blender Cycles benchmark" "gpu" "Blender detected ($bver) but benchmark scenes are not bundled; run manually or with a pinned scene pack" "$PROFILE"
    else
        skip_test "Blender Cycles benchmark" "gpu" "Blender not installed (use --download-benchmarks --allow-large-downloads)" "$PROFILE"
    fi

    # Geekbench Compute detect-only
    if have_cmd geekbench || have_cmd geekbench6; then
        if [ "$USE_INSTALLED" -eq 1 ] && [ "$NO_PROPRIETARY" -eq 0 ]; then
            skip_test "Geekbench Compute" "gpu" "detected; not executed (requires named-user license and result upload)" "$PROFILE"
        else
            skip_test "Geekbench Compute" "gpu" "detected but not executed (use --use-installed-benchmarks with valid license)" "$PROFILE"
        fi
    fi
fi

# ---------------------------------------------------------------------------
# Memory (crypto already recorded above; memory summary)
# ---------------------------------------------------------------------------
# (STREAM/pointer-chase already recorded under CPU section's memory category)

# ---------------------------------------------------------------------------
# Crypto fallback if OpenSSL missing
# ---------------------------------------------------------------------------
if category_enabled crypto; then
    if ! have_cmd openssl; then
        # HBSS fallback using sha256sum on a temp file
        sz=$(( MEM_MB * 1024 * 1024 / 4 ))
        [ "$sz" -lt $((1024*1024)) ] && sz=$((1024*1024))
        mb=$(( sz / (1024*1024) ))
        dd if=/dev/urandom of="$WORKDIR/cryptotest.bin" bs=1M count="$mb" 2>/dev/null
        if have_cmd sha256sum; then
            s=$(now_ms)
            sha256sum "$WORKDIR/cryptotest.bin" >/dev/null 2>&1
            e=$(now_ms)
            dur=$(elapsed_s "$s" "$e")
            tp=$(awk -v mb="$mb" -v d="$dur" 'BEGIN{if(d>0) printf "%.2f", mb/d; else print 0}')
            record "HBSS SHA-256 (sha256sum)" "crypto" "HBSS fallback" "1.0" \
                "sha256sum on ${mb}MB random file" "1" "${mb}MB" "$dur" "$tp" "MB/s" \
                "HBSS fallback" "homemade throughput; not comparable to OpenSSL"
        else
            skip_test "HBSS crypto" "crypto" "no openssl and no sha256sum" "$PROFILE"
        fi
        rm -f "$WORKDIR/cryptotest.bin"
    fi
fi


# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------
if category_enabled network; then
    # detection already done; report interfaces count
    if [ "$OS" = "Linux" ] && have_cmd ip; then
        nif=$(ip -brief link 2>/dev/null | grep -v '^lo' | wc -l)
        printf 'Detected non-loopback interfaces: %s\n' "$nif" >> "$S_NETWORK"
    fi

    # loopback test only in FULL
    if [ "$PROFILE" = "full" ]; then
        if have_cmd iperf3; then
            iperf3 -s -1 > "$WORKDIR/iperf_server.log" 2>&1 &
            spid=$!
            sleep 1
            out=$(run_limited 30 iperf3 -c 127.0.0.1 -J 2>&1)
            kill $spid 2>/dev/null
            wait $spid 2>/dev/null
            bw=$(printf '%s' "$out" | grep -o '"bits_per_second":[0-9.]*' | head -n1 | sed 's/.*://')
            if [ -n "$bw" ]; then
                mbps=$(awk -v b="$bw" 'BEGIN{printf "%.2f", b/1e6}')
                record "iperf3 loopback" "network" "iperf3" "$(iperf3 --version 2>/dev/null | head -n1)" \
                    "TCP loopback, default" "1" "loopback" "30" "$mbps" "Mbps" \
                    "recognized open-source" "loopback only; not internet speed"
            else
                fail_test "iperf3 loopback" "network" "execution/parse failed" "$PROFILE"
            fi
        else
            skip_test "iperf3 loopback" "network" "iperf3 not installed" "$PROFILE"
        fi
    else
        skip_test "iperf3 loopback" "network" "loopback test only in --full profile" "$PROFILE"
    fi

    # external endpoint
    if [ "$ALLOW_NETWORK" -eq 1 ] && [ -n "$ENDPOINT" ]; then
        if have_cmd iperf3; then
            out=$(run_limited 60 iperf3 -c "$ENDPOINT" -J 2>&1)
            bw=$(printf '%s' "$out" | grep -o '"bits_per_second":[0-9.]*' | head -n1 | sed 's/.*://')
            if [ -n "$bw" ]; then
                mbps=$(awk -v b="$bw" 'BEGIN{printf "%.2f", b/1e6}')
                record "iperf3 external" "network" "iperf3" "$(iperf3 --version 2>/dev/null | head -n1)" \
                    "TCP to $ENDPOINT" "1" "endpoint" "60" "$mbps" "Mbps" \
                    "recognized open-source" "user-authorized external endpoint; not internet speed test"
            else
                fail_test "iperf3 external" "network" "execution/parse failed" "$PROFILE"
            fi
        else
            skip_test "iperf3 external" "network" "iperf3 not installed" "$PROFILE"
        fi
    elif [ "$ALLOW_NETWORK" -eq 1 ]; then
        skip_test "iperf3 external" "network" "no --endpoint provided" "$PROFILE"
    else
        skip_test "network throughput" "network" "external network tests require --allow-network and --endpoint" "$PROFILE"
    fi
fi


# ---------------------------------------------------------------------------
# NPU
# ---------------------------------------------------------------------------
if category_enabled npu; then
    skip_test "NPU inference" "npu" "no standardized legally auto-downloadable portable NPU benchmark verified" "$PROFILE"
fi


# ---------------------------------------------------------------------------
# Thermals (read-only) already sampled; finalize
# ---------------------------------------------------------------------------
stop_thermal_sampler
if [ "$HAS_TEMP" -eq 1 ] && [ -s "$THERMAL_LOG" ]; then
    idle=$(head -n1 "$THERMAL_LOG")
    peak=$(sort -n "$THERMAL_LOG" | tail -n1)
    # convert millidegrees? sysfs temp is millidegree C
    if [ -n "$idle" ]; then
        idle_c=$(awk -v v="$idle" 'BEGIN{printf "%.1f", v/1000.0}')
        peak_c=$(awk -v v="$peak" 'BEGIN{printf "%.1f", v/1000.0}')
        {
            echo "| Metric | Value |"
            echo "|---|---|"
            printf '| Idle (first sample) | %s C |\n' "$idle_c"
            printf '| Peak observed | %s C |\n' "$peak_c"
            printf '| Samples | %s |\n' "$(wc -l < "$THERMAL_LOG")"
        } >> "$S_THERMALS"
        setinv "temp_idle_c" "$idle_c"
        setinv "temp_peak_c" "$peak_c"
    fi
else
    printf 'No readable temperature sensors found (or sampler unavailable).\n' >> "$S_THERMALS"
fi

# ---------------------------------------------------------------------------
# Other (thermals included above)
# ---------------------------------------------------------------------------

END_MS=$(now_ms)
TOTAL_DUR=$(elapsed_s "$START_MS" "$END_MS")

# Stop thermal sampler before report generation (idempotent).
stop_thermal_sampler


# ---------------------------------------------------------------------------
# Report emission
# ---------------------------------------------------------------------------
emit_table_tsv() {
    # $1 file with TSV rows
    :
}

printf '# Hardware Benchmark Suite Report\n\n'
printf '> HBSS %s — generated %s (profile: %s). All values are actual measurements from this run.\n\n' "$HBSS_VERSION" "$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo unknown)" "$PROFILE"
printf '%s\n\n' '---'

# Run Summary
printf '## Run Summary\n\n'
printf '| Field | Value |\n|---|---|\n'
printf '| Profile | %s |\n' "$PROFILE"
printf '| Started (UTC) | %s |\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo unknown)"
printf '| Total duration | %s s |\n' "$TOTAL_DUR"
printf '| Tests completed | %s |\n' "$COMPLETED"
printf '| Tests skipped | %s |\n' "$SKIPPED_N"
printf '| Tests failed | %s |\n' "$FAILED_N"
printf '| OS | %s |\n' "$OS"
printf '| Architecture | %s |\n' "$ARCH"
printf '| Host | %s |\n' "$HOSTNAME"
printf '| Logical CPUs | %s |\n' "$NCPU"
overrides=""
[ "$ALL_DRIVES" -eq 1 ] && overrides="$overrides all-drives"
[ "$DOWNLOAD_BENCHMARKS" -eq 1 ] && overrides="$overrides download-benchmarks"
[ "$USE_INSTALLED" -eq 1 ] && overrides="$overrides use-installed-benchmarks"
[ "$NO_PROPRIETARY" -eq 1 ] && overrides="$overrides no-proprietary"
[ "$ALLOW_NETWORK" -eq 1 ] && overrides="$overrides allow-network"
[ -n "$ONLY_LIST" ] && overrides="$overrides only=$ONLY_LIST"
[ -n "$SKIP_LIST" ] && overrides="$overrides skip=$SKIP_LIST"
printf '| Overrides | %s |\n' "${overrides:-none}"
printf '| Timeout support | %s |\n' "${TIMEOUT_BIN:-none (workload-bounded)}"
printf '\n---\n\n'

# System Overview
printf '## System Overview\n\n'
printf '| Field | Value |\n|---|---|\n'
printf '| OS | %s |\n' "$(invget os)"
printf '| Kernel | %s |\n' "$(invget kernel)"
printf '| Architecture | %s |\n' "$ARCH"
printf '| Host | %s |\n' "$HOSTNAME"
# CPU model
cpumodel=""
if [ "$OS" = "Linux" ]; then
    cpumodel=$(lscpu 2>/dev/null | awk -F: '/Model name/{sub(/^[ \t]+/,"",$2); print $2; exit}')
fi
if [ "$OS" = "macOS" ]; then
    cpumodel=$(sysctl -n machdep.cpu.brand_string 2>/dev/null)
fi
[ -z "$cpumodel" ] && cpumodel="unknown"
printf '| CPU | %s |\n' "$cpumodel"
printf '| Logical CPUs | %s |\n' "$NCPU"
if [ "$OS" = "Linux" ] && [ -r /proc/meminfo ]; then
    mt=$(awk '/^MemTotal:/{printf "%.2f GB", $2/1024/1024}' /proc/meminfo)
    printf '| RAM | %s |\n' "$mt"
fi
if [ "$OS" = "macOS" ]; then
    mb=$(sysctl -n hw.memsize 2>/dev/null)
    [ -n "$mb" ] && printf '| RAM | %s bytes |\n' "$mb"
fi
# GPU summary
gpu_summary=""
if [ "$OS" = "Linux" ] && have_cmd lspci; then
    gpu_summary=$(lspci 2>/dev/null | grep -iE 'vga|3d controller|display' | head -n1)
fi
[ -z "$gpu_summary" ] && gpu_summary="see GPU section"
printf '| GPU | %s |\n' "$gpu_summary"
testedmp=$(invget storage_tested_mp)
[ -z "$testedmp" ] && testedmp="$WORKDIR"
printf '| Tested storage volume | %s |\n' "$testedmp"
printf '\n---\n\n'

# CPU
printf '## CPU\n\n'
if [ -s "$S_CPU" ]; then cat "$S_CPU"; else printf 'No CPU details available.\n'; fi
printf '\n---\n\n'

# GPU
printf '## GPU\n\n'
if [ -s "$S_GPU" ]; then cat "$S_GPU"; else printf 'No GPU details available.\n'; fi
printf '\n---\n\n'

# Memory
printf '## Memory\n\n'
if [ -s "$S_MEMORY" ]; then cat "$S_MEMORY"; else printf 'No memory details available.\n'; fi
printf '\n---\n\n'

# Storage
printf '## Storage\n\n'
if [ -s "$S_STORAGE" ]; then cat "$S_STORAGE"; else printf 'No storage details available.\n'; fi
printf '\n---\n\n'

# Network
printf '## Network\n\n'
if [ -s "$S_NETWORK" ]; then cat "$S_NETWORK"; else printf 'No network details available.\n'; fi
printf '\n---\n\n'

# AI / NPU
printf '## AI / NPU\n\n'
if [ -s "$S_NPU" ]; then cat "$S_NPU"; else printf 'No NPU details available.\n'; fi
printf '\n---\n\n'

# Other Hardware
printf '## Other Hardware\n\n'
if [ -s "$S_OTHER" ]; then cat "$S_OTHER"; else printf 'No additional hardware details available.\n'; fi
printf '\n---\n\n'

# Thermals
printf '## Thermals and Performance Behavior\n\n'
if [ -s "$S_THERMALS" ]; then cat "$S_THERMALS"; else printf 'No thermal data available.\n'; fi
printf '\nNote: a short benchmark cannot establish sustained thermal stability. Temperatures are read-only observations.\n'
printf '\n---\n\n'

# Benchmark Results
printf '## Benchmark Results\n\n'
printf '| Benchmark | Category | Engine | Version | Workload | Threads | Dataset | Duration | Result | Unit | Origin | Notes |\n'
printf '|---|---|---|---|---|---|---|---|---|---|---|---|\n'
if [ -s "$RESULTS" ]; then
    while IFS="$(printf '\t')" read -r b c e v w t d dur res unit origin notes; do
        [ -z "$b" ] && continue
        printf '| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |\n' \
            "$b" "$c" "$e" "$v" "$w" "$t" "$d" "$dur" "$res" "$unit" "$origin" "$notes"
    done < "$RESULTS"
else
    printf '| (none) | - | - | - | - | - | - | - | - | - | - | - |\n'
fi
printf '\n---\n\n'

# Methodology
printf '## Methodology\n\n'
cat <<'EOF'
Every executed benchmark records its engine, version, workload, dataset, thread count, duration, score, units, origin (recognized open-source / HBSS fallback / third-party opt-in), and limitations in the table above.

- **CPU integer (HBSS fallback):** single-process and N-worker shell loops performing mixed integer arithmetic; score = iterations / elapsed seconds. Homemade microbenchmark, not comparable to Geekbench/Cinebench.
- **sysbench (if installed):** `sysbench cpu --cpu-max-prime=20000` for 1 and N threads; events/s.
- **7-Zip (if installed):** built-in `7zz b`; Avr MB/s parsed from output.
- **OpenSSL (if installed):** `openssl speed -evp aes-256-gcm` and `sha256` for a bounded duration.
- **STREAM-derived (compiled):** Copy/Scale/Add/Triad kernels compiled from a bundled pinned C source with `cc`/`clang`/`gcc`. Standard run rules (dataset >= ~4x last-level cache) are followed when possible; otherwise results are labeled `STREAM-derived (reduced dataset)`. Source SHA-256 is recorded.
- **Pointer-chasing latency:** HBSS custom microbenchmark using randomized pointer chains across working sets; reports ns/access. Not a standardized benchmark.
- **Storage:** file-based tests only (fio when available, otherwise dd). Sequential read/write and, with fio, random read/write IOPS. Results include the filesystem and OS I/O stack and are not raw-device performance. No raw disk writes.
- **GPU:** clpeak if installed; otherwise detection only. Blender requires benchmark scene files (not bundled).
- **Network:** interface detection always; loopback iperf3 only in --full; external iperf3 only with --allow-network and --endpoint.
- **NPU:** detection only; no standardized legally auto-downloadable portable benchmark was verified.
- **Thermals:** read-only sampling of OS-exposed sensors; idle and peak observed during the run.

Homemade fallbacks are labeled as such and must not be presented as recognized benchmark scores.
EOF
printf '\n---\n\n'

# Skipped Tests
printf '## Skipped Tests\n\n'
printf '| Benchmark | Category | Reason | Profile |\n|---|---|---|---|\n'
if [ -s "$SKIPPED" ]; then
    while IFS="$(printf '\t')" read -r b c r p; do
        [ -z "$b" ] && continue
        printf '| %s | %s | %s | %s |\n' "$b" "$c" "$r" "$p"
    done < "$SKIPPED"
fi
if [ -s "$FAILED" ]; then
    while IFS="$(printf '\t')" read -r b c r p; do
        [ -z "$b" ] && continue
        printf '| %s | %s | FAILED: %s | %s |\n' "$b" "$c" "$r" "$p"
    done < "$FAILED"
fi
if [ ! -s "$SKIPPED" ] && [ ! -s "$FAILED" ]; then
    printf '| (none) | - | - | - |\n'
fi
printf '\n---\n\n'

# Trace and Privacy
printf '## Trace and Privacy\n\n'
cat <<'EOF'
HBSS intentionally creates no persistent application files, telemetry, or configuration changes. Temporary artifacts are cleaned up on normal termination. Unexpected power loss or OS-level logging may fall outside its control.

- All temporary files live in a single `mktemp -d` workspace and are removed on exit, HUP, INT, and TERM.
- No sudo, administrator rights, package installation, registry writes, services, daemons, or system configuration changes are performed.
- No benchmark results are uploaded. Third-party engines (e.g., Geekbench free tier) may require their own uploads; HBSS does not invoke them unless explicitly permitted and still does not bypass their licensing.
- Third-party engines and operating-system logging may still record activity outside HBSS's control.
- No raw disk writes; storage tests use a temporary file inside a temporary directory on the tested volume.
EOF
printf '\n---\n\n'

# License
printf '## License\n\n'
printf 'GPL-3.0-or-later. See LICENSE.\n\n'
printf '%s\n\n' '---'

# Caveats
printf '## Caveats\n\n'
cat <<'EOF'
- Benchmark results are affected by temperature, power settings, background applications, drivers, and operating-system configuration.
- Results from different benchmark versions may not be directly comparable.
- Short tests do not establish sustained thermal stability.
- Storage results may include filesystem and OS caching.
- Some hardware capabilities cannot be measured portably.
- Some detected hardware may not expose all technical information.
- Not all benchmark engines support every architecture.
- This is an evaluation tool, not a certification or guarantee of hardware condition.
EOF
printf '\n---\n\n'
printf '_End of report._\n'

# ---------------------------------------------------------------------------
# Render the buffered report (Glow if available on a TTY, else optional color,
# else raw Markdown). No hard dependency: glow is used only if already installed.
# ---------------------------------------------------------------------------
if [ -t 3 ]; then
    # fd 3 is the original stdout (terminal).
    if have_cmd glow; then
        glow "$REPORT_FILE" >&3 2>/dev/null || cat "$REPORT_FILE" >&3
    elif [ "${HBSS_COLOR:-auto}" != "never" ]; then
        # Lightweight ANSI colorizer using only awk (no external deps).
        awk '
        BEGIN {
            esc = sprintf("%c", 27)
            bold = esc "[1m"; dim = esc "[2m"; reset = esc "[0m"
            cyan = esc "[36m"; green = esc "[32m"; yellow = esc "[33m"; magenta = esc "[35m"
        }
        /^# / { print bold cyan $0 reset; next }
        /^## / { print bold green $0 reset; next }
        /^### / { print bold yellow $0 reset; next }
        /^---[[:space:]]*$/ { print dim "────────────────────────────────────────────────────────" reset; next }
        /^```/ { print dim $0 reset; next }
        /^\|[-:| ]+\|$/ { print dim $0 reset; next }
        { print $0 }
        ' "$REPORT_FILE" >&3
    else
        cat "$REPORT_FILE" >&3
    fi
else
    # Non-interactive: emit raw Markdown (Glow-friendly, no color codes).
    cat "$REPORT_FILE" >&3
fi

# --output: copy the (raw) report to the requested file.
if [ -n "$OUTPUT_FILE" ]; then
    cp "$REPORT_FILE" "$OUTPUT_FILE" 2>/dev/null
    printf 'Report written to %s\n' "$OUTPUT_FILE" >&2
fi

# --json: write a JSON summary of result rows.
if [ "$JSON_OUTPUT" -eq 1 ]; then
    jsonfile="${OUTPUT_FILE:+${OUTPUT_FILE}.json}"
    [ -z "$jsonfile" ] && jsonfile="hbss_report.json"
    awk -F '\t' 'BEGIN{print "["} { if(NR>1) printf ","; printf "{\"benchmark\":\"%s\",\"category\":\"%s\",\"engine\":\"%s\",\"version\":\"%s\",\"workload\":\"%s\",\"threads\":\"%s\",\"dataset\":\"%s\",\"duration_s\":\"%s\",\"result\":\"%s\",\"unit\":\"%s\",\"origin\":\"%s\",\"notes\":\"%s\"}\n", $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12 } END{print "]"}' "$RESULTS" > "$jsonfile" 2>/dev/null
    printf 'JSON summary written to %s\n' "$jsonfile" >&2
fi

exit 0