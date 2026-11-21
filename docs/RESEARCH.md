# HBSS — Primary-Source Research Findings: Benchmark Tools, Licensing & Inventory APIs

**Research date:** 2026-11-21
**Researcher:** Subagent (primary-source web research only; no code, no implementation)
**Scope:** Determine which benchmark engines HBSS may legally and safely auto-download and run under its hard constraints (no permanent install, no sudo/admin, no telemetry, no raw disk writes, pinned + SHA-256-verified downloads, per-test timeouts, three profiles, Linux / Windows 10+ PowerShell 5.1 / macOS Intel+Apple Silicon, x86_64 + ARM64), and which must be detected-only, skipped, or require a manual license.

**Method & trust note.** All external web content was treated as *untrusted data*. Facts below are drawn from official vendor sites, official documentation, official GitHub repositories/releases, and official license texts. Where a source is secondary it is explicitly labelled **[SECONDARY]**. "Could not verify" is used where no authoritative confirmation was found. Version numbers reflect what the official pages stated on the research date and will drift; HBSS should pin explicitly.

---

## 0. Executive summary (most decision-relevant facts)

1. **The three "famous" suites are not auto-downloadable.** Geekbench's EULA is a named-user, non-commercial, non-redistributable license that *requires uploading all results* to Primate Labs and only permits offline use with paid Pro; an "I accept" click may be required ([Geekbench 6 EULA](https://www.primatelabs.com/legal/eula-v6.html)). MAXON's EULA forbids copying/distribution/open-source-licensing and requires acceptance during registration; Cinebench is a free-license, named-user product with a separate site-wide "Cinebench Development Program" for OEMs ([MAXON EULA](https://www.maxon.net/en/legal/eula)). CrystalDiskMark is MIT/freeware but is **GUI-only, has no usable command-line arguments, and self-elevates via UAC**; its own maintainer says "CrystalDiskMark is only GUI wrapper of DiskSpd ... use DiskSpd directly" ([maintainer comment](https://github.com/hiyohiyo/CrystalDiskMark/issues/2), [official license](https://crystalmark.info/ja/software/crystaldiskmark/crystaldiskmark-license/)).
2. **The best legal auto-download engines are:** Phoronix Test Suite (GPLv3), Blender/Blender Benchmark offline CLI (GPL, Cycles CPU/GPU, official SHA-256 files), 7-Zip `7zz b` (LGPL, standalone console), fio (GPLv2), Microsoft DiskSpd (MIT, official SHA-256 digest via GitHub release API), and — with caveats — y-cruncher (custom, permissive mirroring/non-commercial license; x86-only) and clpeak (GPLv3, cross-API GPU/NPU; unsigned binaries).
3. **Sysfs/procfs/WMI/system_profiler are the right inventory backbone** — built into the OS, no download, no admin. Root/admin-requiring tools (dmidecode via `/dev/mem`, Intel MLC MSR access, macOS powermetrics) must be avoided or used only via their unprivileged fallbacks.
4. **No standardized, legally auto-downloadable, portable NPU benchmark was confirmed.** The cross-vendor NPU benchmarks found are proprietary (Novabench, PassMark PerformanceTest NPU Mark); the only open-licensed cross-API option (clpeak AI backends) is a pre-release with unsigned binaries and requires vendor runtimes.
5. **HBSS being GPL-3.0-or-later does not grant any right to redistribute proprietary third-party binaries** — each third-party license stands on its own ([GNU GPLv3 text](https://www.gnu.org/licenses/gpl-3.0.html), [SPDX GPL-3.0-or-later](https://spdx.org/licenses/GPL-3.0-or-later.html)).

---

## 1. Licensing & legal framework

### 1.1 GPLv3 / "GPL-3.0-or-later" obligations
- The official, canonical GPLv3 text is at [gnu.org/licenses/gpl-3.0.html](https://www.gnu.org/licenses/gpl-3.0.html); SPDX defines `GPL-3.0-or-later` as "GPLv3 or some later version" and notes the license was released 29 June 2007 ([SPDX](https://spdx.org/licenses/GPL-3.0-or-later.html)).
- **Conveying verbatim source** (GPLv3 §4): keep copyright notices, license notices, warranty disclaimers, and give recipients a copy of the License; you may charge any price ([SPDX-reproduced GPLv3 §4](https://spdx.org/licenses/GPL-3.0-or-later.html)).
- **Modified source** (§5): mark changes with dates, license the whole work under GPLv3, keep notices; interactive interfaces must display appropriate legal notices where the original does ([SPDX](https://spdx.org/licenses/GPL-3.0-or-later.html)).
- **Object/binary form** (§6): convey with Corresponding Source, or a written offer valid ≥3 years, or (for noncommercial) an identified source location; "System Libraries" are excluded ([SPDX](https://spdx.org/licenses/GPL-3.0-or-later.html)).
- "Convey" means any propagation enabling others to make/receive copies; mere network interaction without transferring a copy is not conveying ([SPDX](https://spdx.org/licenses/GPL-3.0-or-later.html)). **Implication for HBSS:** a curl-to-shell script that is executed on the user's own machine, without redistributing third-party binaries, is not conveying those binaries. Each auto-downloaded binary nevertheless must itself legally permit that download/execution and any redistribution.
- **Why GPL does not unlock proprietary tools:** a GPL license covers only the work the copyright holder placed under it. The Geekbench EULA explicitly prohibits "rent, lease, lend, sell, redistribute, sublicense, commercialize or otherwise commercially exploit" and prohibits making the app available over a network for multiple devices ([EULA §4](https://www.primatelabs.com/legal/eula-v6.html)). MAXON's EULA states the user "shall not ... cause the Software to become subject to ... an open source software license" and "may not copy, rework, decompile, reverse-engineer, distribute, modify or reproduce" except as law permits ([MAXON EULA §§1.11, 10.3](https://www.maxon.net/en/legal/eula)).

### 1.2 Privacy wording that is accurate for HBSS
- HBSS itself performs no telemetry; it writes to a temporary working directory and removes it at exit, and never writes to raw block devices. (Design intent, not an external factual claim.)
- **Third-party tools may have their own network behaviour:** Geekbench free "requires that all Benchmark Results be uploaded to Primate Labs' Online Services" ([EULA §2a](https://www.primatelabs.com/legal/eula-v6.html)) and reports that it "requires an active internet connection and automatically uploads benchmark results" ([AUR package comments quoting the CLI, SECONDARY](https://aur.archlinux.org/packages/geekbench)); Blender Open Data collects anonymous system data but can be run fully offline with `--background` ([Blender Open Data](https://opendata.blender.org/about/)); Phoronix Test Suite can upload to OpenBenchmarking.org, so HBSS must use non-interactive/batch mode and never auto-upload.
- **OS-level logging outside HBSS's control:** process execution may be recorded by OS facilities (e.g. Linux journald/auditd, Windows Event Log, macOS unified logging). HBSS cannot and should not claim to suppress these; phrasing should be "HBSS does not transmit data; third-party engines and operating-system logging may still record activity." (General OS behaviour; no vendor promise of silence exists.)

---

## 2. CPU / system suites

### 2.1 Geekbench 6 (and current Geekbench 7) + Geekbench CLI
- **Name/upstream/version/maintainer:** Geekbench, [geekbench.com](https://www.geekbench.com/) / Primate Labs Inc. The task names Geekbench 6, but the official Linux download page currently states **Geekbench 7.1.0** ([geekbench.com/download/linux](https://www.geekbench.com/download/linux/)) — verify current stable at pin time. Geekbench 6 was released 2023-02-14 ([blog](https://www.geekbench.com/blog/2023/02/geekbench-6/)).
- **License & redistribution:** Proprietary EULA. "Geekbench License" is "limited, personal, non-exclusive, **non-commercial**, non-transferable, perpetual, **non-sublicensable and revocable** ... for one (1) specific named user"; use "requires that all Benchmark Results be uploaded"; "Geekbench Pro License" is a paid named-user corporate license; "**may be asked ... to confirm your acceptance ... by clicking an 'I accept' button, checkbox, or similar mechanism**" ([EULA §§2, 4](https://www.primatelabs.com/legal/eula-v6.html)). Restrictions forbid network distribution, rental, sale, **redistribution**, sublicensing and commercialization ([EULA §4](https://www.primatelabs.com/legal/eula-v6.html)). Microsoft's VirtualClient docs state "GeekBench6 is a commercial workload. Virtual Client cannot distribute the license and binary" ([Microsoft docs](https://microsoft.github.io/VirtualClient/docs/workloads/geekbench/)).
- **CLI & invocation:** Official `geekbench6`/`geekbench` CLI exists; typical command `geekbench --cpu` (or `geekbench6 --cpu`); free tier prints "Geekbench 6 requires an active internet connection and automatically uploads benchmark results ... Upgrade to Geekbench 6 Pro to enable offline use ... `geekbench --unlock <email> <key>`" ([AUR package comments, SECONDARY but verbatim CLI output](https://aur.archlinux.org/packages/geekbench)).
- **Checksums / pinning / size:** Official tarballs at `cdn.geekbench.com/Geekbench-<version>-Linux.tar.gz`; no SHA-256 published on the official download page (verified: download page lists system requirements only). Microsoft docs show bundled runtimes for linux-arm64, linux-x64, win-arm64, win-x64 ([VirtualClient](https://microsoft.github.io/VirtualClient/docs/workloads/geekbench/)). **Result auto-upload = telemetry, disallowed by HBSS constraints.**
- **OS/arch:** macOS, Windows, Linux, iOS, Android ([EULA §3](https://www.primatelabs.com/legal/eula-v6.html)); Linux build requires Ubuntu 22.04+ / 4 GB RAM / Intel or AMD processor ([download page](https://www.geekbench.com/download/linux/)).
- **Caveats:** named-user/EULA click, no redistribution, mandatory uploads on free tier, Pro required for offline/headless. **Verdict: NEEDS-MANUAL-LICENSE.**

### 2.2 Cinebench (MAXON)
- **Name/upstream/maintainer:** Cinebench, MAXON (Maxon Computer GmbH for the Cinebench brand) ([MAXON EULA preamble](https://www.maxon.net/en/legal/eula)).
- **License:** Proprietary EULA, updated September 2026. Acceptance occurs "during the registration process and/or by downloading, installing, reproducing, or otherwise using"; "The use of the Software without the conclusion of this License Agreement is an infringement of copyright" ([EULA](https://www.maxon.net/en/legal/eula)). §1.11 forbids placing the software under an OSI/FSF open-source licence; §10.3 forbids copying/distribution/reproduction except as law permits; §9 licences are named-user, non-transferable, non-sublicensable ([EULA](https://www.maxon.net/en/legal/eula)). §9.3 allows free commercial use for entities under USD 1 billion revenue (with conditions) and points hardware manufacturers to the "Cinebench Development Program" for a site-wide licence ([EULA §9.3](https://www.maxon.net/en/legal/eula)).
- **CLI / headless:** No official headless CLI suitable for silent unattended use was verified; the product is a GUI benchmark distributed via MAXON's installer/account flow. EULA acceptance during registration blocks silent acceptance.
- **Checksums:** Not verified/published for a silent auto-download path.
- **Caveats:** interactive EULA, redistribution explicitly prohibited, no official standalone non-interactive engine. **Verdict: NEEDS-MANUAL-LICENSE** ( realistically SKIP for HBSS default; only usable if the user has independently installed and licensed it, and even then HBSS should not bundle it).

### 2.3 Phoronix Test Suite (PTS)
- **Name/upstream/version/maintainer:** Phoronix Test Suite, [phoronix-test-suite.com](https://www.phoronix-test-suite.com/), developed by Phoronix Media; README states v10.8.6 ([GitHub](https://github.com/phoronix-test-suite/phoronix-test-suite?tab=readme-ov-file)); stable v10.8.4 also widely packaged ([Homebrew formula](https://raw.githubusercontent.com/Homebrew/homebrew-core/master/Formula/p/phoronix-test-suite.rb)).
- **License:** GNU GPLv3 / "GPL-3.0-or-later"; "can be used for any personal or professional usage free of charge" ([download page](https://www.phoronix-test-suite.com/index.php?k=downloads), [Homebrew formula](https://raw.githubusercontent.com/Homebrew/homebrew-core/master/Formula/p/phoronix-test-suite.rb)).
- **CLI:** Fully automated engine: "fully automated manner from test installation to execution and reporting". Can run locally straight from an extracted tar.gz/zip without installation; only hard dependency is PHP CLI (PHP 5.3+) ([README](https://github.com/phoronix-test-suite/phoronix-test-suite?tab=readme-ov-file)). Non-interactive execution is supported via batch mode; HBSS must ensure results are not uploaded to OpenBenchmarking.org.
- **Checksums/pinning:** Official release tarballs on GitHub releases and `phoronix-test-suite.com/releases/` ([releases index](https://www.phoronix-test-suite.com/releases/)); Homebrew/Solus package files publish SHA-256 for pinned tarballs ([Homebrew](https://raw.githubusercontent.com/Homebrew/homebrew-core/master/Formula/p/phoronix-test-suite.rb), [Solus](https://raw.githubusercontent.com/getsolus/packages/main/packages/p/phoronix-test-suite/package.yml)).
- **OS/arch:** Linux, Solaris, *BSD, Hurd, macOS, Windows; PHP CLI required ([download page](https://www.phoronix-test-suite.com/index.php?k=downloads)).
- **Caveats:** PTS is a *test harness*: it downloads test profiles/dependencies from its own repositories, and those dependencies have heterogeneous licenses and may need compilers/root via package managers. HBSS should use only a curated allow-list of free tests, offline/batch mode, and SHA-256-pinned profiles. **Verdict: AUTO-DOWNLOAD + RUN (curated tests only).**

### 2.4 sysbench
- **Name/upstream/version/license:** sysbench, [github.com/akopytov/sysbench](https://github.com/akopytov/sysbench/), GPLv2 (README badge "GPLv2", spec "GPLv2+"), latest release 1.0.20 ([releases](https://github.com/akopytov/sysbench/releases)).
- **CLI:** `sysbench cpu run`, `sysbench memory run`, `sysbench fileio ...`; general syntax `sysbench [options]... [testname] [command]`; built-in `cpu`, `memory`, `fileio`, `threads`, `mutex` tests ([README](https://github.com/akopytov/sysbench/)).
- **Checksums/pinning/binary availability:** Distributed via packagecloud binary repos (x86_64, i386, aarch64) or Homebrew on macOS; **no standalone official prebuilt binary download with checksums**. Installing requires repository setup / sudo ([README](https://github.com/akopytov/sysbench/)).
- **OS/arch:** Linux, macOS (Homebrew); **native Windows support dropped as of 1.0** — WSL recommended ([README](https://github.com/akopytov/sysbench/)).
- **Caveats:** Requires LuaJIT and installation/build; conflicts with no-install/no-sudo. **Verdict: DETECT-IF-INSTALLED ONLY.**

### 2.5 lmbench (incl. `lat_mem_rd`)
- **Name/upstream/license:** lmbench, hosted at [lmbench.sourceforge.net](https://lmbench.sourceforge.net/) and [github.com/intel/lmbench](https://github.com/intel/lmbench) (GPLv2). Its `COPYING-2` adds restrictions that **override the GPL**: "You may not distribute results in any public forum, in any publication, or in any other way if you have modified the benchmarks" and "You may not distribute the results for a fee of any kind. This includes web sites which generate revenue from advertising" ([COPYING-2](https://github.com/intel/lmbench/blob/master/COPYING-2)). `lat_mem_rd.c` carries the same publication restriction ([source](https://github.com/intel/lmbench/blob/master/src/lat_mem_rd.c)).
- **CLI/binary:** `make results` from source; no official prebuilt binaries; no published checksums ([intel/lmbench README](https://github.com/intel/lmbench)).
- **Caveats:** Source-only build, non-standard GPL+restrictions on publishing results, no official binary. **Verdict: SKIP / UNRELIABLE** (at most detect-if-installed; do not bundle/report lmbench results as a normal published HBSS report).

### 2.6 y-cruncher
- **Name/upstream/version/maintainer:** y-cruncher by Alexander J. Yee, [numberworld.org/y-cruncher](https://numberworld.org/y-cruncher/); current release **v0.8.7 Build 9547 (2025-11-23)** ([homepage](https://numberworld.org/y-cruncher/)).
- **License:** Custom, permissive for HBSS-like use: "You may mirror and distribute this software free of charge for any purpose. You may use this software free of charge for any non-commercial purpose. You may also use this software for any academic purpose (including technology reviews), even if they are commercial"; commercial use requires contacting the author ([license](https://numberworld.org/y-cruncher/license.html)). **Caveat:** "Downloading any of these files constitutes as acceptance of the license agreement" ([download page](https://numberworld.org/y-cruncher/)) — a clickwrap-by-download, and licensing terms "may change at any time with or without prior notification" ([license](https://numberworld.org/y-cruncher/license.html)).
- **CLI/binary/size:** Official ZIP/TAR.XZ binaries: Windows 45.0 MB, Linux static 34.2 MB, Linux dynamic 27.4 MB ([download page](https://numberworld.org/y-cruncher/)). Compute/pi benchmark with command-line workload selection.
- **OS/arch:** Windows 8+ and 64-bit Linux; **x86/x64 only — no ARM64/Apple Silicon** ([download page](https://numberworld.org/y-cruncher/)).
- **Caveats:** x86-only; license acceptance by download; no SHA-256 published on the official page (verified: download page lists sizes, not hashes); heavy sustained CPU/memory/disk use. **Verdict: DETECT-IF-INSTALLED ONLY** (or strictly x86-only auto-download if HBSS pins its own verified hash and accepts the by-download acceptance).

### 2.7 Blender Benchmark / Blender (CPU + GPU)
- **Name/upstream/version/license:** Blender, Blender Foundation, [blender.org](https://www.blender.org/download/) / [opendata.blender.org](https://opendata.blender.org/about/); current stable **Blender 5.3.0 (2026-11-10)** ([download page](https://www.blender.org/download/)). Software is GNU GPL; benchmark scenes are public domain (CC0); results data are license-free/public domain ([Blender news](https://www.blender.org/news/introducing-blender-benchmark/), [Open Data about](https://opendata.blender.org/about/)).
- **CLI (official offline invocation):**
  `path-to-blender-executable --background --factory-startup -noaudio --debug-cycles --enable-autoexec --engine CYCLES scene-path.blend --python main.py -- --device-type CPU` — GPU device types are also supported; outputs the same score as the launcher ([Open Data "Run Offline"](https://opendata.blender.org/about/)). The launcher CLI also exposes `benchmark-launcher-cli benchmark ...` with JSON output ([Blender forum, SECONDARY](https://forum.blender.org/t/blender-benchmark-launcher-cli-and-documentation/11225)).
- **Checksums/pinning:** Official **SHA-256 files published** e.g. `https://download.blender.org/release/Blender5.3/blender-5.3.0.sha256` listing `blender-5.3.0-linux-x64.tar.xz`, `blender-5.3.0-windows-x64.zip`, `blender-5.3.0-windows-arm64.zip`, `blender-5.3.0-macos-arm64.dmg` ([sha256 file](https://download.blender.org/release/Blender5.3/blender-5.3.0.sha256), [release index](https://download.blender.org/release/Blender5.2/)). Sizes ~250–390 MB ([download page](https://www.blender.org/download/)).
- **OS/arch:** Windows x64/ARM64, Linux x64, macOS arm64 confirmed in the official SHA-256 manifest; **Intel macOS build availability must be verified at pin time** ([sha256 manifest](https://download.blender.org/release/Blender5.3/blender-5.3.0.sha256)).
- **Privileges:** No admin/sudo; scene files and cache go to user-writable dirs (e.g. `~/.cache/blender-benchmark-launcher`) ([Open Data about](https://opendata.blender.org/about/)).
- **Caveats:** Large download; offline mode must be used to avoid any upload; Cycles device detection can be fragile in headless VMs. **Verdict: AUTO-DOWNLOAD + RUN.**

### 2.8 7-Zip (`7zz b` benchmark)
- **Name/upstream/version/license:** 7-Zip by Igor Pavlov, [7-zip.org](https://7-zip.org/download.html); **v26.06 (2026-11-06)**. License: GNU LGPL (except unRar code); LZMA SDK public domain; some BSD-3-clause code ([readme](https://github.com/ip7z/7zip/blob/main/DOC/readme.txt)).
- **CLI:** `7zz b` runs the built-in benchmark ([Ubuntu manpage for 7zz](https://manpages.ubuntu.com/manpages/jammy/en/man1/7zz.1.html)); `7za` is the reduced-format standalone. `7zz` is the all-format standalone console binary ([readme](https://github.com/ip7z/7zip/blob/main/DOC/readme.txt)).
- **Binaries/checksums:** Official "7-Zip Extra" standalone console archives (`.7z` for Windows, `.tar.xz` for Linux x86-64/arm64 and macOS arm64/x86-64) are hosted on 7-zip.org with version-pinned paths ([download page](https://7-zip.org/download.html)). **No SHA-256 values are published on the official download page** (verified from fetched page) — HBSS must pin its own verified hashes.
- **OS/arch:** Windows x64/x86/arm64, Linux x86-64/arm64, macOS Intel/Apple Silicon console builds ([download page](https://7-zip.org/download.html)).
- **Privileges/size:** Standalone console archive, no install, no admin, small (~1–2 MB). **Verdict: AUTO-DOWNLOAD + RUN.**

---

## 3. Memory

### 3.1 STREAM
- **Name/upstream/maintainer:** STREAM benchmark, University of Virginia [cs.virginia.edu/stream](https://www.cs.virginia.edu/stream/ref); created/maintained by John D. McCalpin ([ref page](https://www.cs.virginia.edu/stream/ref)).
- **License:** Explicitly permissive: "You are free to use this program and/or to redistribute this program"; modification for commercial use allowed; publishing results allowed provided results are labelled if modified/non-compliant ("tuned STREAM benchmark results", "based on a variant..."); "Use ... constitutes acceptance of these licensing restrictions" ([run rules](https://www.cs.virginia.edu/stream/ref)).
- **Binary/CLI:** **Source-only** — official guidance strongly recommends compiling `stream.c` (or Fortran) yourself; "a few obsolete precompiled binaries" exist and are unlikely to obey current run rules ([ref page](https://www.cs.virginia.edu/stream/ref)). No official SHA-256.
- **Caveats:** Requires a compiler; run rules require arrays large enough for modern caches; call any variant an honestly-labelled HBSS fallback. **Verdict: SKIP / UNRELIABLE as an auto-download engine** (may be compiled locally into a temp dir and labelled "STREAM-derived" if a toolchain exists).

### 3.2 Intel MLC
- **Name/upstream/version:** Intel® Memory Latency Checker, v3.13; official download `mlc_v3.13.tgz`, size **1.3 MB**, published **SHA-256 `A8537E8FF3FAD626D75A383FABC224CCC4CC98A0111C9989F7FB26B639F12019`** ([download page](https://www.intel.com/content/www/us/en/download/736633/intel-memory-latency-checker-intel-mlc.html)).
- **License:** Custom Intel "Outbound License Agreement" shipped in the package; AUR marks it `LicenseRef-custom` ([AUR](https://aur.archlinux.org/packages/intel-mlc)); no general redistribution right verified.
- **Privileges/caveats:** "Root privileges are required to run this tool as the tool modifies the H/W prefetch control MSR"; MSR driver must be loaded (`modprobe msr`); Windows 3.13 reintroduced an MSR prefetcher driver ([Intel article](https://www.intel.com/content/www/us/en/developer/articles/tool/intelr-memory-latency-checker.html)). x86 only. **Verdict: SKIP / UNRELIABLE** — directly violates no-sudo/no-kernel-access constraint.

### 3.3 sysbench memory / lmbench lat_mem_rd / ramspeed
- **sysbench memory:** GPLv2, `sysbench memory run`; same detect-only constraints as §2.4 ([README](https://github.com/akopytov/sysbench/)). **Verdict: DETECT-IF-INSTALLED ONLY.**
- **lmbench `lat_mem_rd`:** GPL+publication restrictions; source-only ([source](https://github.com/intel/lmbench/blob/master/src/lat_mem_rd.c), [COPYING-2](https://github.com/intel/lmbench/blob/master/COPYING-2)). **Verdict: SKIP / UNRELIABLE.**
- **RAMspeed:** v2.6.0 (2009), custom `LicenseRef-Alasir`, UNIX-like i386/amd64/alpha only, build script only, official site alasir.com ([GitHub](https://github.com/cruvolo/ramspeed), [OpenEmbedded recipe](https://layers.openembedded.org/layerindex/recipe/516942/)). **Verdict: SKIP / UNRELIABLE** (obsolete, no ARM, unclear redistribution terms, no official binaries).

---

## 4. Storage

### 4.1 fio
- **Name/upstream/version/license:** fio ("flexible I/O tester"), [github.com/axboe/fio](https://github.com/axboe/fio/), GPLv2, canonical git at kernel.org; current release **fio-3.43 (2026-09-23)** ([releases API](https://api.github.com/repos/axboe/fio/releases/latest)).
- **CLI:** `fio <jobfile>` or command-line options; time-bounded jobs with `--runtime`/`--time_based`; use a **temporary file, never a raw device** (fio can destroy data on physical disks — same class of warning as DiskSpd).
- **Checksums/pinning:** Windows x64/x86 **MSI installers** published as GitHub release assets with upstream SHA-256 digests, e.g. `fio-3.43-x64.msi` `sha256:8299e6e6fbc024d3b74aa1ce62fb94ef6960b45629fbfa678b720834b6eb34aa` (2,871,296 bytes) ([GitHub release API](https://api.github.com/repos/axboe/fio/releases/latest)). Source tarballs at `brick.kernel.dk/snaps/` ([README](https://github.com/axboe/fio/)).
- **OS/arch:** Linux, macOS, Windows, BSD, Solaris, AIX, HP-UX; Windows 7+/Server 2008 R2+; MSI needs extracting into a temp dir (no permanent install) ([README](https://github.com/axboe/fio/)).
- **Caveats:** Linux `libaio` engine needs dev packages if building; raw-device writes must be forbidden by HBSS; MSI is nominally an installer. **Verdict: AUTO-DOWNLOAD + RUN (temp-file jobs only).**

### 4.2 Microsoft DiskSpd
- **Name/upstream/version/license:** DiskSpd by Microsoft Windows/Server/CSS engineering, [github.com/microsoft/diskspd](https://github.com/microsoft/diskspd), **MIT License**, current **v2.3 (2026-09-04 / announced 9/3/2026)** ([repo](https://github.com/microsoft/diskspd), [release API](https://api.github.com/repos/microsoft/diskspd/releases/latest)).
- **CLI:** `diskspd.exe <options> <testfile>`; XML output for automation; official warning: "If you use DiskSpd to write data to a physical disk, you might destroy the data on that disk. DiskSpd does not ask for confirmation" ([MS blog](https://learn.microsoft.com/en-us/archive/blogs/josebda/diskspd-powershell-and-storage-performance-measuring-iops-throughput-and-latency-for-both-local-disks-and-smb-file-shares)). Use a temp file, not a physical disk.
- **Checksums/pinning:** GitHub release asset `DiskSpd.ZIP` has upstream digest `sha256:18609981e8b04b4f645f1fd182ad0541615fe71722de36a9a933c54f747218a3`, size 3,606,329 bytes, version-pinned URL `https://github.com/microsoft/diskspd/releases/download/v2.3/DiskSpd.ZIP` ([release API](https://api.github.com/repos/microsoft/diskspd/releases/latest)).
- **OS/arch:** Windows only; binary release contains **amd64 and arm64** builds; minimum Windows 10 version 1803 ([release notes](https://github.com/microsoft/diskspd/releases/tag/v2.3)). Elevation is recommended for raw-device access but not required for a normal file-based test ([MS blog](https://learn.microsoft.com/en-us/archive/blogs/josebda/diskspd-powershell-and-storage-performance-measuring-iops-throughput-and-latency-for-both-local-disks-and-smb-file-shares)).
- **Caveats:** Windows-only; no Linux/macOS. **Verdict: AUTO-DOWNLOAD + RUN (Windows storage engine).**

### 4.3 CrystalDiskMark
- **License:** MIT License per the official licence page ("free of charge ... use, copy, modify, merge, publish, distribute, sublicense, and/or sell") and the developer's About page ("All of my programs are freeware ... can be freely distributed") ([official licence](https://crystalmark.info/ja/software/crystaldiskmark/crystaldiskmark-license/), [About](https://crystalmark.info/en/information/about/)). It uses Microsoft DiskSpd (MIT) as its benchmark core ([history](https://crystalmark.info/en/software/crystaldiskmark/crystaldiskmark-history/)).
- **Headless feasibility:** **None.** Source inspection shows no functional command-line arguments; command-line strings are used only to self-elevate via UAC `runas` ([SECONDARY: SuperUser analysis](https://superuser.com/questions/1935094/crystaldiskmark-ver8-9-benchmark-command-line)). Maintainer closed an automation feature request saying "CrystalDiskMark is only GUI lapper of DiskSpd. If you require an automation feature, please use DiskSpd directly" ([issue #2](https://github.com/hiyohiyo/CrystalDiskMark/issues/2)).
- **Caveats:** GUI, UAC elevation, no CLI, no published checksums relevant to headless use. **Verdict: SKIP / UNRELIABLE** — use DiskSpd instead (which is what CDM itself wraps).

### 4.4 ioping
- **Name/license:** ioping by Konstantin Khlebnikov / Kir Kolyshkin, [github.com/koct9i/ioping](https://github.com/koct9i/ioping/), **GPLv3-or-later**, stable **v1.3** ([releases](https://github.com/koct9i/ioping/releases)).
- **Binary/CLI:** Source-only (`make`), no official prebuilt binaries or published SHA-256; available via distro/Homebrew/MacPorts packages ([README](https://github.com/koct9i/ioping/), [Homebrew formula](https://formulae.brew.sh/formula/ioping)).
- **OS/arch:** Linux, macOS (Apple Silicon + Intel bottles), Windows, *BSD ([README](https://github.com/koct9i/ioping/), [Homebrew](https://formulae.brew.sh/formula/ioping)).
- **Caveats:** Needs build/install or package manager. **Verdict: DETECT-IF-INSTALLED ONLY.**

---

## 5. Crypto — OpenSSL `speed`
- **License/version:** OpenSSL is **Apache License 2.0** in current 3.x/4.x lines ([GitHub repo](https://github.com/openssl/openssl)); older 1.x releases used the OpenSSL license (a 4-clause BSD-style license) — pin and record the version in the report.
- **CLI:** `openssl speed -evp aes-128-gcm -seconds N -multi N -mr` (`-mr` = machine-readable, `-elapsed`, `-bytes`, `-testmode` are documented) ([openssl-speed docs](https://docs.openssl.org/master/man1/openssl-speed/)).
- **Availability/pinning:** OpenSSL **does not distribute binary packages**; source tarballs at `openssl-library.org/source/`, precompiled binaries come from OS vendors or third parties ([README](https://github.com/openssl/openssl)). Built in to most Linux/macOS/BSD systems; not guaranteed on Windows/PowerShell 5.1.
- **Caveats:** Version-dependent algorithm list; `-engine` removed in OpenSSL 4.0 ([docs](https://docs.openssl.org/master/man1/openssl-speed/)). **Verdict: DETECT-IF-INSTALLED ONLY** (use the system `openssl`; never auto-download a crypto binary).

---

## 6. Network — iperf3
- **License/version/maintainer:** iperf3 by ESnet / Lawrence Berkeley National Laboratory, **three-clause BSD license**, current **3.22.1 (2026-11-19)** ([docs](https://software.es.net/iperf/), [releases](https://github.com/esnet/iperf/releases/)).
- **CLI/model:** Client/server: `iperf3 -s` on one endpoint, `iperf3 -c <host> -J` (JSON) on the other; measures TCP/UDP/SCTP throughput, loss, etc. ([docs](https://software.es.net/iperf/)).
- **Checksums/binaries:** ESnet distributes **source tarballs only**, with **published SHA-256 checksums**, at `https://downloads.es.net/pub/iperf/`; ESnet explicitly states it does not distribute binaries and warns that GitHub-generated archives will not match published checksums ([obtaining docs](https://software.es.net/iperf/obtaining.html)).
- **OS/arch:** Officially supported: Ubuntu Linux, FreeBSD, macOS; Windows/Android builds are third-party only ([obtaining docs](https://software.es.net/iperf/obtaining.html)).
- **Caveats:** Requires two endpoints (a loopback-only test is of little value), opens listening sockets, no official Windows binary, likely needs a build on macOS/Linux. **Verdict: DETECT-IF-INSTALLED ONLY** (only use with an explicitly local server and user awareness).

---

## 7. GPU & accelerator benchmarks

### 7.1 Geekbench Compute
- Same proprietary EULA as §2.1: named-user, non-commercial, no redistribution, **mandatory results upload** on the free tier, Pro required for offline ([EULA](https://www.primatelabs.com/legal/eula-v6.html), [CLI output quoted, SECONDARY](https://aur.archlinux.org/packages/geekbench)). The Windows bundle includes `pl_opencl_*.dll` for OpenCL ([VirtualClient packaging list](https://microsoft.github.io/VirtualClient/docs/workloads/geekbench/)). **Verdict: NEEDS-MANUAL-LICENSE. Do NOT assume Geekbench can be auto-downloaded — verified it cannot.**

### 7.2 Blender Benchmark GPU rendering via CLI
- Cycles is a path-tracing renderer supporting CPU and GPU backends (CUDA, HIP, oneAPI, Metal) through Blender's official builds; the documented offline command accepts `--device-type CPU` and GPU device types ([Open Data about](https://opendata.blender.org/about/)). Official binaries + SHA-256 are published (§2.7), GPL license, no EULA, no upload in offline mode. This is the **most portable legally auto-downloadable CPU+GPU benchmark for HBSS**. **Verdict: AUTO-DOWNLOAD + RUN.**

### 7.3 clpeak (cross-API GPU + AI/NPU)
- **Name/license/version:** clpeak by krrishnarraj, [github.com/krrishnarraj/clpeak](https://github.com/krrishnarraj/clpeak/), **GPLv3**; **v2.0.0 is a pre-release (2026-05-06)** ([releases](https://github.com/krrishnarraj/clpeak/releases/tag/2.0.0)).
- **APIs covered:** CUDA, ROCm/HIP, Metal, oneAPI/SYCL, Vulkan, OpenCL, plus AI runtimes (ONNX Runtime, Core ML, LiteRT) that can reach NPUs; CLI with `--list-devices`, `--devices`, `--bandwidth`, `-o run.clpeak.json` ([repo](https://github.com/krrishnarraj/clpeak/)).
- **Caveats:** Release binaries are **unsigned** — Windows SmartScreen "More info → Run anyway", macOS Gatekeeper quarantine removal, and Linux snap or raw zip ([repo release notes](https://github.com/krrishnarraj/clpeak/)). Those interactive trust steps conflict with safe unattended execution; pre-release status and vendor-runtime requirements add risk. SHA-256 publication not verified. **Verdict: DETECT-IF-INSTALLED ONLY** (legally GPLv3-redistributable but operationally unsuitable for silent auto-download without further verification).

### 7.4 API and "reputable portable headless GPU benchmark" conclusion
- APIs: OpenCL (cross-vendor), Vulkan (cross-vendor compute), CUDA (NVIDIA), HIP/ROCm (AMD), Metal (Apple). Blender's Cycles uses these through official GPL builds ([Open Data](https://opendata.blender.org/about/)); clpeak exposes all of them ([clpeak repo](https://github.com/krrishnarraj/clpeak/)).
- OpenCL-Benchmark (ProjectPhysX) is another cross-platform OpenCL peak-performance tool but is **source/compile-based** ([repo](https://github.com/ProjectPhysX/OpenCL-Benchmark/)).
- **Verified conclusion:** at least two legally auto-downloadable engines exist (Blender GPL, clpeak GPLv3), but the only one with official SHA-256 files, signed/standard OS install paths and no interactive trust bypass is **Blender**. Geekbench Compute is **not** auto-downloadable (§7.1).

---

## 8. NPU benchmarks
- **Novabench NPU test** is a proprietary commercial benchmark covering Apple Neural Engine (Core ML), Qualcomm Hexagon (QNN), Intel AI Boost (OpenVINO), AMD XDNA (Vitis AI), reporting measured TOPS via SSD-ResNet50 and selfie segmentation ([Novabench](https://novabench.com/benchmark-test/npu)). Proprietary → not redistributable by HBSS.
- **PassMark PerformanceTest NPU Mark** is a proprietary commercial benchmark using OpenVINO/XRT/QNN matrix multiply ([PassMark help](https://www.passmark.com/products/performancetest/v12/help/2-Benchmarks/6-NPU-Mark/32-NPU-Matrix-Multiplication/npu-matrix-multiplication-help.php)). Proprietary → not redistributable.
- **Open option:** clpeak's GPLv3 AI/ONNX backends can reach NPUs but are pre-release, unsigned, and require vendor runtimes ([clpeak repo](https://github.com/krrishnarraj/clpeak/)).
- **Conclusion:** **No standardized, legally auto-downloadable, portable, unattended NPU benchmark was verified.** HBSS should report NPU *presence/name* from inventory APIs only and label any NPU performance number as unavailable, never fabricate one. **Verdict: SKIP / UNRELIABLE.**

---

## 9. Inventory APIs (primary docs)

### 9.1 Linux (no download, no root for the core paths)
- `/proc/cpuinfo` and `/proc/meminfo` are the kernel's documented CPU/memory interfaces; `meminfo` reports total usable RAM ([kernel /proc docs](https://www.kernel.org/doc/html/latest/filesystems/proc.html)).
- `/sys/devices/system/cpu/cpuX/` exposes topology (`topology/core_siblings`, `thread_siblings`, `physical_package_id`, cache info) to unprivileged readers ([kernel sysfs ABI docs](https://www.kernel.org/doc/Documentation/ABI/testing/sysfs-devices-system-cpu)).
- `lscpu` (util-linux) aggregates sysfs + `/proc/cpuinfo` (CPUs, threads, cores, sockets, NUMA, caches) and gives stable `Field: data` output for non-TTYs ([man7 lscpu(1)](https://man7.org/linux/man-pages/man1/lscpu.1.html)).
- `lsblk` (util-linux) and `lspci` (pciutils) are the standard block-device and PCI inventory commands; `smartctl` (smartmontools) is **GPLv2** ([COPYING](https://github.com/smartmontools/smartmontools/blob/main/COPYING)) and some smartctl operations need root/device access; `sensors` (lm-sensors) is GPL, libsensors LGPL, and sensors-detect must be run as root ([lm-sensors repo](https://github.com/lm-sensors/lm-sensors/)); `hwinfo` is GPLv2-or-later ([openSUSE/hwinfo](https://github.com/openSUSE/hwinfo/), [Arch package](https://archlinux.org/packages/extra/x86_64/hwinfo/)).
- `dmidecode` is GPL, but it first reads DMI from sysfs (`/sys/firmware/dmi/tables/DMI`, `/sys/devices/virtual/dmi/id`) and **only falls back to `/dev/mem`**, which needs root; "most of these files are even readable by regular users" ([dmidecode project](https://dmidecode.nongnu.org/), [manpage](https://manpages.ubuntu.com/manpages/plucky/en/man8/dmidecode.8.html)). HBSS should prefer sysfs and treat dmidecode as optional.

### 9.2 Windows (PowerShell 5.1 built into Windows 10+)
- WMI/CIM hardware classes are official and documented: `Win32_Processor`, `Win32_PhysicalMemory`, `Win32_PhysicalMemoryArray`, `Win32_VideoController`, `Win32_DiskDrive`, `Win32_OperatingSystem`, `Win32_BaseBoard`, `Win32_BIOS`, `Win32_Battery`, etc. ([MS Learn: Computer System Hardware Classes](https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/computer-system-hardware-classes)).
- `Get-CimInstance` is available in **PowerShell 5.1** (documented at `?view=powershell-5.1`), with local access via COM/WMI and no admin needed for most classes ([MS Learn Get-CimInstance 5.1](https://learn.microsoft.com/en-us/powershell/module/cimcmdlets/get-ciminstance?view=powershell-5.1)); `Get-PhysicalDisk` is the Storage cmdlet for physical disks. All are OS built-ins — no download.

### 9.3 macOS (built-in, no download)
- `system_profiler` reports hardware/software configuration with `-json`/`-xml`, `-detailLevel mini|basic|full`, and a `-timeout` (default 180 s) that is useful for HBSS per-test timeouts ([man page reproduced](https://www.sudo.is/docs/macos/)). Data types include `SPHardwareDataType`, `SPDisplaysDataType`, `SPMemoryDataType`, `SPNVMeDataType`, `SPPowerDataType`, `SPSoftwareDataType` ([data type list](https://www.sudo.is/docs/macos/), [focused inventory guide](https://sekin.in/how-to-find-comprehensive-mac-system-information-via-terminal/)).
- `sysctl -n hw.model`, `hw.machine`, `hw.memsize` give low-level values ([guide](https://sekin.in/how-to-find-comprehensive-mac-system-information-via-terminal/)); `ioreg` is the I/O Kit registry dump tool ([guide](https://sekin.in/how-to-find-comprehensive-mac-system-information-via-terminal/)).
- `powermetrics` **requires sudo/root** ("powermetrics must be invoked as the superuser"); it reports CPU/GPU/ANE estimated power but its own documentation warns values are estimates and should not be used for device comparisons ([powermetrics man page](https://manp.gs/mac/1/powermetrics), [AppleStackExchange, SECONDARY](https://apple.stackexchange.com/questions/405713/does-the-powermetrics-command-line-tool-come-pre-installed-on-mac)). **HBSS must not call it.**

---

## 10. DECISION INPUTS

### 10.1 Per-tool verdict table

| Tool / category | Verdict | One-line reason (source) |
|---|---|---|
| Geekbench 6 / 7 CPU + CLI | **NEEDS-MANUAL-LICENSE** | Named-user, non-commercial, no redistribution, mandatory result uploads, Pro needed for offline ([EULA](https://www.primatelabs.com/legal/eula-v6.html)) |
| Geekbench Compute | **NEEDS-MANUAL-LICENSE** | Same EULA + OpenCL DLLs; free tier auto-uploads ([EULA](https://www.primatelabs.com/legal/eula-v6.html), [VirtualClient](https://microsoft.github.io/VirtualClient/docs/workloads/geekbench/)) |
| Cinebench | **NEEDS-MANUAL-LICENSE** | EULA acceptance at registration; distribution and OSS-licensing forbidden; no silent CLI ([MAXON EULA](https://www.maxon.net/en/legal/eula)) |
| Phoronix Test Suite | **AUTO-DOWNLOAD + RUN** | GPLv3, runs locally, fully automated; use curated tests only ([download page](https://www.phoronix-test-suite.com/index.php?k=downloads)) |
| sysbench (CPU/memory/fileio) | **DETECT-IF-INSTALLED ONLY** | GPLv2 but no official standalone binary; needs package/compile, no native Windows ([repo](https://github.com/akopytov/sysbench/)) |
| lmbench / lat_mem_rd | **SKIP / UNRELIABLE** | GPL + extra result-publication restrictions, source-only ([COPYING-2](https://github.com/intel/lmbench/blob/master/COPYING-2)) |
| y-cruncher | **DETECT-IF-INSTALLED ONLY** | Permissive mirroring/non-commercial license but download-as-acceptance, x86-only, no published hashes ([license](https://numberworld.org/y-cruncher/license.html)) |
| Blender Benchmark (CPU+GPU) | **AUTO-DOWNLOAD + RUN** | GPL + CC0 scenes, official SHA-256 manifests, documented headless CLI ([Open Data](https://opendata.blender.org/about/), [sha256](https://download.blender.org/release/Blender5.3/blender-5.3.0.sha256)) |
| 7-Zip `7zz b` | **AUTO-DOWNLOAD + RUN** | LGPL standalone console builds for all target OS/arch; pin own hashes ([download](https://7-zip.org/download.html)) |
| STREAM | **SKIP / UNRELIABLE** | Free to redistribute but source-only; compile locally and label as variant ([run rules](https://www.cs.virginia.edu/stream/ref)) |
| Intel MLC | **SKIP / UNRELIABLE** | Custom Intel license; requires root/MSR driver, x86 only ([Intel article](https://www.intel.com/content/www/us/en/developer/articles/tool/intelr-memory-latency-checker.html)) |
| RAMspeed | **SKIP / UNRELIABLE** | 2009 custom-license source-only tool, no ARM ([repo](https://github.com/cruvolo/ramspeed)) |
| fio | **AUTO-DOWNLOAD + RUN** | GPLv2, official SHA-256 on release assets; temp-file jobs only ([release API](https://api.github.com/repos/axboe/fio/releases/latest)) |
| Microsoft DiskSpd | **AUTO-DOWNLOAD + RUN** | MIT, x64+ARM64 ZIP with upstream SHA-256, Windows 10+ ([release API](https://api.github.com/repos/microsoft/diskspd/releases/latest)) |
| CrystalDiskMark | **SKIP / UNRELIABLE** | MIT but GUI-only, no CLI, UAC self-elevation; maintainer says use DiskSpd ([issue](https://github.com/hiyohiyo/CrystalDiskMark/issues/2)) |
| ioping | **DETECT-IF-INSTALLED ONLY** | GPLv3 but source-only, no official binaries/hashes ([repo](https://github.com/koct9i/ioping/)) |
| OpenSSL `speed` | **DETECT-IF-INSTALLED ONLY** | Apache-2.0 (3.x), built into most Unix; no official binaries; Windows not guaranteed ([docs](https://docs.openssl.org/master/man1/openssl-speed/)) |
| iperf3 | **DETECT-IF-INSTALLED ONLY** | BSD-3-clause, requires client+server, ESnet ships source only (SHA-256), no official Windows binary ([obtaining](https://software.es.net/iperf/obtaining.html)) |
| clpeak (GPU/NPU, cross-API) | **DETECT-IF-INSTALLED ONLY** | GPLv3 but pre-release, unsigned binaries requiring SmartScreen/Gatekeeper bypass ([repo](https://github.com/krrishnarraj/clpeak/)) |
| NPU benchmarks (Novabench, PassMark) | **SKIP / UNRELIABLE** | Proprietary/commercial; no standardized legally auto-downloadable portable NPU benchmark ([Novabench](https://novabench.com/benchmark-test/npu), [PassMark](https://www.passmark.com/products/performancetest/v12/help/2-Benchmarks/6-NPU-Mark/32-NPU-Matrix-Multiplication/npu-matrix-multiplication-help.php)) |
| Linux `/proc`, `/sys`, `lscpu` | **OS BUILT-IN** | Kernel/util-linux interfaces, unprivileged ([kernel docs](https://www.kernel.org/doc/html/latest/filesystems/proc.html), [lscpu](https://man7.org/linux/man-pages/man1/lscpu.1.html)) |
| `dmidecode`, `smartctl`, `sensors`, `hwinfo`, `lspci`, `lsblk` | **DETECT-IF-INSTALLED ONLY** | Optional Linux inventory; several need root for full data ([dmidecode](https://manpages.ubuntu.com/manpages/plucky/en/man8/dmidecode.8.html), [lm-sensors](https://github.com/lm-sensors/lm-sensors/)) |
| Windows WMI/CIM + `Get-CimInstance` + `Get-PhysicalDisk` | **OS BUILT-IN** | PowerShell 5.1 documented on Windows 10+; no admin for most classes ([MS Learn](https://learn.microsoft.com/en-us/powershell/module/cimcmdlets/get-ciminstance?view=powershell-5.1)) |
| macOS `system_profiler`, `sysctl`, `ioreg` | **OS BUILT-IN** | Built-in, JSON/XML output, configurable timeout ([man](https://www.sudo.is/docs/macos/)) |
| macOS `powermetrics` | **SKIP / UNRELIABLE** | Requires sudo/root; estimates unsuitable for comparison ([man](https://manp.gs/mac/1/powermetrics)) |

**Verdict counts (benchmark tools only, 20 tools listed above excluding 4 inventory rows):** AUTO-DOWNLOAD + RUN = **5** (PTS, Blender, 7-Zip, fio, DiskSpd); DETECT-IF-INSTALLED ONLY = **6** (sysbench, y-cruncher, ioping, OpenSSL, iperf3, clpeak); SKIP / UNRELIABLE = **6** (lmbench, STREAM, Intel MLC, RAMspeed, CrystalDiskMark, NPU benchmarks); NEEDS-MANUAL-LICENSE = **3** (Geekbench CPU, Geekbench Compute, Cinebench).

### 10.2 Engine vs. fallback strategy per category and OS

- **Linux**
  - Recognized engines: Phoronix Test Suite (curated free tests), Blender (Cycles CPU/GPU), 7-Zip `7zz b`, fio, and — if present — sysbench / ioping / OpenSSL / iperf3 / y-cruncher.
  - Honestly-labelled HBSS fallbacks: CPU prime-hash/loop microbenchmark, memory bandwidth/latency microbenchmark, temp-file storage test where fio/ioping are unavailable, `/proc`+`/sys` inventory.
  - Never used: Intel MLC (root), lmbench (publication restrictions), powermetrics (N/A).
- **Windows 10+ / PowerShell 5.1**
  - Recognized engines: DiskSpd (MIT, x64+ARM64), Blender (x64+ARM64), 7-Zip `7zz b`, fio (MSI extracted to temp).
  - Honestly-labelled fallbacks: PowerShell/.NET CPU + memory + temp-file storage microbenchmarks, WMI/CIM inventory, `Get-PhysicalDisk`.
  - Never auto-downloaded: Geekbench, Cinebench, CrystalDiskMark (GUI/EULA/admin/no CLI).
- **macOS (Intel + Apple Silicon)**
  - Recognized engines: Blender (GPU via Metal through Cycles), 7-Zip `7zz`, fio, Phoronix; system `openssl` if present.
  - Honestly-labelled fallbacks: `sysctl`/`system_profiler` inventory, shell/compiled microbenchmarks.
  - `powermetrics` skipped (sudo); y-cruncher/Intel MLC unavailable on ARM (and x86 Windows/Linux-only for y-cruncher).
- **GPU:** primary recognized engine is Blender Cycles (CPU/GPU). clpeak is detect-only due to unsigned binaries/pre-release. Geekbench Compute is manual-license only. No GPU result should be fabricated; report "not measured / engine unavailable" when no engine is present.
- **NPU:** inventory-only (presence/name); no performance number without a proprietary tool the user installed themselves, and any such number must be attributed explicitly to that third-party tool.

---

## 11. Things that could NOT be verified (explicit gaps)
- Officially published SHA-256 for 7-Zip, sysbench, lmbench, STREAM, ramspeed, ioping, Blender *benchmark scene files* (as opposed to the Blender application binaries), and y-cruncher: not found on their official pages. HBSS must pin its own verified hashes for any of these it chooses to download.
- A legal, silent, non-interactive Cinebench invocation: not verified (EULA acceptance and GUI-only distribution).
- Geekbench 7 EULA text specifically (the fetched official EULA is v6); Geekbench 7's "requires internet / auto-uploads" behaviour was observed in the official Linux download page and CLI output quoted in the AUR, but the v7 EULA itself was not fetched.
- Intel MLC's full outbound license terms (only the download page and AUR `LicenseRef-custom` classification were verified).
- macO Intel Blender 5.3.0 build availability (the SHA-256 manifest fetched listed macOS arm64 only).
- Whether clpeak publishes SHA-256 for its release assets.
