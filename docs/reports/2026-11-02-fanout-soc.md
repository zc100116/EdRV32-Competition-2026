# SoC 高扇出拆分（测量日期 2026-11-01）

基线 `bf56df5c`；RTL/验证 `880dada7`（含观察器/checker适配）；最终验证见下文。
工具：Yosys 0.70+219、Verilator 5.020、Icarus 12.0；目标 PG2L200H-6，参考综合不是器件映射。
方法：SIM_MODE、W LUTRAM 行为模型，其余 tech 包装及变量乘法黑盒、ABC LUT6；按输入 pin/bit 统计。
测量脚本仅在生成流程中将 syn_preserve FF 按位展开并 keep，RTL 只有 syn_preserve；数字只作参考，资源/时序以 PDS 为准。
原始参考数据：`build/fanout-soc/reference-{before,final}/<子系统>/{loads,fanout128}.tsv`，包含扇出≥128普查。

| 项 | RTL 位置与做法 | Yosys 改前→改后最大负载（包含副本） |
|---|---|---|
| S1 | `rtl/mem/edrv32_mem_xbar_rbuf.v:112`，非法读只覆盖 RRESP/RLAST，数据取 RAM 原值 | pending_error 259→4 |
| S2 | `rtl/mem/edrv32_mem_xbar.v:518`、`rtl/tech/edrv32_ram_mem_xbar_w.v:24`，预测下一读地址并按既有两个144位 IP复制地址/active | 地址13824→629；读使能288→144 |
| S3 | `rtl/mem/edrv32_mem_xbar_regs.v:118/256`、`rtl/soc/edrv32_mem_subsys.v:237`，每端口读/写/等待三组清零及复位，APB组内/组间两级选择 | 端口复位428→164；全局复位446→222；CLEAR 228→84 |
| S4 | `rtl/mem/edrv32_mem_ddr_gw.v:12/283/335`、mem_subsys，拆共享区域复位为网关读/写/CDC及fabric主控/rbuf/scheduler/W读源 | 共享783→449；网关各份12/15/40 |
| S5 | `rtl/eth/edrv32_eth{,_regs}.v`，控制/配置/窗口/peer、PERF、rx/tx/DMA/MDIO分区，APB两级选择 | 架构复位814→364；PERF复位352→96；控制复位404→156；清零605→169 |
| S6 | `rtl/media/disp/edrv32_disp{,_regs}.v`、`rtl/common/edrv32_async_fifo_ram.v:41`，区域/L0/L1/PERF复制，APB两级，FIFO数据选择四份 | mem/pix复位663/724→143/378；寄存器复位733→296；soft_clear 671→228；head_valid 261→68 |
| S7 | `rtl/media/vin/edrv32_vin{,_regs,_ch,_ch2,_p1_arb}.v`，配置/通道/PERF复位分组、FIFO/仲裁选择按64位复制，配置事件部分和寄存 | regs复位949→137；CH0复位838→80；slot选择289→96；仲裁344→151 |
| S8 | `rtl/media/geo/edrv32_geo.v`、`rtl/media/pix/edrv32_pix_filter.v:220`，GEO按单元复制复位/clear，PIX灰度单元分配给0/2/3副本 | GEO复位476→287、clear 22→9；PIX 886→351（291/209/310/351） |
| S9 | `rtl/npu/edrv32_npu{,_conv,_regs}.v`，同D/使能的FSM副本分发start/cancel，复位按子单元，PERF逐计数器清零 | 区域复位789→537、conv复位470→283；cancel 339→242；寄存器soft_reset 354→91；start 690→251；perf_clear 264→1 |
| S10 | `rtl/soc/edrv32_sys_subsys.v:1281`起，原bus/periph共享复位改为每外设/桥接实例独立源 | 两共享根424/701→135/552；目标I2C61、CLINT149 |

S2 经协调器批准按144位物理 IP分片；IP和fpga文件不变，rd_en仍使用当拍握手与active副本，未增加握手级。
S3 内部接口 rst_mem_stat 7→21位（每端口132/132/164），rst_mem_regs 1→3位（222/208/32）；副本均由同一原始复位源并列产生，释放拍不变。
S4 网关rst_mem 1→3位（12/15/40），xbar主复位1→4位（449/116/152/60）。
S10 新增 `u_reset_sys_<单元>_n`：xbar52、rom10、sram10、clint149、plic135、apb_bridge11、media_apb_bridge11、apb_decoder8、uart126、gpio552、i2c61。
APB参考原址负载 mem/ETH/DISP 为4/4/4→7/8/8；组内地址最大7/8/9，组选最大15/32/32。两级结构不增加访问周期，PDS布线收益尚未实测。
S7 仅PERF15累加晚一拍（已获协调器确认）；IRQ/ERR_CODE/帧接纳时机不变，部分和随PERF一起SOFT_RST清零。
卡31来自win `67da9f8d`；N131、N52、N22等自动名的具体门级连接未取得，不将参考网名冒充PDS唯一回映。
仍有单元内部高负载：NPU regs复位537、GPIO复位552、fabric主控449、DISP scan复位378、ETH窗口复位364；均在普查中保留，需PDS继续复核。
测试适配：MX-09只取消本地SLVERR拍的数据为零要求，仍检查RID/RRESP/RLAST/拍数，并保留DDR错误拍原数据检查；MX-10注入修正到现有统计bank寄存器；内部复位/启动端口随位宽适配；NPU观察器对start副本作OR归约；被动APB observer/checker仅把敏感表改为异步复位，检查内容不变。

验证：22个RTL文件风格0告警，SB验证24文件风格0告警，8个子系统lint 0告警；14个单元目录17/17、8个block 86/86、3个board 3/3，合计106/106 PASS。
验证摘要 `build/fanout-soc/verification.log`；本机Icarus矩阵及对应Verilator使用flock和-j1；其余在用户提供的仿真主机（环境不记录）完成，独立目录并行、每次编译-j1。
复现（RTL用上述提交，验证用本报告所在提交；目录与命令均为仓库内相对路径）：
```sh
. ~/.local/opt/edrv32/env.sh
python3 tools/synth/fanout_soc.py build/fanout-soc/reference-before --revision bf56df5c
python3 tools/synth/fanout_soc.py build/fanout-soc/reference-final
python3 tools/check/verilog_style.py $(git diff --name-only bf56df5c -- '*.v')
for t in mem_subsys eth disp vin geo pix npu sys_subsys; do (cd rtl/filelists && verilator --lint-only -Wall -DSIM_MODE --top-module edrv32_$t -f $t.f); done
for t in mem_xbar mem_ddr_gw eth_regs eth_rx edrv32_async_fifo_ram disp_regs vin_regs vin_ch vin_ch2 vin_p1_arb pix_filter npu_conv npu_top npu_regs; do flock /tmp/edrv32-sim.lock python3 tools/regress.py smoke --path verif/unit/$t -j 1; done
for t in mem_subsys eth vin pix geo disp npu sys_subsys; do flock /tmp/edrv32-sim.lock python3 tools/regress.py smoke --path verif/block/$t -j 1; done
for t in board_vision board_render board_npu; do flock /tmp/edrv32-sim.lock python3 tools/regress.py smoke --path verif/soc/$t -j 1; done
```
