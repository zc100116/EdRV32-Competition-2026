# S3：LVGL 应用界面与平台游戏

S3 是一个 DDR 应用，启动后显示四项 LVGL 应用列表：游戏、widgets、benchmark 和
RN-17 自比对。游戏由同一个 ELF 内的入口启动，不包含 NES。
Linux 端只运行软件构建、主机图像和逻辑检查；HDMI、实际帧率和无撕裂结果待上板确认，
不运行完整 SoC 仿真。

## 构建与加载

在仓库根目录：

```sh
. ~/.local/opt/edrv32/env.sh
make -C sw PROGRAM=s3 MEMORY=ddr_app -j1
```

LVGL 从固定在 v9.6.0 的 `third_party/lvgl` 子模块直接编译，不修改子模块。
尚未检出的工作树先执行 `git submodule update --init third_party/lvgl`。
游戏资源由 `tools/s3/` 中的标准库 Python 脚本在构建时生成到 `build/`。
应用源码为 C11，使用 `-Wall -Wextra -Werror`。

在渲染板级顶层 `fpga/rtl/edrv32_fpga_board_render_top.v` 的 bitstream 上运行，
该 B3R 顶层包含 CPU、DDR、RND、DISP 和 ETH；S3 使用 RND/DISP，并在平台层初始化 ETH；WIN3 建立对端后以 100 Hz 采样 DDR，
每 16 条发送一批 EDTM，调试工具选择 B3R。
Windows 使用 BIOS 的 ELF 加载协议：

```sh
py tools/board/uart_tool.py build/sw/s3/s3.elf --elf --port COM3 --log build/board/s3.log
```

先启动工具，再按住 KEY1 复位。工具通过菜单 4 提速，依次通过菜单 2 加载 ELF 非空
PT_LOAD 段，通过菜单 3 跳转 ELF 入口。默认应用 CPU 入口为 0x90000000，物理地址
为 0x10000000。DDR 程序加载后直接运行；复位会重新从 SRAM 启动。
UART 继承 BIOS 选定的波特率。协议和波特率选项见
[`tools/board/README.md`](../../../tools/board/README.md)。

## 输入与应用切换

| 按键 | UART | 主界面 | 游戏 |
|---|---|---|---|
| KEY1 | `a` | 前一项 | 左移；暂停菜单切换选项 |
| KEY2 | `d` | 后一项 | 右移；暂停菜单切换选项 |
| KEY3 | `w` | 启动 | 跳跃；确认菜单；死亡/终点后重来 |
| KEY4 | `p` | 演示中返回 | 暂停/继续；死亡/终点后返回 |

GPIO bit0–3 为低有效按键。UART 每个字符产生一次同键输入，持续移动可重复发送。
暂停菜单可以继续或返回主界面。widgets/benchmark 中 KEY4 返回列表；benchmark
自然完成时先打印场景和平均帧率，仍可按 KEY4 返回。

主循环只在 LVGL 拥有显示时调用 `s3_lvgl_step()`。游戏入口停止 LVGL 刷新，停止 DISP
并等待 IDLE 后设置自己的 L0 地图、L1 双缓冲。退出游戏后恢复 LVGL 显示，关闭 L1，
L0 卷轴归零并使整个界面失效以重画。演示退出时删除演示自己的定时器和动画，保留
LVGL 框架定时器，避免 benchmark 后台继续换场景。

`s3_platform.c` 是唯一中断所有者：RND 使用 `rnd_irq_register()`，PLIC 源 11 分发到
`rnd_irq_handle()`；DISP 源 12 分发到媒体驱动，记录 FRAME 与两层 SWITCH。
两个应用均通过 `s3_rnd_run()` 等待中断完成，不分别注册处理函数。
主循环每轮只采样一次输入，再通过 `s3_lvgl_input()` 交给 LVGL 键盘设备，避免两个
读者相互消费 UART 字符。游戏运行期间由游戏独自采样输入。
RND 错误打印 `ERR_CODE`、`CUR_DESC` 后停止，DISP 错误打印 `ERR_CODE` 后停止。
没有超时、重试或错误后软件渲染替代路径。

`begin` 在停止 IDLE 后配置初始 Surface，等待初始 FRAME；DISP v0.3 的第一帧没有
SWITCH。后续 `present` 在最近 FRAME 后的提交窗口集中写入暂存卷轴和 L0/L1 NEXT_BASE，
等待每个提交层的 SWITCH 再返回。返回时已在新 FRAME，应用循环不额外等待一帧，
以便每个 FRAME 更新一次。只有同次提交之后尚未产生新 FRAME 时才先等待 FRAME。
LVGL 和游戏只写空闲的后缓冲，遵守 SoC 7.3 R3。

## DDR 与 cache

所有代码、字体、图像、瓦片、调色板、LVGL 内存池、Surface 和命令列表均由
`sw/bsp/ld/ddr_app.ld` 放在 64 MiB DDR 应用窗口，CPU 可缓存地址从 0x90000000 开始。
传给 RND/DISP 的地址用 `rnd_physical()` 转成 DDR 物理地址。
显示 Surface 基址 4 KiB 对齐、跨距为 32 B 的倍数，命令列表 64 B 对齐。

RND 提交前，驱动写回命令列表和声明的 CPU 源数据；需要读改写的 CPU 脏目标也必须
列入 sources。完成中断在所有写事务结束后作废 targets，再通知调用者，随后 CPU
软件绘制或逐像素比对才能读写这些像素。CPU 软件绘制完成后，下一次 RND 提交前
重新写回修改区域。所有维护均通过 BSP cache 接口。

LVGL 与游戏使用独立的静态分配，同时保留，切换时不动态分配 Surface，不复用彼此
的缓冲。资源数组为 DDR rodata；LVGL 内部对象及临时图层来自静态 DDR 内存池。

## 上板检查

- 主界面四项清晰、KEY/UART 选择与启动正确，LVGL 每秒输出
  `LVGL fps=<> rnd_tasks=<> sw_tasks=<>`。
- widgets 文字、圆角、渐变、阴影、图像和透明混合正确。
- benchmark 完成后保存每场景帧率与平均帧率；这是规格第 7 节待定指标的上板依据。
- RN-17 自比对保存全覆盖/边缘最大 LSB 差、>1 LSB 像素占比和五档分布，按定稿容差判定。
- 游戏四屏卷轴平滑、无撕裂，左右朝向和透明区正确，得分条正确，收集、死亡重来、
  终点和暂停继续/退出均正常。
- 保存每秒 `GAME fps=<> rnd_ms=<> cpu_ms=<>`，核对 60 fps 与实际 RND/CPU 开销。
- 在菜单、widgets、benchmark、自比对和游戏之间反复切换，确认 L1 关闭、L0 卷轴清零
  及 LVGL 整屏恢复正确，没有旧精灵、后台演示或图像残留。

板上检查结果尚未取得；主机模型执行时间不能作为硬件 RND 时间或上板 FPS。

## 游戏主机结果与估算

```sh
python3 tools/s3/game_check.py > build/s3/pm/game-check.log 2>&1
```

在本集成工作树通过：固定输入到达 x=4964、camera=3840、得分 2100，死亡后重来、
暂停冻结、地形碰撞、坠坑、甲虫碰撞和退出均 PASS。生产入口的 FRAME/SWITCH 桩通过
69 次交替翻页，峰值 111 条命令；桩输出的 60 fps 和 0.200 ms 是算术/接口验证数据，
不是板上性能。参考模型四批原始命令 4/49/48/59 条全部完成，旧精灵清透明、HFLIP、
I8 调色板 alpha、RGB565 颜色键和两段 TILEMAP 检查通过。

游戏使用静态 5120×720 RGB565 L0，stride=10240，SCROLL_X=0…3840；依据 DISP
15 位卷轴和 16 位跨距范围，整关一次画好，无需补画列。RND clip X 为 12 位，
初始化用两条重设目的指针的 2560×720 TILEMAP。L1 双缓冲逐缓冲清旧矩形，普通复用帧
59 条命令（11 COPY、5 BLIT、1 FILL、42 GLYPH），暂停峰值 111 条，存储容量 256 条。
资源生成与完整逻辑/性能计算见 [`game/README.md`](game/README.md)。

普通帧 RND **估算**为 0.331 ms（无等待）至 0.816 ms（用报告首拍延迟 40 周期组的
字形吞吐外推），依据 RND 规格第 7 节、125 MHz 和
[`RN-18 报告`](../../../docs/reports/2026-10-29-perf-rnd.md)：
`(88036/8 + 4864/1.5 + 66528/7.398250 + 13230/0.728928) / 125000` ms。
这些估算不含额外命令调度、cache、中断或共享 DDR 竞争，不能作为板上 60 fps 保证。

本工作树 PPM：`build/s3/game/game-frame.ppm`。已经人工查看模型合成画面：主角、琥珀、
尖刺、背景和得分条位置正确，透明区域没有覆盖背景，未见旧精灵残留。

## LVGL 绘制单元与 RN-17

配置为 `LV_OS_NONE`、RGB565、DIRECT 双缓冲，CLINT tick。DIRECT 的脏区同步通过
RND COPY 写入已释放的后缓冲，最终 flush 通过共享平台提交并等 SWITCH。
第三方源码 0 告警，没有按文件放宽 `-Werror`。

| 类型 | RND 认领范围 |
|---|---|
| FILL | 纯色、圆角、水平/竖直线性渐变；多 stops 拆成保留原 RECT 的 CLIP 色条 |
| BORDER | 圆角、宽度和四边选择 |
| LABEL / LETTER | fmt_txt 位图字体，零旋转/描边；LETTER 无缩放/skew、normal blend |
| IMAGE / LAYER | RGB565、ARGB8888 非预乘、I1/I2/I4/I8，最近邻缩放、四种 blend、recolor、单值 RGB565 颜色键 |
| A8 IMAGE | 1:1、normal blend，转 GLYPH |
| BOX_SHADOW | `bg_cover=1`、width≤62 |
| BLUR | radius≤31、corner_radius=0 |

旋转、skew、bitmap mask、圆角裁图、径向/锥形复杂渐变及 LINE/ARC/TRIANGLE/MASK/
VECTOR/3D 不认领；这些是正常的软件任务分配，不是 RND 出错后的替代路径。
每次 dispatch 执行一个 LVGL task，任务内最多 **32 条 RND 命令/门铃**，编译期常数
`S3_RND_BATCH_COMMANDS=32`。主机用值 32；板上尚未测量。文字按多个 GLYPH 批量提交，
图像回调在解码缓冲释放前完成提交。按类型打印 claimed/unclaimed，统计每秒实际任务数。

RN-17 主机已由 A 员工用真实 widgets 三帧和 benchmark 八场景完整执行：
本次按定稿判据重跑668批、2891条原始描述符、21168044个目标像素；软件参考由 LVGL 软件单元生成，
硬件侧描述符交 `rnd_ref.py` 执行。完整差异表、五档分布、源代码依据和条件见
[`lvgl/RN17_RESULTS.md`](lvgl/RN17_RESULTS.md)。本次重跑未改绘制算法。

用户已定稿的容差按 RGB565 的 R5/G6/B5 最低位计：全覆盖区每通道≤1 LSB，
全帧>1 LSB 的像素≤1%，边缘不设单像素上限。主机和板上的统计及 PASS/FAIL
均调用 `lvgl/rn17_compare.c` 的共用实现，不保留旧 8 位通道统计或判据。
本次11帧全部PASS，全覆盖区最大差均1 LSB，>1 LSB像素比例最大0.464844%。
初版超出开发初值的记录已改为历史说明，不保留旧判据的结果表。
LVGL 的 RGB565 通道内量化混合与 RND 的 RGB888 展开后混合不同，阴影算法也不同；
这些已检查的事实不构成对所有差异的逐任务归因。

```sh
python3 tools/s3/lvgl_host.py > build/s3/lvgl/build.log 2>&1
python3 tools/s3/rn17.py --no-build > build/s3/lvgl/rn17.log 2>&1
python3 tools/s3/menu_capture.py > build/s3/lvgl/menu-capture.log 2>&1
```

主机脚本只用 Python 标准库和主机 C 编译器。RN-17 的 22 张 SW/RND PPM、命令与原始日志
在 `build/s3/lvgl/`；菜单导出调用生产 `menu.c`，独立检查列表导航后输出真实 RND 合成帧。
主机和板上共用相同逐像素比较代码及边缘分类。主界面 RN-17 项运行板上同帧 SW/RND
自比对，并将全覆盖/边缘最大 LSB 差、>1 LSB 像素比例和五档 LSB 分布打印到 UART。

## 完整 ELF 与静态地址表

集成代码 `8b57684` 上执行上述统一 make 命令成功，编译和最终链接 **0 warning、0 error**，
未放宽第三方告警；日志 `build/s3/pm/rv32-build.log`，map 为 `build/sw/s3/s3.map`。
xPack GCC 15.2.0，RV32IM_Zicsr / ilp32，C11、`-O2 -Wall -Wextra -Werror`。

| text（含只读常量） | data | bss | 合计（不含运行期栈） |
|---:|---:|---:|---:|
| 1119800 B | 1408 B | 53206720 B | 54327928 B（51.811 MiB） |

以下来自最终 ELF 的 `nm -S -n`，单位均为字节。物理地址为 CPU 地址减 0x80000000。
所有对象启动时已保留；游戏和 LVGL 不复用这些存储。

| 对象 | CPU 地址 | DDR 物理地址 | 字节 |
|---|---|---|---:|
| 代码 `.text` | 0x90000000 | 0x10000000 | 595192 |
| `.rodata`：字体、图像、游戏资源等 | 0x90091500 | 0x10091500 | 524608 |
| LVGL 静态 TLSF 堆 | 0x90112610 | 0x10112610 | 25165824 |
| 脏区 COPY 命令 | 0x91912640 | 0x11912640 | 64 |
| 阴影/模糊临时区 | 0x91912840 | 0x11912840 | 6291456 |
| 字形批内 staging | 0x91f12840 | 0x11f12840 | 524288 |
| LVGL RND 命令表 | 0x91f92840 | 0x11f92840 | 2048 |
| RN-17 SW 参考图 | 0x91f93140 | 0x11f93140 | 1843200 |
| LVGL L0 buffer0 | 0x92156000 | 0x12156000 | 1843200 |
| LVGL L0 buffer1 | 0x92318000 | 0x12318000 | 1843200 |
| RN-17 边缘分类 | 0x924da004 | 0x124da004 | 921600 |
| 游戏 RND 命令表 | 0x925bb280 | 0x125bb280 | 16384 |
| 游戏 L1 buffer0 | 0x925c0000 | 0x125c0000 | 3686400 |
| 游戏 L1 buffer1 | 0x92944000 | 0x12944000 | 3686400 |
| 游戏 L0 整关 | 0x92cc8000 | 0x12cc8000 | 7372800 |

游戏资源的 CPU 地址：glyphs=0x901062e0、RGB565 尖刺=0x90109080、I8 精灵=0x90109380、
map=0x90109c80、tiles=0x90110d00、palette=0x90111500，均属于上表 DDR rodata。
`.data` VMA 为 0x90111bc0，加载镜像 LMA 为 0x90111640，由通用启动代码恢复。
BSS 末端 0x933d0000，栈顶 0x94000000，之间剩余 12779520 B；这是地址空间余量，
不是运行期栈深度测量。

## 集成主机验收与交付

本分支重新构建主机共享库：510 个 C 源文件，C11 `-Wall -Wextra -Werror`，0 告警。
`python3 tools/s3/menu_capture.py` PASS：检查选择回绕和启动编号，调用生产 `menu.c`，
执行真实 RND 命令并输出 `build/s3/lvgl/menu-rnd.ppm`。本帧 484 条命令、1693643 个
处理像素。已经人工查看：四应用卡片、选中框、标题和 KEY/UART 提示完整，没有裁切或残影。
同时查看了 widgets 的 RND PPM，界面、文字、图像和布局正常；像素差异仍按 RN-17 表报告。

主界面完整首帧 RND **估算**（不是上板测量）：6 FILL、4 BORDER、474 GLYPH；
快速填充 921600 像素、其余 alpha 操作 701066 像素、字形 70977 像素。
沿用前述 RN-18 实测快速填充吞吐 14.543159 px/cycle、规格 BLIT 初值 1.5 px/cycle
外推圆角/边框，以及 A4 字形吞吐外推 A8：

```text
T = (921600/14.543159 + 701066/1.5 + 70977/0.728928) / 125000
  = 5.025 ms（估算，无等待；以 40-cycle 字形组外推为 7.624 ms）
```

不含额外命令调度、CPU 翻译、cache、中断、软件未认领任务和 SWITCH 等待；A4→A8、
BLIT→圆角/边框均为外推。静态菜单空闲时不会持续重画整个首帧。
逐操作像素统计在 `build/s3/lvgl/menu-estimate.txt`，原始描述符为 `menu.commands.bin`。

| 验收 | 命令/证据 | 结果 |
|---|---|---|
| 完整 DDR 程序 | `make -C sw PROGRAM=s3 MEMORY=ddr_app -j1` | PASS，0 告警 |
| 主机 LVGL 构建 | `python3 tools/s3/lvgl_host.py` | PASS，510 源文件，0 告警 |
| RN-17 演示逐像素比对 | `python3 tools/s3/rn17.py --no-build` | 定稿 LSB 判据下11帧全部PASS，最多0.464844%像素>1 LSB |
| 生产菜单与 RND PPM | `python3 tools/s3/menu_capture.py` | PASS，PPM 已人工确认 |
| 游戏逻辑/入口/参考合成 | `python3 tools/s3/game_check.py` | PASS，PPM 已人工确认 |
| Python 语法、C/Python 行风格、提交差异 | AST parse、`git diff --check` | PASS |
| Verilog lint / SoC 仿真 | 本任务无 RTL 改动，不运行 | 不适用 |
| 真实板上功能/帧率/一致性 | 前述上板清单 | 尚未取得 |

本集成工作树的主要产物绝对路径：

- ELF：`/home/workspace/orca/workspaces/EdRV32-Competition-2026/task-b3-s3/build/sw/s3/s3.elf`
- 主界面 PPM：`/home/workspace/orca/workspaces/EdRV32-Competition-2026/task-b3-s3/build/s3/lvgl/menu-rnd.ppm`
- 游戏 PPM：`/home/workspace/orca/workspaces/EdRV32-Competition-2026/task-b3-s3/build/s3/game/game-frame.ppm`
- RN-17 表与日志：本工作树 `build/s3/lvgl/rn17-results.md`、`rn17-lsb.log`（A3 按定稿判据重跑）
- 集成构建/游戏日志：`build/s3/pm/rv32-build.log`、`game-check.log`；菜单日志：`build/s3/lvgl/menu-capture.log`

员工任务由本项目经理拆分，Orca 运行时拒绝深度 2（设置最大 1）后，由协调者按原任务卡
代派 A/B，均从本分支 `afee031` 拉出独立 worktree；已核对启动回执 `launch.effective`
为 Codex `gpt-6.1-sol` / `high`。A/B 并行开发；重构建串行，A 完成后许可移交本分支。
C 由项目经理依协调者回复实现，审核 A/B 后在本分支 cherry-pick 集成。

| 分工 | 员工提交 | 本分支集成提交 |
|---|---|---|
| A：LVGL 配置/API、绘制单元/显示/RN-17、主机工具、结果 | `546be8a`、`146b4fd`、`76e0513`、`e45a150` | `2d678b8`、`e2bd886`、`cf67e84`、`8b57684` |
| B：游戏、生成资源、逻辑/模型验证、文档 | `5b03b02`、`97de803` | `00d7134`、`733fc71` |
| C：共享平台、主界面、构建登记、主界面 PPM、集成文档 | 本分支项目经理 | 从 `afee031` 起的 `s3:` / `tools:` 集成提交 |

修改归属：`sw/Makefile` 仅登记 `s3`；新增 `sw/apps/s3/` 根目录的
`main.c`、`menu.c/h`、`s3_platform.c/h`、`program.mk`、本 README；
`game/` 的逻辑、绘制、入口、头文件、构建片段、README；
`lvgl/` 的配置、绘制单元、服务、freestanding 支持、RN-17 统计、构建片段和报告；
`tools/s3/` 的游戏资源/检查/host C 桩、LVGL 资源/host/target/RN-17 工具和生产菜单捕获。
没有修改 `third_party/`、驱动、BSP、BIOS、NES、RTL、规格、testplan、FPGA 或 verif。
