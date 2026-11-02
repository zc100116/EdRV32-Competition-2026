# cpu_core_smoke

Unified regression (from the repository root):

```sh
. ~/.local/opt/edrv32/env.sh
make smoke
```

`test.yaml` supplies simulator, ISA parameter and optional software selection;
`files.f` paths are relative to that file. Logs are under `build/regress/smoke/unit/`.

The shared program is `sw/tests/cpu_smoke`, built through `sw/Makefile` using
its `program.mk` ISA selection. Both RVC settings run the same RV32IM/Zicsr image.
The ideal cache models return hits one cycle after request acceptance and apply
committed writes before serving simultaneous reads. Completion uses the BSP
`tohost` symbol at SRAM+0x40 (verified with the linked ELF symbol table); zero
initialization is not an exit request. The test also covers self-modifying SRAM
code with FENCE.I, stale lane-1 BTB prediction recovery and adjacent store/load.
