# Linux and macOS .NET Debugging

Covers tools and workflows for .NET debugging on Linux and macOS. The primary skill references target Windows/WinDbg; this file provides the cross-platform equivalent commands and gotchas.

## Core Tools

### dotnet-dump

Collects and analyzes managed dumps without a native debugger. Available on Linux, macOS, and Windows.

Install:
```bash
dotnet tool install -g dotnet-dump
```

Collect a dump from a running process:
```bash
dotnet-dump collect -p <PID>
dotnet-dump collect -p <PID> -o /tmp/myapp.dmp     # explicit output path
dotnet-dump collect -p <PID> --type Full             # full dump with all memory
```

Open interactive analysis:
```bash
dotnet-dump analyze /tmp/myapp.dmp
```

SOS commands work directly inside the `dotnet-dump analyze` prompt (no prefix needed):
```
> clrstack           # managed call stack for current thread
> dumpheap -stat     # heap summary by type
> dumpheap -type System.String   # objects of a specific type
> gcroot <addr>      # find GC roots holding an object alive
> pe                 # print current exception
> threads            # list managed threads
> threadpool         # thread pool state and CPU usage
> syncblk            # monitor lock contention
> pstacks            # parallel stacks (grouped call stacks)
> dumpobj <addr>     # inspect a specific object
```

Key limitation: `dotnet-dump` is not a native debugger. Native stack frames and native memory commands are unavailable. Use LLDB for mixed native/managed analysis.

### createdump

The .NET runtime's built-in dump creator, installed with every runtime version. Located in the runtime directory:
```bash
dotnet --list-runtimes
# Example output: Microsoft.NETCore.App 9.0.1 [/usr/share/dotnet/shared/Microsoft.NETCore.App/9.0.1]
# createdump lives at: /usr/share/dotnet/shared/Microsoft.NETCore.App/9.0.1/createdump
```

Manual collection:
```bash
sudo /usr/share/dotnet/shared/Microsoft.NETCore.App/9.0.1/createdump <PID>
sudo /usr/share/dotnet/shared/Microsoft.NETCore.App/9.0.1/createdump <PID> -f /tmp/coredump.%d
```

Preferred over `gdb`/`gcore` because system-generated dumps may lack managed state, causing SOS commands to show UNKNOWN for type and function names.

## Automatic Crash Dump Configuration

Set environment variables to have the runtime invoke `createdump` automatically on unhandled exceptions and crashes:

| Variable | Description | Default |
|---|---|---|
| `DOTNET_DbgEnableMiniDump` | Set to `1` to enable crash dump generation | `0` |
| `DOTNET_DbgMiniDumpType` | Dump type: `1`=Mini, `2`=Heap, `3`=Triage, `4`=Full | `2` (Heap) |
| `DOTNET_DbgMiniDumpName` | Output path template. Supports `%p` (PID), `%e` (exe name), `%h` (hostname), `%t` (epoch time) | `/tmp/coredump.<pid>` |
| `DOTNET_CreateDumpDiagnostics` | Set to `1` for diagnostic logging from createdump | `0` |
| `DOTNET_EnableCrashReport` | Set to `1` to generate a JSON crash report alongside the dump (not Windows) | `0` |

Example systemd unit override:
```ini
[Service]
Environment=DOTNET_DbgEnableMiniDump=1
Environment=DOTNET_DbgMiniDumpType=4
Environment=DOTNET_DbgMiniDumpName=/var/dumps/core.%e.%p.%t
```

Dump type guidance:
- **Mini (1)**: Small. Module lists, thread lists, exception info, all stacks. Good for crash triage.
- **Heap (2)**: Large. Includes GC heaps. Default; sufficient for most managed investigations.
- **Triage (3)**: Same as Mini but strips PII (paths, passwords). Use in regulated environments.
- **Full (4)**: Everything including module images. Required for single-file and NativeAOT apps.

## LLDB with SOS

LLDB is the recommended native debugger for Linux and macOS. Use it when you need both managed and native stack analysis.

### Setup

Install LLDB (version 10+ recommended):
```bash
sudo apt-get install lldb        # Ubuntu/Debian
sudo dnf install lldb            # Fedora/RHEL
apk add lldb py3-lldb            # Alpine
xcode-select --install           # macOS (ships with Xcode CLI tools)
```

Install SOS and download symbols:
```bash
dotnet tool install -g dotnet-debugger-extensions && dotnet-debugger-extensions install
# Or the older, narrower install: dotnet tool install -g dotnet-sos && dotnet-sos install
dotnet tool install -g dotnet-symbol && dotnet-symbol <path-to-dump>
```

The installer creates `~/.lldbinit` to auto-load the SOS plugin when LLDB starts.

### Core Dump Analysis

```bash
lldb --core <dump-file> <host-program>
# <host-program> is typically "dotnet" or the self-contained app binary
```

Once inside LLDB:
```
(lldb) setsymbolserver -ms           # point to Microsoft symbol server
(lldb) loadsymbols                   # load native symbols
(lldb) clrstack                      # managed stack (current thread)
(lldb) dumpheap -stat                # heap summary
(lldb) gcroot <addr>                 # GC root chain
(lldb) pe                            # print exception
(lldb) threads                       # list managed threads
(lldb) setclrpath <path>             # override DAC/runtime binary location
```

### Live Process Attach

```bash
lldb -p <PID>
# If permission denied:
sudo lldb --source ~/.lldbinit -p <PID>
```

Elevated LLDB does not auto-load `~/.lldbinit`; pass it explicitly with `--source`.

### SOS Command Differences from WinDbg

In WinDbg, SOS commands use the `!` prefix (e.g., `!clrstack`). In LLDB:
- Newer `dotnet-debugger-extensions`: commands work directly (`clrstack`, `dumpheap`, etc.)
- Older `dotnet-sos` installs: may require `sos` prefix (`sos clrstack`, `sos dumpheap`)
- `bt` (LLDB native backtrace) shows native frames; `clrstack` shows managed frames

## Container Debugging

### Collecting Dumps Inside a Container

```bash
# Install tools inside the container
docker exec -it <container> dotnet tool install -g dotnet-dump

# Collect dump
docker exec -it <container> ~/.dotnet/tools/dotnet-dump collect -p 1
```

Caveats:
- `dotnet-dump` and `dotnet-gcdump` can consume significant memory and disk. Ensure container resource limits are sufficient.
- `dotnet-dump collect` spawns a helper process requiring ptrace permissions. You may need `--cap-add=SYS_PTRACE` on the container or adjust seccomp profiles.

### Sidecar Pattern

Run diagnostic tools in a separate container. Requirements:
1. **Shared process namespace** -- `--pid=container:<target>` in Docker, or `shareProcessNamespace: true` in Kubernetes
2. **Shared /tmp directory** -- volume mount required because the .NET diagnostic port Unix Domain Socket lives in `/tmp`
3. Without shared `/tmp`, use `--diagnostic-port` to specify the socket path explicitly

```bash
# Docker example: run sidecar sharing PID namespace and /tmp
docker run --pid=container:myapp -v myapp_tmp:/tmp mcr.microsoft.com/dotnet/sdk:9.0
```

### Automatic Crash Dumps in Containers

```dockerfile
ENV DOTNET_DbgEnableMiniDump=1
ENV DOTNET_DbgMiniDumpType=2
ENV DOTNET_DbgMiniDumpName=/dumps/core.%e.%p
VOLUME /dumps
```

Mount a host or persistent volume at `/dumps` so dumps survive container restarts.

### Kubernetes

Ephemeral debug containers (Kubernetes 1.23+):
```bash
kubectl debug -it <pod> --image=mcr.microsoft.com/dotnet/sdk:9.0 --target=<container>
```

For persistent diagnostic sidecars, use an `emptyDir` volume shared between app and sidecar containers for the `/tmp` diagnostic port socket.

## Common Scenarios

### Crash Analysis (Segfault, Unhandled Exception)

1. Ensure `DOTNET_DbgEnableMiniDump=1` is set before the crash occurs.
2. Managed exception: `dotnet-dump analyze <dump>` then `pe`, `clrstack`, `threads`.
3. Native crash (SIGSEGV): use LLDB -- `lldb --core <dump> dotnet` then `bt` (native) and `clrstack` (managed).

### High Memory / OOM Killer Investigation

The Linux OOM killer terminates processes without generating a .NET dump. Check `dmesg | grep -i "oom\|killed process"` first. For proactive investigation before OOM:
```bash
dotnet-dump collect -p <PID> --type Heap
dotnet-dump analyze <dump>
> dumpheap -stat              # top memory consumers by type
> gcroot <addr>               # trace why an object is retained
> gcheapstat                  # GC generation breakdown
```

### Hang Diagnosis (Deadlock, Thread Starvation)

```bash
dotnet-dump collect -p <PID>
dotnet-dump analyze <dump>
> threads                     # list all managed threads
> syncblk                     # show lock contention and owners
> pstacks                     # grouped parallel stacks
> threadpool                  # thread pool saturation check
```

For deadlock detection, cross-reference `syncblk` owners with `setthread <id>` and `clrstack` to identify circular waits.

### High CPU Investigation

Live check: `dotnet-counters monitor -p <PID> --counters System.Runtime` or `top -H -p <PID>` to find hot OS threads. Then collect a dump and in `dotnet-dump analyze`: `threads`, `threadpool`, `setthread <id>`, `clrstack`. There is no `!runaway` equivalent; correlate OS thread IDs from `top -H` with managed thread IDs via `threads`.

## dotnet-monitor (Production Diagnostics)

A REST API for collecting dumps, traces, logs, and metrics without attaching a debugger. Designed for production and containerized environments.

Install as global tool (`dotnet tool install -g dotnet-monitor`) or Docker image (`mcr.microsoft.com/dotnet/monitor`). Start with `dotnet-monitor collect --urls https://localhost:52323 --no-auth` (dev only).

Key REST endpoints:
- `GET /processes` -- list monitored .NET processes
- `GET /dump?pid=<PID>&type=Full` -- collect a dump
- `GET /trace?pid=<PID>` -- collect an EventPipe trace
- `GET /logs?pid=<PID>` -- stream structured logs
- `GET /metrics` -- Prometheus-format metrics

Trigger-based collection (configure via `settings.json`):
- CPU threshold triggers (e.g., collect dump when CPU exceeds 80% for 30 seconds)
- Memory threshold triggers (e.g., collect GC dump when heap exceeds 500 MB)
- Custom EventCounter thresholds

Run as a Kubernetes sidecar with shared `/tmp` volume for the diagnostic port. In listen mode, use `--diagnostic-port` so `dotnet-monitor` accepts connections from the app runtime.

## Cross-Platform Differences from WinDbg

| Feature | WinDbg | Linux/macOS Equivalent |
|---|---|---|
| `!analyze -v` | Automated crash triage | No equivalent. Manual: `pe` + `clrstack` + `bt` |
| `!runaway` | Per-thread CPU time | `top -H -p <PID>` + correlate with `threads` |
| `.symfix` / `.sympath` | Symbol server config | `setsymbolserver -ms` in LLDB, or `dotnet-symbol` |
| `!address -summary` | Virtual memory map | `/proc/<PID>/smaps`, `pmap <PID>` |
| `!heap -s` | Native heap summary | Not available in managed tools; use `valgrind` or native profilers |
| `~* kb` | All thread stacks | `pstacks` in dotnet-dump, or `thread backtrace all` in LLDB |
| `!uniqstack` | Deduplicated stacks | `pstacks` in dotnet-dump |
| Dump format | `.dmp` (Windows minidump) | ELF core dump on Linux, Mach-O on macOS |

## Agent Gotchas

- **Do not assume WinDbg commands work on Linux.** Use `dotnet-dump` or LLDB with SOS. The `!` prefix syntax is WinDbg-specific.
- **Container dumps require headroom.** `dotnet-dump collect` can consume memory comparable to the target process heap. If the container is near its memory limit, the collection will trigger the OOM killer.
- **OOM kills do not generate .NET dumps by default.** The kernel terminates the process before the runtime can invoke `createdump`. Configure `DOTNET_DbgEnableMiniDump` for crash dumps, but OOM kills bypass that path. Monitor `dmesg` and set up proactive collection with `dotnet-monitor` triggers.
- **LLDB SOS prefix varies by install method.** With `dotnet-debugger-extensions`, commands work without prefix. With older `dotnet-sos`, commands may need the `sos` prefix. If commands are not recognized, try both forms.
- **Elevated LLDB skips ~/.lldbinit.** When running `sudo lldb`, pass `--source ~/.lldbinit` explicitly or SOS will not load.
- **ARM64 Linux has limited SOS support in older runtimes.** .NET 6 and earlier have incomplete ARM64 SOS support. Use .NET 7+ for reliable ARM64 dump analysis.
- **Cross-architecture analysis is not supported.** Analyze dumps on the same architecture and Linux distro as the target. An x64 dump cannot be opened in an ARM64 `dotnet-dump`.
- **macOS has no `/proc` filesystem.** Use `dotnet-counters` or `dotnet-trace` instead of `/proc`-based tools for live process inspection.
- **Dump output path in containers is relative to the target process filesystem.** When using `dotnet-dump` from a sidecar, the dump is written in the target container's filesystem context, not the sidecar's.
