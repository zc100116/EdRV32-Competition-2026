# U-11 F2 stale prediction recovery

Run from the repository root:

Cases cover upper-halfword positions in the same or following group, both length
mismatches, correct compressed and 32-bit predictions, and D/M/E priority over F2.
The checker compares PC, raw bytes, expanded instructions and RAS checkpoints,
including older instructions already queued in IB before recovery.

Unified regression (from the repository root):

```sh
. ~/.local/opt/edrv32/env.sh
make smoke
```

`test.yaml` supplies simulator, ISA parameter and optional software selection;
`files.f` paths are relative to that file. Logs are under `build/regress/smoke/unit/`.
