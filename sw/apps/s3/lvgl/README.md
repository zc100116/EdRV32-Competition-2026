# S3 LVGL v9.6.0 / RND fragment

本目录是一个 DDR S3 程序里的 LVGL 服务，没有独立 `main`，没有 NES 入口。
依据 design rnd-disp 4.2/4.3、rnd-spec v0.2 2/5.4、DISP v0.3 5.3、RN-17。
`third_party/lvgl` 使用原始 v9.6.0 (`80ca777e37a2b176770726a02e07a6fb79ef0b39`)，
没有修改子模块源码，没有第三方告警豁免。

## 接入主程序

主程序的 `program.mk` 在设置自身 `PROGRAM_SOURCES` 后 include 本目录 `program.mk`。
调用方提供 `s3_platform.h` 的实现和 `sw/drivers/rnd.c`，包含驱动/BSP 头目录。
构建入口为 `make -C sw PROGRAM=s3 MEMORY=ddr_app -j1`，由项目经理完成最终集成。
本片段自行加入 LVGL、widgets/benchmark、绘制单元、RN-17、生成图像和 freestanding 支持。
`PROGRAM_LDLIBS` 必须保留 `--wrap=lv_draw_sw_blend`；这个包装只观察 RN-17 的 AA mask，
正常绘制仍直接调用 LVGL 原始 blend。`freestanding.c` 提供目标构建实际缺少的 `memset`，
不需要 libc 堆或 libm；libgcc 由统一软件 Makefile 链接。

公共接口见 `s3_lvgl.h`：

| 函数 | 调用约定 |
|---|---|
| `s3_lvgl_init()` | 平台初始化后调用一次；建立显示、按键设备、默认 group 和绘制单元 |
| `s3_lvgl_display()` | 给 C 的主界面使用的 LVGL display；主界面直接用 LVGL 建立 |
| `s3_lvgl_input(keys)` | 主循环每轮唯一一次 `s3_input()` 的结果；LVGL 不再次消费 UART |
| `s3_lvgl_step()` | 主循环持续调用；`lv_timer_handler`，每秒输出 fps/rnd_tasks/sw_tasks |
| `s3_lvgl_restore_display()` | 从游戏返回时重新接管 L0、关闭 L1、整屏失效并立即重画 |
| `s3_lvgl_start_widgets()` | 清理当前内容，启动真正的 `lv_demo_widgets` |
| `s3_lvgl_start_benchmark()` | 启动真正的 `lv_demo_benchmark`；结束打印每场景/平均 FPS |
| `s3_lvgl_stop_demo()` | 返回菜单前调用，清理 screen/top、演示定时器和动画 |
| `s3_lvgl_self_compare()` | 当前界面同一时刻先 SW、后 RND，CPU 比较并打印 RN-17 统计 |
| `s3_lvgl_set_rnd(bool)` | RN-17/测量切换；不是错误后的软件回退 |

暂停就是主循环不再调用 `step`；恢复先调用 `restore_display`，再继续调用 `step`。
`s3_display_begin` 的平台契约负责停止/IDLE、L0 初始 FRAME、关闭 L1 和卷轴归零。
`flush` 使用 `s3_display_present` 等待 SWITCH，主循环不用再额外 `s3_wait_frame`。
演示清理先删除对象，让 widget 析构回收其定时器，再删除启动后剩余的演示定时器；
保留启动前的显示刷新、输入、sysmon 和应用定时器。benchmark 的 scene timer 因而不会覆盖菜单。

`s3_lvgl_mark` 是可选菜单图像符号（`LV_IMAGE_DECLARE(s3_lvgl_mark)`），
由 `tools/s3/lvgl_assets.py` 生成原创 64×64 RGB565 C 数组，输出仅在 `build/s3/`。
演示使用锁定 LVGL 子模块自带资源；许可原文见其 `LICENCE.txt`、`COPYRIGHTS.md` 和字体文件头。
没有下载其他图片、字体或游戏素材。

## 显示、内存与 cache

使用 L0 RGB565 1280×720 **DIRECT 双缓冲**，跨距 2560 B。
DIRECT 保留 LVGL 的脏区调度；v9.6 的 `sync_cb` 用 RND COPY 将上一帧必要脏区同步到
已经释放的绘制缓冲，不进行正常运行的全帧复制。`flush_cb` 最后一次 flush 才 clean 并提交，
同步等待 SWITCH 后调用 `lv_display_flush_ready`，LVGL 才能复用旧扫描缓冲。
首次扫描 buffer1，首次绘制 buffer0。RN-17 显式停止显示后离线重画两次，结束再启用显示。

DDR app 链接窗口：CPU `0x90000000` / 物理 `0x10000000`，64 MiB。
所有代码、常量字体/图像、静态对象和 LVGL 内置堆都随整个 app 链接在该 DDR 窗口，
没有 SRAM 资源、系统 `malloc`、运行期新增池或绝对地址分配。
最终绝对地址以 C 集成 ELF/map 为准；本片段不给共享应用硬编码地址。

| 静态对象 | 字节 | 对齐/用途 |
|---|---:|---|
| LVGL `work_mem_int` | 25165824 | 内置静态 TLSF 池（24 MiB） |
| `buffers` | 3686400 | 每块 4 KiB 对齐；两块各 1843200 B，扫描/绘制交换 |
| `reference` | 1843200 | 64 B；RN-17 保存 SW 图像 |
| `edges` | 921600 | 每像素 1 B；RN-17 coverage 并集 |
| `temporary` | 6291456 | 64 B；仅 RND 阴影/模糊暂存 |
| `glyphs` | 524288 | 64 B；逐字形的批内 A8 数据副本 |
| `commands` | 2048 | 64 B；32 条 × 64 B |
| COPY descriptor | 64 | 64 B；脏区同步 |
| 原创 mark 像素 | 8192 | 64 B；DDR 常量 |

上述主缓冲/池合计约 36.66 MiB，另加 LVGL 的小状态、字体/图像常量、程序和栈。
LVGL 的临时 draw buffers、解码结果均从这一个 DDR 静态池分配。
RND 专用 scratch 初始化时通过 BSP `cache_clean_invalidate` 交给硬件，之后 CPU 不访问其内容。

cache 交替规则（rnd 5.4 / SoC 7.4）：

1. CPU 对目标的写入在 RND RMW 前 clean：目标涉及的完整行作为 batch source。
2. 命令、CPU 准备的 glyph/image/palette source 交给统一驱动 clean，然后 `s3_rnd_run(batch)`。
3. 共享 DONE IRQ 确认所有写响应结束，统一驱动 invalidate batch target，返回后通知 LVGL 任务完成。
4. CPU 软件绘制单元随后可读写这些 cache 行；下一次 RND 再执行第 1 步。
5. 目标范围按整行交接，避免部分 cache 行 invalidate 丢弃邻近 CPU 脏像素。
6. 展示前 clean 整个 Surface；扫描期间仅作为 COPY 源，不作 RND 目标。

## 认领范围与批量

硬件单元 ID=2，score=50；SW=1，score=100。每次 dispatch 同步执行一个 LVGL task，
任务内最多批量 **32 条命令/门铃**（`S3_RND_BATCH_COMMANDS`，主机和板上相同）。
LABEL 的多个 glyph 共用批次；容量满时提交并等共享 IRQ。图像解码回调结束前提交，
以保证解码源在释放前完成读取。没有另行注册 RND IRQ，没有完成轮询或软件重做路径。

| LVGL task | 认领参数 / 翻译 |
|---|---|
| FILL | 无渐变、水平/竖直线性渐变、圆角；常见双端点用 Q16 FILL；一般 stops 分成保留原圆角 RECT 的逐像素 CLIP 色条 |
| BORDER | 四边选择、宽度、圆角，LVGL top/bottom 位换成 RND 定义 |
| LABEL / LETTER | 配置的 fmt_txt 位图字体，零旋转/描边；LETTER 还要求无缩放/skew、normal blend |
| IMAGE / LAYER | RGB565、非预乘 ARGB8888、I1/I2/I4/I8；无旋转/skew/圆角裁图/bitmap mask；最近邻缩放、四种 blend、recolor、单一 RGB565 colorkey |
| A8 IMAGE | 1:1、normal blend，用 GLYPH 着色 |
| BOX_SHADOW | `bg_cover=1`、width≤62；RND 不具备透明背景所需的逆圆角切除，因此该参数不认领 |
| BLUR | radius≤31、corner_radius=0；硬件两遍盒滤波，算法与 LVGL IIR 不同 |

LINE、ARC、TRIANGLE、MASK、VECTOR、3D、径向/锥形/任意方向复杂渐变，以及表中
超出硬件参数的任务，由 LVGL 正常分给 SW，并按类型累计未认领数。
不通过限制实际演示或变更测试容差来隐藏差异。

v9.6 LABEL 使用 `lv_draw_label_iterate_characters`，回调收到 glyph descriptor 后还需调用
`lv_font_get_glyph_bitmap_internal(g, _draw_buf)` 取得 A8 draw buffer。
这个 buffer 会被下一 glyph 改写并在 iterator 结束时释放，因此先复制到静态批次 staging；
不能把字体 glyph_data 当作持久源。LETTER 使用同一回调和 `lv_draw_unit_draw_letter`。
`lv_color_to_u32` 带 FF alpha，进入 RND 的 COLOR/RC_COLOR 前显式截成 RGB888，OPA 单独编码。

`s3_draw_rnd_print_stats` 输出累计每类型 claimed/unclaimed 和 commands/doorbells。
RN-17 另输出该帧 RND 渲染的增量，SW 参考渲染的任务数不混入该帧 RND/SW 统计。

## RN-17 复现和上板

```sh
git submodule update --init third_party/lvgl
python3 tools/s3/lvgl_host.py
python3 tools/s3/rn17.py --no-build > build/s3/lvgl/rn17.log 2>&1
. ~/.local/opt/edrv32/env.sh
python3 tools/s3/lvgl_target.py > build/s3/lvgl/target-build.log 2>&1
git diff --check
```

编译均单线程；`lvgl_target.py` 只做 RV32 片段编译和可重定位链接，不创建另一个主程序。
完整程序按前述统一 S3 make 入口由 C 集成。源清单以 `program.mk` 为准。
主机 GCC 13.3、目标 xPack GCC 15.2，C11 `-O2 -Wall -Wextra -Werror -ffreestanding -fno-builtin`；
相同 `lv_conf.h`、分辨率、缓存交接和 batch=32，没有告警豁免。

runner 运行真实 widgets 的 16/176/656 ms 三帧和 benchmark 的八个场景，
不是手写 RND 场景。每个 compare 冻结 CLINT 对应毫秒时间和动画，分别整屏重画 SW/RND。
Linux 桩把绘制单元产生的原始 64 B descriptors 和 CPU source 字节交给仓库
`verif/block/rnd/rnd_ref.py` 的 `execute`，再回写实际目标内存；不在主机调用 SW 代替 RND。
host stub 同时检查 batch target 与当前扫描 Surface 不重叠。
最后运行真正 benchmark 的结束回调，再验证两次 benchmark → stop → menu，越过下一场景期限
后菜单仍未被覆盖。主界面的最终 PPM 由 C 集成时生成。

输出 `build/s3/lvgl/`：`*-sw.ppm` / `*-rnd.ppm`（1280×720）、各帧真实
`*.commands.bin`、`rn17-results.md` 和 UART 风格日志。生成物均不入库。
RND Python 模型直接读取批次 source；需要重现源数据时重新运行 runner，源数据没有另外伪造。

统计按 RGB565 展开后的 RGB888 通道做比较，主机/板上共用同一 C 实现。
按协调者确认的规则，边缘是 SW 非255 AA mask 与 RND FILL/BORDER/GLYPH 非255覆盖率的并集，
BOX_SHADOW 模糊区域整体归边缘；其余为全覆盖区。
每帧打印 max_rgb、full_max、edge_max、>3 像素数/百万分比、五档差异分布、该帧认领/未认领数。
分布区间为 0–3、4–8、9–16、17–48、49–255（按像素的最大通道差）。
原始判据保持 full≤3、edge≤48、>3像素≤1%，超出时打印 FAIL，runner 返回 1。
**初值超限必须保留并报告，不自动放宽容差。** 实测表见同目录 `RN17_RESULTS.md`。

板上在想检查的 widgets/benchmark 帧调用 `s3_lvgl_self_compare()`，输入/动画暂停在同一时刻，
显示停止后 SW/RND 各重画一次，用 CPU 输出相同统计；随后恢复 RND 开关原值和 L0 显示。
RND 错误由共享平台打印 ERR_CODE/CUR_DESC 后停止，服务不改用 SW。
KEY1/2 对应 group PREV/NEXT，KEY3 ENTER，KEY4 ESC；输入快照由主循环提供。

## 性能估算边界

batch=32 是本次可复现开发常数，仍需上板以真实 DDR/CPU/cache/IRQ 开销定稿。
125 MHz RND 输入参数来自 `docs/reports/2026-10-29-perf-rnd.md`：
RGB565 全屏 FILL 63370 cycles（0.506960 ms），ARGB 全屏 FILL 124570 cycles，
ARGB BLIT 1.958659 px/cycle；16×20 A4 glyph 平均 439.001 cycles（无读延迟）/
1904.001 cycles（40-cycle 首拍读延迟）。本移植使用 A8 glyph，不能将 A4 数字称为 A8 实测。
估算时分别统计 fast fill 像素、alpha 像素、COPY 字节和门铃次数，再加 CPU 翻译、
cache clean/invalidate、SW 未认领任务、DONE IRQ、SWITCH 等待；这些软件/板级项尚无实测值。
Python 模型运行时间、人工推进 host tick 的 FPS 都不是板上性能结果。
待上板：真正 RND 的 RN-17 同帧结果、benchmark 各场景/平均 FPS、每秒统计、
SWITCH/FRAME/输入实机行为、最终 ELF 地址/栈及其他 S3 功能共存的 DDR 占用。
