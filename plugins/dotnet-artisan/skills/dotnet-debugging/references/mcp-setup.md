# MCP Setup

## Prerequisites
- `uvx` installed and available in PATH.
- `cdb.exe` installed (from Debugging Tools for Windows).

## Install cdb (Debugging Tools for Windows)
Preferred non-interactive install:

```powershell
winget install 9PGJGD53TN86 --accept-source-agreements --accept-package-agreements
```

Fallback installer path:
1. Download the Windows SDK installer from Microsoft: `https://developer.microsoft.com/windows/downloads/windows-sdk/`.
2. Run setup and select only `Debugging Tools for Windows` (other SDK components are optional).
3. Expected `cdb` paths after install:
	- `C:/Program Files (x86)/Windows Kits/10/Debuggers/x64/cdb.exe`
	- `C:/Program Files/Windows Kits/10/Debuggers/x64/cdb.exe`

## Verify cdb Installation
Use one of these checks:

```powershell
Get-Command cdb -ErrorAction SilentlyContinue
```

```powershell
Test-Path "C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\cdb.exe"
Test-Path "C:\Program Files\Windows Kits\10\Debuggers\x64\cdb.exe"
```

## Required Server Command
Use this launch command for the WinDbg MCP server:

```bash
uvx --from git+https://github.com/svnscha/mcp-windbg mcp-windbg
```

## VS Code MCP Configuration
Add/update your MCP server configuration (for example in user `mcp.json`) so this server is available to the agent.

## Validate Availability
Before debugging, confirm WinDbg MCP tools are callable in chat (for example, open remote or dump actions succeed).

## Troubleshooting
- If tools are missing, verify the server entry in `mcp.json`.
- Restart the chat/session after MCP config changes.
- Confirm `uvx` is installed and reachable in PATH.
- Confirm `cdb.exe` is installed and reachable by full path.
