# EdRV32 模块引用例化树

范围：从板无关系统顶层 `edrv32_soc_top` 展开；不展开 FPGA 顶层、Pango 生成 IP、门级原语和未被当前顶层例化的备用模块。重复的结构单元用“×N”合并表示。

| 引用例化树（实例名 : 模块名） | 源码路径 | 主要职责 / 备注 |
|---|---|---|
| `edrv32_soc_top` | `rtl/soc/top/edrv32_soc_top.v` | 板无关的完整 SoC 顶层 |
| ├─ `u_cached_core : edrv32_cached_core` | `rtl/cpu/core/edrv32_cached_core.v` | CPU、PMA、Cache 和维护路由封装 |
| │&nbsp;&nbsp;├─ `u_dmem_route_pma : edrv32_pma_classifier` | `rtl/cpu/lsu/edrv32_pma_classifier.v` | 数据地址属性和 DTCM/D$/维护窗口路由 |
| │&nbsp;&nbsp;├─ `u_imem_pma : edrv32_pma_classifier` | `rtl/cpu/lsu/edrv32_pma_classifier.v` | 取指权限和 ITCM/I$ 路由 |
| │&nbsp;&nbsp;├─ `u_core : edrv32_core` | `rtl/cpu/core/edrv32_core.v` | 八级 CPU 的结构化集成与连线 |
| │&nbsp;&nbsp;│&nbsp;&nbsp;├─ `u_branch_predictor : edrv32_branch_predictor` | `rtl/cpu/control/edrv32_branch_predictor.v` | BTB、BHT、RAS |
| │&nbsp;&nbsp;│&nbsp;&nbsp;├─ `u_if1_stage : edrv32_if1_stage` | `rtl/cpu/frontend/edrv32_if1_stage.v` | IF1：PC/epoch 和取指候选 |
| │&nbsp;&nbsp;│&nbsp;&nbsp;├─ `u_pipe_if1_to_if2 : edrv32_pipe_if1_to_if2` | `rtl/cpu/pipeline/edrv32_pipe_if1_to_if2.v` | R1：已接受请求的 PC/epoch tag 队列 |
| │&nbsp;&nbsp;│&nbsp;&nbsp;├─ `u_if2_stage : edrv32_if2_stage` | `rtl/cpu/frontend/edrv32_if2_stage.v` | IF2：响应配对和 6-halfword 缓冲 |
| │&nbsp;&nbsp;│&nbsp;&nbsp;├─ `u_pipe_if2_to_align : edrv32_pipe_if2_to_align` | `rtl/cpu/pipeline/edrv32_pipe_if2_to_align.v` | R2：最老 halfword window |
| │&nbsp;&nbsp;│&nbsp;&nbsp;├─ `u_align_stage : edrv32_align_stage` | `rtl/cpu/frontend/edrv32_align_stage.v` | ALIGN：16/32-bit 对齐和跨 word 拼接 |
| │&nbsp;&nbsp;│&nbsp;&nbsp;│&nbsp;&nbsp;└─ `u_decompress : edrv32_rvc_decompress` | `rtl/cpu/frontend/edrv32_rvc_decompress.v` | RVC 解压及合法性判断 |
| │&nbsp;&nbsp;│&nbsp;&nbsp;├─ `u_pipe_align_to_decode : edrv32_pipe_align_to_decode` | `rtl/cpu/pipeline/edrv32_pipe_align_to_decode.v` | R3：规范指令、PC、预测和异常信息 |
| │&nbsp;&nbsp;│&nbsp;&nbsp;├─ `u_decode_stage : edrv32_decode_stage` | `rtl/cpu/decode/edrv32_decode_stage.v` | DECODE：译码、读 GPR、依赖检查与 uop 形成 |
| │&nbsp;&nbsp;│&nbsp;&nbsp;│&nbsp;&nbsp;├─ `u_decoder : edrv32_decoder` | `rtl/cpu/decode/edrv32_decoder.v` | 指令类型和控制字段译码 |
| │&nbsp;&nbsp;│&nbsp;&nbsp;│&nbsp;&nbsp;├─ `u_immgen : edrv32_immgen` | `rtl/cpu/decode/edrv32_immgen.v` | 立即数生成 |
| │&nbsp;&nbsp;│&nbsp;&nbsp;│&nbsp;&nbsp;├─ `u_regfile : edrv32_regfile` | `rtl/cpu/datapath/edrv32_regfile.v` | 32×32 GPR，2 组合读、1 COMMIT 写 |
| │&nbsp;&nbsp;│&nbsp;&nbsp;│&nbsp;&nbsp;└─ `u_operand_resolve : edrv32_operand_resolve` | `rtl/cpu/decode/edrv32_operand_resolve.v` | 按年龄选择寄存化旁路结果 |
| │&nbsp;&nbsp;│&nbsp;&nbsp;├─ `u_pipe_decode_to_ex : edrv32_pipe_decode_to_ex` | `rtl/cpu/pipeline/edrv32_pipe_decode_to_ex.v` | R4：完整 uop 和已选择操作数 |
| │&nbsp;&nbsp;│&nbsp;&nbsp;├─ `u_ex_stage : edrv32_ex_stage` | `rtl/cpu/execute/edrv32_ex_stage.v` | EX：ALU、分支、EA 和 MDU 分派 |
| │&nbsp;&nbsp;│&nbsp;&nbsp;│&nbsp;&nbsp;├─ `u_pc_relative_target : edrv32_adder32` | `rtl/cpu/datapath/edrv32_adder32.v` | PC 相对目标地址加法 |
| │&nbsp;&nbsp;│&nbsp;&nbsp;│&nbsp;&nbsp;├─ `u_alu : edrv32_alu` | `rtl/cpu/execute/edrv32_alu.v` | 正式结构化整数 ALU |
| │&nbsp;&nbsp;│&nbsp;&nbsp;│&nbsp;&nbsp;│&nbsp;&nbsp;├─ `u_add_sub : edrv32_adder32` | `rtl/cpu/datapath/edrv32_adder32.v` | 加减法 |
| │&nbsp;&nbsp;│&nbsp;&nbsp;│&nbsp;&nbsp;│&nbsp;&nbsp;├─ `u_shift : edrv32_shifter32` | `rtl/cpu/datapath/edrv32_shifter32.v` | 逻辑/算术移位 |
| │&nbsp;&nbsp;│&nbsp;&nbsp;│&nbsp;&nbsp;│&nbsp;&nbsp;└─ `u_compare : edrv32_compare32` | `rtl/cpu/datapath/edrv32_compare32.v` | 有符号/无符号比较 |
| │&nbsp;&nbsp;│&nbsp;&nbsp;│&nbsp;&nbsp;└─ `u_branch_unit : edrv32_branch_unit` | `rtl/cpu/execute/edrv32_branch_unit.v` | 分支条件判断 |
| │&nbsp;&nbsp;│&nbsp;&nbsp;│&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;└─ `u_compare : edrv32_compare32` | `rtl/cpu/datapath/edrv32_compare32.v` | 分支比较器 |
| │&nbsp;&nbsp;│&nbsp;&nbsp;├─ `u_pipe_ex_to_mem1 : edrv32_pipe_ex_to_mem1` | `rtl/cpu/pipeline/edrv32_pipe_ex_to_mem1.v` | R5：执行结果、地址和控制流结果 |
| │&nbsp;&nbsp;│&nbsp;&nbsp;├─ `u_mem1_stage : edrv32_mem1_stage` | `rtl/cpu/lsu/edrv32_mem1_stage.v` | MEM1：PMA 分类和访存 packet 形成 |
| │&nbsp;&nbsp;│&nbsp;&nbsp;│&nbsp;&nbsp;└─ `u_pma_classifier : edrv32_pma_classifier` | `rtl/cpu/lsu/edrv32_pma_classifier.v` | 当前指令的数据访问属性判断 |
| │&nbsp;&nbsp;│&nbsp;&nbsp;├─ `u_pipe_mem1_to_mem2 : edrv32_pipe_mem1_to_mem2` | `rtl/cpu/pipeline/edrv32_pipe_mem1_to_mem2.v` | R6：2-entry timing-cut FIFO |
| │&nbsp;&nbsp;│&nbsp;&nbsp;├─ `u_mem2_stage : edrv32_mem2_stage` | `rtl/cpu/lsu/edrv32_mem2_stage.v` | MEM2：D$ lookup、等待与 load 结果形成 |
| │&nbsp;&nbsp;│&nbsp;&nbsp;│&nbsp;&nbsp;└─ `u_cached_load_format : edrv32_lsu_format` | `rtl/cpu/lsu/edrv32_lsu_format.v` | 命中/补行数据的 load 对齐与扩展 |
| │&nbsp;&nbsp;│&nbsp;&nbsp;├─ `u_pipe_mem2_to_commit : edrv32_pipe_mem2_to_commit` | `rtl/cpu/pipeline/edrv32_pipe_mem2_to_commit.v` | R7：已完成的 commit packet |
| │&nbsp;&nbsp;│&nbsp;&nbsp;├─ `u_commit_stage : edrv32_commit_stage` | `rtl/cpu/commit/edrv32_commit_stage.v` | COMMIT：唯一不可撤销副作用和架构提交点 |
| │&nbsp;&nbsp;│&nbsp;&nbsp;│&nbsp;&nbsp;├─ `u_lsu_format : edrv32_lsu_format` | `rtl/cpu/lsu/edrv32_lsu_format.v` | store 数据/写掩码及 uncached load 格式化 |
| │&nbsp;&nbsp;│&nbsp;&nbsp;│&nbsp;&nbsp;└─ `u_csr_file : edrv32_csr_file` | `rtl/cpu/csr/edrv32_csr_file.v` | CSR、trap 状态、cycle/instret |
| │&nbsp;&nbsp;│&nbsp;&nbsp;│&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;└─ `u_hpm_counters : edrv32_hpm_counters` | `rtl/cpu/csr/edrv32_hpm_counters.v` | 可参数裁剪的 HPM3…16 |
| │&nbsp;&nbsp;│&nbsp;&nbsp;├─ `u_mdu_scoreboard : edrv32_mdu_scoreboard` | `rtl/cpu/control/edrv32_mdu_scoreboard.v` | 一槽 MDU pending-rd RAW/WAW 检查 |
| │&nbsp;&nbsp;│&nbsp;&nbsp;├─ `u_mdu : edrv32_mdu` | `rtl/cpu/mdu/edrv32_mdu.v` | 乘除分派、授权和公共结果槽 |
| │&nbsp;&nbsp;│&nbsp;&nbsp;│&nbsp;&nbsp;├─ `gen_portable_multiplier.u_multiplier : edrv32_mul_booth4_wallace` | `rtl/cpu/mdu/edrv32_mul_booth4_wallace.v` | 非 FPGA 路径：Booth4、Wallace、3 段乘法 |
| │&nbsp;&nbsp;│&nbsp;&nbsp;│&nbsp;&nbsp;│&nbsp;&nbsp;├─ `u_negate_x1/x2/x4/x8 + u_final_product_adder : edrv32_adder64 ×5` | `rtl/cpu/datapath/edrv32_adder64.v` | 64-bit 取负和末级求和；每个内部例化两个 `edrv32_adder32` |
| │&nbsp;&nbsp;│&nbsp;&nbsp;│&nbsp;&nbsp;│&nbsp;&nbsp;└─ `u_reduce_* : edrv32_wallace_compress_3to2 ×16` | `rtl/cpu/datapath/edrv32_wallace_compress_3to2.v` | Wallace 压缩树；内部按位生成 `edrv32_full_adder` |
| │&nbsp;&nbsp;│&nbsp;&nbsp;│&nbsp;&nbsp;└─ `u_divider : edrv32_div_nonrestoring` | `rtl/cpu/mdu/edrv32_div_nonrestoring.v` | radix-2 非恢复迭代除法器 |
| │&nbsp;&nbsp;│&nbsp;&nbsp;│&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;└─ `edrv32_adder32 ×6 + edrv32_full_adder ×2` | `rtl/cpu/datapath/` | 取绝对值、迭代加减、余数校正和结果符号处理 |
| │&nbsp;&nbsp;│&nbsp;&nbsp;└─ `u_redirect_ctrl : edrv32_redirect_ctrl` | `rtl/cpu/control/edrv32_redirect_ctrl.v` | EX/COMMIT redirect 仲裁并寄存输出 |
| │&nbsp;&nbsp;├─ `u_icache : edrv32_icache` | `rtl/cpu/cache/edrv32_icache.v` | 4 KiB、2-way、命中II=1、单项blocking miss I$ |
| │&nbsp;&nbsp;│&nbsp;&nbsp;├─ `u_way0_array : edrv32_cache_array` | `rtl/cpu/cache/edrv32_cache_array.v` | way 0 同步 tag/data 数组 |
| │&nbsp;&nbsp;│&nbsp;&nbsp;└─ `u_way1_array : edrv32_cache_array` | `rtl/cpu/cache/edrv32_cache_array.v` | way 1 同步 tag/data 数组 |
| │&nbsp;&nbsp;├─ `u_dcache : edrv32_dcache` | `rtl/cpu/cache/edrv32_dcache.v` | 4 KiB、2-way、WB+WA、blocking D$ |
| │&nbsp;&nbsp;│&nbsp;&nbsp;├─ `u_way0_array : edrv32_cache_array` | `rtl/cpu/cache/edrv32_cache_array.v` | way 0 同步 tag/data 数组 |
| │&nbsp;&nbsp;│&nbsp;&nbsp;└─ `u_way1_array : edrv32_cache_array` | `rtl/cpu/cache/edrv32_cache_array.v` | way 1 同步 tag/data 数组 |
| │&nbsp;&nbsp;└─ `u_cache_maint : edrv32_cache_maint` | `rtl/cpu/cache/edrv32_cache_maint.v` | CPU-local cache maintenance MMIO |
| ├─ `u_axi_interconnect : axi_interconnect` | `rtl/soc/fabric/axi_interconnect.v` | I$/D$ 直连的 2-master/5-slave AXI 互连 |
| │&nbsp;&nbsp;├─ `u_axi_rd_fabric : axi_rd_fabric` | `rtl/soc/fabric/axi_rd_fabric.v` | AXI 读地址/数据路由、仲裁和 owner 跟踪 |
| │&nbsp;&nbsp;└─ `u_axi_wr_fabric : axi_wr_fabric` | `rtl/soc/fabric/axi_wr_fabric.v` | AXI 写地址/数据/响应路由和 owner 跟踪 |
| ├─ `u_boot_rom : boot_rom_axi` | `rtl/soc/mem/boot_rom_axi.v` | AXI Boot ROM slave |
| │&nbsp;&nbsp;└─ `gen_rtl_boot_rom.u_boot_rom_storage : boot_rom_storage` | `rtl/soc/mem/boot_rom_storage.v` | 非 FPGA 路径的同步 ROM 存储体 |
| ├─ `u_sram : sram_axi` | `rtl/soc/mem/sram_axi.v` | AXI 片上 SRAM slave |
| │&nbsp;&nbsp;└─ `gen_rtl_storage.u_sram_storage : sram_storage` | `rtl/soc/mem/sram_storage.v` | 非 FPGA 路径的同步 SRAM 存储体 |
| ├─ `u_a2n_clint : axi2native` | `rtl/soc/fabric/axi2native.v` | CLINT AXI 转 native bridge |
| ├─ `u_clint : clint` | `rtl/soc/intc/clint.v` | `mtime`、MSIP、MTIP |
| ├─ `u_a2n_plic : axi2native` | `rtl/soc/fabric/axi2native.v` | PLIC AXI 转 native bridge |
| ├─ `u_plic : plic` | `rtl/soc/intc/plic.v` | UART/GPIO/SPI + platform source 4..31 聚合为 MEIP |
| ├─ `u_a2p : axi2apb` | `rtl/soc/fabric/axi2apb.v` | AXI 转 APB bridge |
| ├─ `u_apb_mux : apb_mux` | `rtl/soc/fabric/apb_mux.v` | APB slot 选择和响应复用 |
| ├─ `u_uart0 : uart` | `rtl/soc/periph/uart.v` | UART0 外设 |
| │&nbsp;&nbsp;├─ `u_tx_fifo : sync_fifo` | `rtl/com/sync_fifo.v` | UART 发送 FIFO |
| │&nbsp;&nbsp;└─ `u_rx_fifo : sync_fifo` | `rtl/com/sync_fifo.v` | UART 接收 FIFO |
| ├─ `u_gpio0 : gpio` | `rtl/soc/periph/gpio.v` | 16-bit GPIO 外设 |
| └─ `u_spi0 : spi` | `rtl/soc/periph/spi.v` | SPI0 外设 |
| &nbsp;&nbsp;&nbsp;&nbsp;├─ `u_sync_fifo_tx : sync_fifo` | `rtl/com/sync_fifo.v` | SPI 发送 FIFO |
| &nbsp;&nbsp;&nbsp;&nbsp;└─ `u_sync_fifo_rx : sync_fifo` | `rtl/com/sync_fifo.v` | SPI 接收 FIFO |
