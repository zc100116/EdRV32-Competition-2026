# 手部关键点板端软件

- 日期：2026-11-15；基线 `e1bcb880`，提交见本报告所在提交；Linux x86_64，GCC 15.2.0，C11 / `-Wall -Wextra -Werror`。
- 手部模型：卡 80 `best.pt`；训练池有效图排序后 `default_rng(0)` 抽 96 张，独立种子合成 45/60/90/180 px；percentile 95 / margin 1.05。
- 快照 `sw/apps/showcase/models/yolov8n-hand/`，生成命令见 README；3,505,408 B / 77 描述符；与离线评估模型和量化 JSON 逐字节相同。
- `--task hand --model-source` 已由基线支持；第三个嵌入模型从快照构建不需要 torch。
- detect、pose 的快照未改；嵌入 C 与基线脚本输出逐字节相同。
- 默认 ELF：`build/sw/showcase/showcase.elf`，20,030,120 B；`make -C sw PROGRAM=showcase` 通过。
- CPU 后处理 ELF：`build/sw/showcase-cpupost/showcase.elf`，20,034,136 B；`make -C sw PROGRAM=showcase SHOWCASE_POST=cpu` 通过。
- DDR 物理偏移：detect 描述符 `[0x00080000,0x00090000)`、模型 `[0x00100000,0x00500000)`；pose `[0x00090000,0x000a0000)`、`[0x00500000,0x00900000)`。
- hand 独立描述符 `[0x000a0000,0x000b0000)`、模型 `[0x00900000,0x00d00000)`；均未与现有区域重叠。
- WORK `0x01000000`、INPUT `0x04000000`、OUTPUT `0x05000000/0x05200000`、POST `0x05100000/0x05120000` 与 pose 独占复用；OUTPUT 每槽 1,048,320 B。
- 经 ask 授权，应用窗口由 64 MiB 扩为 128 MiB，DDR 偏移 `[0x10000000,0x18000000)`；不缩堆、不挪区，HW/CPU ELF DDR 末偏移 `0x14331c40` / `0x14332c40`（CPU 地址加 `0x80000000`）。
- 进入手部页切 hand，关闭启动条件后排空再切回 detect；全部手绘框、21 点和 CPU 实线骨架，局部失效，无镜像；最大面积手控制状态区。
- 规则不看可见度：`d=|4−8|/|0−9|`，`d<0.25` 捏住、`d>0.4` 张开，其间保持；阈值在 `page_hand.c` 中。
- 食/中/无名/小指：尖到腕距离 `>1.1×` 6/10/14/18 到腕距离；拇指：4 到 17 距离 `>1.1×` 3 到 17 距离。
- 0 指伸直=石头；仅食/中指伸直=剪刀；5 指=布；其余=“—”。
- 每秒一行（size=NPU px；d 两位小数；fingers 拇指到小指）：
  `hand fps=… npu=… wait=… decode=… kpt=… gui=… e2e=… period=… hands=… size=… d=… fingers=… rps=… idle=… npu_gap=…`
- 首次取得最大手及捏合/五指位/RPS 变化时立即输出（ms 为启动后毫秒）：
  `hand_evt ms=… pinch=0|1 d=… fingers=… rps=rock|scissors|paper|none size=…`
- 无手时清空状态；再检出时从张开状态开始；事件用于记录最大手连续检出期间的变化。
- `make -C sw/tests/showcase/vision hand`：通过；两张离线 A 样本 IMG_00029662 / IMG_00009943，经 npu_ref OUTPUT、板端 C 后处理和解码，对照 hand_eval INT8 最大误差 0.000031 px。
- 同一主机测试验证五指位、四种 RPS 输出及 0.25/0.4 边界滞回；`make -C sw/tests/showcase/vision test` 通过。
- `make -C sw/tests/showcase/vision runtime`：通过，含 hand 模型复制/切换、21 点、双 OUTPUT、排空及恢复 detect、每秒手部统计只消费一次；原 pose 检查通过。
- Python py_compile、git diff --check、Verilog 风格检查（0 文件 / 0 告警）通过；未改 RTL，RTL lint 不适用。
- 原始日志与两张 OUTPUT/expected：`build/npu/hand_board/`。
- 上板：卡 68 R2 用 CPU 后处理 ELF；检查启动器/APP=8、进出页和暂停、所有框/点/连线无残留、画面方向及两种框长边。
- 上板：从近到远记录 180/120/90 NPU px 附近的检出；捏合开合、石头/剪刀/布连续保持并记录 `hand_evt` 闪烁；核对每秒统计与五指位顺序。
- 未访问仿真虚拟机、未跑 SoC 仿真或上板；硬件实测仍待卡 68 R2。
