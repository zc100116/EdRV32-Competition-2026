# Showcase smooth P1

- 固件代码：`208b78c46`，已 rebase 到 `origin/zc100116/b3`（`2f785b7dd`）。
- 工具：xPack RISC-V GCC 15.2.0；主机 GCC 13.3.0 / UBSan；C11 `-Wall -Wextra -Werror`。
- 器件/速度等级：本次为主机构建和测试，不涉及 FPGA 时序测量；未上板、未跑 SoC 仿真。
- 对比基线：卡 92 `b03134225` 的同步页 vsync 中位 20–25 ms；本次暂无新板测数字。

退出根因：L0 NEXT_BASE 已取得 REF_DISPLAY，但 application task 消费较早的 FRAME 时
STOPPING 提前关闭 L0，导致新地址从未扫描、无法通过 SWITCH 释放；DISP 继续扫描 L1，
IDLE 也不会释放它。现在等待提交之后的 FRAME 且 CUR_BASE 匹配，再关闭 L0。
另恢复同步页退出时由 GUI 暂停的页面定时器，首页状态可继续刷新。
定向复现用例在原生产代码 `49a910c77` 的 `assert(display_enabled)` 失败，修复后通过。
调试过程见 [调试记录](../debug/2026-11-16-showcase-sync-stop-hang.md)。

FRAME 用 CLINT 计时；周期 T≈16.683 ms，立即提交窗口 W=15.000 ms，留 T−W=1.683 ms
供中断响应和 L0/L1 成对写入。窗口内在关中断临界区立即写，窗口外在下次 FRAME 写。
窗口内等待估算为 T−phase；窗口外为 2T−phase。若完成相位均匀，vsync 中位估算
为 T/2+(T−W)≈10.025 ms（约 10 ms，非板测结果）；实际中位数待上板确认。

抓取顶栏“节奏 自适应/均匀”对所有同步页生效，运行期间保留，每次切换打印
`display pace=adaptive|even`。均匀模式在上次换画面的第 2 个 FRAME 后取最新结果，
目标第 3 帧锁存（约 19.98 fps）；来不及则顺延。未取结果被替换并释放，已开始渲染或
写 NEXT_BASE 的结果完成提交，此边界经协调者确认；pace 统计继续输出。

爱心发箍宽度系数 614→798（1.300 倍），其他头饰不变。
八字胡锚点 N+0.55×((Mleft+Mright)/2−N)，宽度仍按嘴角距离；测试 y=360→346。

在 `. ~/.local/opt/edrv32/env.sh` 环境中，以下命令均通过、0 告警：
- `flock /tmp/edrv32-sw-build.lock make -C sw -j2 PROGRAM=showcase`
- `flock /tmp/edrv32-sw-build.lock make -C sw -j2 PROGRAM=showcase SHOWCASE_POST=cpu`
- `flock /tmp/edrv32-sw-build.lock make -C sw/tests/showcase sync sticker grab games`
日志在 `build/sw/tests/showcase/`：`smooth-build-hw.log`、`smooth-build-cpu.log`、
`smooth-rebased.log`；覆盖退出交错、定时器恢复、session 矩阵、成对提交窗口及均匀节奏。
按协调者确认，FreeRTOS 已从 b3 删除，本次不构建 RTOS 版；`shell.c` 未修改。
