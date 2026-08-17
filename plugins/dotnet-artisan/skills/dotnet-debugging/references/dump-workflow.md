# Dump Workflow

## Purpose
Analyze a saved dump when live attach is not available.

## Steps
1. Confirm dump path.
2. Open dump with `mcp_mcp-windbg_open_windbg_dump`.
3. Run baseline commands:
- `!analyze -v`
- `lm`
- `~* kb`
4. Run scenario command pack based on symptom.
5. Close with `mcp_mcp-windbg_close_windbg_dump`.

## Notes
- For intermittent hangs, two dumps 20-30 seconds apart improve confidence.
- Prefer full dumps when possible for complete stack/module context.
