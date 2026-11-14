# 人体姿态单独上板软件交付

- 基线 `3a9a36a7`；实现为本报告所在提交；Linux，xPack GCC 15.2.0，C11，`-Wall -Wextra -Werror`。
- 两个构建各执行一次并通过，编译/链接 0 告警；未跑 SoC 仿真、未访问仿真虚拟机、未上板。
- 默认：`make -C sw PROGRAM=showcase` → `build/sw/showcase/showcase.elf`，**16,489,640 B**。
- CPU：`make -C sw PROGRAM=showcase SHOWCASE_POST=cpu` → `build/sw/showcase-cpupost/showcase.elf`，**16,497,708 B**。
- 构建日志：`build/pose-board-{hw,cpu}-build.log`；两个 ELF 都包含 detect 和 pose。
- 快照生成 commit/命令见 `sw/apps/showcase/models/yolov8n-pose/README.md`；从快照重建不需要 torch。
- detect 快照未改；原生成器和新生成器的 detect 嵌入 C 文件逐字节相同。

DDR 地址均为物理偏移，区间右端不包含：

| 用途 | detect | pose |
|---|---|---|
| 描述符预留 | `[0x00080000,0x00090000)` | `[0x00090000,0x000a0000)` |
| 模型预留（含后处理查表） | `[0x00100000,0x00500000)` | `[0x00500000,0x00900000)` |
| 实际描述符/模型 B | 4,352 / 3,248,896 | 4,928 / 3,505,408 |

WORK `0x01000000`、INPUT `0x04000000` 是互斥复用的工作区；应用 ELF 从 `0x10000000` 开始。
pose OUTPUT 两槽为 `[0x05000000,0x050fff00)` / `[0x05200000,0x052fff00)`，各 1,048,320 B。
第一槽到 POST 尚余 256 B；POST `[0x05100000,0x05160000)`、图像 `>=0x06000000` 均不重叠。
进入 pose 页切换描述符/模型基址、阈值和 CPU 查表；退出先关闭启动条件并排空，再恢复 detect。

串口每秒一行（时间均为 ms，抖动为 1280×720 像素）：
```text
pose fps=… npu=… wait=… decode=… kpt=… gui=… e2e=… period=… persons=… idle=… npu_gap=… jit_lw=… jit_rw=… jit_ls=… jit_rs=…
```
`kpt` 是 NMS 后关键点处理耗时；`jit_*` 对每帧最大行人的可见点取一秒内 `sqrt(var(x)+var(y))`，无样本输出 0。
`make -C sw/tests/showcase/vision pose` 通过：COCO 139/785 先缩放到 1280×720，npu_ref OUTPUT 经板端 C 后处理；框/分数/anchor 一致，关键点最大误差 0.000031 / 0.000061 px（限值 0.5 px）。
`make -C sw/tests/showcase/vision test`、`make -C sw/tests/showcase/vision runtime` 均通过；后者覆盖模型切换、OUTPUT 交替、举手指示及在途退出排空。
主机日志：`build/pose-board-host-{pose,vision,runtime}.log`；夹具在 `build/npu/pose_board/test/`。
APP=7 协议主机测试通过；PC 工具仅追加应用名称并执行一次 `py_compile`；`git diff --check` 通过，Verilog 风格 0 文件/0 告警，未改 RTL，Verilator lint 不适用。

上板检查：卡 68 R2 使用 CPU ELF；卡 75 布通后使用默认 ELF，确认启动器或 PC APP=7 能进入姿态页。
确认摄像头、所有人框/置信度、17 点骨架和人数/NPU/fps/端到端延迟；最大行人分别举左右手，只有同侧腕和肩可见且腕高于肩时亮起对应指示。
静止站立采集 `jit_lw/rw/ls/rs` 和耗时；暂停/继续、切换到实时识别及其他原有页，确认无旧骨架、无卡死且 detect 恢复；板端性能和抖动尚待实测。
