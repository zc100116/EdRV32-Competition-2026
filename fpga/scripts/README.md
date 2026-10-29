PDS 导入脚本（Tcl）：导入除 IP 外的源文件、约束文件，设置宏定义
`import_media_top.tcl`：在 EdRV32-FPGA/EdRV32-MEDIA 中导入五个媒体/网络文件列表（去重）、测量顶层和约束，定义 FPGA_MODE。

`import_board_b1_top.tcl`：导入 B1 顶层、CPU/系统文件列表和约束，定义 FPGA_MODE；PLL 与其余 IP 在 PDS 中生成。


B2：在已按 `fpga/ip/README.md` 生成 IP 的 PG2L200H-6/FBB676 工程中执行
`source <仓库绝对路径>/fpga/scripts/import_board_b2_top.tcl`。脚本按自身位置定位仓库，
递归展开 `rtl/filelists/soc.f`，源文件按首次出现去重，添加四个板级文件和 B2 FDC，
使用 `FPGA_MODE` 编译 `edrv32_fpga_board_b2_top`；不启动仿真或布局布线。
