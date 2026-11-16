# Showcase 四模型功能验证页（2026-11-16）

- 基线：`94fc1cdb`；构建代码 `597be03e`（rebase 到 `45377e7b`）；GCC 15.2.0，C11 `-Wall -Wextra -Werror`。
- 目标板：卡 68 R2，180 MHz；本文为主机验证，未上板、未跑 SoC 仿真。
- 默认构建：`make -C sw PROGRAM=showcase`；ELF `build/sw/showcase/showcase.elf`（29,563,724 字节，PASS）。
- CPU 后处理：`make -C sw PROGRAM=showcase SHOWCASE_POST=cpu`；ELF `build/sw/showcase-cpupost/showcase.elf`（29,567,676 字节，PASS）。
- 构建日志：`build/demo-build-hw.log`、`build/demo-build-cpu.log`；两者均包含六个模型。
- detect、pose 快照未修改；原版与新版嵌入脚本生成的两个 C 文件逐字节一致。

DDR（物理地址；每个描述符区 64 KiB，模型区 4 MiB）：

| 模型 | 描述符 | 模型区 |
|---|---|---|
| detect | 0x00080000 | 0x00100000 |
| pose | 0x00090000 | 0x00500000 |
| gesture | 0x000a0000 | 0x00900000 |
| face | 0x000b0000 | 0x0c000000 |
| doodle | 0x000c0000 | 0x0c400000 |
| helmet | 0x000d0000 | 0x0c800000 |

- 对照 B2 软件设计 3.3 与 `board/ddr_map.h`；协调者批准后三个模型避开 UPLOAD `[0x0b000000,0x0b800000)`，不移动已有区域。
- 页面切换：模型表配置描述符、权重、OUTPUT、类别、关键点与阈值；先关闭启动、排空，再重配；退出恢复 detect。
- 简笔画：CH0 摄像头 → PIX 灰度/二值化 → 底图环/L0；CH2 独立选择 VIN_MEMORY，读最新已完成 CH0 帧再送 NPU。
- 槽位：内存源读期间持有 REF_GEO；CH2 完成后转 REF_PAIR，再交 REF_NPU；与 L0 引用共同形成 VIN busy 位，最后一个引用释放后才允许改写。
- e2e 保留 CH0 摄像头完成时间；阈值默认 128，按键 ±8，并即时输出 `doodle thr=N`。

串口每秒一行（时间单位 ms；shown 为实际呈现的新结果数，disp 为 L1 实际翻页次数）：

```text
gesture fps=… shown=… disp=… npu=… wait=… decode=… kpt=… gui=… e2e=… hands=… cls=… conf=… size=… idle=…
gesture_evt ms=… cls=… conf=… size=…
face fps=… shown=… disp=… npu=… wait=… decode=… gui=… e2e=… faces=… size=… idle=…
doodle fps=… shown=… disp=… npu=… wait=… decode=… gui=… e2e=… objs=… thr=… idle=…
helmet fps=… shown=… disp=… npu=… wait=… decode=… gui=… e2e=… helmet=… head=… idle=…
```

- 现有 vision、pose、image 的统计行同样加入 shown/disp；gesture_evt 在最大手连续同类三帧后的状态改变时即时输出。
- `make -C sw/tests/showcase/vision test`、`runtime`、`models` 均 PASS（test 的 PASS 见 `build/demo-host.log`；runtime 修正后 PASS 见 `build/demo-runtime.log`；模型见 `build/demo-models.log`）。
- 四模型各一张真实评估图经板端 C 后处理/关键点解码，与 `models_eval.integer` INT8 比对：gesture 0.375、face 0.500、doodle 0.500、helmet 0.4375 px 最大误差；三帧防抖 PASS。
- `make -C sw/apps/showcase/sim demos` PASS；截图为 [手势](assets/demo-gesture.png)、[人脸](assets/demo-face.png)、[简笔画](assets/demo-doodle.png)、[安全帽](assets/demo-helmet.png)，来自 C 比对通过的 INT8 夹具；界面时延数字为模拟数据。
- `git diff --check` PASS；`python3 tools/check/verilog_style.py sw/apps/showcase sw/tests/showcase` 为 0 文件/0 告警；未改 RTL，Verilator lint 不适用；C 编译告警作为错误处理。
- 上板检查：用 CPU ELF；逐页进入/退出和暂停/恢复，确认模型排空、detect 恢复、无旧框；对照 fps/shown/disp 与肉眼刷新。
- 手势检查三帧切换和 grip 色块，关键点默认开；人脸检查四类贴纸随眼距缩放、关键点默认关；安全帽检查计数与红条。
- 简笔画检查白底黑线、板上按键 ±8 串口、内存源反压时底图无撕裂；记录相机到呈现的 e2e 和连续运行结果。
