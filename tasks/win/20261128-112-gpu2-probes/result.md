# 卡 112 结果

| 项 | 值 |
|---|---|
| 工程源码 HEAD | `35ec01496c9acea5a3b9963435fe22eb32bc9c13` |
| PDS | 2022.2-SP6.1 build 138931，PG2L200H-6 FBB676 |
| 约束 | 五个工程均为 `clk_i` 单时钟，4.545 ns |
| 当前阶段 | 五个探针完成布局布线和时序报告。DRM 同址行为验证通过。 |

## 汇总

Slow Corner，WNS、TNS、WHS、THS 单位 ns。Fmax 为 PDS 估算。资源取布线后层次顶层计数，control set 取 ADS 综合。

| 工程 | WNS / TNS | WHS / THS | Fmax MHz | LUT / FF | DRM / APM / 分布式 RAM / I/O | CLMA / CLMS | Control sets | P&R 墙钟 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| [fp32](artifacts/fp32) | -4.078 / -2673.007 | 0.145 / 0.000 | 115.9689 | 8,241 / 5,045 | 0 / 8 / 80 / 34 | 2046 / 732 | 83 | 0h:4m:50s |
| [sfu](artifacts/sfu) | -2.712 / -579.827 | 0.142 / 0.000 | 137.7980 | 4,546 / 3,862 | 15 / 4 / 60 / 34 | 1237 / 343 | 42 | 0h:4m:9s |
| [setup](artifacts/setup) | -4.188 / -1115.513 | 0.165 / 0.000 | 114.5082 | 1,337 / 1,362 | 0 / 6 / 0 / 4 | 386 / 96 | 5 | 0h:2m:22s |
| [banks](artifacts/banks) | 0.444 / 0.000 | 0.106 / 0.000 | 243.8430 | 1,589 / 15,362 | 159 / 0 / 0 / 4 | 3266 / 808 | 2 | 0h:3m:4s |
| [banks_lutram](artifacts/banks_lutram) | 0.698 / 0.000 | 0.131 / 0.000 | 259.9428 | 4,901 / 21,986 | 15 / 0 / 3,312 / 4 | 3517 / 1617 | 74 | 0h:3m:50s |

Banks 两方案均满足 220 MHz，LUTRAM 方案由 159 降至 15 个 DRM。FP32、SFU 和 Setup 均有 setup 违例。路线、上下游关键段及高扇出见各组附件。

## 各工程最差路径与重点段

- **fp32** 最差为 -4.078 ns，15 逻辑级，逻辑 / 布线延迟 3.061 / 5.309 ns。起点 `u_fp32/g_lane[3].u_scalar/u_product/u_tail/u_apm/gopapm/CLK`，终点 `u_fp32/g_lane[3].u_scalar/tap_s6_increment_r/opit_0_L6Q_perm/I3`。 [路径明细](artifacts/fp32/setup_top20_detail.txt) · [IP 消息](artifacts/fp32/ip-messages.txt)
- **sfu** 最差为 -2.712 ns，14 逻辑级，逻辑 / 布线延迟 2.990 / 4.228 ns。起点 `request_lfsr_r[12]/opit_0_inv/CLK`，终点 `u_sfu/u_seed_rom/u_ip/U_ipm2l_dpram_ip_rom_gpu2_sfu/ADDR_LOOP[0].DATA_LOOP[0].U_GTP_DRM36K_E1/gopdrm_36k/ADA0[12]`。 [路径明细](artifacts/sfu/setup_top20_detail.txt) · [IP 消息](artifacts/sfu/ip-messages.txt)
- **setup** 最差为 -4.188 ns，27 逻辑级，逻辑 / 布线延迟 4.192 / 4.242 ns。起点 `mantissa_r[1]/opit_0_srl/CLK`，终点 `u_probe/u_normalize/truncated_r[3]/opit_0_L6Q_perm/I3`。 [路径明细](artifacts/setup/setup_top20_detail.txt) · [IP 消息](artifacts/setup/ip-messages.txt)
- **banks** 最差为 +0.444 ns，0 逻辑级，逻辑 / 布线延迟 1.644 / 2.281 ns。起点 `u_probe/g_setup[70].u_half1/u_ip/U_ipm2l_sdpram_ip_ram_gpu2_sdp72/ADDR_LOOP[0].DATA_LOOP[0].U_GTP_DRM36K_E1/gopdrm_36k/CLKB[0]`，终点 `u_probe/g_setup[70].capture_r[75]/opit_0/D`。 [路径明细](artifacts/banks/setup_top20_detail.txt) · [IP 消息](artifacts/banks/ip-messages.txt)
- **banks_lutram** 最差为 +0.698 ns，3 逻辑级，逻辑 / 布线延迟 0.801 / 2.494 ns。起点 `u_probe/g_rf[2].capture_r[51]/opit_0/CLK`，终点 `rf_rd_data_observed_r/opit_0_L6Q_perm/I2`。 [路径明细](artifacts/banks_lutram/setup_top20_detail.txt) · [IP 消息](artifacts/banks_lutram/ip-messages.txt)

| 工程 | 重点段 | Slow Corner setup 裕量 ns |
|---|---|---:|
| fp32 | DP 第一级 product_o → s1_small_r | -3.703 |
| fp32 | DP 第二层 result_o → s1_small_r | -3.275 |
| fp32 | DP 对齐加法 s1_small_r → s2_sum_r | +2.701 |
| fp32 | DP 舍入 s2_sum_r → result_o | -3.285 |
| fp32 | 最终 DP 舍入 s2_sum_r → 队列写口 | -3.030 |
| fp32 | APM 原语间级联 | +2.733 |
| sfu | SFU s6_c_r → s7_forward_r | +1.772 |
| sfu | APM 原语间级联 | +2.734 |
| setup | N48 首拍 | -4.188 |
| setup | APM 原语间级联 | +2.734 |
| banks | DRM 读出 → 业务捕获寄存器 | +0.444 |
| banks_lutram | DRM 读出 → 业务捕获寄存器 | +1.422 |
| banks_lutram | Setup LUTRAM 读出寄存器 → 业务捕获寄存器 | 未取得 |

重点段优先取同口径最差 200 条路径，未出现在其中的路径使用 PDS 起终点过滤导出。各组目录保留原始报告、阶段日志和导出参数。

## 修订版配置与 DRM 仿真

已同步任务提交 35ec0149。A 组仍使用原 gpu2_probe_fp32.pds，源文件指向已修复的 edrv32_ram_gpu2_queue.v。包装和 IDF 的 8 个端口逐项一致。写时钟与读时钟都接 clk_i，rst 接 0，保留 16×32、异步读、输出寄存器关闭。A 组已生成队列 IP，并完成布线。

B、D、E 的 DRM SDP 保持厂商默认 NORMAL_WRITE。检查了现有 B、D、E 的已生成 RTL，尺寸、读使能、无输出寄存器、无初始化和无字节使能均与本轮一致。修订与 B、C、D、E 的 RTL、FDC 和 IP 可选参数无差异，沿用各自已生成 IP 和既有流程产物。

按第 4b 步在 ModelSim SE-64 2020.4 使用 B 的 scratch、D 的 SDP72/SDP36 和本机 Pango GTP_DRM 模型仿真。第一次加载报 vsim-3009，原因是测试模块缺少时间单位。仅在本地 .do 的 vlog 命令加 -timescale 1ns/1ps 后重新运行，任务测试源码保持原样。

```text
# PASS drm_collision
#    Time: 70 ns  Iteration: 1  Instance: /drm_collision_check
# Errors: 0, Warnings: 1
```

SDP72 和 SDP36 在同沿同址读写时读到旧字，下一次读得到新字。SFU scratch 同沿读到包装转发的新字。唯一载入告警为厂商 GTP_DRM36K_E1.v(746) 的 vopt-2250，mem_read_a 缺少返回值赋值。

本地脚本与两次原始日志在 G:/codex_project/edrv32-card112/build/win/20261128-112-gpu2-probes/。

## 工程配置

| 工程 | RTL 文件 | 预填 IP 配置 |
|---|---:|---|
| A · fp32 | 11 | `ip_ram_gpu2_queue`，Distributed SDP RAM，16×32 |
| B · sfu | 19 | `ip_rom_gpu2_sfu`，DRM TDP 1024×32，两独立读使能及 HEX 初值。 `ip_ram_gpu2_sfu_scratch`，DRM SDP 1024×32。两份 Distributed SDP 分别为 32×16 和 32×5。 |
| C · setup | 7 | 使用器件 APM 原语，无需生成 IP。 |
| D · banks | 4 | `ip_ram_gpu2_sdp72` 512×72，`ip_ram_gpu2_sdp36` 1024×36，均为 DRM SDP。 |
| E · banks_lutram | 5 | 与 D 相同的两份 DRM SDP，另有 `ip_lutram_gpu2_setup92`，Distributed SDP 16×92。 |

## 初版配置时的问题与偏离

- A 的 `rtl/tech/edrv32_ram_gpu2_queue.v` 实例要求 `clk`。本机 PDS Distributed SDP RAM 的 UI 和生成模板固定提供 `wr_clk`、`rd_clk` 和 `rst`，没有名为 `clk` 的端口。IDF 已保留本机 IP 的实际参数和端口定义，A 暂停在 Compile 前，待协调者修复包装或指定兼容 IP。
- 本机 DRM TDP 初始化选择校验要求文件后缀为 `.dat`。已用任务脚本生成 1,024 行 HEX 字，并将 `rom.hex` 同内容复制成 `init/rom.dat`。IDF 的 `INIT_FILE` 已指向该文件，`INIT_FORMAT=HEX`。
- 本机 DRM SDP RAM 的界面未找到独立的 Read First / Old Data 选项，生成模板对底层端口固定使用 `NORMAL_WRITE`。B 的 scratch 和 D/E 的两个 SRAM 已填齐可选参数，同沿读写同地址时读旧值的语义尚未验证。
- 各工程目录内保留从同一提交复制的 `edrv32_build_mode.vh`，供 PDS 首次加载时解析。RTL 原文件及 FDC 沿用源码提交。

[DRM 同址仿真日志和本地脚本](artifacts/drm-collision)
