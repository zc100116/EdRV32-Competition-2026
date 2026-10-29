# RND 命令渲染器微架构

| 项 | 内容 |
|---|---|
| 日期 | 2026-10-29 |
| 状态 | R-R2 通用双像素流水；PDS 面积、125 MHz 时序仍需 Windows 实测 |
| 依据 | `rnd-spec.md` v0.2；`dma2d-spec.md` v0.1；`2026-10-29-rnd-disp.md` 第 4、5 节 |
| 实现 | R-R2 RTL `7dce50a`；测试 `6f5285b`；R-R1 基线 `70f833d` |

## 1. 背景和问题

RND 顺序执行 DDR 中的 64 B 命令。与旧 render 不同，目标 ARGB8888 是非预乘，
需要保留目标 alpha，再用 Q[oa] 求回 straight-alpha 混合比例。新增索引格式、亚字节字形、
边框选择、BLIT 模式和 TILEMAP；COPY 必须保留同一缓冲内的重叠语义。

R-R2 保留连续传输专用路径，通用路径改为双 bank 分块加载、采样、写出，共享一个双像素运算流水线。命令调度只允许
当前命令拥有读、写 DMA；上一条命令最后一个 B 返回后，才读取下一条命令。

## 2. 约束

- 顶层 `edrv32_rnd` 的全部外部端口与规格第 3 节一致，单 clk_mem，125 MHz。
- 可综合 Verilog-2001；只用规范列出的三个错误码，不检查越界、CLIP、重叠或超时。
- 所有 DDR 访问经 `edrv32_dma2d_rd` 和 `edrv32_dma2d_wr`，各 1 实例，OUTSTANDING 均为 8。
- 行缓冲和调色板使用协调者的固定技术包装。数据寄存器、RAM 内容均不复位。
- 全屏填充、1:1 ARGB8888 BLIT 的规格指标为开发初值；10K LUT 面积也需 PDS 实测定稿。
- 按协调者确认的 v0.2，RGB565 BLUR 的水平中间结果为 `{0,R,G,B}`，每像素 4 B；
  只在最终写回时 P565。COPY 不同 stride 的源/目标由软件保证不重叠，RTL 不检查。

## 3. 可选方案

| 方案 | 优点 | 代价 |
|---|---|---|
| 所有命令逐像素读写 | 控制和采样统一 | 每个像素等待 DDR，无法达到连续 BLIT 吞吐 |
| 所有格式全部展开并全程流式 | 吞吐高 | 缩放、索引、瓦片、掩码、圆角和多遍模糊的调度复杂 |
| 连续行路径加通用逐对调度（R-R1） | 纯色填充、COPY、常用连续 BLIT 保持宽数据流 | 每对等待 over，I8 约 0.1 像素/拍 |
| 连续行路径加通用双 bank 流水（R-R2） | 源、目标行片段在 RAM 中时每拍采样两个像素，加载/着色/写出重叠 | 增加 RAM 端口副本、标签和双 lane 地址/颜色计算 |

R-R2 采用第四种。索引调色板整表预载到双份 RAM。通用绘制按目标 beat 划分最多
512 像素的 chunk，两个 bank 交替拥有相邻 chunk；块边界不拆开一个目标 beat。
普通源读取覆盖两个端点的对齐范围，两个 lane 各有当前/下一 beat 的同步读口副本，
处理未对齐 RGB565/ARGB 像素跨 beat 的拼接。范围超过 16 KiB 的缩小采样按需取 beat，
用四项带地址缓存容纳一对像素最多涉及的四个 beat；只等源数据，不等前一对 over。
TILEMAP 在加载时按地图顺序收集瓦片行，每瓦片分配三个 beat 槽，并登记地图 entry。
地图 beat 缓存和缩小采样 beat 缓存仅在当前命令内有效，命令开始及 ABORT 清 valid。

## 4. 决策

### 4.1 模块和命令对应

| 模块 | 责任/命令 |
|---|---|
| `edrv32_rnd` | 命令抓取、合法性检查、执行器选择、读写客户端互斥仲裁、错误和 ABORT 排空 |
| `edrv32_rnd_regs` | APB、DONE_COUNT/CUR_DESC、IRQ、PERF；ENABLE 不门控 DOORBELL |
| `edrv32_rnd_decode` | OP/格式/MODE 错误 3；有符号 RECT、含端点 CLIP、空区域和快速填充条件 |
| `edrv32_rnd_address` | GLYPH/COPY 采样、BLIT Q16.16 缩放/翻转、TILEMAP 地图/瓦片和亚字节地址 |
| `edrv32_rnd_source` | RGB565 展开、A1/A2/A4/A8、I1/I2/I4/I8、颜色键、recolor 和整体 OPA |
| `edrv32_rnd_draw` | 通用 FILL/BORDER/GLYPH/BLIT/TILEMAP、阴影着色；双 bank chunk 调度、双 lane 采样和标签写回 |
| `edrv32_rnd_alpha_pipe` | 全部 over 和 BLIT 模式的公共双像素流水线 |
| `edrv32_rnd_round_row` / `coverage` | 逐行半径钳位、16 步整数平方根、双像素 Q4 覆盖率 |
| `edrv32_rnd_fill` | 无渐变、半径 0、OPA=255 的 FILL，256 位/拍，无目标读 |
| `edrv32_rnd_copy` | 一整行源快照、首尾重新对齐、按方向遍历重叠行，256 位/拍 |
| `edrv32_rnd_blit` | 正常模式、两端 ARGB8888、1:1、行/起点 beat 对齐、宽为 8 像素倍数的 BLIT |
| `edrv32_rnd_blur` | BOX_SHADOW 掩码生成和两遍滤波；BLUR 两遍滤波及最终目标写回 |
| `edrv32_rnd_blur_coeff` / `blur_math` | 每命令 17 拍求 M_R；四通道、两像素的乘法/舍入单元 |

快速 BLIT 的条件仅用于选择内部数据路径，不产生错误。其余合法 BLIT 由通用绘制器处理。
公共 over 流水线由两个调度器互斥使用，没有复制 alpha 算术。

### 4.2 DMA 与事务边界

读 DMA 按当前执行器选择命令、源、目标、地图、调色板或临时区描述符。
命令固定读 64 B；通用绘制读目标 chunk、源连续片段或瓦片行；模糊读一个对齐 beat；COPY 和快速 BLIT 读整行对齐范围。
COPY 把非 beat 对齐的源行转成从像素 0 开始的 RAM 行，最多 512 beat，即 4096 个 ARGB 像素。
首尾可能多读的 beat 只用于像素重新对齐。

写 DMA 接受快速填充、COPY、快速 BLIT 的一整行描述符和流，或通用绘制的 chunk 数据流、模糊的一拍写回。
COPY/快速 FILL 按行等 B；draw/快速 BLIT 的 bank 在其最后一个 B 后才复用，另一 bank 可同时读/计算。
突发最长 16 beat、不跨 4 KiB、ID=0 均由公共 dma2d 实现。

总线发现非 OKAY 响应立即记录错误 1 或 2，停止发新工作，同时向两 DMA 发 ABORT。
已置 VALID 的地址/数据由 DMA 保持，已承诺的写突发按 dma2d 契约补零 strobe、等 B；
顶层仅在两 DMA 都 idle 后清 BUSY。非法命令在访问图像数据前以错误 3 停止。
软件 ABORT 同样清流水 valid 和执行器状态，不计当前命令、不置 DONE；已写部分保留。

### 4.3 片上存储

| 存储 | 宽 × 深 | 写/读端口 | 延迟 | 时钟 | 初始化 | 实例 |
|---|---|---|---|---|---|---:|
| `edrv32_ram_rnd_line`，BLIT 源双 bank | 256 × 512 | 1W（32 个字节使能）/1R | 同步读 1 拍，禁读保持 | clk_mem | 无 | 2 |
| 同包装，BLIT 目标/结果双 bank | 256 × 512 | 同上 | 同上 | clk_mem | 无 | 2 |
| 同包装，COPY 源行快照 | 256 × 512 | 同上 | 同上 | clk_mem | 无 | 1 |
| 同行包装，draw 原目标快照双 bank | 256 × 512 | 同上，render 只读 | 同步读 1 拍 | clk_mem | 无 | 2 |
| 同行包装，draw 结果双 bank | 256 × 512 | 同上，alpha 写、写 DMA 读 | 同步读 1 拍 | clk_mem | 无 | 2 |
| 同行包装，draw 原始源双 bank、双 lane、当前/下一 beat | 256 × 512 | 广播写，每份 1R | 同步读 1 拍 | clk_mem | 无 | 8 |
| `edrv32_ram_rnd_palette`，索引表 | 32 × 256 | 1W/1R，两份写广播、按 lane 读 | 同步读 1 拍 | clk_mem | 无 | 2 |
| 同调色板包装，draw 地图 entry 双 bank、双 lane | 32 × 256 | 同 bank 两份写广播、按 lane 读 | 同步读 1 拍 | clk_mem | 无 | 4 |
| Q 函数 `edrv32_rnd_q.vh` | 24 位 × 256 个常数 | 两次组合函数调用，外部寄存器 | 在 alpha 第 2 级登记为 1 拍 | clk_mem | 生成常数，Q[0]=0 | 两个逻辑读口 |

R-R1 为 82 KiB；R-R2 为 278 KiB 逻辑数据位（17 个行包装、6 个调色板包装）。全部已使用协调者包装；没有业务 RTL 自建 RAM。
行 RAM 同址读写从调度上分离：COPY 先整行读、后整行写；快速 BLIT 的读原值与写结果
在流水中相隔至少 8 拍，双像素仅需每 4 拍进入下一 ARGB beat，因而访问不同地址。
写回端只读取已经完成计算的 bank。draw 的源和原目标只在加载阶段写；结果 bank 计算完才交写出。
因此包括缩小采样停顿在内，所有行 RAM 都不依赖同址读写行为。
两个索引调色板 RAM 在画图前写完，画图期间只读；地图 entry bank 在使用前装完。

寄存器缓存为大跨度缩小采样 4 beat、地图 1 beat，命令为 512 位寄存器。
调色板按 I8/I4/I2/I1 分别预载 256/16/4/2 项；从对齐 DDR beat 提取每项，广播写入两 RAM。
预载按实际调色板地址选择首 beat 偏移，支持规格要求的 4 B 对齐。没有对未使用条目初始化或校验。Q 使用协调者提供的生成函数，未增加 ROM IP。

### 4.4 双像素流水

R-R2 通用前端按公共 alpha 的 ready 整体推进，所有 valid、标签、地址和 RAM 读使能保持一致。
源缺失只暂停这一前端；已进入 alpha 的旧结果继续写回。标签含 bank、chunk 最后一对、
第二 lane 有效和目标字节偏移，替代 R-R1 的 `S_BLEND_WAIT`。bank 选择随各级标签传递，
最后一对发射后即切换到下一已加载块，既不等前端排空，也不等 over 结果。

| 前端级 | 数据运算 |
|---|---|
| 0 | 双目标坐标，原目标 RAM 和双 lane 地图 entry 同步读；覆盖率、渐变登记 |
| 1 | 双 lane 源地址/亚字节位置登记；目标像素截取；第一覆盖率乘积 |
| 2 | 每 lane 当前/下一源 beat 同步读，或缩小采样缓存；第二覆盖率/OPA 乘积 |
| 3 | 跨 beat 拼接原始像素、登记位移/掩码；两个索引调色板同步读；最终填充 alpha |
| 4 | 格式展开、OPA、颜色键/recolor，登记公共 alpha 输入 |

随后沿用 R-R1 的八级公共 alpha：

| 级 | 数据运算 |
|---|---|
| 0 | 目标 RGB565 展开；`(255-sa)*Da`、模式乘积、饱和加/减的候选值 |
| 1 | d 归一化、oa、四种模式选择 |
| 2 | 组合 Q[oa] 查询的寄存器；同拍登记 payload |
| 3 | `sa*Q[oa]`，24×8 位乘法 |
| 4 | 加 32768、取 Q16 整数比例 r；不透明目标直接用 sa |
| 5 | 三通道的 `r*S+(255-r)*D`，范围 0…65025 |
| 6 | d 归一化、ARGB/RGB565 打包、sa=0 原值旁路 |
| 7 | 输出寄存器，隔开后级字节选择 |

两 lane 每拍可接受一对像素。输出反压时整体 clock enable 停住，valid、标签和数据一起保持；
无反压时持续 2 像素/拍。ABORT 清 valid，不复位数据寄存器。
快速 BLIT 把 bank 和 pair index 随标签传递，结果直接以 8 字节使能写入目标 RAM。

### 4.5 各命令调度

- FILL：快速情形每行直接送常量 beat；其余按行算覆盖率，按 x/y 求有符号渐变，
  双 lane 按拍进入公共 over，按标签和字节使能写入结果 RAM。
- BORDER：命令开始先分拍登记尺寸、有效半径、内缘坐标和内缘尺寸，切断长组合链；
  外 RECT 与内 RECT 分别算行边缘。覆盖率乘积、归一化/OPA 乘积、最终 d 分拍登记。
  内缘空或本行不在内缘时 cov_i=0，不增加错误。
- GLYPH：源字节由地址生成器选择，亚字节从高位取，An 展开再乘 OPA。
- BLIT：连续 ARGB 情形读加载、计算、写回三者跨 bank 重叠；其余通过通用 chunk 加载/采样流水，
  recolor 后交公共模式/over 运算。索引源先整表装入两个调色板 RAM。
- COPY：按首像素物理地址决定行方向，每行完整读入 RAM 才开始写，处理同 stride 四向重叠。
  行快照屏蔽横向重叠；写出时用相邻归一化 beat 拼接并生成首尾 strobe。
- BOX_SHADOW：扩展网格 cov→TEMP0，水平 TEMP0→TEMP1，竖直 TEMP1→TEMP0，
  然后构造内部 A8 GLYPH 着色命令，沿用 over；内部 stride 用 32 位，保留大网格的跨距。
- BLUR：对 A 的原值做水平遍，边缘取最近像素，把 8 位通道存入 4 B/像素临时区；
  竖直遍读临时区，最终写回目标，RGB565 仅在此处截断。
- TILEMAP：地图 beat 缓存提供瓦片号和翻转；加载器把当前 chunk 所需瓦片行收集进源 RAM，
  地图 entry 同步写到两份 metadata RAM。渲染按 entry 计算翻转后的槽内地址，每拍取双像素。

模糊按 tap 累加，半径 31 时每通道最大和 16065，14 位累加器足够。
M_R 每命令仅求一次；滤波乘法与舍入分两拍。阴影越网格取 0，BLUR 越 A 取最近值。
PERF1 只累计最终目标区域，不把临时区的内部遍历重复计为目标像素。

### 4.6 与 legacy 的差异

旧 alpha/round 的双像素和逐行平方根结构作为参考，按新文件和规格重写：
非预乘 oa/Q 比例替换旧预乘饱和相加；完整 12 位半径和 SIDES 内缘替换旧对称边框；
M_R 替换旧精确平均纠偏算法；新增加四种模式、索引调色板、亚字节掩码、TILEMAP。
所有旧 DMA 直接 AXI 的调度改为公共 dma2d 客户端，没有移入旧互连、合成 DMA、
帧控制器、写保护器或 HDMI。`legacy/` 未进入文件列表。

## 5. 影响和验证

规格和 IP 包装由协调者维护。R-R2 只改 `rtl/media/rnd/` 的父调度器和 draw、
`verif/unit/rnd_engine/tb.sv` 及本记录；寄存器、文件列表、公共 DMA 和技术包装未改。

### 5.1 可复现命令

环境：先执行 `. ~/.local/opt/edrv32/env.sh`。Verilator 5.020；软件 GCC 15.2.0。

```sh
python3 tools/check/verilog_style.py rtl/media/rnd
(cd rtl/filelists && verilator --lint-only -Wall -DSIM_MODE --top-module edrv32_rnd -f rnd.f)
python3 tools/regress.py smoke --path verif/unit/rnd_alpha -j 1
python3 tools/regress.py smoke --path verif/unit/rnd_round -j 1
python3 tools/regress.py smoke --path verif/unit/rnd_blur -j 1
python3 tools/regress.py smoke --path verif/unit/rnd_address -j 1
python3 tools/regress.py full --path verif/unit/rnd_alpha -j 1
python3 tools/regress.py full --path verif/unit/rnd_round -j 1
python3 tools/regress.py full --path verif/unit/rnd_blur -j 1
python3 tools/regress.py full --path verif/unit/rnd_address -j 1
python3 tools/regress.py full --path verif/unit/rnd_engine -j 1
python3 tools/regress.py perf --path verif/unit/rnd_engine -j 1
make -C sw PROGRAM=regs_check -j 1
```

完整顶层测试冷编译约 4 分钟，归 full，不放 smoke。full 包含 R=31 的两种格式 BLUR/阴影。
测试独立用整数除法写 over 参考，而 DUT 用 d/Q 表；覆盖全部 sa/Da、模式和两种目标格式，
共 1,048,576 像素。地址测试穷举 65,536 个合法性组合并检查 10,000 个地址样本。
端到端测试逐字节比较目标外保护区，检查各命令的字节使能、重叠 COPY、相邻命令读写顺序、
三种错误、ABORT、空区域、忽略的 SRC_FMT 和 SOFT_RST。

最终回归结果（RTL `1b64468`，所有项 PASS，日志在 `build/regress/<档位>/unit/<目录>/`）：

| 单元 | smoke | full |
|---|---|---|
| rnd_alpha | 36 s，1,048,576 像素 | 24 s，同样本与反压/清流水检查 |
| rnd_round | 24 s，半径/边缘/外部覆盖率 | 25 s，通过 |
| rnd_blur | 60 s，32 个半径、16,000 对通道和 | 53 s，通过 |
| rnd_address | 24 s，合法性、地址、packed alpha | 20 s，通过 |
| rnd_engine | 因冷编译超过 60 s 归 full | 基础 137 案例、R=31 扩展合计 141 案例全部通过 |

完整顶层最终冷构建 244 s，复用构建的第二组 2 s；无并行仿真，全部 `-j 1`。
`make -C sw PROGRAM=regs_check -j 1` 通过，日志 `build/rnd/regs-check.log`；
业务 RTL 及两个 RAM 包装合计 17 个文件风格 0 告警，顶层 Verilator `-Wall` 0 告警。

### 5.2 R-R1 周期基线

RTL `1b64468`，125 MHz；原始结果 `build/rnd/perf-final.log`。
命令为完成 full 构建后运行：

```sh
build/regress/full/unit/rnd_engine/full/verilator/obj/sim +PERF
```

模型关闭随机背压，R 连续返回，B 固定延迟 5 拍且 AW 按 B 串行；因此这是带写响应等待的
保守带宽条件，不把它标作零延迟 DDR。命令列表抓取、行间调度和最终 B 都计入 PERF0。

| 操作 | 目标像素 | PERF0 周期 | 像素/拍 | 125 MHz 时间 |
|---|---:|---:|---:|---:|
| 全屏 RGB565 快速 FILL | 921,600 | 84,251 | 10.93874 | 0.674008 ms |
| 全屏 ARGB8888 快速 FILL | 921,600 | 167,051 | 5.51688 | 1.336408 ms |
| ARGB8888→ARGB8888 1:1 BLIT | 921,600 | 468,609 | 1.96667 | 3.748872 ms |
| I8→RGB565，256×240，1:1 | 61,440 | 624,669 | 0.098356 | 4.997352 ms |
| I8→RGB565，256×240 放大三倍至 768×720 | 552,960 | 5,559,549 | 0.099461 | 44.476392 ms |

I8 使用覆盖 0…255 的变化索引值和完整 256 项 ARGB 调色板；OPA=147，目标旧值含变化颜色。
三倍采样 SCALE_X/Y=`0x00005555`，完全按规格的 Q16.16 最近邻算式。
整表 RAM 避免逐像素 DDR 调色板缺失；R-R1 的 I8 仍走通用逐对调度，等待 over 返回，
R-R1 未达到连续 ARGB 路径的 1.5 像素/拍。三倍绘制约 22.48 次/秒，未计软件和总线竞争；R-R2 提升见 5.5。

### 5.3 R-R1 Yosys 参考资源

RTL `1b64468`，Yosys 0.70+219（5053d0e26），XC7 映射，保留层次、RAM 包装为黑盒。
这不是 PG2L200H/PDS 面积。LUT 为 LUT2–LUT6 个数之和，FF 为 FD* 个数之和；
另有 193 个 SRL16E、2 个 RAM32M，未折算到 LUT 列。DSP48 与 Pango APM 不等价。
表中 LUT/FF/DSP 是该模块自身、不含子实例；`$mul` 是 proc/opt 后逻辑乘法站点数。

| 模块（省略 edrv32_） | 实例数 | 自身 LUT | 自身 FF | 自身 DSP48 | 自身 $mul |
|---|---:|---:|---:|---:|---:|
| rnd | 1 | 1,931 | 886 | 0 | 0 |
| dma2d_rd，OUTSTANDING=8 | 1 | 219 | 166 | 0 | 0 |
| dma2d_wr，OUTSTANDING=8 | 1 | 479 | 437 | 0 | 0 |
| rnd_alpha_pipe | 1 | 746 | 500 | 22 | 22 |
| rnd_draw | 1 | 4,374 | 1,394 | 14 | 8 |
| rnd_copy | 1 | 3,995 | 542 | 0 | 0 |
| rnd_blit | 1 | 1,514 | 73 | 5 | 5 |
| rnd_blur | 1 | 3,144 | 758 | 7 | 3 |
| rnd_fill | 1 | 235 | 25 | 1 | 1 |
| rnd_regs | 1 | 506 | 305 | 0 | 0 |
| rnd_address | 2 | 603 | 0 | 13 | 5 |
| rnd_decode | 6 | 253 | 0 | 0 | 0 |
| rnd_coverage | 3 | 173 | 0 | 0 | 0 |
| rnd_round_row | 2 | 291 | 113 | 2 | 2 |
| rnd_source | 1 | 172 | 0 | 7 | 7 |
| rnd_blur_coeff | 1 | 31 | 52 | 0 | 0 |
| rnd_blur_math | 1 | 1 | 66 | 8 | 8 |
| 按实例累计，含公共 DMA、不含技术 RAM | — | **21,172** | **5,430** | **94** | **68** |

逻辑 RAM 为行包装 5 个、调色板包装 2 个，未用 FF 或 LUT 来替代它们。
原始资源/乘法统计：`build/rnd/resources-final.json`、`operators-final.json`、`synth-final.log`。
参考综合可在根目录复现（输出全部留 build）：

```sh
mkdir -p build/rnd
python3 - <<'YOSYS_SCRIPT'
from pathlib import Path
files = ['rtl/common/edrv32_dma2d_rd.v', 'rtl/common/edrv32_dma2d_wr.v']
files += [str(p) for p in sorted(Path('rtl/media/rnd').glob('*.v'))]
script = ('read_verilog -lib -DSIM_MODE -Irtl/include '
          'rtl/tech/edrv32_ram_rnd_line.v rtl/tech/edrv32_ram_rnd_palette.v\n')
script += 'read_verilog -DSIM_MODE -Irtl/include ' + ' '.join(files) + '\n'
script += 'hierarchy -top edrv32_rnd\nproc\nopt\n'
script += 'tee -o build/rnd/operators-final.json stat -json\n'
script += 'synth_xilinx -top edrv32_rnd -family xc7 -noiopad -noclkbuf\n'
script += 'tee -o build/rnd/resources-final.json stat -json\n'
Path('build/rnd/synth-final.ys').write_text(script)
YOSYS_SCRIPT
yosys -Q -T -s build/rnd/synth-final.ys > build/rnd/synth-final.log 2>&1
```

### 5.4 R-R1 最长组合路径和后续可折叠项

RTL `1b64468` 在 `proc; opt; flatten; opt` 后、切掉技术 RAM 和 FF 的最长拓扑链为
**29 个算子**：顶层状态/BUSY → SOFT_RST/cancel → 写流 valid → dma2d 写握手 →
FILL 接收像素计数 → PERF1 加法器。原始路径 `build/rnd/path-final-ram-cut.log`。
这是算子深度而非纳秒 STA；包含互斥状态路径，不能据此宣称 125 MHz 收敛。
此前 BORDER 几何→覆盖率→两次 alpha 乘法的 32 算子链，已通过命令几何寄存器和
覆盖率/OPA 分拍切断。公共 alpha 和 blur 的乘法/归一化级划分见 4.4、4.5。

路径重现是在上述脚本的 `proc; opt` 后改执行：

```text
flatten
opt
select edrv32_rnd
select -del t:edrv32_ram_rnd_line t:edrv32_ram_rnd_palette
tee -o build/rnd/path-final-ram-cut.log ltp -noff
```

以下仅供 PDS 超预算后的收敛任务选择，**估算不能相加，也不构成本轮 PDS 资源承诺**：

| 可折叠项 | 依据与预计收益 |
|---|---|
| 公共几何集中解码一次 | 现有 6 个 decode，每个参考 253 LUT；去掉 5 份的原始上限 1,265 LUT，PDS flatten 已共享的部分不能重复计入，实际额外收益范围 0–1.3K LUT |
| COPY 使用专用行首地址或共享地址运算器 | 两个完整 address 实例各 603 LUT/13 DSP48；COPY 不需要缩放/TILEMAP。原始删除上限一份（603 LUT/13 DSP），保留两路行地址后净节省需实测，预计约 0.2–0.5K LUT、数个 DSP |
| 行地址以 stride 递推、统一 shadow stride 入口 | fill、blit、blur 的行基址乘法，以及 draw 的 stride 修正乘法可减少；按当前 32×16/18、32×32 的映射，估计可少 2–8 个 DSP48 和约 0.1–0.5K LUT，代价是地址寄存器和阶段控制 |
| COPY 读/写相位共享重新对齐器 | 读快照和写回互斥；两个 256 位数据选择网络可分时共用。按 256 bit×4/5 级 mux 的粗估，扣除入口选择后可能省约 0.3–0.8K LUT；须以 PDS 综合确认 |
| 滤波与颜色算术分时共享 | blur_math 的第二 lane 当前输入固定 0，扁平化应先删除无用四通道；再考虑把 blur 的乘法与空闲 alpha/source 级共享，约 0–4 个 DSP 的进一步空间，新增选择逻辑可能增加 LUT，先看 PDS |

协调者已明确本轮不做面积重构、不裁功能、不改规格。10K LUT 与 125 MHz 的定稿依据为
`rnd-plan` R-W1 的 PDS 实测；若超出预算，再由协调者开收敛 Task，必要时由用户决定裁减。

### 5.5 R-R2 吞吐与回归

R-R2 RTL 和测试 commit 见文首；R-R1 对照为 `70f833d`。工具、125 MHz、R 连续返回、
B 固定延迟 5 拍且 AW 按 B 串行的条件与 5.2 相同；PERF0 包含命令抓取和最后 B。
每个测量都用原有整数参考模型比较所有目标像素和目标外字节；原有期望值保持不变。
原始日志：`build/rnd/r2/perf-r1.log`、`build/rnd/r2/perf-final.log`。

| 操作 | 像素 | R-R1 周期 | R-R2 周期 | R-R1 像素/拍 | R-R2 像素/拍 | 门槛 |
|---|---:|---:|---:|---:|---:|---:|
| I8→RGB565，256×240，1:1 | 61,440 | 624,669 | 31,465 | 0.098356 | **1.952646** | ≥1.5 |
| I8→RGB565，三倍到 768×720 | 552,960 | 5,559,549 | 278,441 | 0.099461 | **1.985914** | ≥1.5 |
| A8 GLYPH→ARGB8888，256×64 | 16,384 | 166,477 | 8,386 | 0.098416 | **1.953732** | ≥1.5 |
| 1000 条 A4 GLYPH→ARGB8888，每条 16×20 | 320,000 | 3,257,001 | 509,001 | 0.098250 | **0.628682** | 记录 |
| TILEMAP，16×16 I8 瓦片→RGB565，1280×720 | 921,600 | 10,444,749 | 675,177 | 0.088236 | **1.364975** | ≥1.0 |
| 圆角 FILL→ARGB8888，1024×512，r=16 | 524,288 | 5,769,261 | 263,387 | 0.090876 | **1.990561** | ≥1.5 |
| ARGB8888→ARGB8888 1:1 BLIT，1280×720 | 921,600 | 468,609 | 468,609 | 1.966672 | **1.966672** | ≥1.9 |

A4 的平均每条周期数为 R-R1 **3257.001**、R-R2 **509.001**，含每条命令的抓取和最终 B。
短字形只有每行 8 对像素，行加载、流水延迟和响应延迟占比高；没有把它标作长行稳态吞吐。
两种快速 FILL 保持 84,251 / 167,051 周期（RGB565 / ARGB8888），与 R-R1 相同。

采样前端在连续行片段驻留源 RAM 时每拍发射一对，跨 chunk 不等待已发射结果排空。
三倍 I8 测量还检查第 257 对输入早于前 256 对 alpha 结果全部返回，防止块边界重新引入等待。
源连续范围超过 16 KiB 的缩小采样使用四 beat 缓存，缺失等源数据，不再等 over。
目标首尾的单 lane、短行、命令/行间延迟均计入表中数值。

回归命令仍为 5.1 的四个算术/地址单元 smoke、full，以及 rnd_engine full，全部 `-j 1`、
每次 `--path` 一个目录、不使用 `--parallel`。四个单元的两个档位共 8 PASS；
rnd_engine 基础 137 案例和扩展 150 案例均 PASS。rnd_engine 没有 smoke 档用例，端到端归 full。
新增 full 场景覆盖跨 beat 的未对齐 RGB565/ARGB 源、两个 lane 最多四个分散源 beat、
未对齐调色板起点、跨 chunk 长行、带翻转的多 chunk TILEMAP，以及 GLYPH/I8 流水中 ABORT。
风格和顶层 `-Wall` lint 均为 0 告警；日志在 `build/rnd/r2/style.log`、`lint.log`、
`full-final.log`、`units-final.log`，各用例原始结果仍在 `build/regress/`。

R-R2 吞吐复现（先完成 rnd_engine full 构建）：

```sh
build/regress/full/unit/rnd_engine/full/verilator/obj/sim +PERF \
    > build/rnd/r2/perf-final.log 2>&1
```

R-R1 同工作负载复现：保留本版本 testbench，只替换父调度器和 draw 为 `70f833d`，
其余 RTL 与 R-R1 相同。`+R1_BASELINE` 仅停用新增的 R-R2 吞吐和调度判据，逐位参考比较仍启用。

```sh
python3 - <<'R1_BUILD'
import subprocess
import sys
from pathlib import Path
sys.path.insert(0, 'tools')
from regress import expand_files
out = Path('build/rnd/r2/baseline').resolve()
out.mkdir(parents=True, exist_ok=True)
names = ['edrv32_rnd.v', 'edrv32_rnd_draw.v']
for name in names:
    (out / name).write_bytes(subprocess.check_output(
        ['git', 'show', '70f833d:rtl/media/rnd/' + name]))
sources = expand_files(Path('verif/unit/rnd_engine/files.f'))
sources = [str(out / Path(f).name) if Path(f).name in names else f for f in sources]
(out / 'files.f').write_text('\n'.join(sources) + '\n')
R1_BUILD
verilator --binary --timing --top-module tb --Mdir "$PWD/build/rnd/r2/baseline/obj" \
    -o sim -j 1 -DSIM_MODE -f build/rnd/r2/baseline/files.f \
    > build/rnd/r2/baseline/compile.log 2>&1
build/rnd/r2/baseline/obj/sim +PERF +R1_BASELINE > build/rnd/r2/perf-r1.log 2>&1
```

### 5.6 R-R2 Yosys 和组合链对比

同 5.3 的 Yosys 0.70+219 / XC7、保留层次、技术 RAM 黑盒条件。这里仍为参考映射，
不是 PG2L200H 的 PDS 资源或纳秒时序；DSP48 不等同 Pango APM。

| 项 | R-R1 | R-R2 |
|---|---:|---:|
| 按实例累计 LUT，含 DMA、不含技术 RAM | 21,172 | **26,864** |
| 同上 FF | 5,430 | **7,876** |
| 同上 DSP48 | 94 | **162** |
| proc/opt 后按实例累计 `$mul` 站点 | 68 | **102** |
| draw 自身 LUT / FF / DSP48 | 4,374 / 1,394 / 14 | **8,315 / 3,840 / 36** |
| draw 内 address / source 实例 | 1 / 1 | **4 / 2** |
| 行 RAM / 调色板包装实例 | 5 / 2 | **17 / 6** |
| 逻辑 RAM 数据位 | 82 KiB | **278 KiB** |
| RAM/FF 切断的最长 `ltp` 算子数 | 29 | **28** |

增加来自双 lane 地址/颜色运算、五级 payload、四 beat 缩小采样缓存及同步读口副本。
alpha 算术 RTL 未改；标签由常量改成有效 bank/偏移后，其自身 LUT 从 746 变为 787。
顶层自身 LUT 从 1,931 变为 1,660，FF 仍为 886。其余模块自身映射数字不变。
本轮没有用功能裁减补偿资源增加；R-W1 后续 PDS 测量应使用 R-R2 的 RTL commit。

最长链仍在顶层状态/BUSY→SOFT_RST/cancel→写 DMA 握手→FILL 像素计数→PERF1，
没有新增更深的组合链。通用源地址与缓存命中/发射控制之间增加地址寄存级，
写 valid 选择按互斥执行器并列归并，避免把新增客户端串接到原来的优先选择链。
这是算子深度对比，不据此宣称 125 MHz 已收敛。

综合使用 5.3 的脚本，把输出目录/文件改为 `build/rnd/r2/operators.json`、
`resources.json` 和 `synth.log`；路径使用 5.4 的脚本，输出 `build/rnd/r2/path.log`。
本轮实际脚本为 `build/rnd/r2/synth.ys`、`path.ys`，全部输出仅留 build。

## 6. 状态

R-R2 完成通用像素路径流水化、R-R1 逐位回归、吞吐测量和参考综合；不宣称已取得 PDS 面积或时序结论。SoC 顶层接入与 Windows PDS 实测不在本 Task。
