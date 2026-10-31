PDS 导入脚本（Tcl）：导入除 IP 外的源文件、约束文件，设置宏定义

**执行方式（全部脚本相同）**：在 PDS Tcl 控制台中，当前目录为 FPGA 工程目录
`G:\codex_project\EdRV32-FPGA\<工程>`，执行
`source ../../EdRV32-Competition-2026/fpga/scripts/<脚本>`。脚本用
`../../EdRV32-Competition-2026` 定位仓库（PDS 中 `info script` 不能用来定位），
include 目录只传 `rtl/include` 一个路径（PDS 自己加入工程目录）。这是 B3I、B3V 在
Windows 上验证过的写法；新写导入脚本必须照此，不能自行推算仓库位置。

`import_media_top.tcl`：在 EdRV32-FPGA/EdRV32-MEDIA 中导入五个媒体/网络文件列表（去重）、测量顶层和约束，定义 FPGA_MODE。

`import_board_b1_top.tcl`：导入 B1 顶层、CPU/系统文件列表和约束，定义 FPGA_MODE；PLL 与其余 IP 在 PDS 中生成。


B2：在已按 `fpga/ip/README.md` 生成 IP 的 PG2L200H-6/FBB676 工程中执行
上面的执行方式运行 `import_board_b2_top.tcl`（导入 162 个源文件）。
递归展开 `rtl/filelists/soc.f`，源文件按首次出现去重，添加四个板级文件和 B2 FDC，
使用 `FPGA_MODE` 编译 `edrv32_fpga_board_b2_top`；不启动仿真或布局布线。

B3N：`import_board_npu_top.tcl` 导入 CPU/SYS/MEM/NPU/ETH 文件列表及板级适配器、顶层（106 个源文件），使用 `FPGA_MODE`、`edrv32_fpga_board_npu_top.fdc`（13 个时钟）和 24 种 IP；Linux 检查：`tclsh verif/soc/board_npu/check_import.tcl`。

B3R：`import_board_render_top.tcl` 导入 CPU/SYS/MEM/RND/DISP/ETH，共 103 个源文件、19 种 IP、14 个时钟（RND v2 起；卡 21 用的 99f453b1 为 98 个、18 种）。
B3VN：`import_board_vnpu_top.tcl` 保持 145 个源文件、29 种 IP、17 个时钟。
三者 ETH 均经 `edrv32_fpga_rgmii` 内的 `ip_pll_eth`（125 MHz、30°），不增加 SYS/VIDEO/NPU PLL 输出；
B3R/B3N 需新增生成 `ip_pll_eth`、`ip_ram_eth_buf`、`ip_ram_eth_fifo`，配置见 `fpga/ip/README.md`。
浅存储使用方案 B 的 `ip_lutram_mem_xbar_w`；NPU 另用 `ip_lutram_npu_quant/residual/result`。
