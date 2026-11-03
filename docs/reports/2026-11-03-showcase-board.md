# showcase v2 板端交付（2026-11-03）

源码：`73c0b871`，基底 `c889c090`；集成 `41e4e379`，显示过滤 `16a8baa0`，CoreMark `7259274f`。
工具：xPack GCC 15.2.0 / RV32IM，LVGL 9.6.0；硬件验收目标为卡 48 F CPU125、VRN。

## 内存和代码组（`riscv-none-elf-size -A` 实测字节）

| 段 | 字节 | 起始地址 / 用途 |
|---|---:|---|
| `.sram_text` | 6956 | 0x10000000，调度、platform、中断、虚拟输入、memcpy/memset |
| `.sram_coremark_text` | 15632 | 0x10001b40，CoreMark 算法、初始化、栈切换 |
| `.sram_coremark_data` | 2764 | 0x10005850，常量、种子、工作内存 |
| `.sram_coremark_stack` | 8192 | 0x10006320，栈顶 0x10008320 |
| `.text.nes` | 94024 | 0x90000000，nofrendo CPU/PPU/APU/mapper 与 NES 移植 |
| `.text.lvgl` | 245092 | LVGL 绘制和刷新，紧随 NES |
| `.text.ui` | 20004 | 共享页面、主题和显示过滤，紧随 LVGL |
| `.text` / `.rodata` / `.data` | 465100 / 1490908 / 11832 | 其余 DDR 代码、常量和初始化数据 |
| `.tohost` / `.bss` / `.noinit` | 72 / 329576 / 41975808 | DDR 状态、LVGL 内存及帧缓冲 |
| `.game_pack` | 7085120 | 0x92a94000，EDGP v2，30 条 EDG2 |

SRAM 地址跨度 33568 B；DDR 应用窗口为 0x90000000–0x93ffffff，栈顶 0x94000000。
游戏上传区为 DDR 偏移 0x0b000000 / 8 MiB，复位清空列表；其他固定缓冲见 `board/ddr_map.h`。
布局按模块排列，尚无实板热度数据；`prof <秒数>` 后用 `python3 tools/sw/prof_map.py ELF 日志` 映射前 256 行。
GUI 未暂停且应用请求立即继续时，应用任务把下一次唤醒推迟 1 ms，保留固定优先级；NES/独占图层不延迟。

## CoreMark 实际编译与放置

六个 CoreMark 源文件及 `monitor/benchmark.c` 实际均追加以下选项（完整七条命令见 `build/showcase-coremark-commands.txt`）：
`-O3 -funroll-all-loops -finline-limit=600 -falign-functions=4 -falign-jumps=4 -falign-loops=4 -fstrict-aliasing -march=rv32im_zicsr_zifencei`。
最后的 `-O3` 覆盖公共 `-O2`；`-fstrict-aliasing` 恢复该配置的默认值，抵消 NES 公共选项；ABI 为 ilp32，ITERATIONS=5000。
实际命令摘录（省略公共 include、构建元数据和 C11 参数；完整原文保存在上述七条命令文件）：
```sh
riscv-none-elf-gcc ... -O3 -funroll-all-loops -finline-limit=600 -falign-functions=4 -falign-jumps=4 -falign-loops=4 -fstrict-aliasing -march=rv32im_zicsr_zifencei -Dmain=coremark_main -c third_party/coremark/core_main.c
riscv-none-elf-gcc ... -O3 -funroll-all-loops -finline-limit=600 -falign-functions=4 -falign-jumps=4 -falign-loops=4 -fstrict-aliasing -march=rv32im_zicsr_zifencei -Wno-maybe-uninitialized -c third_party/coremark/core_list_join.c
riscv-none-elf-gcc ... -O3 -funroll-all-loops -finline-limit=600 -falign-functions=4 -falign-jumps=4 -falign-loops=4 -fstrict-aliasing -march=rv32im_zicsr_zifencei -c third_party/coremark/core_matrix.c
riscv-none-elf-gcc ... -O3 -funroll-all-loops -finline-limit=600 -falign-functions=4 -falign-jumps=4 -falign-loops=4 -fstrict-aliasing -march=rv32im_zicsr_zifencei -c third_party/coremark/core_state.c
riscv-none-elf-gcc ... -O3 -funroll-all-loops -finline-limit=600 -falign-functions=4 -falign-jumps=4 -falign-loops=4 -fstrict-aliasing -march=rv32im_zicsr_zifencei -c third_party/coremark/core_util.c
riscv-none-elf-gcc ... -O3 -funroll-all-loops -finline-limit=600 -falign-functions=4 -falign-jumps=4 -falign-loops=4 -fstrict-aliasing -march=rv32im_zicsr_zifencei -c sw/apps/coremark/core_portme.c
riscv-none-elf-gcc ... -O3 -funroll-all-loops -finline-limit=600 -falign-functions=4 -falign-jumps=4 -falign-loops=4 -fstrict-aliasing -march=rv32im_zicsr_zifencei -c sw/apps/monitor/benchmark.c
```
`iterate=0x10001b40`，list=0x10001d48，matrix=0x100030a8，state=0x100040ec，初始化=0x100056fc。
`work_memory=0x10005b4c`（2000 B），seed1/2/3=0x10005b48/44/40；运行栈在 SRAM，其他代码选项未改。
5000 次由页面提示显示后开始，结果为 Iterations/Sec 和 CoreMark/MHz；实板分数与运行时长尚未测量。

## 验证和上板要点

`make -C sw PROGRAM=showcase -j 1` 完整通过，最终更新后以 `-o FORCE` 增量复核；两次日志均无 warning/error。
`make -C sw/apps/showcase/sim shots win` 通过，包含真实键盘/编码器/指针操作、80 类末项和两张新截图。
`make -C sw/tests/showcase test`、`make -C sw/tests/sched test`、`make -C sw/tests/showcase/vision test runtime` 全部通过。
从 ELF 提取 `.game_pack` 后，主机解析确认 30 款、7085120 B；prof_map 用实际 ELF 的 sched_run 两行样本验证累计 10 次。
日志：`build/showcase-board-final.log`、`build/showcase-board-incremental-final.log`、`build/showcase-sim-final.log`、`build/showcase-host.log`、`build/showcase-vision.log`。
段和符号原文：`build/showcase-size.txt`、`build/showcase-symbols.txt`；截图：`build/sim/shots/{detection-settings,vision-filtered}.png`。
上板检查通信/应用最长 step ≤1/5 ms、GUI 静止占用、30 fps 上限、流式画面、CoreMark 实际耗时及分数。
验证 VRN 图像处理置灰，F 七种处理模式；三种输入、5 s 光标隐藏、串口页暂停虚拟串口输入、NES 两次返回。
验证 ECHO 收/回计数、模型/图片异步 DONE、游戏上传追加、名字 A8 重着色和 RGB565 封面；显示过滤不得改变 PC 结果。
VISION 和 TOOL 已集成，stub 已删除，无未完成的软件集成步骤；热度排序及实板性能留待上板采样。
