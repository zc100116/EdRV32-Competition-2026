# RND COPY / FILL / BLUR clk_mem 时序测量（T-RND2）

| 项 | 条件 |
|---|---|
| 日期 | 2026-10-30 |
| 改前 RTL | `05088f4b13d5d8399f63deef48dc2760ad0f5bec` |
| 改后 RTL | `0db1333a672c49a29e24c7a4c810d00b4bf156f2` |
| 规格 | `rnd-spec.md` 2、5、7；`rnd-testplan.md` |
| PDS | 2022.2-SP6.1，PG2L200H-6/FBB676，clk_mem 8 ns |
| Linux 工具 | Yosys 0.70+219（5053d0e26）；Verilator 5.020；Python 3.12 |
| 原始数据 | 本 worktree `build/rnd-copy-blur/`；最终汇总 `final-paired-summary.json`，改前网表 `local-final/before/`，改后网表 `after-final/after/`；参考向量 `after/selected/` |

本轮仅修改 COPY、FILL、BLUR 三个 RTL 文件。`blur_coeff` 和 `blur_math` 保持原实现，纳入同口径测量。没有取得改后 PDS，LUT6 级数不能换算物理裕量或 Fmax。

## 地址公式与周期关系

- COPY 依据 2.5 的 12 位 CLIP、有符号 16 位 RECT 和 2.6 的无符号 16 位 SRC_X/Y：有效绘制区内 `0≤x−X0,y−Y0≤4095−(−32768)=36863`，差值用 16 位；加 SRC_X/Y 后最大 102398，用 17 位。因此目标乘法为 12×16，源行为 17×16，源/目标地址仍按 32 位取模。坐标差、源坐标、乘积各自寄存，两个 32 位地址加法复用按 12/12/8 位分组的寄存加法流水。首行比较源/目标地址选择方向，后续行按已寄存的正/负 stride 更新；每行完整读入再写出的重叠语义不变。
- FILL 首行寄存 12×16 行乘积，将乘积与列字节偏移相加后，再用 12/12/8 位流水加基址；后续行的地址在当前行写出期间提前算好。首行设置延迟及每行一拍跨度准备计入 RN-18；数据阶段继续每拍一个 256 位 beat。COPY/FILL 的边界像素数在描述符阶段寄存，输出只选择首拍、末拍、单拍或全拍计数。
- COPY/FILL 在初始地址提交或上一行响应时准备低 5 位跨度和，在 SPAN 拍提交高位进位；COPY 用已寄存的末拍索引比较取代“索引加一再比较”。
- COPY/FILL 的 decode 按父模块已完成的分派固定为 05/01，不保留阴影扩展分支。均未修改共享 address/decode 文件。
- BLUR/BOX_SHADOW 在原 17 步倒数计算期间准备几何和起点。RECT 最大尺寸 65536，R≤31，故扩展尺寸≤65598、对齐跨距≤65600，均保留 17 位；临时区大小乘法为 17×17，目标起点为 12×16。乘积直接寄存，后续基址使用分组加法流水；矩形扩展、维度和首 tap 坐标的减法也分拍完成。RGB565 仍只在最后写回截断一次。
- BLUR 的每行首 tap、每像素首 tap、当前采样地址使用递推。横向步长为源像素字节数，纵向步长为源跨距。当前坐标在 `[lower,upper)` 内才使下一 tap 的 clamped 地址递增；两侧重复边界地址，阴影的网格外 tap 仍取零。行、像素地址的两级部分和在现有 ROW/PIXEL/OUTPUT 周期提前准备，由 NEXT_ROW/STORE 提交最后的高位进位；阴影 seed 的三拍像素循环和滤波的两拍 tap 循环均不增拍。
- 命中 tap 仍为 `S_SAMPLE→S_ADD` 两拍。S_SAMPLE 寄存低 12 位和、中间 12 位的两种进位候选及所选像素；S_ADD 选择中间结果、提交高 8 位进位并累加像素。读缺失在原 READ_WAIT 边沿直接从返回数据寄存像素，不新增状态。
- BLUR 裁剪比较拆为有符号高 9 位/无符号低 9 位谓词、组合谓词、边界选择三个寄存阶段；最终 shadow_draw 的裁剪和源偏移也在倒数计算期间完成，不再经过通用 decode。窗口的上下界用 7 位有符号 tap 边界寄存：当到边缘距离≥32 时记为±32，因 R≤31，这与原坐标比较严格等价。行/列距离、剩余距离按已有循环递增/递减，行剩余距离按 9/8 位两段减一。末像素/末行比较在 PIXEL/ROW 提前寄存，避免长比较接计数器使能。
- BLUR 的 OUTPUT 拍准备 32 位字节掩码和按地址低两位旋转的像素字节，STORE 拍逐字节写入既有 256 位工作寄存器，代替动态宽 part-select；RGB565 仍在此处截断，拍数不变。
- 调用侧在系数计算期间寄存 width/height，已有 ROW 中寄存 row_local、row_inside 和初始 coverage_x，STORE 中递增 coverage_x。round_row/coverage 的端口和握手语义不变。协调者已将共享模块内部的剩余路径转给 T-RND1，最终共享路径级数以其集中验收为准。

令网格内局部坐标为 `(i,j)`，源网格原点地址为 B、源跨距为 S、像素字节数为 P。水平遍首 tap 地址为 `B+j*S+max(i-R,0)*P`，竖直遍为 `B+max(j-R,0)*S+i*P`。每像素首 tap 不超过网格上界，只需下界 clamp；后续 tap 在界内递增、两侧保持。BLUR 水平遍 B 为 `DST_BASE+top*DST_STRIDE+left*P`，其余 B 为相应临时区基址，全部加法保持 32 位取模。

## 测量口径和复现

每个模块单独作为 top，子模块展开；输入 `command_i` 对应集成顶层的 `command_r` 寄存器边界，其他输入/输出保留模块边界。两种 RAM IP 使用端口黑盒。Yosys、Verilator 仿真编译/运行、regress 调用均由 `/tmp/edrv32-sim.lock` 串行化，仿真编译 `-j 1`。协调者后续明确允许 style 与 `verilator --lint-only` 不加 flock，最终 lint 按该调整执行。

流程为 `read_verilog -D FPGA_MODE; hierarchy -top <module>; proc; flatten; opt; wreduce; opt_clean; write_json coarse.json`。只将变量×变量 `$mul` 的 A/B/Y 原有连线逐个换为同端口宽度的 `ip_mul_N` 黑盒，保留实例属性；随后 `read_json hard.json; synth -top <module> -flatten -noabc; abc -lut 6 -dress; opt_clean; write_json netlist.json`。各黑盒输入作为终点、输出作为新起点，不把乘法展开为 LUT，也不把乘法跨越的路径视为连续 LUT 链。

用仓库 `tools/synth/netlist_paths.py` 的 `analyze()` 分析 FF 的 D/CE、RAM 和硬块端口、模块端口；组合级数均为映射后的 LUT6 级数。乘法前/后两段按每个乘法实例另行统计，零级表示寄存器/模块边界直接连硬块端口。最终命令为 `flock /tmp/edrv32-sim.lock python3 build/rnd-copy-blur/after_job.py measure`；改前对应 `local_job.py measure`，乘法分段重新用 `before_segments.py` 统计。`local-final/{coarse,fine}.ys` 与 `after-final/{coarse,fine}.ys` 保存映射命令，各模块 `coarse.json`、`mul.json`、`netlist.json` 保存网表与宽度；`before-segments.json`、`after-final-summary.json`、`final-paired-summary.json` 保存汇总。文末附同流程的完整复现脚本，独立于这些本地中间文件。

coarse 网表结构检查：原 COPY 的 4 个乘法、FILL 的 1 个乘法、BLUR 自身的 3 个乘法，共 8 处存在乘法输入组合逻辑或乘法输出未直接入寄存器；最终本任务归属内均为 0 处。BLUR 的两个剩余乘积后减法位于共享 `u_round_row`，已由 T-RND1 另行处理；本工作树保留原文件，表格明确包含该旧实现。`blur_coeff` 无乘法；`blur_math` 的 8 个 14×17 乘法原本即满足两侧寄存器结构。证据为 `build/rnd-copy-blur/final-structure.json`；常数乘法扫描在这 5 个模块及其子模块的 coarse 网表内均为空，没有残留常数乘法位置可列。

## PDS 改前数据

B3R 全域 clk_mem WNS −18.535 ns、TNS −21067.526 ns、8298/50471 个违例端点。卡 10 回传的最差 setup 列表由 draw 端点占据，没有 COPY/FILL/BLUR 的模块内 setup 路径，不能从该列表补造本任务各模块的 PDS 裕量和级数。唯一出现 COPY 的记录是异步复位路径 `u_sys/u_reset_ctrl/u_mem/release_sync_r/CLK` → `u_rnd/u_copy/u_address/N96/RSTY`，+3.761 ns / 1 级；它不是 clk_mem 数据 setup 证据。

PDS 综合层次资源（`resource_hier_synthesis.txt`）为 COPY 3169 LUT / 547 FF / 11 APM、FILL 181 LUT / 27 FF / 1 APM、BLUR 2911 LUT / 926 FF / 9 APM；BLUR 数字包含其子模块。改后实际 APM 数量等待 PDS；下文独立报告 Yosys 保留的逻辑乘法数量和位宽，不将其冒充器件 APM 个数。

## Yosys 前后结果

COPY/FILL 全模块最大级数收敛至 8；BLUR 自身切除共享模块边界后的最大级数为 8。BLUR 的全模块 25 级来自未修改的共享 coverage/round_row 逻辑，按协调者确认不计入本任务验收，合并后由 T-RND1 统一测量。新增 FF 是分组算术、地址递推及描述符流水的面积代价。

| 模块（含子模块） | 全模块 LUT6 改前→改后 | 本任务逻辑改后 LUT6 | LUT 改前→改后 | FF 改前→改后 | 逻辑乘法节点 改前→改后 |
|---|---:|---:|---:|---:|---:|
| copy | 40→8 | 8 | 4943→4944 | 542→1406 | 4→2 |
| fill | 25→8 | 8 | 619→819 | 25→422 | 1→1 |
| blur | 43→25 | 8 | 4515→5553 | 1005→2827 | 9→8 |
| blur_coeff | 7→7 | 7 | 45→45 | 52→52 | 0→0 |
| blur_math | 2→2 | 2 | 74→74 | 138→138 | 8→8 |

“本任务逻辑”以共享 decode/address/coverage/round_row 的输出端口再切一个起点，排除共享模块内部的 FF 终点；其他 FF、硬块输入和模块输出均保留。全模块列不加这些共享接口切点。FF 的 D 和 CE 都计入最大级数。

### 乘法位宽与两侧路径

下面是 coarse 优化后的实际端口位宽 A×B→Y，不能换算成物理 APM 个数。BLUR 临时区乘法 RTL 为 17×17；stride 的低 5 位恒零，Yosys 将其等价缩成 12×17→27 再接 5 位零。BLUR 中只保留使用的 4 个 normalize 通道；独立 blur_math top 保留 8 通道。

| 模块 | 改前逻辑乘法位宽及数量 | 改后逻辑乘法位宽及数量 |
|---|---|---|
| copy | 12×16→28：1；32×16→32：1；32×32→48：2 | 12×16→28：1；17×16→32：1 |
| fill | 12×16→28：1 | 12×16→28：1 |
| blur | 12×12→24：1；13×18→27：1；14×17→24：1；14×17→31：3；16×16→32：1；32×18→32：2 | 12×12→24：1；12×16→28：1；12×17→27：1；14×17→24：1；14×17→31：3；16×16→32：1 |
| blur_coeff | 无 | 无 |
| blur_math | 14×17→24：8 | 14×17→24：8 |

每行按版本网表的乘法序号统计。前段从 FF/模块输入/非乘法硬块输出出发，止于该乘法 A/B；后段从该乘法 Y 出发，止于 FF/模块输出/非乘法硬块输入。两段都不越过另一个乘法，避免把串接乘法伪装成普通组合段。`无直达 FF` 表示先进入另一乘法，不能记为 0；原 COPY 地址模块内存在此串接路径。0 级表示直连寄存器或集成 command_r 对应的输入边界。

| 版本 | top | 归属 / 序号 | A×B→Y | 寄存器→乘法输入 LUT6 | 乘法输出→寄存器 LUT6 |
|---|---|---|---|---:|---:|
| before | copy | copy / 0 | 32×32→48 | 24 | 24 |
| before | copy | copy / 1 | 32×32→48 | 8 | 无直达 FF |
| before | copy | copy / 2 | 32×16→32 | 13 | 20 |
| before | copy | copy / 3 | 12×16→28 | 0 | 17 |
| before | fill | fill / 0 | 12×16→28 | 0 | 15 |
| before | blur | blur / 0 | 13×18→27 | 30 | 21 |
| before | blur | blur / 1 | 32×18→32 | 32 | 21 |
| before | blur | blur / 2 | 32×18→32 | 31 | 22 |
| before | blur | blur_math / 3 | 14×17→31 | 0 | 0 |
| before | blur | blur_math / 4 | 14×17→31 | 0 | 0 |
| before | blur | blur_math / 5 | 14×17→31 | 0 | 0 |
| before | blur | blur_math / 6 | 14×17→24 | 0 | 0 |
| before | blur | round_row / 7 | 12×12→24 | 0 | 10 |
| before | blur | round_row / 8 | 16×16→32 | 0 | 12 |
| before | blur_math | blur_math / 0 | 14×17→24 | 0 | 0 |
| before | blur_math | blur_math / 1 | 14×17→24 | 0 | 0 |
| before | blur_math | blur_math / 2 | 14×17→24 | 0 | 0 |
| before | blur_math | blur_math / 3 | 14×17→24 | 0 | 0 |
| before | blur_math | blur_math / 4 | 14×17→24 | 0 | 0 |
| before | blur_math | blur_math / 5 | 14×17→24 | 0 | 0 |
| before | blur_math | blur_math / 6 | 14×17→24 | 0 | 0 |
| before | blur_math | blur_math / 7 | 14×17→24 | 0 | 0 |
| after | copy | copy / 0 | 12×16→28 | 0 | 0 |
| after | copy | copy / 1 | 17×16→32 | 0 | 0 |
| after | fill | fill / 0 | 12×16→28 | 0 | 0 |
| after | blur | blur_math / 0 | 14×17→31 | 0 | 0 |
| after | blur | blur_math / 1 | 14×17→31 | 0 | 0 |
| after | blur | blur_math / 2 | 14×17→31 | 0 | 0 |
| after | blur | blur_math / 3 | 14×17→24 | 0 | 0 |
| after | blur | round_row / 4 | 12×12→24 | 0 | 10 |
| after | blur | round_row / 5 | 16×16→32 | 0 | 12 |
| after | blur | blur / 6 | 12×17→27 | 0 | 0 |
| after | blur | blur / 7 | 12×16→28 | 0 | 0 |
| after | blur_math | blur_math / 0 | 14×17→24 | 0 | 0 |
| after | blur_math | blur_math / 1 | 14×17→24 | 0 | 0 |
| after | blur_math | blur_math / 2 | 14×17→24 | 0 | 0 |
| after | blur_math | blur_math / 3 | 14×17→24 | 0 | 0 |
| after | blur_math | blur_math / 4 | 14×17→24 | 0 | 0 |
| after | blur_math | blur_math / 5 | 14×17→24 | 0 | 0 |
| after | blur_math | blur_math / 6 | 14×17→24 | 0 | 0 |
| after | blur_math | blur_math / 7 | 14×17→24 | 0 | 0 |

### 各模块最差 20 条路径

两列各自按该版本最大级数降序排列，排行相同不表示起终点相同。信号采用映射 JSON 的 RTL 别名。PDS 没有回传这些模块内数据路径的逐条裕量，因此各条 PDS 改前/改后裕量均为未取得；表中数字仅是 Yosys LUT6 级数。

#### copy

| # | 改前起点 → 终点 | LUT6 | 改后起点 → 终点 | LUT6 |
|---:|---|---:|---|---:|
| 1 | `u_decode.op_o[4]` → `y_r[0]` | 40 | `src_addr_r[15]` → `y_r[0]` | 8 |
| 2 | `u_decode.op_o[4]` → `y_r[1]` | 40 | `src_addr_r[15]` → `y_r[1]` | 8 |
| 3 | `u_decode.op_o[4]` → `y_r[2]` | 40 | `src_addr_r[15]` → `y_r[2]` | 8 |
| 4 | `u_decode.op_o[4]` → `y_r[3]` | 40 | `src_addr_r[15]` → `y_r[3]` | 8 |
| 5 | `u_decode.op_o[4]` → `y_r[4]` | 40 | `src_addr_r[15]` → `y_r[4]` | 8 |
| 6 | `u_decode.op_o[4]` → `y_r[5]` | 40 | `src_addr_r[15]` → `y_r[5]` | 8 |
| 7 | `u_decode.op_o[4]` → `y_r[6]` | 40 | `src_addr_r[15]` → `y_r[6]` | 8 |
| 8 | `u_decode.op_o[4]` → `y_r[7]` | 40 | `src_addr_r[15]` → `y_r[7]` | 8 |
| 9 | `u_decode.op_o[4]` → `y_r[8]` | 40 | `src_addr_r[15]` → `y_r[8]` | 8 |
| 10 | `u_decode.op_o[4]` → `y_r[9]` | 40 | `src_addr_r[15]` → `y_r[9]` | 8 |
| 11 | `u_decode.op_o[4]` → `y_r[10]` | 40 | `src_addr_r[15]` → `y_r[10]` | 8 |
| 12 | `u_decode.op_o[4]` → `y_r[11]` | 40 | `src_addr_r[15]` → `y_r[11]` | 8 |
| 13 | `u_decode.op_o[4]` → `reverse_r` | 39 | `src_addr_r[15]` → `state_r[2]` | 8 |
| 14 | `u_decode.op_o[4]` → `u_address.src_addr_o[30]` | 38 | `src_addr_r[0]` → `u_row.wr_addr_i[7]` | 8 |
| 15 | `u_decode.op_o[4]` → `u_address.src_addr_o[31]` | 38 | `state_r[3]` → `u_row.wr_data_i[11]` | 8 |
| 16 | `u_decode.op_o[4]` → `u_address.src_addr_o[27]` | 37 | `state_r[3]` → `u_row.wr_data_i[120]` | 8 |
| 17 | `u_decode.op_o[4]` → `u_address.src_addr_o[28]` | 37 | `state_r[3]` → `u_row.wr_data_i[121]` | 8 |
| 18 | `u_decode.op_o[4]` → `u_address.src_addr_o[29]` | 37 | `state_r[3]` → `u_row.wr_data_i[122]` | 8 |
| 19 | `u_decode.op_o[4]` → `u_address.src_addr_o[25]` | 36 | `state_r[3]` → `u_row.wr_data_i[123]` | 8 |
| 20 | `u_decode.op_o[4]` → `u_address.src_addr_o[26]` | 36 | `state_r[3]` → `u_row.wr_data_i[124]` | 8 |

#### fill

| # | 改前起点 → 终点 | LUT6 | 改后起点 → 终点 | LUT6 |
|---:|---|---:|---|---:|
| 1 | `u_decode.op_o[0]` → `wr_addr_o[28]` | 25 | `state_r[0]` → `span_low_r[4]` | 8 |
| 2 | `u_decode.op_o[0]` → `wr_addr_o[29]` | 25 | `state_r[0]` → `span_low_r[5]` | 8 |
| 3 | `u_decode.op_o[0]` → `wr_addr_o[30]` | 25 | `u_decode.command_i[144]` → `state_r[0]` | 8 |
| 4 | `u_decode.op_o[0]` → `wr_addr_o[31]` | 25 | `state_r[0]` → `span_low_r[1]` | 7 |
| 5 | `u_decode.op_o[0]` → `wr_addr_o[26]` | 24 | `state_r[0]` → `span_low_r[2]` | 7 |
| 6 | `u_decode.op_o[0]` → `wr_addr_o[27]` | 24 | `state_r[0]` → `span_low_r[3]` | 7 |
| 7 | `u_decode.op_o[0]` → `wr_addr_o[23]` | 23 | `span_low_r[5]` → `span_bytes_r[12]` | 7 |
| 8 | `u_decode.op_o[0]` → `wr_addr_o[24]` | 23 | `span_low_r[5]` → `span_bytes_r[13]` | 7 |
| 9 | `u_decode.op_o[0]` → `wr_addr_o[25]` | 23 | `span_low_r[5]` → `span_bytes_r[14]` | 7 |
| 10 | `u_decode.op_o[0]` → `wr_addr_o[21]` | 22 | `span_low_r[5]` → `span_bytes_r[15]` | 7 |
| 11 | `u_decode.op_o[0]` → `wr_addr_o[22]` | 22 | `u_decode.command_i[96]` → `x_bytes_r[2]` | 7 |
| 12 | `u_decode.op_o[0]` → `wr_addr_o[19]` | 21 | `u_decode.command_i[96]` → `x_bytes_r[3]` | 7 |
| 13 | `u_decode.op_o[0]` → `wr_addr_o[20]` | 21 | `u_decode.command_i[96]` → `x_bytes_r[11]` | 7 |
| 14 | `u_decode.op_o[0]` → `wr_addr_o[17]` | 20 | `offset_low_r[14]` → `row_offset_r[21]` | 7 |
| 15 | `u_decode.op_o[0]` → `wr_addr_o[18]` | 20 | `offset_low_r[14]` → `row_offset_r[22]` | 7 |
| 16 | `u_decode.op_o[0]` → `wr_addr_o[14]` | 19 | `offset_low_r[14]` → `row_offset_r[23]` | 7 |
| 17 | `u_decode.op_o[0]` → `wr_addr_o[15]` | 19 | `offset_low_r[14]` → `row_offset_r[25]` | 7 |
| 18 | `u_decode.op_o[0]` → `wr_addr_o[16]` | 19 | `offset_low_r[14]` → `row_offset_r[26]` | 7 |
| 19 | `u_decode.op_o[0]` → `pixel_count_o[1]` | 18 | `offset_low_r[14]` → `row_offset_r[27]` | 7 |
| 20 | `u_decode.op_o[0]` → `pixel_count_o[2]` | 18 | `x_bytes_r[0]` → `offset_low_r[14]` | 7 |

#### blur

| # | 改前起点 → 终点 | LUT6 | 改后起点 → 终点 | LUT6 |
|---:|---|---:|---|---:|
| 1 | `u_decode.op_o[0]` → `state_r[1]` | 43 | `edge_r[1]` → `output_pixel_r[0]` | 25 |
| 2 | `u_decode.op_o[0]` → `cache_addr_r[30]` | 38 | `edge_r[1]` → `output_pixel_r[1]` | 25 |
| 3 | `u_decode.op_o[0]` → `cache_addr_r[31]` | 38 | `edge_r[1]` → `output_pixel_r[2]` | 25 |
| 4 | `u_decode.op_o[0]` → `rd_addr_o[30]` | 38 | `edge_r[1]` → `output_pixel_r[3]` | 25 |
| 5 | `u_decode.op_o[0]` → `rd_addr_o[31]` | 38 | `edge_r[1]` → `output_pixel_r[4]` | 25 |
| 6 | `u_decode.op_o[0]` → `cache_addr_r[27]` | 37 | `edge_r[1]` → `output_pixel_r[5]` | 25 |
| 7 | `u_decode.op_o[0]` → `cache_addr_r[28]` | 37 | `edge_r[1]` → `output_pixel_r[6]` | 25 |
| 8 | `u_decode.op_o[0]` → `cache_addr_r[29]` | 37 | `edge_r[1]` → `output_pixel_r[7]` | 25 |
| 9 | `u_decode.op_o[0]` → `rd_addr_o[27]` | 37 | `row_local_r[1]` → `u_round_row.dy_r[13]` | 16 |
| 10 | `u_decode.op_o[0]` → `rd_addr_o[28]` | 37 | `row_local_r[1]` → `u_round_row.dy_r[14]` | 16 |
| 11 | `u_decode.op_o[0]` → `rd_addr_o[29]` | 37 | `row_local_r[1]` → `u_round_row.dy_r[15]` | 16 |
| 12 | `u_decode.op_o[0]` → `cache_addr_r[23]` | 36 | `row_local_r[1]` → `u_round_row.dy_r[10]` | 15 |
| 13 | `u_decode.op_o[0]` → `cache_addr_r[24]` | 36 | `row_local_r[1]` → `u_round_row.dy_r[11]` | 15 |
| 14 | `u_decode.op_o[0]` → `cache_addr_r[25]` | 36 | `row_local_r[1]` → `u_round_row.dy_r[12]` | 15 |
| 15 | `u_decode.op_o[0]` → `cache_addr_r[26]` | 36 | `row_local_r[1]` → `u_round_row.dy_r[7]` | 13 |
| 16 | `u_decode.op_o[0]` → `state_r[0]` | 36 | `row_local_r[1]` → `u_round_row.dy_r[8]` | 13 |
| 17 | `u_decode.op_o[0]` → `rd_addr_o[23]` | 36 | `row_local_r[1]` → `u_round_row.dy_r[9]` | 13 |
| 18 | `u_decode.op_o[0]` → `rd_addr_o[24]` | 36 | `height_r[0]` → `u_round_row.state_r[1]` | 13 |
| 19 | `u_decode.op_o[0]` → `rd_addr_o[25]` | 36 | `row_local_r[1]` → `u_round_row.dy_r[6]` | 12 |
| 20 | `u_decode.op_o[0]` → `rd_addr_o[26]` | 36 | `u_round_row.radicand_r[30]` → `u_round_row.edge_r[12]` | 12 |

#### blur_coeff

| # | 改前起点 → 终点 | LUT6 | 改后起点 → 终点 | LUT6 |
|---:|---|---:|---|---:|
| 1 | `divisor_r[1]` → `remainder_r[0]` | 7 | `divisor_r[1]` → `remainder_r[0]` | 7 |
| 2 | `divisor_r[1]` → `remainder_r[1]` | 6 | `divisor_r[1]` → `remainder_r[1]` | 6 |
| 3 | `divisor_r[1]` → `remainder_r[2]` | 6 | `divisor_r[1]` → `remainder_r[2]` | 6 |
| 4 | `divisor_r[1]` → `remainder_r[3]` | 6 | `divisor_r[1]` → `remainder_r[3]` | 6 |
| 5 | `divisor_r[1]` → `remainder_r[4]` | 6 | `divisor_r[1]` → `remainder_r[4]` | 6 |
| 6 | `divisor_r[1]` → `remainder_r[5]` | 6 | `divisor_r[1]` → `remainder_r[5]` | 6 |
| 7 | `divisor_r[1]` → `quotient_r[0]` | 6 | `divisor_r[1]` → `quotient_r[0]` | 6 |
| 8 | `valid_r` → `valid_r` | 4 | `valid_r` → `valid_r` | 4 |
| 9 | `step_r[3]` → `step_r[4]` | 4 | `step_r[3]` → `step_r[4]` | 4 |
| 10 | `valid_r` → `numerator_r[0]` | 3 | `valid_r` → `numerator_r[0]` | 3 |
| 11 | `valid_r` → `numerator_r[5]` | 3 | `valid_r` → `numerator_r[5]` | 3 |
| 12 | `valid_r` → `numerator_r[6]` | 3 | `valid_r` → `numerator_r[6]` | 3 |
| 13 | `valid_r` → `numerator_r[7]` | 3 | `valid_r` → `numerator_r[7]` | 3 |
| 14 | `valid_r` → `numerator_r[8]` | 3 | `valid_r` → `numerator_r[8]` | 3 |
| 15 | `valid_r` → `numerator_r[9]` | 3 | `valid_r` → `numerator_r[9]` | 3 |
| 16 | `valid_r` → `numerator_r[10]` | 3 | `valid_r` → `numerator_r[10]` | 3 |
| 17 | `valid_r` → `numerator_r[11]` | 3 | `valid_r` → `numerator_r[11]` | 3 |
| 18 | `valid_r` → `numerator_r[12]` | 3 | `valid_r` → `numerator_r[12]` | 3 |
| 19 | `valid_r` → `numerator_r[13]` | 3 | `valid_r` → `numerator_r[13]` | 3 |
| 20 | `valid_r` → `numerator_r[14]` | 3 | `valid_r` → `numerator_r[14]` | 3 |

#### blur_math

| # | 改前起点 → 终点 | LUT6 | 改后起点 → 终点 | LUT6 |
|---:|---|---:|---|---:|
| 1 | `valid_r[1]` → `pixel_r[32]` | 2 | `valid_r[1]` → `pixel_r[32]` | 2 |
| 2 | `valid_r[1]` → `pixel_r[33]` | 2 | `valid_r[1]` → `pixel_r[33]` | 2 |
| 3 | `valid_r[1]` → `pixel_r[34]` | 2 | `valid_r[1]` → `pixel_r[34]` | 2 |
| 4 | `valid_r[1]` → `pixel_r[35]` | 2 | `valid_r[1]` → `pixel_r[35]` | 2 |
| 5 | `valid_r[1]` → `pixel_r[36]` | 2 | `valid_r[1]` → `pixel_r[36]` | 2 |
| 6 | `product_r[140]` → `pixel_r[37]` | 2 | `product_r[140]` → `pixel_r[37]` | 2 |
| 7 | `valid_r[1]` → `pixel_r[37]` | 2 | `valid_r[1]` → `pixel_r[37]` | 2 |
| 8 | `product_r[140]` → `pixel_r[38]` | 2 | `product_r[140]` → `pixel_r[38]` | 2 |
| 9 | `valid_r[1]` → `pixel_r[38]` | 2 | `valid_r[1]` → `pixel_r[38]` | 2 |
| 10 | `product_r[140]` → `pixel_r[39]` | 2 | `product_r[140]` → `pixel_r[39]` | 2 |
| 11 | `valid_r[1]` → `pixel_r[39]` | 2 | `valid_r[1]` → `pixel_r[39]` | 2 |
| 12 | `valid_r[1]` → `pixel_r[40]` | 2 | `valid_r[1]` → `pixel_r[40]` | 2 |
| 13 | `valid_r[1]` → `pixel_r[41]` | 2 | `valid_r[1]` → `pixel_r[41]` | 2 |
| 14 | `valid_r[1]` → `pixel_r[42]` | 2 | `valid_r[1]` → `pixel_r[42]` | 2 |
| 15 | `valid_r[1]` → `pixel_r[43]` | 2 | `valid_r[1]` → `pixel_r[43]` | 2 |
| 16 | `valid_r[1]` → `pixel_r[44]` | 2 | `valid_r[1]` → `pixel_r[44]` | 2 |
| 17 | `product_r[171]` → `pixel_r[45]` | 2 | `product_r[171]` → `pixel_r[45]` | 2 |
| 18 | `valid_r[1]` → `pixel_r[45]` | 2 | `valid_r[1]` → `pixel_r[45]` | 2 |
| 19 | `product_r[171]` → `pixel_r[46]` | 2 | `product_r[171]` → `pixel_r[46]` | 2 |
| 20 | `valid_r[1]` → `pixel_r[46]` | 2 | `valid_r[1]` → `pixel_r[46]` | 2 |

### BLUR 归属内最差 20 条路径（改后）

共享接口作为切点后，最长组合段如下。共享 coverage/round_row 已另行转交 T-RND1，不修改这些文件。

| # | 起点 → 终点 | LUT6 |
|---:|---|---:|
| 1 | `phase_r[0]` → `sample_step_r[2]` | 8 |
| 2 | `tap_max_r[3]` → `state_r[1]` | 8 |
| 3 | `tap_max_r[3]` → `sample_pixel_r[24]` | 8 |
| 4 | `tap_max_r[3]` → `sample_pixel_r[25]` | 8 |
| 5 | `tap_max_r[3]` → `sample_pixel_r[26]` | 8 |
| 6 | `tap_max_r[3]` → `sample_pixel_r[27]` | 8 |
| 7 | `tap_max_r[3]` → `sample_pixel_r[28]` | 8 |
| 8 | `tap_max_r[3]` → `sample_pixel_r[29]` | 8 |
| 9 | `tap_max_r[3]` → `sample_pixel_r[30]` | 8 |
| 10 | `tap_max_r[3]` → `sample_pixel_r[31]` | 8 |
| 11 | `state_r[4]` → `sample_pixel_r[9]` | 8 |
| 12 | `state_r[4]` → `sample_pixel_r[10]` | 8 |
| 13 | `state_r[4]` → `sample_pixel_r[15]` | 8 |
| 14 | `state_r[4]` → `sample_pixel_r[21]` | 8 |
| 15 | `row_remaining_low_r[9]` → `row_remaining_r[14]` | 8 |
| 16 | `row_remaining_low_r[9]` → `row_remaining_r[15]` | 8 |
| 17 | `row_remaining_low_r[9]` → `row_remaining_r[16]` | 8 |
| 18 | `column_remaining_r[3]` → `column_remaining_r[13]` | 8 |
| 19 | `column_remaining_r[3]` → `column_remaining_r[15]` | 8 |
| 20 | `command_i[300]` → `temp_base_mid_r[11]` | 7 |

## 回归与性能

按协调者最后调整，最终 RTL 的回归、性能由 T-RND1 集中验收；范围为 lint、改动模块的单元 smoke、少量模块用例和板级 smoke，其余随上板验证。本任务已停止尚未执行的 rnd_engine/full、block/full、perf 等仿真任务。

以下为最后一轮跨度、裁剪及 tap 比较拆分之前的工作树草案参考结果；最终提交不在本任务重复仿真。

| 已执行命令 / 用例 | 参考结果 |
|---|---|
| `flock /tmp/edrv32-sim.lock python3 tools/regress.py smoke --path verif/unit/rnd_blur -j 1` | 1 PASS / 0 FAIL |
| `flock /tmp/edrv32-sim.lock python3 tools/regress.py smoke --path verif/unit/rnd_round -j 1` | 1 PASS / 0 FAIL |
| `flock /tmp/edrv32-sim.lock python3 build/rnd-copy-blur/blur_perf.py after` | 40 个实际 RTL / 独立 Python 全内存逐字节向量 PASS |

40 项覆盖 COPY 两格式×四方向重叠、重合、不同源/目标；FILL 首尾字节偏移、负 RECT、两格式纯色；两格式 BLUR/BOX_SHADOW 的 R=0/1/8/31。其中两项 COPY 使用 `RECT=(-32768,-32768,17,12)`、`SRC_X=32768`、`SRC_Y=65535`、`SRC_STRIDE=1`，明确覆盖 16 位坐标差、相加后第 17 位和不对齐源字节。

单元激励使用 `50dcc2d3`（本分支 `bcad3621`）的非重叠 BLIT 缓冲修正。rnd_engine 只有 full 档，原 smoke 命令未选中用例；按协调者要求未执行后续 full，由集中验收处理。未修改该测试修正的内容。

### blur/shadow 参考周期

相同现有 block harness 与独立 Python 模型，种子 1，读延迟 3、随机背压 30、B 延迟 3。PERF0 包含整条命令，阴影包含最终着色。

| 向量 | `05088f4b` PERF0 | 参考草案 PERF0 | 增幅 | PERF1 | 逐字节 |
|---|---:|---:|---:|---:|---|
| RN-11，ARGB8888，blur=8，corner=7 | 218085 | 218085 | 0.000% | 486 | PASS |
| RN-12，ARGB8888，R=8 | 638 | 638 | 0.000% | 6 | PASS |

参考日志 `build/rnd-copy-blur/selected-before.log`、`selected-after.log`；单元日志在 `build/regress/smoke/unit/rnd_{blur,round}/verilator/`。最终代码保持 SAMPLE/ADD 两拍 tap 和 PIXEL/OUTPUT/STORE 三拍 seed 调度；上述参考运行后还拆分了跨度、裁剪、tap 比较及输出字节选择，最终字节与周期结果由集中验收认定。

RN-18 改后八场景尚未取得，不能判定最终 ≤2% 条件；按协调者调整交集中验收/上板，不将上述小向量周期替代 RN-18。

| 读延迟 | 场景 | 2026-10-29 PERF0 | 最终 PERF0 / 增幅 |
|---:|---|---:|---|
| 0 | ARGB8888 FILL | 124570 | 待集中验收 |
| 0 | RGB565 FILL | 63370 | 待集中验收 |
| 0 | ARGB8888 BLIT | 267677 | 待集中验收 |
| 0 | 1000 A4 GLYPH | 439001 | 待集中验收 |
| 40 | ARGB8888 FILL | 124609 | 待集中验收 |
| 40 | RGB565 FILL | 63409 | 待集中验收 |
| 40 | ARGB8888 BLIT | 267794 | 待集中验收 |
| 40 | 1000 A4 GLYPH | 1904001 | 待集中验收 |

最终提交已完成以下检查，均为 0 告警：

```sh
python3 tools/check/verilog_style.py rtl/media/rnd
(cd rtl/filelists && verilator --lint-only -Wall -DSIM_MODE --top-module edrv32_rnd -f rnd.f)
git diff --check
```

日志分别为 `build/rnd-copy-blur/style-final.log`（15 文件 / 0 warnings）与 `lint-final.log`（空输出 / exit 0）。原验收中的 block/full、block/perf、rnd_engine/full 未执行最终提交，不能列作 PASS；原命令如下，执行计划以协调者集中验收的缩减范围为准。

```sh
flock /tmp/edrv32-sim.lock python3 tools/regress.py full --path verif/block/rnd -j 1
flock /tmp/edrv32-sim.lock python3 tools/regress.py perf --path verif/block/rnd -j 1
flock /tmp/edrv32-sim.lock python3 tools/regress.py full --path verif/unit/rnd_engine -j 1
```


## 同口径复现脚本

在改后 RTL 提交的仓库根目录，将下面代码保存为 `build/rnd-copy-blur/reproduce.py`，执行：

```sh
flock /tmp/edrv32-sim.lock python3 build/rnd-copy-blur/reproduce.py measure
```

脚本从 `05088f4b` 导出改前 RTL，两个版本在同一工具版本下按相同流程映射。结果在 `build/rnd-copy-blur/reproduce/summary.json`，每模块的 coarse、硬块网表、LUT6 网表与完整 Yosys 命令一并保留。工具版本使用表头条件；共享模块未合入 T-RND1 修改。该代码只做时序测量，不运行回归。

```python
from pathlib import Path
import json,subprocess,sys,re,shutil
sys.path.insert(0,str(Path.cwd()))
from tools.synth.yosys_synth import read_filelist
from tools.synth.netlist_paths import analyze

import re
from tools.synth.netlist_paths import analyze,is_ff
SHARED=('edrv32_rnd_decode.v','edrv32_rnd_coverage.v','edrv32_rnd_round_row.v','edrv32_rnd_address.v')
def owned_paths(design):
    m=next(v for v in design['modules'].values() if int(v.get('attributes',{}).get('top','0'),2))
    outputs=['argb_o','left_o','top_o','right_o','bottom_o','width_o','height_o','fast_fill_o','illegal_o','empty_o','op_o','src_fmt_o','flags_o','edge_q4_o','edge_valid_o','radius_o','row_ready_o','coverage_o','dst_addr_o','src_addr_o','map_addr_o','sub_shift_o','sub_mask_o','sample_x_o','sample_y_o']
    shared_pattern=r'^u_(?:decode|coverage|round_row|address)\.(?:'+'|'.join(outputs)+r')(?:\[|$)'
    driven={b for port in m['ports'].values() if port['direction']=='input' for b in port['bits'] if isinstance(b,int)}
    driven.update(b for c in m['cells'].values() for pn,bs in c['connections'].items() if c['port_directions'][pn]=='output' for b in bs if isinstance(b,int))
    cut_bits={b for name,v in m['netnames'].items() if re.search(shared_pattern,name) for b in v['bits'] if isinstance(b,int) and b in driven}
    cut_bits.update(b for port in m['ports'].values() if port['direction']=='input' for b in port['bits'] if isinstance(b,int))
    cut_bits.update(b for c in m['cells'].values() if is_ff(c['type']) or c['type'].startswith('ip_') for pn,bs in c['connections'].items() if c['port_directions'][pn]=='output' for b in bs if isinstance(b,int))
    for b in cut_bits:
        m['netnames']['__timing_cut_'+str(b)]={'hide_name':1,'bits':[b],'attributes':{}}
    starts=[r'^__timing_cut_']
    ends=[r'^'+re.escape(p)+r'(?:\[|$)' for p,v in m['ports'].items() if v['direction']=='output']
    for name,c in m['cells'].items():
        if (is_ff(c['type']) or c['type'].startswith('ip_')) and not any(f in c['attributes'].get('src','') for f in SHARED):
            ends.append(r'^'+re.escape(name)+r'\.[^[]+\[')
    ends=['(?:'+'|'.join(ends)+')']
    return analyze(design,starts=starts,ends=ends)

import re
from tools.synth.netlist_paths import analyze,is_ff

def mul_segments(design,name,index):
    m=next(v for v in design['modules'].values() if int(v.get('attributes',{}).get('top','0'),2))
    roots={b for p in m['ports'].values() if p['direction']=='input' for b in p['bits'] if isinstance(b,int)}
    for c in m['cells'].values():
        if is_ff(c['type']) or (c['type'].startswith('ip_') and not c['type'].startswith('ip_mul_')):
            roots.update(b for pn,bs in c['connections'].items() if c['port_directions'][pn]=='output' for b in bs if isinstance(b,int))
    for bit in roots:m['netnames']['__reg_root_'+str(bit)]={'hide_name':1,'bits':[bit],'attributes':{}}
    pre=analyze(design,starts=[r'^__reg_root_'],ends=[r'^'+re.escape(name)+r'\.[AB]\['])
    ends=[r'^'+re.escape(p)+r'(?:\[|$)' for p,v in m['ports'].items() if v['direction']=='output']
    for n,c in m['cells'].items():
        if is_ff(c['type']) or (c['type'].startswith('ip_') and not c['type'].startswith('ip_mul_')):
            ends.append(r'^'+re.escape(n)+r'\.[^[]+\[')
    for b in m['cells'][name]['connections']['Y']:
        if isinstance(b,int):m['netnames']['__mul_output_'+str(index)+'_'+str(b)]={'hide_name':1,'bits':[b],'attributes':{}}
    post=analyze(design,starts=[r'^__mul_output_'+str(index)+'_'],ends=['(?:'+'|'.join(ends)+')'])
    return pre['max_levels'],post['max_levels']

root=Path.cwd();base=root/'build/rnd-copy-blur/reproduce';mode=sys.argv[1]
def run(args,log):
    log.parent.mkdir(parents=True,exist_ok=True)
    with log.open('w') as f:
        subprocess.run(args,stdout=f,stderr=subprocess.STDOUT,check=True)
def summary(r):
    return dict(max_levels=r['max_levels'],totals=r['totals'],paths=[dict(start=x['start']['signal'],end=x['end']['signal'],levels=x['levels']) for x in r['paths'][:20]])
if mode=='measure':
    files=[];includes=set();read_filelist(root/'rtl/filelists/rnd.f',files,includes)
    baseline=root/'build/rnd-copy-blur/before/src'
    for name in subprocess.check_output(['git','ls-tree','-r','--name-only','05088f4b','rtl'],text=True).splitlines():
        dest=baseline/name;dest.parent.mkdir(parents=True,exist_ok=True)
        dest.write_bytes(subprocess.check_output(['git','show','05088f4b:'+name]))
    stub=root/'build/rnd-copy-blur/stubs.v'
    stub.write_text('(* blackbox *) module ip_ram_rnd_line (input wr_clk, wr_en, input [8:0] wr_addr, input [255:0] wr_data, input [31:0] wr_byte_en, input wr_rst, rd_clk, rd_clk_en, rd_rst, input [8:0] rd_addr, output [255:0] rd_data); endmodule\n(* blackbox *) module ip_ram_rnd_palette (input wr_clk, wr_en, input [8:0] wr_addr, input [31:0] wr_data, input wr_rst, rd_clk, rd_clk_en, rd_rst, input [8:0] rd_addr, output [31:0] rd_data); endmodule\n')
    jobs=[];commands=[]
    for phase in ['before','after']:
        src='build/rnd-copy-blur/before/src/' if phase=='before' else ''
        for short in ['copy','fill','blur','blur_coeff','blur_math']:
            top='edrv32_rnd_'+short;d=base/phase/short;d.mkdir(parents=True,exist_ok=True);jobs.append((phase,short,top,d))
            commands.append('read_verilog -D FPGA_MODE '+' '.join('-I'+src+p for p in includes)+' '+' '.join(src+p for p in files)+' build/rnd-copy-blur/stubs.v\nhierarchy -top '+top+'\nproc\nflatten\nopt\nwreduce\nopt_clean\nwrite_json '+str(d.relative_to(root)/'coarse.json')+'\ndesign -reset\n')
    (base/'coarse.ys').write_text(''.join(commands));run(['yosys','-Q','-T','-s',str(base/'coarse.ys')],base/'coarse.log')
    commands=[]
    for phase,short,top,d in jobs:
        design=json.loads((d/'coarse.json').read_text());m=design['modules'][top];muls=[];constants=[]
        for name,c in m['cells'].items():
            if c['type']!='$mul':continue
            const={p:''.join(reversed(c['connections'][p])) for p in ['A','B'] if all(isinstance(b,str) for b in c['connections'][p])}
            if const:
                constants.append(dict(operands=const,widths={p:len(b) for p,b in c['connections'].items()}));continue
            kind='ip_mul_'+str(len(muls));ports={};offset=2
            for pn,bits in c['connections'].items():
                ports[pn]={'direction':c['port_directions'][pn],'bits':list(range(offset,offset+len(bits)))};offset+=len(bits)
            design['modules'][kind]={'attributes':{'blackbox':'1'},'ports':ports,'cells':{},'netnames':{pn:dict(hide_name=0,bits=v['bits'],attributes={}) for pn,v in ports.items()}}
            owner='round_row' if 'u_round_row' in name else 'blur_math' if 'u_normalize' in name else short
            muls.append(dict(index=len(muls),cell=name,owner=owner,widths={p:len(b) for p,b in c['connections'].items()}));c['type']=kind;c['parameters']={}
        (d/'mul.json').write_text(json.dumps(muls));(d/'constants.json').write_text(json.dumps(constants));(d/'hard.json').write_text(json.dumps(design))
        commands.append('read_json '+str(d.relative_to(root)/'hard.json')+'\nsynth -top '+top+' -flatten -noabc\nabc -lut 6 -dress\nopt_clean\nwrite_json '+str(d.relative_to(root)/'netlist.json')+'\ndesign -reset\n')
    (base/'fine.ys').write_text(''.join(commands));run(['yosys','-Q','-T','-s',str(base/'fine.ys')],base/'fine.log')
    result={}
    for phase,short,top,d in jobs:
        design=json.loads((d/'netlist.json').read_text());m=design['modules'][top];r=analyze(design)
        owned=owned_paths(design)
        muls=json.loads((d/'mul.json').read_text())
        for item in muls:
            name=item.pop('cell');item['before_levels'],item['after_levels']=mul_segments(design,name,item['index'])
        result[phase+'/'+short]=dict(all=summary(r),owned=summary(owned),multipliers=muls,constants=json.loads((d/'constants.json').read_text()))
    (base/'summary.json').write_text(json.dumps(result,indent=2))
    print(json.dumps(result),flush=True)
```
