# 完整 NPU 的 9 个 IP 核对

来源：全部沿用 `G:/codex_project/EdRV32-FPGA/EdRV32-NPU-DP/ipcore/`；完整 NPU CMR 列出这 9 个 .idf，Compile/Synthesize 均完成。
本轮没有修改 RTL 包装或重新生成 IP。以下配置与端口摘自实际生成的 .idf/.v。

## ip_mul_npu_quant_high

- 模块名：`ip_mul_npu_quant_high`；封装：FBB676。
- 端口：`ce, rst, clk, a, b, p`；包装端口集合一致。
- SNR 层次中 16 个实例，合计 DRM36K=0，APM=16。
- 配置：ASIZE=16; BSIZE=16; A_SIGNED=1; B_SIGNED=1

- 生成 .v 中实际流水：XYREG=1; MREG=1; PREG=0; INREG=0; OUTREG=0。

## ip_mul_npu_quant_low

- 模块名：`ip_mul_npu_quant_low`；封装：FBB676。
- 端口：`ce, rst, clk, a, b, p`；包装端口集合一致。
- SNR 层次中 16 个实例，合计 DRM36K=0，APM=16。
- 配置：ASIZE=18; BSIZE=16; A_SIGNED=1; B_SIGNED=1

- 生成 .v 中实际流水：XYREG=1; MREG=1; PREG=0; INREG=0; OUTREG=0。

## ip_ram_npu_line

- 模块名：`ip_ram_npu_line`；封装：FBB676。
- 端口：`wr_data, wr_addr, wr_en, wr_clk, wr_rst, rd_data, rd_addr, rd_clk, rd_clk_en, rd_rst`；包装端口集合一致。
- SNR 层次中 2 个实例，合计 DRM36K=16，APM=0。
- 配置：WR_ADDR_WIDTH=10; WR_DATA_WIDTH=256; RD_ADDR_WIDTH=10; RD_DATA_WIDTH=256; OUTPUT_REG=true; RD_CLK_EN=true; WR_CLK_EN=false; RESET_TYPE=ASYNC; CAS_MODE=36K

## ip_ram_npu_lut

- 模块名：`ip_ram_npu_lut`；封装：FBB676。
- 端口：`wr_data, wr_addr, wr_en, wr_clk, wr_rst, rd_data, rd_addr, rd_clk, rd_clk_en, rd_rst`；包装端口集合一致。
- SNR 层次中 16 个实例，合计 DRM36K=16，APM=0。
- 配置：WR_ADDR_WIDTH=12; WR_DATA_WIDTH=8; RD_ADDR_WIDTH=12; RD_DATA_WIDTH=8; OUTPUT_REG=true; RD_CLK_EN=true; WR_CLK_EN=false; RESET_TYPE=ASYNC; CAS_MODE=36K

## ip_ram_npu_quant

- 模块名：`ip_ram_npu_quant`；封装：FBB676。
- 端口：`wr_data, wr_addr, wr_en, wr_clk, wr_rst, rd_data, rd_addr, rd_clk, rd_clk_en, rd_rst`；包装端口集合一致。
- SNR 层次中 8 个实例，合计 DRM36K=8，APM=0。
- 配置：WR_ADDR_WIDTH=9; WR_DATA_WIDTH=64; RD_ADDR_WIDTH=9; RD_DATA_WIDTH=64; OUTPUT_REG=true; RD_CLK_EN=true; WR_CLK_EN=false; RESET_TYPE=ASYNC; CAS_MODE=36K

## ip_ram_npu_residual

- 模块名：`ip_ram_npu_residual`；封装：FBB676。
- 端口：`wr_data, wr_addr, wr_en, wr_clk, wr_rst, rd_data, rd_addr, rd_clk, rd_clk_en, rd_rst`；包装端口集合一致。
- SNR 层次中 1 个实例，合计 DRM36K=4，APM=0。
- 配置：WR_ADDR_WIDTH=9; WR_DATA_WIDTH=256; RD_ADDR_WIDTH=9; RD_DATA_WIDTH=256; OUTPUT_REG=true; RD_CLK_EN=true; WR_CLK_EN=false; RESET_TYPE=ASYNC; CAS_MODE=36K

## ip_ram_npu_result

- 模块名：`ip_ram_npu_result`；封装：FBB676。
- 端口：`wr_data, wr_addr, wr_en, wr_clk, wr_rst, rd_data, rd_addr, rd_clk, rd_clk_en, rd_rst`；包装端口集合一致。
- SNR 层次中 1 个实例，合计 DRM36K=8，APM=0。
- 配置：WR_ADDR_WIDTH=9; WR_DATA_WIDTH=512; RD_ADDR_WIDTH=9; RD_DATA_WIDTH=512; OUTPUT_REG=true; RD_CLK_EN=true; WR_CLK_EN=false; RESET_TYPE=ASYNC; CAS_MODE=36K

## ip_ram_npu_scratch

- 模块名：`ip_ram_npu_scratch`；封装：FBB676。
- 端口：`wr_data, wr_addr, wr_en, wr_clk, wr_rst, rd_data, rd_addr, rd_clk, rd_clk_en, rd_rst`；包装端口集合一致。
- SNR 层次中 2 个实例，合计 DRM36K=8，APM=0。
- 配置：WR_ADDR_WIDTH=9; WR_DATA_WIDTH=256; RD_ADDR_WIDTH=9; RD_DATA_WIDTH=256; OUTPUT_REG=false; RD_CLK_EN=true; WR_CLK_EN=false; RESET_TYPE=ASYNC; CAS_MODE=36K

## ip_ram_npu_weight

- 模块名：`ip_ram_npu_weight`；封装：FBB676。
- 端口：`wr_data, wr_addr, wr_en, wr_clk, wr_rst, rd_data, rd_addr, rd_clk, rd_clk_en, rd_rst`；包装端口集合一致。
- SNR 层次中 24 个实例，合计 DRM36K=96，APM=0。
- 配置：WR_ADDR_WIDTH=9; WR_DATA_WIDTH=256; RD_ADDR_WIDTH=9; RD_DATA_WIDTH=256; OUTPUT_REG=true; RD_CLK_EN=true; WR_CLK_EN=false; RESET_TYPE=ASYNC; CAS_MODE=36K

7 个 RAM 的 wr_rst、rd_rst 在包装内接 1'b0，按前轮确认保留；两个量化乘法器同样 rst=1'b0、ce=1'b1。
DRM18K=0；整机 DRM36K=157、APM=290 以 SNR 总计为准，还包含直接例化原语及推断存储，不等于上面 9 类 IP 的简单求和。
