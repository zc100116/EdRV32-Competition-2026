PDS 导入脚本（Tcl）：导入除 IP 外的源文件、约束文件，设置宏定义
`import_media_top.tcl`：在 EdRV32-FPGA/EdRV32-MEDIA 中导入五个媒体/网络文件列表（去重）、测量顶层和约束，定义 FPGA_MODE。

`import_board_b1_top.tcl`：导入 B1 顶层、CPU/系统文件列表和约束，定义 FPGA_MODE；PLL 与其余 IP 在 PDS 中生成。
