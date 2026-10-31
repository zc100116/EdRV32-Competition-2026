# B3N NPU 单独上板连线冒烟

依据：T-BN1、`docs/design/2026-10-30-board-npu-test.md` 第 3、5 节、
SoC 规格 4、5、6.1、7 和 NPU 规格 3、4。测试使用真实 CPU/SYS/MEM/NPU/ETH，
复用 board_render 的 DDR 用户口/差分输入模型和 board_vnpu 的 150 MHz NPU PLL 模型。

顶层保留 sys/NPU PLL、DDR IP/适配器、RGMII、UART、四个按键和五个 LED。
CPU 通过网关连接 P2，NPU 接 P3、媒体 APB 槽 6、PLIC13；
ETH 接 P6、槽 7、PLIC14；MAC RX/TX 共用 RGMII 内 125 MHz、30° PLL 输出，
reset_ctrl 生成 ETH 域复位，PLL lock 不参与全局复位。MEM_XBAR 槽 8/PLIC15 照常连接，槽 9 预留。
移除的 P0/P1/P4/P5 主口全部输入接 0、输出开路；APB 槽 0–5、10–15
返回 PRDATA=0/PREADY=1/PSLVERR=1，PLIC8–12 接 0，沿用 B3-10 空槽契约。
SYS 中只用于已移除域的复位同步器时钟接 clk_mem，相应复位输出开路；
I2C 输入接高电平、输出开路。板级复位为 rst_n_i & sys_lock & npu_lock，
DDR 初始化和各域复位释放沿用现有 reset_ctrl。

`run.py` 调用以下生成命令并运行独立参考模型：

```sh
~/.local/opt/edrv32-py/bin/python tools/npu/gen_case.py \
    --op conv --seed 1 --width 4 --height 1 --cout 16 --out build/board_npu/case
~/.local/opt/edrv32-py/bin/python tools/npu/ref/npu_ref.py build/board_npu/case
```

两条命令之间，runner 把生成镜像及寄存器中的区域基址移到现有 64 KiB DDR 模型内：
DESC=0x1000、MODEL=0x2000、WORK=0x3000、INPUT=0x4000、OUTPUT=0x5000。
描述符的相对偏移保持不变；4×1、Cin16/Cout16、1×1/S1/HALF_TAIL 的输出为 64 字节。
DDR 后门只加载描述符、模型、输入及与参考值逐字节不同的输出初值，
参考输出作为生成的 C 数组编进 SRAM。CPU 读取 NPU/ETH ID，读一次已移除 VIN 的 ID
并核对 load access fault，然后写 NPU 寄存器启动，等 PLIC13 DONE，
通过 DDR 非缓存别名逐字节比较全部输出。TB 同时检查被读槽的三个 APB 返回信号。

测试先核对真实 BIOS 菜单，再复位进入 SRAM。CLINT 启动窗口和 UART 加速沿用
B3-10：Q4 BAUD_DIV=256、peer=6.25 Mbaud；不依赖 NPU 内部延迟。
成功日志必须包含 NPU ID、VIN SLVERR、PLIC13 DONE 和输出比较的 PASS 行。

```sh
. ~/.local/opt/edrv32/env.sh
python3 tools/check/verilog_style.py fpga/rtl/edrv32_fpga_board_npu_top.v verif/soc/board_npu
python3 verif/soc/board_npu/run.py --lint-only
tclsh verif/soc/board_npu/check_import.tcl
flock /tmp/edrv32-sim.lock python3 tools/regress.py smoke --path verif/soc/board_npu -j 1
```

runner 对板级顶层和 TB 分别运行 Verilator 5.020 的
`--lint-only --timing -Wall +define+SIM_MODE --top-module <top> <展开的 files.f>`，
编译使用 `--binary -j 1`，日志位于 `build/board_npu/` 和
`build/regress/smoke/soc/board_npu/verilator/run.log`。

导入检查在 `build/board_npu/import_check/tmp/EdRV32-FPGA/P` 中执行，
其 `tmp/EdRV32-Competition-2026` 符号链接指回当前仓库，验证与 Windows 相同的相对路径。
实际导入 105 个源文件，FDC 保留 13 个时钟：clk_board、clk_ddr_ref、clk_sys、clk_npu、
rst_clk、clk_mem、phy_dq_clk_0/1、phy_dq_sysclk_0/1、clk_rgmii_ref、clk_eth、clk_rgmii_tx；DDR PHY 的 multicycle、
uncertainty、异步组和布局约束均沿用 B2，仅删去不存在的时钟、引脚及相关组。
Tcl mocks 只检查导入和约束语法，PDS 放置布线和板上功能由后续 Windows 任务验收。

需要 24 种生成 IP：

- 板级：ip_pll_sys、ip_pll_npu、ip_ddr3。
- CPU/SYS：ip_ram_icache_tag、ip_ram_icache_data、ip_ram_dcache_tag、
  ip_ram_dcache_data、ip_mul_s33x33、ip_rom_boot、ip_ram_sram。
- MEM：ip_ram_mem_xbar_r、ip_lutram_mem_xbar_w。
- NPU：ip_ram_npu_line、ip_ram_npu_weight、ip_lutram_npu_quant、ip_ram_npu_lut、
  ip_lutram_npu_residual、ip_lutram_npu_result、ip_ram_npu_scratch、
  ip_mul_npu_quant_low、ip_mul_npu_quant_high；INT8 MAC 使用 APM 原语。

- ETH：ip_pll_eth、ip_ram_eth_buf、ip_ram_eth_fifo；RGMII IO 行为模型复用 board_vision。

ETH 覆盖与 board_vnpu 相同：板级接空闲 RGMII 引脚、CPU 读 ETH ID；不增加网络流量检查。
