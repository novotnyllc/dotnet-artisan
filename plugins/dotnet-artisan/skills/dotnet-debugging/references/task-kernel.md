# Task: Kernel Triage

## When To Use
- BSOD/bugcheck analysis.
- Kernel dump or kernel remote debug session.

## Commands
- `!analyze -v`
- `k`
- `lm`
- `!thread`
- `!process 0 1`

## Deliver
- Bugcheck or kernel fault summary.
- Faulting stack and likely driver/module.
- Confidence and next capture steps.

## Guardrail
If only user-mode evidence is available, state that kernel conclusions are limited.
