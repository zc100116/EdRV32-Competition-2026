# Showcase P4 应用验收与浮窗开销

代码提交：`8c9599a8`，基于 DISPLAY 集成提交 `2151e29c`。
目标硬件为卡 52 对应的 F CPU125 配置；本次在 Linux 完成构建、主机测试与截图，没有新增 FPGA 测量。

## 命令与结果

```sh
. ~/.local/opt/edrv32/env.sh
make -C sw PROGRAM=showcase -j 1
make -C sw/apps/showcase/sim shots win -j 1
make -C sw/tests/showcase test
make -C sw/tests/showcase/vision test runtime -j 1
```

以上命令均通过，编译日志中为 0 warning。
固件使用 xPack GCC 15.2.0；主机为 x86_64 Linux、GCC 13.3.0、`-O2`；Windows 产物由 Zig 交叉构建。
原始日志分别为 `build/p4-apps/firmware.log`、`sim.log`、`host.log`、`vision-host.log`。

模拟器生成 26 张截图与 `build/sim/showcase_sim.exe`。
新增截图位于 `build/sim/shots/`：`overlay-home.png`、`overlay-games.png`、
`renderer-list.png`、`renderer-result.png`、`benchmark-results.png`、
`coremark-counters.png`、`page-back.png`。
模拟器中的 benchmark、RND 硬件结果与 CoreMark 数字是脚本展示数据，不是板上测量。

主机测试覆盖游戏→列表→首页及原焦点恢复、鼠标返回与 benchmark 停止、
HPM 两轮/八槽到 16 个事件的 64 位映射、每帧入口输入采样、
UART 调试页中的虚拟设备、单字节连接请求不产生 DONE，以及原有协议/调度/显示/视觉回归。

## 浮窗测量

`main_shots.c` 中 `measure_overlay()` 使用同一份浮窗 UI，
在独立的 **320×240 ARGB8888 DIRECT** 主机显示上执行 120 次更新。
每次推进模拟时钟 500 ms，计时包括数据格式化、对象更新和软件绘制。
最终串口式主机输出为：

```text
Overlay 320x240 ARGB software, 120 refreshes: average_us=328 max_us=829
```

主机测量不含板端 cache 维护、显示交接等待，不能替代 FPGA 上的 ≤2% 占用验收。
没有旧版同尺寸、同条件的测量基线。

NES 中主 GUI 暂停，RND 与 IRQ 仍归 NES；浮窗只用软件，L1 扫描该小矩形，
双缓冲通过 SWITCH1 释放。benchmark 按协调者确认的口径保留全屏 L1，浮窗放 sys layer。
板端每秒记录 `overlay_cpu` 与 `max_us`，CPU 统计包含浮窗对象更新与绘制。

## 板上需观察的数字

- 连接建立后应看到 `Showcase:`、`ETH peer IP:`、`ETH peer port:`；输入应切换到 ETH。
  分别经 UART/ETH 多次按下与释放，记录 `NES input` 的两组 `max_ms` / `avg_ms`，目标最大值 ≤16.7 ms。
  本次没有取得两通道的板上延迟，未输入时输出的零值不是延迟测量结果。
- 开浮窗运行 NES：每秒 `overlay_cpu` ≤2%；检查 `max_us`、渲染 fps、显示 fps、DDR 波形及两个引擎忙碌率。
  常规通信任务 `max_us` ≤1000，常规应用切片 ≤5000；NES/CoreMark/benchmark 是已批准的独占场景。
- benchmark 完整完成 16 个场景并停在结果表，实测 fps 非零；返回键和鼠标按钮可停止，已完成结果保留。
- 渲染器全部运行覆盖 22 个绘制项，含两种目标格式；单项显示硬件/软件 us、加速比和相同像素数/18432。
  数字来自同步 RND 提交与 LVGL 软件绘制，背景初始化和逐像素比较不计入绘制时间；DISP 是独立交互演示。
- CoreMark 保留 g15-tuned 和 SRAM 放置（链接图中 `iterate` 为 `0x10001c20`）；
  检查两轮 mcycle/minstret、全部 16 个事件、IPC、I$/D$ MPKI 和页面编译选项。
