# Sanity Check

## 60-Second Preflight
1. Confirm WinDbg MCP tools are available.
2. Confirm `cdb.exe` exists.
3. Confirm target PID or dump path.
4. Choose mode (live vs dump).
5. Set symbols if stacks are unclear: see [symbols](./symbols.md).

## Quick Commands
```powershell
Get-Command cdb -ErrorAction SilentlyContinue
Get-Process | Where-Object { $_.ProcessName -match '<name-pattern>' } | Select-Object Id,ProcessName
```
