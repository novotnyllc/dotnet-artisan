# Symbols

## Quick Setup
Run in WinDbg session:

```text
.symfix
.reload
```

For Microsoft symbol server with local cache:

```text
.sympath srv*C:\symbols*https://msdl.microsoft.com/download/symbols
.reload /f
```

## Symbol Servers

| Server | URL | What it provides |
|--------|-----|-----------------|
| Microsoft | `https://msdl.microsoft.com/download/symbols` | .NET runtime, Windows OS, Visual Studio |
| NuGet | `https://symbols.nuget.org/download/symbols` | NuGet packages that publish symbols (SourceLink-enabled) |

### Adding Both Servers (WinDbg)

```text
.sympath srv*C:\symbols*https://msdl.microsoft.com/download/symbols
.sympath+ srv*C:\symbols*https://symbols.nuget.org/download/symbols
.sympath+ C:\path\to\your\pdbs
.reload /f
```

### Adding Both Servers (dotnet-dump / lldb)

```bash
# Environment variable for dotnet-dump and SOS
export DOTNET_SYMBOL_SERVER="https://msdl.microsoft.com/download/symbols;https://symbols.nuget.org/download/symbols"
```

### Adding NuGet Symbols in Visual Studio

In Visual Studio: **Tools > Options > Debugging > Symbols**, add:
- `https://symbols.nuget.org/download/symbols`

This enables stepping into source of NuGet packages that publish symbols via SourceLink.

## Verify Symbols
- `lm` to inspect module load status.
- `lmv m <module>` to confirm symbol details for a module.
- If stacks show many `Unknown`/raw addresses, symbols are likely incomplete.

## Troubleshooting
- Ensure network access to `msdl.microsoft.com` and `symbols.nuget.org`.
- Use a writable local cache directory.
- Re-run `.reload /f` after changing symbol path.
- If only one module is problematic, use `lmv m <module>` first.
- NuGet symbol server only works for packages that opt into symbol publishing — if symbols aren't found, the package author may not publish them.
