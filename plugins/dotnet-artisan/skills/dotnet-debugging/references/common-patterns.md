# Common Patterns

## COM/RPC Wait Chain
Signals:
- `combase`/`RPCRT4` frames on blocked threads.
- UI thread in modal loop waiting on cross-apartment call.
Next commands:
- `~* kb`
- `!uniqstack -pn`
- targeted `~<thread> kv`

## UI Message Pump Blocked
Signals:
- `GetMessage`/`MsgWaitForMultipleObjectsEx` path with no forward progress.
Next commands:
- `!analyze -hang`
- `~0 kv`
- `~* kb`

## Worker Starvation
Signals:
- Many duplicate worker stacks in waits.
Next commands:
- `!uniqstack -pn`
- `!runaway`
- inspect representative blocked worker

## Hot Loop / High CPU
Signals:
- Single thread dominates `!runaway` time.
Next commands:
- `!runaway`
- `~<thread> kv`
- compare with nearby workers

## Memory Pressure
Signals:
- Abnormal address space growth or heap pressure.
Next commands:
- `!address -summary`
- `!heap -s`
