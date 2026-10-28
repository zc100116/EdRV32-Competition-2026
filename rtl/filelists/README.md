文件列表，仿真和综合共用。路径相对本目录；由协调者维护（CLAUDE.md 11.4）。

| 文件 | 内容 |
|---|---|
| `cpu.f` | 处理器核 `edrv32_cpu_core` 及其子模块、乘法器包装 |
| `cache.f` | I$、D$、cache_ctrl、PMA 译码和 4 个 RAM 包装 |
| `cpu_subsys.f` | CPU 子系统 `edrv32_cpu_subsys`（core + I$/D$ + cache_ctrl），包含 cpu.f 和 cache.f |
| `sys_subsys.f` | 系统子系统 `edrv32_sys_subsys`（sys_xbar、ROM/SRAM、APB 桥、CLINT、PLIC、外设、reset_ctrl）及所用公共原语 |
| `npu_datapath.f` | NPU 数据通路子顶层 `edrv32_npu_datapath` 及 12 个子模块、10 个 NPU 包装模块（N-D1；控制器、DMA、寄存器块在 N-C1 补入完整 NPU 文件列表） |
| `npu.f` | NPU 顶层、控制、DMA、串行非卷积执行器、完整数据通路、X9/X10 公共单元与技术包装 |
| `vin.f` | VIN `edrv32_vin`（DVP 前端、帧整形、内存源、写通道、P1 仲裁、寄存器）及所用公共原语和 dma2d（V-R1；存储包装在 V-P1 后替换） |
| `disp.f` | DISP `edrv32_disp`（时序、TMDS 编码、读控制、扫描、停止确认、寄存器）及所用公共原语和 dma2d_rd（V-R2；扫描 FIFO 存储包装在 V-P1 后替换） |
| `pix.f` | PIX `edrv32_pix`（点运算、两级 3×3、行缓存包装、寄存器）（V-R3 补齐 `rtl/media/pix/` 下的文件） |
| `geo.f` | GEO `edrv32_geo`（描述符、块调度、源缓冲、插值、写出、寄存器）及 dma2d（V-R4 补齐 `rtl/media/geo/` 下的文件和存储包装） |
| `eth.f` | ETH `edrv32_eth`（收发前端、过滤和 ARP、窗口写出、分包发送、MDIO、寄存器）及 dma2d（V-R5 补齐 `rtl/eth/` 下的文件、所用 `rtl/common/` 单元；存储包装由 V-P5 加入） |
