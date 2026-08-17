# Crash Dump Analysis Report Template

Use this exact structure.

## Report Header
- Analysis Date: `<YYYY-MM-DD>`
- Dump File: `<name.dmp>`
- File Path: `<full path>`

## Executive Summary
- Crash Type: `<access violation|heap corruption|...>`
- Severity: `<critical|high|medium|low>`
- Root Cause: `<one sentence>`
- Recommended Action: `<one sentence>`

## Dump Metadata
- Creation Time: `<from .time>`
- OS Build: `<from vertarget>`
- Platform: `<x86|x64|arm64>`
- Process Name: `<from !peb>`
- Process Path: `<from !peb>`
- Command Line: `<from !peb>`
- Working Directory: `<from !peb>`

## Crash Analysis
### Exception Details
- Exception Code: `<0x...>`
- Exception Address: `<0x...>`
- Faulting Module: `<module>`
- Module Base Address: `<0x...>`

### Call Stack Analysis
```text
[0] module!function+offset
[1] module!function+offset
[2] module!function+offset
```

### Thread Information
- Crashing or Primary Thread: `<id + reason>`
- Thread Count: `<count>`
- Other Notable Threads: `<list or none>`

## Technical Details
### Memory
- Virtual Size: `<from !peb or analysis>`
- Working Set: `<if available>`
- Heap Notes: `<if relevant>`

### Loaded Modules Summary
| Module | Base Address | Size | Path |
|---|---|---|---|
| `<module>` | `<0x...>` | `<size>` | `<path>` |

## Root Cause Analysis
- What happened: `<technical failure description>`
- Why it happened: `<contributing factors>`
- Code location: `<function/module if known>`
- Memory state: `<null/use-after-free/corruption/unknown>`

## Recommendations
### Immediate Actions
1. `<action>`
2. `<action>`
3. `<action>`

### Investigation Steps
1. `<next debug command or capture>`
2. `<code review target>`
3. `<repro/test scenario>`

### Prevention Measures
1. `<fix class>`
2. `<validation/check>`
3. `<process improvement>`

## Priority Assessment
- Severity: `<critical|high|medium|low>`
- Justification: `<impact, reproducibility, data-loss/security risk>`

## Additional Notes
- Symbols Complete: `<yes|partial|no>`
- Confidence: `<high|medium|low>`
- Missing Evidence: `<what would increase confidence>`

## Attachment Checklist
- Dump(s)
- Stack output (`k`, `~* kb`)
- Module list (`lm`)
- App/OS version and channel
- Repro steps and frequency
