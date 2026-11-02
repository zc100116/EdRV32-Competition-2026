# Save round1, then switch active project to round2 BEFORE the next capture.
dbg_save_project -file G:/codex_project/EdRV32-Competition-2026/tasks/win/20261102-36-b1-ila-frozen/artifacts/ila/round1.dprj
dbg_export_fic -file G:/codex_project/EdRV32-Competition-2026/tasks/win/20261102-36-b1-ila-frozen/artifacts/ila/round1.fic
dbg_save_project -file G:/codex_project/EdRV32-Competition-2026/tasks/win/20261102-36-b1-ila-frozen/artifacts/ila/round2.dprj
dbg_export_fic -file G:/codex_project/EdRV32-Competition-2026/tasks/win/20261102-36-b1-ila-frozen/artifacts/ila/round2.fic
dbg_run
