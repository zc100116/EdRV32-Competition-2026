# 演示系统软件架构：协作式调度框架 + 单 ELF 资源打包

| 项 | 内容 |
|---|---|
| 日期 | 2026-11-02 |
| 状态 | 已决定（用户 2026-11-02 选 B；单 ELF 打包；先在卡 24 B3R 比特流上试验） |
| 关联 | SoC 规格 6.1、7.3、7.4；`sw/apps/s3`、`sw/apps/nes`、`sw/lib/virtual_input*`、`sw/lib/eth_monitor*`；卡 35/36 网口加载 |

## 1. 背景和问题

板测发现软件结构造成的性能浪费（用户 2026-11-02 指出）：

| 现象 | 根因（代码位置） |
|---|---|
| S3 静止界面 CPU 占用 60% 以上 | `sw/apps/s3/main.c` 的 `for(;;)` 不停调用 `lv_timer_handler()`，没有空闲等待；LVGL 以"handler 内时间 / 总时间"计 CPU（`lv_timer.c` 116–120 行），空转被计为忙 |
| 每帧整屏清 cache | `s3_lvgl.c` `flush()` 对 1280×720×2 = 1.8 MB 按地址清（约 5.7 万行），D$ 只有 32 KiB |
| 取时间代价大 | `tick()` → `s3_milliseconds()` 每次读 APB `CLK_SYS_HZ` 并做 64 位除法；LVGL 每帧调用多次 |
| 静止界面周期性重绘 | `LV_USE_PERF_MONITOR 1` 的标签定时刷新 |
| NES 显示 18 fps（模拟 54.5 fps） | `sw/apps/nes/display.c` 的状态机只在每个模拟帧调用一次 `display_poll()` 推进；渲染 → 完成 → 等 SWITCH → 空闲需约 3 次调用，54.5/3 ≈ 18 |

另外 S3、NES、demo、demo_vnpu 是各自独立的程序，演示时要反复加载，不符合"一个完整演示系统"的目标。

## 2. 约束

- 单核 RV32IM，无 MMU，无操作系统；SRAM 64 KiB，程序在 DDR 窗口 0x9000_0000 起 64 MB（`sw/bsp/ld/ddr_app.ld`）。
- 重计算在加速器上（NPU、RND、DISP、VIN、PIX、GEO），完成由 PLIC 中断通知。CPU 重活只有 LVGL 软件渲染和 NES 6502 模拟，两者不会同时运行。
- 没有 flash 启动（QSPI 控制器在 SoC v0.4 删除），每次上电由 BIOS 经网口或串口加载。
- 商业 NES ROM 不入库、不经过 Linux 构建机。
- CLAUDE.md 第 12 节：不加兜底、门禁、校验和。

## 3. 可选方案

| 方案 | 优点 | 缺点 |
|---|---|---|
| A 只用 LVGL 事件和定时器 | 改动最小 | NES、YOLO 这类按帧推进的工作塞进 LVGL 定时器很别扭；CPU 统计口径仍不真实 |
| **B 协作式调度框架 + 中断驱动外设** | 几百行；无上下文切换和锁；空闲 `wfi`，CPU 占用真实可测；每个任务的 CPU 时间可单独统计并展示 | 每个任务的 `step` 必须有时限，不能长时间占用 |
| C 抢占式 RTOS | 写法最自然 | 栈、上下文切换、LVGL 加锁、竞态调试；时间不够 |

## 4. 决策

采用 B；全部应用和资源打包为一个 ELF，一次加载到 DDR。

### 4.1 调度框架 `sw/lib/sched/`

```c
struct sched_task {
    const char *name;
    void (*step)(struct sched_task *task);  /* 运行一小段后返回，不阻塞 */
    uint8_t priority;                       /* 数值小优先 */
    volatile uint32_t events;               /* 中断置位，step 读取并清除 */
    uint64_t wake_at;                       /* mtime；UINT64_MAX 表示只由事件唤醒 */
    uint64_t busy_ticks;                    /* 累计运行时间，供 CPU 占用展示 */
};
void sched_add(struct sched_task *task);
void sched_signal(struct sched_task *task, uint32_t events);   /* 中断上下文可调用 */
void sched_wake_at(struct sched_task *task, uint64_t mtime);
uint32_t sched_take(struct sched_task *task);                  /* 原子取出并清零 events */
void sched_run(void);                                          /* 不返回 */
uint64_t sched_idle_ticks(void);
```

`sched_run` 循环：选出就绪（`events != 0` 或 `mtime >= wake_at`）且优先级最高的任务运行一次 `step`，记账运行时间；没有就绪任务时把 `mtimecmp` 设为最早的 `wake_at`，关中断检查后 `wfi`，醒来记账空闲时间。CPU 占用 = 1 − 空闲时间 / 总时间。

### 4.2 任务和应用

| 任务 | 优先级 | 唤醒 | 内容 |
|---|---|---|---|
| 通信服务 | 0 | UART/ETH 中断事件 | 虚拟按键、PEER、遥测；不做大计算 |
| 当前应用 | 1 | 应用自己的事件或定时 | 调用当前应用的 `step` |
| GUI | 2 | `lv_timer_handler()` 的返回值、输入事件 | LVGL；当前应用独占显示时不运行 |

应用描述符：

```c
struct app {
    const char *name;               /* UTF-8 中文名 */
    const lv_image_dsc_t *icon;
    uint32_t needs;                 /* APP_HW_RND / NPU / VIN / PIX / GEO / ETH 位 */
    uint8_t owns_display;           /* 1：运行时 GUI 任务暂停（如 NES） */
    void (*enter)(void);
    void (*step)(void);
    void (*exit)(void);             /* 释放显示层、外设，回到启动器 */
};
```

启动器（LVGL 主界面）按应用表列出图标，`needs` 中有硬件缺失的应用置灰。硬件存在性在启动时探测：读各媒体引擎的 ID 寄存器，缺失的槽返回 SLVERR，CPU 产生 load access fault（mcause 5）；探测期间的陷入处理只把该引擎记为缺失并跳过该指令，探测结束恢复正常陷入处理。

第一版应用（B3R 上可运行）：NES 游戏（游戏选择页 + 游戏）、LVGL 组件示例、LVGL benchmark、图层示例、系统状态（每个任务 CPU 占用、空闲率、帧率、网口/串口状态）。YOLO、图像处理在后续把 `sw/apps/demo` 的场景移植成应用后加入（不预留空应用）。

### 4.3 LVGL 部分的修改

1. GUI 任务：`step` 调用 `lv_timer_handler()`，返回值设为下一次 `wake_at`；输入中断或虚拟按键事件提前唤醒。
2. `flush`：只清本帧失效区域覆盖的行（DIRECT 模式下 LVGL 给出失效区域）；区域总量超过 D$ 容量时用 `cache_clean_all()`。
3. `tick`：启动时读一次 `CLK_SYS_HZ`，换算为乘法和移位（或 32 位除法），不做 64 位除法、不每次读 APB。
4. 性能监视默认关闭，由系统状态应用展示真实数据。
5. RND 绘制单元的异步完成（CPU 在等 RND 时做软件渲染）本轮不做，先测量本轮改动的效果。

### 4.4 NES 部分的修改

1. 模拟按帧推进：`step` 运行一帧后返回（修改 nofrendo 主循环为每次调用一帧，改动放进 `sw/apps/nes/patches/`）；帧率按 60 Hz 节拍限速，模拟慢于 60 fps 时不等待。
2. 显示状态机由 RND DONE 和 DISP SWITCH 中断推进，中断里只置事件和推进状态；`nes_display_frame` 只在空闲时提交，不再轮询。
3. 退出（KEY4 / 虚拟 ESC）：停 RND、等 DISP 空闲、恢复 GUI 显示层，回到游戏选择页。
4. ROM 从游戏包（4.5）读取，选择哪个游戏由游戏选择页决定。

### 4.5 资源打包

| 资源 | 方式 |
|---|---|
| 代码、LVGL、应用图标 | 正常链接进 ELF |
| 中文字体 | LVGL 自带 `lv_font_source_han_sans_sc_16_cjk`（及 14）；标题需要的 24/32 号用 `lv_font_conv` 从开源可商用字体（Noto Sans SC，OFL）按界面文字表生成子集 C 文件入库，命令和字体版本写进生成文件头 |
| NES 游戏、游戏图标 | **游戏包**：链接脚本在 DDR 程序窗口内保留一段固定地址 NOLOAD 区（`.game_pack`，容量 16 MB）。打包脚本 `tools/sw/pack_games.py`（Python 标准库）读取一个本地目录（ROM + 可选 PNG 图标 + 清单），生成包（头：magic、版本、游戏数；每项：名字、ROM 偏移/长度、图标偏移/尺寸），并把它作为一个新的 PT_LOAD 段写进 ELF，输出一个完整的 ELF。ROM 和最终 ELF 不入库，打包在 Windows 端用户本地目录执行 |

打包后的 ELF 由 BIOS 网口加载（卡 36 修复后的调试工具），串口 921600 为备用。

### 4.6 与现有程序的关系

新程序 `sw/apps/showcase/`。`sw/apps/s3`、`sw/apps/nes` 的可复用代码按 CLAUDE.md 第 2 节"复制到新位置、改写、评审"移入 showcase，旧程序在 showcase 上板验证通过后删除（避免两份代码长期并存）。

## 5. 影响

- 软件：新增 `sw/lib/sched/`、`sw/apps/showcase/`、`tools/sw/pack_games.py`；`sw/Makefile` 增加 showcase 目标。
- 规格：无硬件规格变化。SoC 规格 7.4 的 cache 维护接口不变。
- 测试：主机测试（调度器、游戏包解析、打包脚本往返）；SoC 级 `board_render` 冒烟用 showcase 启动到启动器。
- 上板：Windows 卡用卡 24 B3R 比特流，网口加载打包 ELF，测加载时间、空闲 CPU、benchmark、NES 显示帧率。

## 6. 状态

已决定。实现：T-SHOW-CORE（框架、启动器、LVGL 部分、系统状态）与 T-SHOW-NES（NES 应用、游戏包）并行，NES 由 CORE 集成。
