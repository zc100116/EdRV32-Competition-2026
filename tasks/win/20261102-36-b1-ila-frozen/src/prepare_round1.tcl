# Switch active Debugger project before rearming, so round2 WDF stays preserved.
dbg_save_project -file G:/codex_project/EdRV32-Competition-2026/tasks/win/20261102-36-b1-ila-frozen/artifacts/ila/round1.dprj
dbg_export_fic -file G:/codex_project/EdRV32-Competition-2026/tasks/win/20261102-36-b1-ila-frozen/artifacts/ila/round1.fic
dbg_run
