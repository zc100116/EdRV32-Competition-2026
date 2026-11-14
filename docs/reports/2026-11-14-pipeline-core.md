# T-PIPE-CORE 板端交付（2026-11-14）

- 代码提交：`4fc88eb6`；已 rebase 到 `zc100116/b3` 的 `42b3fa16`。
- 实现 100 B 链的原子校验/替换、8 预设、纯 C 贪心编译、共享内存源及异步 NPU 取样。
- IRQ 驱动 VIN/GEO/RND/NPU 逐跳启动；内存源/GEO/RND 分别按帧号调度，保留最新待处理帧。
- DDR 新区 `[0x14000000,0x18f00000)`：来源及 12 跳各 3×2 MiB 槽，尾部存描述符/缩略图；不与既有区间重叠。
- 实现 DISP 看此级/最终/来源、任意角度检测框外接矩形、RND 框/UI 混合、160×90 的 5 Hz 缩略图。
- L1 保持扫描，最终输出含界面时 global alpha=0；GUI 整个 step、CPU 绘制及待翻页受 front pin 排斥，RND 与 GUI 共用仲裁。
- 同一 PIX 跳内各积木共用输出/缩略图；融合入口另用 CH1 保存原图，检测积木显示真实取样输入（协调者确认）。
- NPU 启动、POST_CTRL.EN、硬件候选输出及 CPU 排序/NMS 沿用 vision.c；两块后处理区保留至 BSP clean 后释放。
- 实现每跳均值/fps/e2e/框滞后/NPU 时间、xbar 各端口读写字节累计、1950 MB/s 上限及每秒 UART 一行。
- EDSC 新增 CHAIN/PRESET/CHAIN_STATE/PIPE_STATS，移除 PROCESS 命令，STATE +20 写 chain_rev；PC 图片限制 app=1/source=1/RUNNING。

| 预设 | 演示参数 | 编译跳表（方括号为积木闭区间，—为摄像头来源） |
|---|---|---|
| 1 标准识别 | 检测、框 | C[—] → N[0] → R[1] |
| 2 边缘识别 | 灰度、Sobel(op4)、检测、框 | F[0] → P[1] → N[2] → R[3] |
| 3 旋转识别 | 90°、100%、检测、框 | C[—] → G[0] → N[1] → R[2] |
| 4 局部放大 | 200%、平移(-160,-90)、检测、框 | C[—] → G[0] → N[1] → R[2] |
| 5 整屏旋转 | 检测、框+UI、30°/75% | C[—] → N[0] → R[1] → G[2] |
| 6 夜视增强 | gamma=1.8、亮度16/对比度320(Q8)、高斯(op2)、检测、框 | F[0] → P[1..2] → N[3] → R[4] |
| 7 多级滤波 | 高斯、Sobel、二值128、膨胀(op6)、高斯 | F[0..2] → P[3..4] |
| 8 PC 图片 | PC RGB565、检测，结果回传 | N[0] |

- 跳表图例：F=CAM-CH0/PIX，C=CAM-CH1，P=MEMSRC-CH0/PIX，N=MEMSRC-CH2/NPU，G=GEO，R=RND。
- UI 集成前：`make -C sw/tests/sched test`、`make -C sw/tests/showcase test` 全部 PASS；原始日志保留。
- 按协调者要求，最终构建后跑一次 `make -C sw/tests/showcase/pipeline test`：PASS（UBSan，含全部 7.1/7.4 规则、两种 CH0/CH2 完成顺序及切链排空）。
- `. ~/.local/opt/edrv32/env.sh; make -C sw PROGRAM=showcase`，UI 调用修正后按批准以 `make -C sw PROGRAM=showcase -o FORCE` 续编：PASS，GCC 15.2.0，C11/-Wall/-Wextra/-Werror，0 告警。
- ELF：13,484,148 B；size：text=13,301,860，data=11,908，bss=50,519,872 B；总计=63,833,640 B；较本分支 UI 集成前 ELF 13,422,700 B 增加 61,448 B。
- 测试图按协调者确认，从 street-scene.png 构建 640×360 RGB565，新增载荷 460,800 B，首次用 GEO 放大到 1280×720；未重建旧版 ELF 测整体增量。
- 原始命令日志：`build/sw/tests/showcase/logs/{sched,showcase,pipeline,build,build-initial}.log`；`git diff --check` 通过；未改 RTL，不适用 Verilog lint/style。
- 已随最新 UI 删除 `ui_data_process*`、`vision_process_applied`、`vision_app_process`、PAGE_PROCESS 辅助代码及旧 process_test；PIX 组合由 pipeline 测试覆盖。
- 协调者确认暂留 `vision_app_camera/image` 及 PAGE_CAMERA/IMAGE 内部路径；main 已移除这些应用入口，供旧 `vision/runtime_test.c` 的 camera/parallel/interrupt_restart/image/cancel/model 测试及 `vision/network_test.c` 回归使用，后续由协调者清理。
- 限制：未跑 SoC 仿真、未访问仿真虚拟机；主机测试使用引擎边界桩，实际帧率、DDR 带宽、IRQ 时延、L1 混合及八预设画质须上板测量。
