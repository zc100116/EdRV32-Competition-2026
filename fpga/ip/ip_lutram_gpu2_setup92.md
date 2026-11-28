# ip_lutram_gpu2_setup92

| 项 | 固定取值 |
|---|---|
| 依据 | gpu-v2-spec §2.6、M-7 `m7_model.py:110` 的16行深度、M-8 72 bank |
| 器件 | PG2L200H；速度等级沿用工程 |
| 创建入口 | PDS IP Compiler → Memory → Distributed RAM → Simple Dual Port RAM |
| Component/Module Name | `ip_lutram_gpu2_setup92` |
| 包装 | `rtl/tech/edrv32_ram_gpu2_setup_lut92.v` |
| 使用者 | `edrv32_gpu2_banks_lutram`，72 个独立实例 |
| Data Width / Depth / Address Width | 92 / 16 / 4，读写等宽等深 |
| Resource | Distributed RAM / LUTRAM，不能选 DRM |
| Write | 上升沿整字写；启用 wr_en；不启用 Byte Write Enable |
| Read | **异步组合读**；不注册地址；关闭 IP 输出寄存器 |
| Clock | wr_clk/rd_clk 同接 clk_gpu；组合读不依赖 rd_clk |
| Reset / Initialization | 不复位内容，无初始化文件；rst 接 0 |

期望端口：wr_clk、rd_clk、rst、wr_en（input 1），wr_addr、rd_addr（input 4），
wr_data（input 92）、rd_data（output 92）。生成目录只加入 Windows 工程，不入库。
包装在 rd_en 上升沿捕获组合旧字，形成同步读 1 拍；同址写也在该沿提交，故捕获旧字。
业务模块再用一拍外部捕获，与 DRM 版本端口时序相同；禁止额外注册 IP 输出。
使用 `fpga/scripts/import_probe_gpu2_banks_lutram_top.tcl`，还需生成
`ip_ram_gpu2_sdp72` 与 `ip_ram_gpu2_sdp36` 供 RF/常量/program 使用。

实际使用容量为72×16×92=105984 bit，替代144 DRM；精确 LUT/LUTRAM/CLMS 数以 PDS 报告为准。
M-8 没有定义16行内部字段布局；本探针只验证独立地址/端口，不声称实现属性 DAG 调度。
Windows 回传配置截图、端口、每实例/总 LUTRAM 和 CLMS，以及220/200/150MHz裕量；
ModelSim 使用同一 G-P04 trace 对照 DRM 版本，核实异步读边沿前值与同址写捕获。
