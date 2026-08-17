# Capture Playbooks

## Single Dump (Fast Snapshot)
Use when app is unstable and may exit soon.

```powershell
procdump64.exe -ma <PID> C:\dumps\app_hang_1.dmp
```

## Two-Dump Hang Capture
Use for hang diagnosis to confirm stable wait chains.

```powershell
procdump64.exe -ma <PID> C:\dumps\app_hang_1.dmp
Start-Sleep -Seconds 25
procdump64.exe -ma <PID> C:\dumps\app_hang_2.dmp
```

## Cross-App Freeze Capture
Use when multiple apps show similar freeze symptoms.
Capture target app plus shell/notification-related processes.

```powershell
Get-Process | Where-Object { $_.ProcessName -match 'ShellExperienceHost|StartMenuExperienceHost|explorer' } | Select-Object Id,ProcessName
```

Then capture each relevant PID:

```powershell
procdump64.exe -ma <PID> C:\dumps\multi_<name>_<pid>.dmp
```

## Notes
- Prefer full dumps (`-ma`) for stack and module fidelity.
- Capture before killing/restarting the process.
