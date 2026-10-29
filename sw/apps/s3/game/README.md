# Amber Run — B3-3b 游戏片段与验收报告

实现提交：`5b03b02`。目标是 S3 DDR 程序中的一个可调用游戏：
`#include "game/game.h"` 后调用 `s3_game_run()`，退出时返回主界面调用者。
本目录不提供独立启动程序或 NES 入口。

根 `sw/apps/s3/program.mk` 初始化 `PROGRAM_SOURCES` 后包含：

```make
include $(ROOT)/sw/apps/s3/game/program.mk
```

完整链接由集成员工执行 `make -C sw PROGRAM=s3 MEMORY=ddr_app -j1`。
本员工只执行了下述轻量主机验收，没有进行完整 RISC-V 链接、SoC 仿真或上板。

## 内容与操作

一关 5120×720，正好四个 1280×720 屏幕。主角有走、跳、重力和逐像素分轴地形碰撞；
关卡包含两处深坑、一处高台、两组尖刺、两只往返巡逻甲虫、12 枚琥珀及终点旗杆。
琥珀加 100 分，踩甲虫加 200 分并弹跳，过终点加 1000 分；碰尖刺、侧碰甲虫或坠坑死亡。
死亡后可重来，关卡和计分重新开始，累计死亡数保留。暂停时物理、敌人和逻辑帧计数冻结。

| 按键 | UART | 游戏中 | 暂停菜单 |
|---|---|---|---|
| KEY1，bit0 | a | 左移 | 切换选项 |
| KEY2，bit1 | d | 右移 | 切换选项 |
| KEY3，bit2 | w | 起跳；死亡/胜利后重来 | 确认选中的继续或返回界面 |
| KEY4，bit3 | p | 暂停；死亡/胜利后返回界面 | 继续 |

输入由共享 `s3_input()` 提供，GPIO 长按可连续移动；串口按键的持续时间由平台统一处理。
跳跃、暂停和菜单确认按按下沿触发。画面顶部及暂停/结算卡也显示操作提示。

## 绘制、卷轴和所有权

依据 [DISP v0.3](../../../../docs/spec/disp-spec.md) 4.2，SCROLL_X 为 15 位，
跨距为 16 位且是 32 B 的倍数。整关跨距 10240 B，横向卷轴范围 0…3840，
在这些限制内，因此整关一次 TILEMAP 绘制，滚动只提交 SCROLL_X，不需要增量列更新。
L0 占 7,372,800 B；扫描窗口最后一列的读取也在已分配的完整行内。

RND 的 CLIP_X 只有 12 位，不能把 5120 像素宽的目标直接写成一条命令。
初始化用两条 2560×720 TILEMAP，第二条目标指针右移 5120 B、MAP_X=2560，
两条仍使用同一 Surface 的 10240 B 跨距；两个 clip 都是 0…2559。
地图、瓦片和初始整关都是真实资源，主机验收执行这两条原始描述符。

L1 是两块 1280×720 ARGB8888 Surface，共 7,372,800 B。
每块独立保存上次画过的矩形；复用时先 COPY 透明零行清掉这些矩形，再 BLIT 精灵和 GLYPH 字形。
零行 COPY 的源 stride=0，重复读取同一行；FILL OPA=0 不会清除旧像素，故未用于清透明。
主角、甲虫和琥珀采用 I8 加 ARGB 调色板 alpha；左向精灵使用 HFLIP。
尖刺使用 RGB565 加颜色键 `0xf81f`，两种透明机制均在参考模型合成图中出现。
字形是本项目生成的 15×21 A8 像素字体，包含得分数字和菜单英文。

所有 Surface 均 4096 B 对齐，命令表 64 B 对齐，资源和零行 32 B 对齐。
代码没有堆分配；Surface、命令及资源为静态对象，由 `ddr_app` 放入 DDR。
源数组在 CPU 0x90000000 开始的 DDR 应用区内，`rnd_physical()` 换为物理 0x10000000 区间。
两块 L1 和 L0 共约 14.06 MiB，另有约 72 KiB 的资源、零行、命令表及记录，适配 64 MiB 应用区。

缓存操作全部通过 `rnd_batch` 的 sources/targets 交给共享 `s3_rnd_run()`；
初始化声明 CPU 初始化过的全部目标也是 source，之后 CPU 不再写 Surface。
每批仅通过平台共享 RND 完成中断执行；RND 错误按平台契约打印 ERR_CODE/CUR_DESC 后停止。

每帧顺序是逻辑 → 后缓冲 RND → `s3_display_scroll()` 暂存卷轴 →
`s3_display_present(NULL, 0, back, 5120)`。平台在 FRAME 后一起提交 scroll 和 L1 基址，
等待 SWITCH 后返回；此时旧前缓冲才能重新绘制，满足 SoC 7.3 R3 和 DISP 5.3。
`present` 自身已经提供 60 Hz FRAME 节奏，循环不再额外 `s3_wait_frame()`。
入口先停 DISP 并等待 IDLE，初始化后开始扫描；退出也停稳再交回主界面。
接口 `void s3_display_scroll(uint16_t x, uint16_t y)` 已由协调者确认，须由平台所有者实现。

每秒打印 `GAME fps=<值> rnd_ms=<值> cpu_ms=<值>`，时间保留三位小数。
RND 时间覆盖 `s3_rnd_run()` 的提交、缓存维护和中断等待；CPU 时间覆盖逻辑及构造命令，
不包含等待 DISP SWITCH 的时间。计时来自平台 CLINT ticks 和频率接口。

## 主机验收与性能估算

仓库根执行：

```sh
mkdir -p build/s3/game
python3 tools/s3/game_check.py > build/s3/game/check.log 2>&1
cc -std=c11 -Wall -Wextra -Werror -O2 \
  -Isw/drivers/include -Isw/bsp/include -Ibuild/s3/game -fsyntax-only \
  sw/apps/s3/game/game_logic.c sw/apps/s3/game/game_render.c sw/apps/s3/game/game.c
git diff --check
```

上述命令通过。主机 C 编译均为 C11、`-Wall -Wextra -Werror`；Python AST 语法检查通过，
所属 C/Python 源码无 Tab、非注释代码行不超过 100 列。没有修改 RTL，Verilog lint 不适用。
资源由 `tools/s3/game_assets.py` 仅用 Python 标准库生成；全部美术和字体是本项目原创像素画，
C 数组、二进制快照、描述符和 PPM 仅输出到 `build/s3/game/`，不入库。

固定通关输入：从 reset 开始，1…840 帧持续 RIGHT，仅在
92、208、324、436、539、642、724 帧叠加 JUMP。生产逻辑到达 x=4964 的终点，
得分 2100，camera=3840；测试未传送，也未直接改写生产状态。
其他固定输入分别验证尖刺死亡（x=692）、重来及死亡数保留、暂停冻结、左右边界/高台碰撞、
深坑坠亡、甲虫侧碰死亡、胜利返回及暂停选择返回。
生产入口另用 FRAME/SWITCH 桩跑 69 次翻页，校验双缓冲交替、扫描 Surface 不被写和退出停稳。
桩固定每批耗时 0.200 ms，得到 `GAME fps=60 rnd_ms=0.200 cpu_ms=0.000`；
这是计时格式/算术验收，**不是硬件性能实测**。

`rnd_ref.py` 执行生产渲染器调用真实驱动编码器得到的全部原始描述符：

| 批次 | 内容 | 命令数 | 处理像素数 |
|---|---|---:|---:|
| 0 | 初始化两段 L0 TILEMAP 和两块 L1 清零 | 4 | 5,529,600 |
| 1 | 初始 L1 buffer0 | 49 | 85,390 |
| 2 | L1 buffer1 | 48 | 84,622 |
| 3 | 复用 buffer0，含清旧矩形和 HFLIP | 59 | 172,658 |

全部批次完成且 ERROR=0，旧主角位置变为 alpha=0，最后按 DISP 2.7 合成 1280×720 PPM。
参考截图可见 I8 主角/琥珀、RGB565 颜色键尖刺、字形得分和背景。
入口/暂停桩测到最大 111 条命令；命令存储容量为 256 条。

普通复用帧的 59 条命令为 11 COPY、5 BLIT、1 FILL、42 GLYPH；各自像素数为
88036、4864、66528、13230。以下是**估算**，没有测量 TILEMAP/I8 小精灵硬件吞吐：
依据 [RND spec 7](../../../../docs/spec/rnd-spec.md) 的 125 MHz、BLIT 1.5 像素/拍初值，
及 [RN-18 报告](../../../../docs/reports/2026-10-29-perf-rnd.md) 的 FILL 7.398250、
GLYPH 0.728928 像素/拍无等待读取数据，将 COPY 取快速通路 8 像素/拍，则

```text
T = (88036/8 + 4864/1.5 + 66528/7.398250 + 13230/0.728928) / 125000
  = 0.331 ms / 帧（估算，无等待）
```

把字形吞吐替换为报告的首拍延迟 40 周期组 0.168067 像素/拍，得 0.816 ms/帧估算。
COPY 吞吐和小尺寸 I8 BLIT 是从通路指标外推；上述数字不含额外命令、缓存维护、
共享 DDR 竞争和中断开销，不是板上保证。暂停卡的命令量另见 111 条主机记录。

本 worktree 的证据绝对路径：

- 日志：`/home/workspace/orca/workspaces/EdRV32-Competition-2026/task-b3-s3-game/build/s3/game/check.log`
- PPM：`/home/workspace/orca/workspaces/EdRV32-Competition-2026/task-b3-s3-game/build/s3/game/game-frame.ppm`
- 逐批统计：`/home/workspace/orca/workspaces/EdRV32-Competition-2026/task-b3-s3-game/build/s3/game/render-stats.txt`
- 实际命令：同目录 `batch0.cmd`…`batch3.cmd`；内存初态为 `memory.bin`。

待集成/上板：根 S3 make include、LVGL 游戏按钮与返回重绘、共享 scroll 接口、完整 DDR 链接；
板上 KEY/UART、60 Hz FRAME/SWITCH、RND 缓存一致性、DISP 读空计数、实际 fps/rnd_ms/cpu_ms。
本员工没有测量或声称这些上板项目通过。

修改文件：`sw/apps/s3/game/{game.h,game.c,game_logic.h,game_logic.c,game_render.h,game_render.c,program.mk,README.md}`；
`tools/s3/{game_assets.py,game_check.py,game_host.c,game_loop_host.c}`。
