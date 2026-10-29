# ip_ddr3

| 项 | 内容 |
|---|---|
| IP 类型 | IP Compiler → DDR3 Interface → Logos2 HMIC_S v1.10 |
| 目标器件 | PG2L200H-6，FBB676 |
| 生成模块名 | `ip_ddr3` |
| 生成工具依据 | 厂商 PDS 2022.2-SP6.4 build 146967 |
| 使用者 | `fpga/rtl/edrv32_fpga_board_b2_top.v` 的 `u_ddr3`，直接例化 |
| 控制器配置来源 | `2_Demo/2_9_ddr3_test/2_9_ddr3_test/ddr3_test/ipcore/ddr3_test/ddr3_test.idf` |
| 板级物理接线来源 | `2_Demo/5_1 双目摄像头例程/ov5640_200k/ov5640.fdc`（同一 Mini Base） |
| 初始化文件 | 无，DDR 上电内容未定义 |

## 推荐：导入现成配置 `fpga/ip/ip_ddr3.idf`

`fpga/ip/ip_ddr3.idf` 是厂商 `2_9_ddr3_test` 例程的 `ddr3_test.idf` 原样复制，只把实例名和文件名中的 `ddr3_test` 改为 `ip_ddr3`。其他参数一项未改：
- 控制器和 PHY 设置；
- 存储器型号、位宽、速率、时序；
- DQ 组和引脚规划。

这个例程已在同一块 Mini Base 板上跑通。

1. 在 B2 工程目录下建 `ipcore/ip_ddr3/`，把 `ip_ddr3.idf` 复制进去。
2. 在 PDS 中打开这个 `.idf`（IP Compiler 打开已有 IP 配置，或在工程中添加该 IP 后选择重新定制），确认实例名为 `ip_ddr3`，点击 Generate。
3. 版本处理：
   - 本机 DDR IP 版本与 idf 记录的 HMIC_S v1.10 不同时，PDS 会提示升级。接受升级。
   - 升级后用下文"有效配置值"表逐项核对，把实际版本和不一致的项回传。
4. 生成后按下文第 5、6 条核对：不加入 example_design 顶层；端口与期望端口一致，尤其 `ref_clk`。

导入失败（PDS 不能打开、或版本无法升级）时，改用下面的 GUI 步骤手动配置。

## 用户 GUI 生成步骤（导入失败时使用）

1. 新建 B2 PG2L200H-6/FBB676 工程，在 IP Compiler 创建 DDR3 Interface，
   名称 **ip_ddr3**，Operating Mode 选 **Controller + PHY**。
   使用与 B1 相同的 PDS；若找不到 HMIC_S，应先在 IP 管理器安装本机厂商
   `6_IP_setup_packet/DDR3/ips2l_hmic_s_v1_16a.iar` 提供的 DDR IP 包，
   并把实际可选版本回传。安装包版本与例程 v1.10 不同，不能声称已在 Linux 验证等价。
2. Memory Type=DDR3，Memory Part=MT41K256M16XX（不是界面残留的 BASE_PART 128M）；
   两颗 x16 合成 x32，Row=15、Column=10、Bank=3，DQS=4、DM=4，容量 1 GiB。
   不使能自定义 memory timing，速率 **1000 Mbps**，参考时钟 **125 MHz**，
   用户 core_clk=125 MHz，用户数据 256 位，用户地址 28 位，ID 4 位，LEN 4 位。
3. CL=7，CWL=6，AL=CL-2，ODT=001，Output Driver=00；其余有效 DDR3
   时序值见下表。GUI 中非当前速率项也列在表中，保持厂商取值。
   `DDR3_CL_VALUE=6` 是厂商 idf 的编码字段，生成 RTL MR0 也使用该编码；
   不把编码字段当作 GUI 的 CL=6 再改一次。
4. Pin Planning 中按本仓库 B2 `.fdc` 的 DDR 引脚表配置，板级总线名是
   `mem_*_o`，IP 内部总线名为 `mem_*`。使用 bank R4 的四组 DQ（G0–G3），
   其余 DQ 组不使能；地址/命令分组按下表。
   外部顶层约束负责每位 DQ/DM、DQS P/N 和地址引脚的实际连线，不照搬生成
   example_design 的默认引脚顺序。完整物理引脚/IO 标准见 `fpga/rtl/README.md`。
5. 生成 IP 并添加其生成的 IP 源和依赖到工程，**不加入 example_design BIST 顶层**。
   生成文件留在 Windows 本地，不入库。IP 生成的 PHY 实现约束按 B2 约束中的
   `u_ddr3` 层级使用；B2 `.fdc` 已列出所需 PHY 时钟和布局位置，不重复导入
   example_design 的 `pnr/ddr_test.fdc`（它使用不同的顶层和端口名）。
6. 核对下面的全部端口，尤其 **ref_clk**：厂商 `_tmpl.v` 漏列了它，但
   `ddr3_test.v` 和 example_design 的实例都实际有该输入。实际生成端口不符时
   明确报错并回传接口，由协调者处理，不编辑生成的 IP。

## 有效配置值（对应厂商 idf 字段）

| 字段 | 取值 |
|---|---|
| `OPERATING_MODE` | `Controller + PHY` |
| `MEM_TYPE` | `DDR3` |
| `DDR_MEM_PART` | `MT41K256M16XX` |
| `CUSTOMIZE_MEM` | `false` |
| `MEM_ROW_WIDTH` | `15` |
| `MEM_COLUMN_WIDTH` | `10` |
| `MEM_BANK_WIDTH` | `3` |
| `MEM_DQ_WIDTH` | `32` |
| `MEM_DM_WIDTH` | `4` |
| `MEM_DQS_WIDTH` | `4` |
| `CTRL_ADDR_WIDTH` | `28` |
| `DESIRED_RATE` | `1000.000` |
| `DESIRED_DDR3_RATE` | `1000.000` |
| `ACTUAL_RATE` | `1000.000` |
| `CLKIN_FREQ` | `125.000` |
| `DFI_CLK_PERIOD` | `8000` |
| `DDR3_CL` | `7` |
| `DDR3_CL_VALUE` | `6` |
| `DDR3_CWL` | `6` |
| `DDR3_AL` | `2` |
| `GUI_DDR3_AL` | `CL-2` |
| `DDR3_OUTPUT_DRIVER` | `00` |
| `DDR3_ODT_VALUE` | `001` |
| `DDRC_TREFI` | `3900` |
| `DDRC_TRFC` | `150` |
| `DDRC_T_FAW` | `22` |
| `DDRC_T_RAS` | `19` |
| `DDRC_T_RC` | `25` |
| `DDRC_T_RCD` | `7` |
| `DDRC_T_RP` | `7` |
| `DDRC_T_RRD` | `5` |
| `DDRC_T_RTP` | `4` |
| `DDRC_T_WR` | `8` |
| `DDRC_T_WTR` | `4` |
| `DDRC_T_XP` | `4` |
| `GUI_DDR3_CL_1066` | `7` |
| `GUI_DDR3_CL_800` | `6` |
| `GUI_DDR3_CWL_1066` | `6` |
| `GUI_DDR3_CWL_800` | `5` |
| `GUI_DDR3_TRAS` | `37.500` |
| `GUI_DDR3_TRCD` | `13.500` |
| `GUI_DDR3_TREFI` | `7.800` |
| `GUI_DDR3_TRFC` | `300.000` |
| `GUI_DDR3_TRP` | `13.500` |
| `GUI_DDR3_TRTP` | `7.500` |
| `GUI_DDR3_TWR` | `15.000` |
| `GUI_DDR3_TWTR` | `7.500` |
| `PHY_TMOD` | `12` |
| `PHY_TMRD` | `4` |
| `PHY_TRCD` | `2` |
| `PHY_TRFC` | `38` |
| `PHY_TRP` | `2` |
| `PHY_TXPR` | `39` |
| `GPLL_BANDWIDTH` | `HIGH` |
| `PPLL_BANDWIDTH` | `HIGH` |
| `STATIC_RATIOI` | `1` |
| `STATIC_RATIOF` | `16` |
| `STATIC_RATIO0` | `2` |
| `CUSTOMIZE_CA` | `true` |
| `CS_n_EN` | `true` |
| `A12_EN` | `true` |
| `A13_EN` | `true` |
| `A14_EN` | `true` |
| `A15_EN` | `false` |
| `BA2_EN` | `true` |
| `A0_GROUP_NUM` | `0` |
| `A10_GROUP_NUM` | `1` |
| `A11_GROUP_NUM` | `1` |
| `A12_GROUP_NUM` | `1` |
| `A13_GROUP_NUM` | `0` |
| `A14_GROUP_NUM` | `0` |
| `A15_GROUP_NUM` | `0` |
| `A1_GROUP_NUM` | `0` |
| `A2_GROUP_NUM` | `0` |
| `A3_GROUP_NUM` | `1` |
| `A4_GROUP_NUM` | `1` |
| `A5_GROUP_NUM` | `0` |
| `A6_GROUP_NUM` | `1` |
| `A7_GROUP_NUM` | `0` |
| `A8_GROUP_NUM` | `1` |
| `A9_GROUP_NUM` | `0` |
| `BA0_GROUP_NUM` | `1` |
| `BA1_GROUP_NUM` | `1` |
| `BA2_GROUP_NUM` | `2` |
| `BANK_DQG_0` | `R4` |
| `BANK_DQG_1` | `R4` |
| `BANK_DQG_2` | `R4` |
| `BANK_DQG_3` | `R4` |
| `BANK_DQG_4` | `L4` |
| `BANK_DQG_5` | `L4` |
| `BANK_DQG_6` | `L4` |
| `BANK_DQG_7` | `L4` |
| `BANK_DQG_8` | `L5` |
| `CAS_GROUP_NUM` | `2` |
| `CA_GROUP_NUM` | `3` |
| `CKE_GROUP_NUM` | `1` |
| `CK_GROUP_NUM` | `2` |
| `CS_GROUP_NUM` | `1` |
| `DQ0_EN` | `true` |
| `DQ1_EN` | `true` |
| `DQ2_EN` | `true` |
| `DQ3_EN` | `true` |
| `DQ4_EN` | `false` |
| `DQ5_EN` | `false` |
| `DQ6_EN` | `false` |
| `DQ7_EN` | `false` |
| `DQ8_EN` | `false` |
| `GROUP_DQG_0` | `G1` |
| `GROUP_DQG_1` | `G0` |
| `GROUP_DQG_2` | `G2` |
| `GROUP_DQG_3` | `G3` |
| `GROUP_DQG_4` | `G0` |
| `GROUP_DQG_5` | `G1` |
| `GROUP_DQG_6` | `G2` |
| `GROUP_DQG_7` | `G3` |
| `GROUP_DQG_8` | `G0` |
| `ODT_GROUP_NUM` | `0` |
| `RAS_GROUP_NUM` | `2` |
| `WE_GROUP_NUM` | `2` |

| `A0_DQS_EN` | `false` |
| `A10_DQS_EN` | `false` |
| `A11_DQS_EN` | `true` |
| `A12_DQS_EN` | `false` |
| `A13_DQS_EN` | `false` |
| `A14_DQS_EN` | `true` |
| `A15_DQS_EN` | `false` |
| `A1_DQS_EN` | `false` |
| `A2_DQS_EN` | `false` |
| `A3_DQS_EN` | `false` |
| `A4_DQS_EN` | `false` |
| `A5_DQS_EN` | `true` |
| `A6_DQS_EN` | `false` |
| `A7_DQS_EN` | `false` |
| `A8_DQS_EN` | `false` |
| `A9_DQS_EN` | `false` |
| `BA0_DQS_EN` | `false` |
| `BA1_DQS_EN` | `false` |
| `BA2_DQS_EN` | `false` |
| `BANK0` | `R5` |
| `BANK1` | `R4` |
| `BANK2` | `L6` |
| `CAS_DQS_EN` | `false` |
| `CKE_DQS_EN` | `true` |
| `CK_DQS_EN` | `true` |
| `CS_DQS_EN` | `false` |
| `DQ0_BANK_NUM` | `1` |
| `DQ1_BANK_NUM` | `1` |
| `DQ2_BANK_NUM` | `1` |
| `DQ3_BANK_NUM` | `1` |
| `DQ4_BANK_NUM` | `2` |
| `DQ5_BANK_NUM` | `2` |
| `DQ6_BANK_NUM` | `2` |
| `DQ7_BANK_NUM` | `2` |
| `DQ8_BANK_NUM` | `0` |
| `ODT_DQS_EN` | `false` |
| `RAS_DQS_EN` | `false` |
| `USER_PINS_CON_EN` | `false` |
| `WE_DQS_EN` | `false` |

## 端口和连接

所有端口在 `u_ddr3` 显式连接；不用的诊断输出留空，调试输入按双目例程固定。
APB 调试不使用，所有输入固定 0；`dbg_ddrphy_rst_n=1`，其余调试输入固定 0。
物理 `ref_clk` 由 N3/N2 上的 125 MHz 差分板钟经 `GTP_INBUFDS` 提供；
`resetn` 由按键及 sys/npu/video PLL lock 合成，独立于 mem_ready。
`core_clk` 只驱动 SoC clk_mem；`ddr_init_done` 经适配器直通 mem_ready，
同步和复位排序由 SoC reset_ctrl 负责（5.2 X8、5.3）。

| 端口 | 方向 | 位宽 |
|---|---|---|
| `ref_clk` | input | 1 |
| `resetn` | input | 1 |
| `core_clk` | output | 1 |
| `pll_lock` | output | 1 |
| `phy_pll_lock` | output | 1 |
| `gpll_lock` | output | 1 |
| `rst_gpll_lock` | output | 1 |
| `ddrphy_cpd_lock` | output | 1 |
| `ddr_init_done` | output | 1 |
| `axi_awaddr` | input | 28 |
| `axi_awuser_ap` | input | 1 |
| `axi_awuser_id` | input | 4 |
| `axi_awlen` | input | 4 |
| `axi_awready` | output | 1 |
| `axi_awvalid` | input | 1 |
| `axi_wdata` | input | 256 |
| `axi_wstrb` | input | 32 |
| `axi_wready` | output | 1 |
| `axi_wusero_id` | output | 4 |
| `axi_wusero_last` | output | 1 |
| `axi_araddr` | input | 28 |
| `axi_aruser_ap` | input | 1 |
| `axi_aruser_id` | input | 4 |
| `axi_arlen` | input | 4 |
| `axi_arready` | output | 1 |
| `axi_arvalid` | input | 1 |
| `axi_rdata` | output | 256 |
| `axi_rid` | output | 4 |
| `axi_rlast` | output | 1 |
| `axi_rvalid` | output | 1 |
| `apb_clk` | input | 1 |
| `apb_rst_n` | input | 1 |
| `apb_sel` | input | 1 |
| `apb_enable` | input | 1 |
| `apb_addr` | input | 8 |
| `apb_write` | input | 1 |
| `apb_ready` | output | 1 |
| `apb_wdata` | input | 16 |
| `apb_rdata` | output | 16 |
| `mem_cs_n` | output | 1 |
| `mem_rst_n` | output | 1 |
| `mem_ck` | output | 1 |
| `mem_ck_n` | output | 1 |
| `mem_cke` | output | 1 |
| `mem_ras_n` | output | 1 |
| `mem_cas_n` | output | 1 |
| `mem_we_n` | output | 1 |
| `mem_odt` | output | 1 |
| `mem_a` | output | 15 |
| `mem_ba` | output | 3 |
| `mem_dqs` | inout | 4 |
| `mem_dqs_n` | inout | 4 |
| `mem_dq` | inout | 32 |
| `mem_dm` | output | 4 |
| `dbg_gate_start` | input | 1 |
| `dbg_cpd_start` | input | 1 |
| `dbg_ddrphy_rst_n` | input | 1 |
| `dbg_gpll_scan_rst` | input | 1 |
| `samp_position_dyn_adj` | input | 1 |
| `init_samp_position_even` | input | 32 |
| `init_samp_position_odd` | input | 32 |
| `wrcal_position_dyn_adj` | input | 1 |
| `init_wrcal_position` | input | 32 |
| `force_read_clk_ctrl` | input | 1 |
| `init_slip_step` | input | 16 |
| `init_read_clk_ctrl` | input | 12 |
| `debug_calib_ctrl` | output | 34 |
| `dbg_slice_status` | output | 68 |
| `dbg_slice_state` | output | 88 |
| `debug_data` | output | 276 |
| `dbg_dll_upd_state` | output | 2 |
| `debug_gpll_dps_phase` | output | 9 |
| `dbg_rst_dps_state` | output | 3 |
| `dbg_tran_err_rst_cnt` | output | 6 |
| `dbg_ddrphy_init_fail` | output | 1 |
| `debug_cpd_offset_adj` | input | 1 |
| `debug_cpd_offset_dir` | input | 1 |
| `debug_cpd_offset` | input | 10 |
| `debug_dps_cnt_dir0` | output | 10 |
| `debug_dps_cnt_dir1` | output | 10 |
| `ck_dly_en` | input | 1 |
| `init_ck_dly_step` | input | 8 |
| `ck_dly_set_bin` | output | 8 |
| `align_error` | output | 1 |
| `debug_rst_state` | output | 4 |
| `debug_cpd_state` | output | 4 |

## 用户口时序与延迟

参考 `edrv32_fpga_ddr_adapter.v`：地址以 32 位字计数，SoC 物理字节地址
[29:2] 接用户口 [27:0]；每个 256 位 beat 地址加 8。AW/AR 是 valid/ready 握手，
LEN=拍数−1（1–16 拍），AP=0。IP 没有 WVALID/WLAST；mem_xbar 在 AW 前
缓冲整笔写，接受 AW 后连续提供数据。WSTRB 每位使能一个字节。
`axi_wusero_last` 合成 BVALID，`axi_wusero_id` 合成 BID，BRESP=OKAY。
RVALID/RLAST/RID 直通，没有 BREADY/RREADY。读写延迟由仲裁、行命中、刷新和
校准决定，不能当成固定拍数；本适配器为纯组合逻辑，附加延迟 0 拍。

“写完成之后新发起的读可见该写”是已存 DDR 适配器的硬件接口假设；本任务仅 lint，
该顺序性仍需 Windows 上板验证。回传实际 IP 版本、端口表、频率、参数截图、
DDR 初始化及 BIOS DDR 读写结果、PDS 资源时序；没有运行板级仿真。
