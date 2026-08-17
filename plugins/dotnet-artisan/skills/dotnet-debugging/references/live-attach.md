# Live Attach Workflow

## Purpose
Attach to a currently hung or misbehaving process through a WinDbg debug server.

## Steps
1. Find process IDs:
```powershell
Get-Process | Where-Object { $_.ProcessName -match '<name-pattern>' } | Select-Object Id,ProcessName,StartTime
```
2. Start debug server with `cdb` (preferred):
```powershell
& "C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\cdb.exe" -server tcp:port=5005 -p <PID>
```
3. If path differs, try:
```powershell
& "C:\Program Files\Windows Kits\10\Debuggers\x64\cdb.exe" -server tcp:port=5005 -p <PID>
```
4. Provide this connection string to MCP:
```text
tcp:Port=5005,Server=127.0.0.1
```
5. Open live session with `mcp_mcp-windbg_open_windbg_remote`.
6. Run scenario command pack.
7. Close with `mcp_mcp-windbg_close_windbg_remote`.

## Notes
- Keep the `cdb`/`windbg` window open while MCP is connected.
- If `5005` is busy, use another port consistently in launch and connection string.
- Localhost (`127.0.0.1`) is recommended for local debugging.
