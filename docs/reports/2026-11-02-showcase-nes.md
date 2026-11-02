# Showcase NES 与游戏包主机验证

代码：`bba8cec721e4e5bf5e16153d8424736a29a916cb`；分支 `zc100116/task-show-nes`。
依据：showcase-software 4.1/4.2/4.4/4.5；未修改原 NES、RTL、FPGA 或规格。
工具：xPack RISC-V GCC/readelf 15.2.0、主机 GCC 13.3.0、Python 3.12.3；无 RTL 仿真或虚拟机访问。

包采用小端，所有偏移相对包起点；头 8 字节，条目 84 字节，随后为 4 字节对齐的 ROM/图标。

| 区域 | 字段 | 类型/字节 |
|---|---|---|
| 头 | magic、version、count | `EDGP`/4、u16=1、u16 |
| 条目 | name | UTF-8/64，零填充，最多 63 字节 |
| 条目 | ROM offset、length | u32、u32 |
| 条目 | icon offset、width、height、format | u32、u16、u16、u32=1 |
| 图标 | ARGB8888 | 64×64，内存 BGRA；无图标 offset/width/height=0 |

本地目录 `games.txt` 每行 `名字|ROM文件|可选PNG图标`；不提交游戏包或打包 ELF。
打包示例：`python3 tools/sw/pack_games.py build/sw/showcase/showcase.elf D:/games D:/showcase-games.elf`。
脚本读取 ELF 的 `.game_pack` 地址/容量，追加只读 PT_LOAD，并替换该地址原有的纯 NOLOAD 段。
PNG 支持 8 位 RGB/RGBA、非隔行、五种滤波、分块 IDAT；最近邻缩放到 64×64。

复现（仓库根目录，先 `. ~/.local/opt/edrv32/env.sh`，初始化锁定的 nofrendo/LVGL 子模块）：

```sh
python3 sw/tests/game_pack/test_pack.py
python3 sw/tests/game_pack/check_frames.py
python3 sw/tests/game_pack/check_compile.py
```

结果：游戏包 Python/C 解析往返、RGB/RGBA 五滤波解码/逐像素缩放、ELF 新段/原段内容检查全部 PASS。
ELF 测试夹具 readelf：新 PT_LOAD 地址 `0x92000000`，FileSiz=MemSiz=`0x100d0`（65744 字节）。
同一仓库 NROM 测试 ROM，原连续循环与逐帧入口前 600 帧共 36,864,000 个像素完全一致。
同一进程停止后重启，再运行 600 帧，仍逐像素一致；修复借用 ROM 被 free 和首帧缓冲残留。
全部 NES 应用/mapper C 文件经 RV32 C11 `-Wall -Wextra -Werror` 编译 PASS；上游核心沿用原警告豁免。
真实 RND/DISP 驱动的主机 IRQ 测试 PASS：忙时跳帧、快照、调色板、DONE/FRAME/SWITCH、停止。
日志/原始帧：`build/sw/game-pack/{readelf.log,compile/,frames/{baseline,step}/}`。
非补丁文件 `git diff --check` 无告警；补丁保留上游统一差分上下文空白；未涉及 RTL lint。

CORE 集成：在其 program.mk 包含 `sw/apps/showcase/nes/program.mk`，应用表加入 `&nes_app`。
采用 CORE 的 app/platform/sched 头（4292ae85、cdd438f1、7944d859、b2058c13），无私有替代头/接口差异。
链接器须导出 `__game_pack_start`，保留独立 16 MiB `.game_pack`；新增段不得与其他 PT_LOAD 的内存范围重叠。
游戏阶段暂停 GUI、按 60 Hz deadline 调度；中断推进显示；每秒打印模拟/显示 fps 与调度 busy_ticks 占用。
KEY4/虚拟 ESC 停游戏，后续 step 等 DISP IDLE 再恢复选择页；再次返回进入启动器。
待 CORE 集成和上板测量实际 fps/CPU；本任务未声称板端帧率或硬件性能结果。
