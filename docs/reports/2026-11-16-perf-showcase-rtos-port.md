# Showcase FreeRTOS 对照移植验收

- 源码：本报告所在提交（构建时 BUILD_COMMIT 为 `59616dfa8`）；基线 `59616dfa8`（最新 b3）；旧移植来源 `7a54602b`，FreeRTOS V11.3.3/MIT。
- 环境：xPack GCC 15.2.0，RV32IM/Zicsr、ilp32；主机 GCC 13.3.0；目标 PG2L200H，速度等级未采集。
- 本次仅软件构建/主机验收，未上板、未运行 SoC 仿真；A/B 优劣待卡 93，之后删除评估参数。
- `SHOWCASE_SCHED=coop|rtos`，默认 coop；应用代码共用，RTOS 代码及 GUI RPC 集中在 `sw/lib/sched/freertos/`。
- 基础优先级：应用 3（视觉服务/槽位、会话、当前应用 step）、GUI 2、通信 1、空闲 0（WFI）。
- 任务以通知等待事件；CLINT 按绝对截止时间唤醒任务，正常模式另有 1 kHz 抢占节拍。
- 共用状态以带优先级继承的递归互斥量串行化服务切片；RND/RPC 阻塞前释放，恢复后重新取得。
- GUI 任务完成 LVGL 初始化、定时器、渲染；应用/通信的界面操作经同步请求队列转交 GUI；仅 RPC 唤醒不推进 LVGL 定时器，未修改 UI 文件。
- RND 完成 ISR 使用 `xSemaphoreGiveFromISR`；GUI 阻塞于二值信号量，完成早于等待也保留通知。
- 外设 ISR 登记事件，通过 FromISR 通知唤醒；PLIC 完成后统一切换任务；NPU 连续启动、FRAME 写 L0/L1 地址保持原路径。
- NES 整个会话关闭周期节拍，截止时间中断继续服务帧节奏和通信；CoreMark 测量包围区同时停用服务截止时间，结束后恢复。
- 游戏逻辑仍在 LVGL 定时器中；沿用硬件后处理、六缓冲池、同步显示与最新体感/贴纸应用。
- `sched` 原字段原样保留，增加 `ctxsw`（实际任务切换次数/秒）、`kern`（内核 API 与 trap 占用，一位小数 %）。
- 窗口随视觉页重置；任务 busy/max 扣除阻塞、被抢占等待及内核/IRQ 时间；CLINT 计时避免 CoreMark 重置/冻结 mcycle 干扰。
- 相比旧分支：优先级改为应用最高，RND 轮询改信号量，采用现有 P0 统计，增加无周期节拍时的绝对截止时间唤醒。
- 旧版逐模块状态锁集中到服务切片入口，临界区同步维护 MIE/内核嵌套；GUI 包装涵盖图层、游戏字体、上传发布；关闭 configASSERT，所有 API 调用保持执行。
- 默认 coop 调度器未改；可执行段总计 960,944 B，较基线 +12 B，仅 `showcase_cpu_report` 统计读取挂钩使函数由 1,304 增至 1,316 B。
- 其余函数大小相同；代码段字节差异还包括上述增长导致的后续数据/常量地址重定位，不含应用算法改变。
- 构建均以 `flock /tmp/edrv32-sw-build.lock make -C sw -j2` 串行，参数分别为 `PROGRAM=showcase`、追加 `SHOWCASE_SCHED=rtos`、再追加 `SHOWCASE_POST=cpu`。
- `make -C sw/tests/sched`、`make -C sw/tests/sched rtos`、`make -C sw/tests/showcase sync` 均通过，0 告警。
- RTOS 主机测试直接执行适配层，模拟硬件/内核边界，覆盖跨阻塞计时、节拍关闭/恢复、截止时间、ISR 信号量与窗口归零、MIE/内核嵌套临界区及 RPC 无定时器唤醒。
- 构建/测试日志及基线 ELF：`build/rtos/`；所有构建均启用 `-Wall -Wextra -Werror`，未修改 RTL，因此无 RTL lint 项。

| 配置 | 可执行代码 B | size text（含只读）B | data B | bss/保留区 B |
|---|---:|---:|---:|---:|
| coop | 960,944 | 39,712,060 | 12,756 | 50,668,972 |
| rtos/hw | 977,504 | 39,728,868 | 12,764 | 50,807,664 |
| rtos/cpu | 977,976 | 39,729,340 | 12,780 | 50,807,216 |

- 大小由 `riscv-none-elf-size` 与 ELF SHF_EXECINSTR 段统计；日志 `coop.log`、`rtos-hw-final.log`、`rtos-cpu-final.log`、`host-tests.log`、`host-rtos-final.log` 均在 `build/rtos/`。
- 交付：`build/rtos/showcase-rtos-hw.elf`（不入库）；目标上板后再取得 FPS、ctxsw、kern 与 CoreMark 分数。
