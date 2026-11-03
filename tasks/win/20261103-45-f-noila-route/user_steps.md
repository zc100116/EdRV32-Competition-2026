# 卡45 F/VRN

关闭旧F和F-D4的PDS窗口以释放内存。打开NOILA副本；不要重新导入、Compile或Synthesize。

F控制台：
```tcl
cd G:/codex_project/EdRV32-FPGA/EdRV32-B3F-RND1-N-NOILA
dev_map -input_db_file {synthesize/edrv32_fpga_board_full_top_syn.adf} -fanout_number 1000 -force_to_run
```
VRN控制台：
```tcl
cd G:/codex_project/EdRV32-FPGA/EdRV32-B3F-VRN-RND1-N-NOILA
dev_map -input_db_file {synthesize/edrv32_fpga_board_vrn_top_syn.adf} -fanout_number 1000 -force_to_run
```

Map完成后Codex核对去核及资源，再由用户GUI运行PnR。两副本D2/LUT6D0/slack40/pincost600/threads5/congestionON。
