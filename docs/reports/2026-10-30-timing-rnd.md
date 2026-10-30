# RND 地址与像素流水化测量（T-RND1，含 T-RND2）

| 项目 | 条件 |
|---|---|
| 日期 | 2026-10-30 |
| 改前 RTL | `05088f4b13d5d8399f63deef48dc2760ad0f5bec` |
| 集成基线 | `b5dc9469da0e99eb0b0b211dbcbd607daf7524b1`（rebase 时的 `zc100116/b3`） |
| 改后 RTL / 主验收 | `60779902b7922405d56149539a6012711bbc972d` |
| 圆角单项入口修正 | `e7121fc739caf75594d1756497153a41fb5d4ca5`；仅验证入口改动，RTL 与主验收相同 |
| T-RND2 纳入提交 | 原 `0db1333a`、`685a3111` → 本分支 `1b989b85`、`c663b3ba`；跳过重复测试修正 `bcad3621` |
| PDS 起点 | `origin/win/20261030-10-b3-timing-rerun`，`2f43834d5d5a2759f200c7c4a86e020125748b61` |
| PDS 器件 / 约束 | PDS 2022.2-SP6.1，PG2L200H-6/FBB676，clk_mem 8 ns |
| 本机测量 | Yosys 0.70+219 / git 5053d0e26；Verilator 5.020；SIM_MODE / FPGA_MODE 分别用于仿真 / 综合 |
| 执行位置 | 用户提供的仿真主机（环境不记录）连接不可用；协调者授权回本机，全部有效验收及前后综合数据均在本机取得 |
| 原始数据 | 本 worktree `build/rnd-timing/`、`build/regress/`、`build/rnd/` |

变量乘法节点 80→68，所有在用操作数及乘积直接接寄存器，残余常数乘法为零。全 RND 最差组合段 **67→27 LUT6 级**；BLUR 含共享模块为 **43→19 级**。没有全部达到 ≤8 级参考目标；协调者明确批准保留当前 RTL、不再扩大修改，残余路径交 PDS 判定。本轮未取得改后 PDS 裕量、物理资源或 Fmax，不能声称 125 MHz 已收敛。

精简功能验收全部 PASS；COPY 短行与 GLYPH 的增幅已分别 ask 并被明确接受，待 B3 上板确认，其他本轮要求的性能项增幅均 ≤2%。

## PDS 改前路径和残余路径

| 配置 | 起点 → 终点 | slow setup 裕量 ns | 级数 |
|---|---|---:|---:|
| B3R | `u_rnd/command_r[176]` → `u_rnd/u_draw/bank_sparse_r[0/1]` | −18.535 | 25 |
| B3R | `u_rnd/command_r[176]` → `u_rnd/u_draw/load_source_bytes_r[15]` | −17.753 | 24 |
| B3F | `u_soc/u_rnd/command_r[3]` → `u_soc/u_rnd/u_draw/bank_sparse_r[0/1]` | −18.700 | 22 |
| B3F | `u_soc/u_rnd/command_r[3]` → `u_soc/u_rnd/u_draw/load_source_bytes_r[15]` | −17.918 | 21 |
| B3V 已收敛参考 | `u_mem/u_xbar/u_rbuf/u_ram/.../CLKB` → `u_mem/u_perf_mon/N106/CEY1` | +0.122 | 8 |

数据来自各配置 `synthesis_paths.tsv` 和 `synthesis_path_detail.txt`。下列改后残余端点未在回传数据中取得对应的改前 PDS 裕量；不能把其他端点的 −18.535 ns 套用到它们。

| 改后残余起点 → 终点 | LUT6 | PDS 改前裕量 | PDS 改后裕量 | 组合段 |
|---|---:|---|---|---|
| `state_r[0]` → `u_regs.perf_r[1][31]` | 27 | 未取得 | 未取得 | cancel / 写 DMA 握手、像素计数选择及 32 位 PERF1 累加 |
| `u_draw.sample_addr_r[0][5]` → `u_regs.perf_r[4][31]` | 26 | 未取得 | 未取得 | 下一 beat 地址、缓存比较及 PERF4 累加 |
| 独立 BLUR `edge_r[4]` → `output_pixel_r[5..7]` | 19 | 未取得 | 未取得 | shared coverage 与 seed 输出 |

## 改动与位宽依据

- 将源地址中的 `v*SRC_STRIDE + v*(effective_stride-SRC_STRIDE)` 合并为 `v*effective_stride`，保持 32 位取模结果。装载通路依次寄存坐标、缩放积、采样坐标、行乘积 / 横向字节偏移、行基址、首尾地址、min/max、span / sparse；与目标 DMA 重叠。
- 每 bank 保存有效源行基址，逐像素不再重复行跨距乘法；渐变保留完整 17×32 有符号 49 位乘积，再分段舍入和钳位。通用着色为十级、alpha 为九级，每拍仍可接受两像素；有效位和数据负载分开写，数据寄存器不复位。
- bounds 在 CHUNK 几何确定后、bank 尚忙时提前计算；已有算术寄存器保持结果，取得 bank 所有权后才发布元数据。没有新增缓存或存储结构。
- 目标行乘法、行基址和 chunk 描述符分拍；后续 chunk 使用对齐字地址递推，首尾字节遮罩保持原语义。TILEMAP 的 map 坐标 / 乘积 / 基址 / 地址分拍，下一瓦片查询与当前源 DMA 重叠；tile 行低 7 位随原 map entry 存入现有 RAM。
- top 的 RECT 扩张和 CLIP 交集分拍，命令启动增加一拍。1:1 BLIT 的坐标、乘积和地址分拍，opacity 乘积前后寄存。
- T-RND2 将 COPY / FILL / BLUR 的几何、分组算术、地址递推和描述符寄存；其范围内独立模块的 ≤8 级结果见 [T-RND2 报告](2026-10-30-timing-rnd-copy-blur.md)。本报告重新测量了包含共享模块的完整 BLUR。

有效目标坐标由 CLIP 限制在 0..4095，RECT 起点是有符号 16 位。未翻转 k 的最大值为 `4095-(-32768)=36863`，翻转最大值 32767，所以无符号 16 位 k 足够；16×32 缩放积完整保留 48 位，再取 `[47:16]`。SRC_X/Y、MAP_X/Y 最大 65535，加 k 最大 102398，需 17 位；地图行号右移 3/4 位后最多 14 位。有效源跨距的父模块来源只有命令 16 位和 shadow 输出低 18 位，因此内部保留 18 位，端口仍为 32 位；coarse 中已知零位可由 `wreduce` 进一步删除。没有新增范围检查或非法配置条件。

coverage 写成 `edge=16E+f`：仅 `E≤x<width-E` 有覆盖；当 `f≠0` 且 `x=E` 或 `x+1=width-E` 时为 `(16-f)<<4`，其余内部为 255。这与原左右 room 的最小值逐点等价。`width-E` 的范围为 −4095..131071，18 位有符号足够。

### 圆角计算

输入几何、钳位半径 / 近端行距离、Q4 半径 / dy、差和因子、乘积分别寄存，再进行原有 16 次开方迭代。radius 输入为零仍直接返回；非零半径的角部行比基线增加 3 拍，非角部行增加 2 拍，原 row/edge 握手吸收延迟。

用 `(radius_q4-dy)*(radius_q4+dy)` 代替两个平方之差；17 位有符号差、18 位有符号和各自寄存，乘积低 32 位直接写独立 FF，保持原模 2³² 结果。`dy=((radius-jd)<<4)-8` 的低 16 位写作 `{radius-jd-1,4'h8}`。

余数为 18 位：处理 n 个输入位对后始终有 `0≤remainder<2*root+1`；第 16 次迭代前 root 最多 15 位、余数最多 16 位，左移两位并引入两位输入最多需 18 位，最后余数小于 2¹⁷。比较与减法合为一次 19 位差，最高位表示借位。输出由已寄存半径和根相减，保持到 edge 握手。

`rnd_round/equivalence` 的参考模块是原 `05088f4b` Verilog（只改模块名 / 文件头，不进 RTL filelist）。radius=0..4095、row_y=0..65535、65536×65536 几何的 **268435456 对严格逐位比较全部 PASS**；既有 round smoke 另覆盖小几何钳位、外部坐标和两 lane 覆盖率。

## 测量口径与资源

脚本为 `tools/rnd/timing_measure.py OUTPUT [TOP]`。先 `proc; flatten; opt; wreduce; opt_clean`，在 alumacc / techmap 前把每个变量乘变量 `$mul` 替换为同端口宽度的独立硬块黑盒，原参数 / 符号 / 源位置保存到 `multipliers.json`；固定端口实例清空 parameters。再 `synth -flatten -noabc; abc -lut 6 -dress; opt_clean`。RAM IP 为端口黑盒。

重新导入前仅重命名工具生成的内部标识符，避免 techmap 编号碰撞；命名寄存器和位连接保留。`netlist_paths.py` 以 FF / RAM / 硬乘法边界切开前后组合段，D 和 CE 均计入。乘法自身延迟不纳入 LUT6 级数，硬节点数不能换算为 PDS 物理 APM 数。

| 口径 | LUT 改前→改后 | FF 改前→改后 | 硬乘法节点 | 常数乘法 | 最大 LUT6 |
|---|---|---|---|---|---|
| 全 RND，同一流程 | 33507→36039 | 9144→16825 | 80→68 | 2→0 | 67→27 |
| BLUR，含全部共享逻辑 | 4566→5452 | 1005→2946 | 9→7 | 0→0 | 43→19 |
| PDS B3R `u_rnd` | 19034→未取得 | 8640→未取得 | APM 118→未取得 | — | 物理裕量见前表 |

PDS B3R 的 DRM 为 60，改后未取得。通用网表保持 17 个 line RAM、6 个 palette RAM 黑盒；全 RND 黑盒总数 103→91。寄存连接检查在完整 RND coarse 网表上做：变量乘法输入非 FF 位或输出非 FF 负载的违规节点 **74→0**，所以每条寄存器间最多一个变量乘法。独立 BLUR 的 command 输入是模块边界，最终寄存规则以完整 RND 网表为准。

| 实例（含子模块）/ 源文件 | 改前 A×B→Y（数量） | 改后 A×B→Y（数量） |
|---|---|---|
| `u_alpha` / `edrv32_rnd_alpha_pipe.v` | 8×8→16：20；8×24→24：2 | 8×8→16：20；8×24→24：2 |
| `u_blit` / `edrv32_rnd_blit.v` | 8×8→16：2；12×16→28：2；32×16→32：1 | 8×8→16：2；12×16→28：1；17×16→32：1 |
| `u_blur` / `edrv32_rnd_blur.v`, `edrv32_rnd_blur_math.v`, `edrv32_rnd_round_row.v` | 12×12→24：1；13×18→27：1；14×17→24：1；14×17→31：3；16×16→32：1；32×32→32：2 | 12×16→28：1；12×17→27：1；14×17→24：1；14×17→31：3；17×18→32：1 |
| `u_copy` / `edrv32_rnd_address.v`, `edrv32_rnd_copy.v` | 12×16→28：1；32×16→32：1；32×32→48：2 | 12×16→28：1；17×16→32：1 |
| `u_draw` / `edrv32_rnd_address.v`, `edrv32_rnd_draw.v`, `edrv32_rnd_round_row.v`, `edrv32_rnd_source.v` | 8×8→16：15；8×16→16：2；12×12→24：1；12×16→28：1；16×16→32：1；17×32→49：8；32×16→32：3；32×32→32：2；32×32→48：6 | 8×8→16：15；12×16→28：1；14×16→30：1；16×32→48：5；17×18→32：1；17×32→49：8；32×17→32：1 |
| `u_fill` / `edrv32_rnd_fill.v` | 12×16→28：1 | 12×16→28：1 |

源位置与符号逐节点保存在 `hard-baseline/multipliers.json`、`hard-final/multipliers.json`，连接在各自 `structure.json`。改前仅余两项常数乘法：`u_draw` 的 tile slot ×3，32×2→9（原 draw 第556行）；改后改为移位加法，两项均已消除。

### RND 中最差 20 条路径

两列分别按各版本排行，不表示同一条路径；下表均为 clk_mem 内组合段。PDS 未取得的格子不填估算值。

| # | 改前起点 → 终点 | LUT6 | 改后起点 → 终点 | LUT6 | 后列端点的 PDS 改前裕量 |
|---:|---|---:|---|---:|---|
| 1 | `command_r[4]` → `u_draw.bank_sparse_r[0]` | 67 | `state_r[0]` → `u_regs.perf_r[1][31]` | 27 | 未取得 |
| 2 | `command_r[4]` → `u_draw.bank_sparse_r[1]` | 67 | `u_draw.sample_addr_r[0][5]` → `u_regs.perf_r[4][29]` | 26 | 未取得 |
| 3 | `command_r[4]` → `u_draw.load_source_bytes_r[12]` | 61 | `u_draw.sample_addr_r[0][5]` → `u_regs.perf_r[4][30]` | 26 | 未取得 |
| 4 | `command_r[4]` → `u_draw.load_source_bytes_r[13]` | 61 | `u_draw.sample_addr_r[0][5]` → `u_regs.perf_r[4][31]` | 26 | 未取得 |
| 5 | `command_r[4]` → `u_draw.load_source_bytes_r[14]` | 61 | `state_r[0]` → `u_regs.perf_r[1][26]` | 26 | 未取得 |
| 6 | `command_r[4]` → `u_draw.load_source_bytes_r[15]` | 61 | `state_r[0]` → `u_regs.perf_r[1][27]` | 26 | 未取得 |
| 7 | `command_r[4]` → `u_draw.load_source_bytes_r[11]` | 60 | `state_r[0]` → `u_regs.perf_r[1][28]` | 26 | 未取得 |
| 8 | `command_r[4]` → `u_draw.load_source_bytes_r[10]` | 59 | `state_r[0]` → `u_regs.perf_r[1][29]` | 26 | 未取得 |
| 9 | `command_r[4]` → `u_draw.load_source_bytes_r[9]` | 58 | `state_r[0]` → `u_regs.perf_r[1][30]` | 26 | 未取得 |
| 10 | `command_r[4]` → `u_draw.load_source_bytes_r[8]` | 57 | `u_draw.sample_addr_r[0][5]` → `u_regs.perf_r[4][18]` | 25 | 未取得 |
| 11 | `command_r[4]` → `u_draw.load_source_bytes_r[7]` | 56 | `u_draw.sample_addr_r[0][5]` → `u_regs.perf_r[4][19]` | 25 | 未取得 |
| 12 | `command_r[4]` → `u_draw.load_source_bytes_r[6]` | 55 | `u_draw.sample_addr_r[0][5]` → `u_regs.perf_r[4][24]` | 25 | 未取得 |
| 13 | `command_r[4]` → `u_draw.load_source_bytes_r[5]` | 54 | `u_draw.sample_addr_r[0][5]` → `u_regs.perf_r[4][25]` | 25 | 未取得 |
| 14 | `command_r[4]` → `u_draw.load_source_base_r[14]` | 51 | `u_draw.sample_addr_r[0][5]` → `u_regs.perf_r[4][26]` | 25 | 未取得 |
| 15 | `command_r[4]` → `u_draw.load_source_base_r[15]` | 51 | `u_draw.sample_addr_r[0][5]` → `u_regs.perf_r[4][27]` | 25 | 未取得 |
| 16 | `command_r[4]` → `u_draw.load_source_base_r[16]` | 51 | `u_draw.sample_addr_r[0][5]` → `u_regs.perf_r[4][28]` | 25 | 未取得 |
| 17 | `command_r[4]` → `u_draw.load_source_base_r[17]` | 51 | `state_r[0]` → `u_regs.perf_r[3][30]` | 25 | 未取得 |
| 18 | `command_r[4]` → `u_draw.load_source_base_r[18]` | 51 | `state_r[0]` → `u_regs.perf_r[3][31]` | 25 | 未取得 |
| 19 | `command_r[4]` → `u_draw.load_source_base_r[19]` | 51 | `state_r[0]` → `u_regs.perf_r[1][10]` | 25 | 未取得 |
| 20 | `command_r[4]` → `u_draw.load_source_base_r[20]` | 51 | `state_r[0]` → `u_regs.perf_r[1][11]` | 25 | 未取得 |

原始网表 / 完整最差 50 条分别为 `hard-baseline/hardnet.json`、`hard-final/hardnet.json` 及同目录 `paths.json/md`；BLUR 为 `blur-before/`、`blur-final/`。这些路径均相对 `build/rnd-timing/`。

## 最终性能

以下全部逐字节 PASS。COPY / BLUR / SHADOW 为现有 block harness：seed=1、读延迟 3、随机背压 30、B 延迟 3；测量脚本 `tools/rnd/timing_perf.py` 只开启负 telemetry kind 的计数打印，保留原字节模型及通用计数器检查，不套用 RN-18 固定尺寸阈值。GLYPH 沿用 2026-10-29 RN-18 场景。圆角 FILL 复用 unit/rnd_engine 原性能项，目标 1024×512，R=16，无随机背压、B 延迟 5。

| 场景 | 改前 PERF0 | 改后 PERF0 | 增幅 | PERF1 | 判定 |
|---|---:|---:|---:|---:|---|
| 圆角 FILL（1024×512，R=16） | 263387 | 263397 | +0.0038% | 524288 | ≤2%，PASS |
| COPY RGB565（RN-10 dr，19×14） | 297 | 334 | +12.4579% | 266 | 接受，待上板确认 |
| COPY ARGB（RN-10 dr，19×14） | 342 | 383 | +11.9883% | 266 | 接受，待上板确认 |
| BOX_SHADOW（RN-11，ARGB，blur=8，corner=7） | 218085 | 218167 | +0.0376% | 486 | ≤2%，PASS |
| BLUR（RN-12，ARGB，R=8） | 638 | 638 | +0.0000% | 6 | ≤2%，PASS |
| 1000 A4 GLYPH，读延迟 0 | 439001 | 502001 | +14.3508% | 320000 | 接受，待上板 LVGL 帧率确认 |
| 1000 A4 GLYPH，读延迟 40 | 1904001 | 1911001 | +0.3676% | 320000 | 接受，待上板 LVGL 帧率确认 |

协调者明确接受 COPY 两个短行配置在这两个固定配置中，每命令多出约 37–41 拍（约 0.3 µs），不再修改；GLYPH 无等待 +14.35%、40 拍 +0.37% 亦明确接受，待上板 LVGL 帧率确认。表中保留原短行配置和两种原读取延迟。

GLYPH 逐拍对照：最后一对 issue→render_result 为 13→19 拍，B 响应后 bank 释放仍 6 拍；第一条 20 行 draw 为 431→493 拍，连同 top 的一拍合为每命令 +63 拍，对应 1000 条 PERF0 +63000。bounds 提前计算前为 511001，提前后为 502001。此处不增加 GLYPH 专用分支、RAM 或缓存。

## 精简验收范围与结果

协调者依据用户“仿真不追求高覆盖，以上板结果为准”的 2026-10-30 决定，统一验收不运行 block/rnd full、rnd_engine full 或全量 perf 档。保留原 531 项为 `run.py directed`（full 档），107 项 full 扩展不变。新的 smoke 是现有向量的代表子集，不改参考模型。

| 验收 | 结果 / 数据 |
|---|---|
| RTL style + RND `-Wall` lint | 15 文件、0 warnings；`style-integrated.log`、`lint-integrated.log` |
| block/rnd smoke | 26 项 PASS，包含修正图案后的 RN-20 两项 |
| rnd_round smoke | 1 PASS / 0 FAIL |
| round_row 旧新 RTL 穷举 | 268435456 对 PASS |
| rnd_blur smoke | 1 PASS / 0 FAIL |
| rnd_address smoke | 1 PASS / 0 FAIL |
| rnd_engine/smoke | 原 full case137/139 两项 PASS |
| board_render smoke | 1 PASS / 0 FAIL，字节读回与 IRQ |
| 受影响单项性能 | 前表 6 类、7 个配置 PASS；增幅例外经 ask 接受 |
| RN-20 原 RTL 对照 | 新图案 horizontal / vertical 在 05088f4b 各 PASS |

`board_render` 是 64×4 opaque FILL，无圆角、不输出 PERF0，只作功能验收，不作为圆角性能证据。主验收记录 `acceptance.json`；圆角单项入口修正后在 `e7121fc7` 补跑通过，RTL 没有变化。

唯一 smoke 列表在 `verif/block/rnd/run.py:SMOKE_CASES`：

| RN 编号 | 项数 | 命令 / 条件 |
|---|---:|---|
| RN-01 | 2 | 两目标格式 opaque FILL |
| RN-03 | 2 | 两目标格式，radius=7，19×16 圆角 FILL |
| RN-04 | 1 | ARGB 竖直负梯度 |
| RN-05 | 1 | ARGB 四边 BORDER，宽7 |
| RN-06 | 5 | A4 GLYPH 两目标格式；A8/A2/A1 各一项 |
| RN-07 | 3 | RGB565→ARGB、I4→RGB565、I1→ARGB，未对齐源 |
| RN-08 | 1 | ARGB，16×缩放，H/V 双翻转 |
| RN-09 | 1 | ARGB BLIT，multiply、key、recolor |
| RN-10 | 2 | 两目标格式右下重叠 COPY |
| RN-11 | 1 | ARGB BOX_SHADOW，blur=8 |
| RN-12 | 1 | ARGB BLUR，R=8 |
| RN-13 | 1 | I4 / 16×16 TILEMAP |
| RN-14 | 1 | 混合命令链 |
| RN-15 | 1 | 非法 opcode |
| RN-16 | 1 | 寄存器语义 |
| RN-20 | 2 | 水平 / 竖直字段极值 |

## 复现命令

先按 CLAUDE.md 加载本机工具环境。仿真串行，编译 `-j 1`；每条仿真和 Yosys 命令都有同一个 flock。

```sh
python3 tools/check/verilog_style.py rtl/media/rnd
(cd rtl/filelists && verilator --lint-only -Wall -DSIM_MODE --top-module edrv32_rnd -f rnd.f)
flock /tmp/edrv32-sim.lock python3 tools/regress.py smoke --path verif/block/rnd -j 1
flock /tmp/edrv32-sim.lock python3 tools/regress.py smoke --path verif/unit/rnd_round -j 1
flock /tmp/edrv32-sim.lock python3 tools/regress.py full --path verif/unit/rnd_round/equivalence -j 1
flock /tmp/edrv32-sim.lock python3 tools/regress.py smoke --path verif/unit/rnd_blur -j 1
flock /tmp/edrv32-sim.lock python3 tools/regress.py smoke --path verif/unit/rnd_address -j 1
flock /tmp/edrv32-sim.lock python3 tools/regress.py smoke --path verif/unit/rnd_engine -j 1
flock /tmp/edrv32-sim.lock python3 tools/regress.py perf --path verif/unit/rnd_engine/round_perf -j 1
flock /tmp/edrv32-sim.lock python3 tools/rnd/timing_perf.py build/rnd/obj/sim build/rnd-timing/perf-final
flock /tmp/edrv32-sim.lock python3 tools/regress.py smoke --path verif/soc/board_render -j 1
PYTHONPATH=$PWD python3 tools/rnd/timing_measure.py build/rnd-timing/hard-final
PYTHONPATH=$PWD python3 tools/rnd/timing_measure.py build/rnd-timing/blur-final edrv32_rnd_blur
```

测量脚本内部逐条给 Yosys 加 flock，不要再在脚本外套同一把锁。GLYPH 单项（先由 block smoke 构建 `build/rnd/obj/sim`）：

```sh
flock /tmp/edrv32-sim.lock python3 - <<'PY_GLYPH'
from pathlib import Path
import subprocess, sys
sys.path.insert(0, 'verif/block/rnd')
from vectors import generate
for latency in (0, 40):
    config = generate(Path('build/rnd-timing/glyph') / str(latency),
                      18, ('glyph', latency), 1)
    subprocess.run(['build/rnd/obj/sim', '+CONFIG=' + str(config)], check=True)
PY_GLYPH
```

改前使用 05088f4b 的 RTL，配相同验证代码 / 测量脚本；基线原始命令和数据为 `hard-baseline/`、`blur-before/`、`before-round-perf.log`、`perf-baseline.log`、`RN20-address-before.log`。可在隔离 checkout 复制当前验证文件后复现：

```sh
git worktree add --detach build/rnd-timing/reference 05088f4b
git archive e7121fc7 verif/block/rnd verif/unit/rnd_engine tools/rnd | tar -x -C build/rnd-timing/reference
(cd build/rnd-timing/reference && PYTHONPATH=$PWD python3 tools/rnd/timing_measure.py build/timing)
(cd build/rnd-timing/reference && PYTHONPATH=$PWD python3 tools/rnd/timing_measure.py build/blur-timing edrv32_rnd_blur)
```

RN-20 对照只取该 checkout 的 `SMOKE_CASES` 中 RN-20 两项执行，生成、编译和比较仍用同一个 runner；集成版已由26项 smoke 执行这两项，不再重复。

## 测试修正与开发中错误

1. **缓冲区重叠**：依据 rnd-spec 2.5 软件前提，原 unit full case137/139 的巨大缩放翻转源采样包含 `0x801f`，落入旧目标 `0x8004`，原结果不受规格保证；授权把目标移至 `0x1004`。原 case149 的第二条 BLIT 保留读取第一条目标 `0x8004`，把第二条目标移至 `0x9004`，继续验证 B-fenced 命令依赖。其余非 COPY 源 / palette / map / tile 与目标核对分离；COPY 四向重叠不变。新 sparse smoke 和原 full 调用同一 task，向量 / 判据不变。
2. **有效源跨距采样**：第一版在 draw start 同边沿读取父模块 S_BEGIN 才更新的 source_stride，得到上一命令值，字形第二源 beat 漏读；改为 S_RADIUS 采样已发布跨距，没有添加兜底或检查。
3. **RN-20 图案别名**：首版图案每4096字节重复，16384/32768/524288字节的高位截断地址差都会读相同图案。授权仅这两项源区改为已有 `(n*13+n/257)&255` 模式；不加向量、不改模型 / 判据。修正后原 RTL 与集成 RTL 的水平 / 竖直两项均逐字节 PASS。
4. **圆角矩阵刺激**：首版 unpacked 行数组连接使旧参考组合 jd 在生成 C++ 中只进入初始 settle，radius=1,row_y=1 旧参考错误返回3而应为0；改用标量行起点加每 lane 固定偏移。参考 Verilog 不变，范围 / 比较条件不变，重跑268435456对 PASS。
5. **GLYPH 摘要抄错**：中间版实际无等待数为511001（+16.4009%），开发摘要曾误抄为较小值；复核实际日志后明确更正、ask并继续定位。最后提前 bounds 为502001（+14.3508%），未隐去超限，最终已接受待上板。
6. **圆角单项入口前缀**：`$test$plusargs("PERF")` 会匹配 `PERF_ROUND`，使原单项调用误运行旧 PERF 集合。改名 `ROUND_PERF` 并增加独立 `round_perf` 入口，实际只补跑圆角 FILL，263397周期、逐字节 PASS；误运行集合保留在 `round-perf-unintended.log`，不作为本轮计划中的全量性能验收。

## 提交清单

| 本分支提交 | 内容 |
|---|---|
| `87b76d86` | rnd: keep BLIT verification buffers disjoint |
| `a3690707` | rnd: register bounds and pixel arithmetic stages |
| `81ff5341` | rnd: shorten descriptor and rounded coverage paths |
| `fee7ca1b` | rnd: preserve multiplier boundaries in timing measurements |
| `26c4812f` | rnd: keep imported timing cell identifiers unique |
| `5e738cd5` | rnd: document reproducible hard multiplier path measurement |
| `ec737af9` | rnd: prepare source bounds while the next bank is busy |
| `1583090f` | rnd: drive equivalence rows from one scalar request |
| `b7bbebd7` | rnd: select focused smoke and rounded fill performance cases |
| `ebe031b3` | rnd: expose address high bits in RN20 source patterns |
| `69c6cd37` | rnd: make focused DMA performance comparisons reproducible |
| `1b989b85` | rnd: pipeline copy fill and blur memory arithmetic |
| `c663b3ba` | rnd: record copy fill and blur timing measurements |
| `60779902` | rnd: measure integrated blur with shared arithmetic included |
| `e7121fc7` | rnd: keep round performance selector distinct from PERF prefix |

T-RND2 原提交 `0db1333a` / `685a3111` 的 cherry-pick 对应表已列于元数据；重复的 `bcad3621` 没有重复纳入。本报告之后的提交仅保存测量结果，不改变上述 RTL。
