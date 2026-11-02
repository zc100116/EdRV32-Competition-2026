# GCC 15.2 monitor 编译选项扫描（卡 41）

日期：2026-11-02。源码 commit：`2b846c9924ed4d7a9f1fcf8dfcd34ecb989821b6`（亦为串口 `BUILD_COMMIT=2b846c99`），加本提交唯一的 Makefile 链接变量改动。CoreMark 子模块：`cfa9ab377835911f23d9b0831c7be302ed1f58de`。

工具链：`riscv-none-elf-gcc (xPack GNU RISC-V Embedded GCC x86_64) 15.2.0`。仅本地编译，未运行仿真或使用仿真主机；性能待卡 41 上板测量。

`sw/Makefile` 只新增默认为空的 `LINK_FLAGS_EXTRA` 变量并传给链接命令，用于传递优化级别和 LTO。两个 LTO 变体均为 `-O3 -flto`，其余为空；未改动 monitor 或 CoreMark 源码，保留既有第三方 CoreMark 的 `-Werror` 豁免。

协调者确认：保持原定 flags，交付 7 个成功变体；两个 LTO 变体如实记录链接失败，不放程序，保留链接变量待后续决定。

## 复现命令

从仓库根目录运行，每个变体构建前均清理 `build/sw/monitor/`。命令顺序对应下方变体表：

```sh
. ~/.local/opt/edrv32/env.sh
# t-base
rm -rf build/sw/monitor/
make -C sw PROGRAM=monitor MEMORY=sram MONITOR_OPT_FLAGS="-O3 -funroll-all-loops -finline-limit=600 -falign-functions=4 -falign-jumps=4 -falign-loops=4" LINK_FLAGS_EXTRA=""
# t-al8
rm -rf build/sw/monitor/
make -C sw PROGRAM=monitor MEMORY=sram MONITOR_OPT_FLAGS="-O3 -funroll-all-loops -finline-limit=600 -falign-functions=8 -falign-jumps=8 -falign-loops=8" LINK_FLAGS_EXTRA=""
# t-lto
rm -rf build/sw/monitor/
make -C sw PROGRAM=monitor MEMORY=sram MONITOR_OPT_FLAGS="-O3 -funroll-all-loops -finline-limit=600 -falign-functions=4 -falign-jumps=4 -falign-loops=4 -flto" LINK_FLAGS_EXTRA="-O3 -flto"
# t-rocket
rm -rf build/sw/monitor/
make -C sw PROGRAM=monitor MEMORY=sram MONITOR_OPT_FLAGS="-O3 -funroll-all-loops -finline-limit=600 -falign-functions=4 -falign-jumps=4 -falign-loops=4 -mtune=rocket" LINK_FLAGS_EXTRA=""
# t-s5
rm -rf build/sw/monitor/
make -C sw PROGRAM=monitor MEMORY=sram MONITOR_OPT_FLAGS="-O3 -funroll-all-loops -finline-limit=600 -falign-functions=4 -falign-jumps=4 -falign-loops=4 -mtune=sifive-5-series" LINK_FLAGS_EXTRA=""
# t-sched
rm -rf build/sw/monitor/
make -C sw PROGRAM=monitor MEMORY=sram MONITOR_OPT_FLAGS="-O3 -funroll-all-loops -finline-limit=600 -falign-functions=4 -falign-jumps=4 -falign-loops=4 -fschedule-insns -fsched-pressure" LINK_FLAGS_EXTRA=""
# t-inl400
rm -rf build/sw/monitor/
make -C sw PROGRAM=monitor MEMORY=sram MONITOR_OPT_FLAGS="-O3 -funroll-all-loops -finline-limit=400 -falign-functions=4 -falign-jumps=4 -falign-loops=4" LINK_FLAGS_EXTRA=""
# t-inl1000
rm -rf build/sw/monitor/
make -C sw PROGRAM=monitor MEMORY=sram MONITOR_OPT_FLAGS="-O3 -funroll-all-loops -finline-limit=1000 -falign-functions=4 -falign-jumps=4 -falign-loops=4" LINK_FLAGS_EXTRA=""
# t-al8-lto
rm -rf build/sw/monitor/
make -C sw PROGRAM=monitor MEMORY=sram MONITOR_OPT_FLAGS="-O3 -funroll-all-loops -finline-limit=600 -falign-functions=8 -falign-jumps=8 -falign-loops=8 -flto" LINK_FLAGS_EXTRA="-O3 -flto"
```

链接共有选项：`-march=rv32im_zicsr_zifencei -mabi=ilp32 -nostdlib -Wl,--gc-sections -Wl,-T,sw/bsp/ld/sram.ld -Wl,-Map,<OUT>/monitor.map`，随后为 `LINK_FLAGS_EXTRA`、对象文件和 `-lgcc`。

## 构建结果

text/data/bss 来自 `riscv-none-elf-size`，单位为字节；`.bin` 为实际文件字节数，7 个成功镜像均严格小于 61440 B。每个非 LTO 变体仅 1 条既有第三方告警：`core_list_join.c:376:29: warning: ‘info.data16’ may be used uninitialized [-Wmaybe-uninitialized]`；两个 LTO 构建无编译 warning，其余 warning 全为 0。

| 变体 | text | data | bss | .bin 字节 | 结果 |
|---|---:|---:|---:|---:|---|
| t-base | 31968 | 8 | 2116 | 31976 | 成功 |
| t-al8 | 32456 | 8 | 2116 | 32464 | 成功 |
| t-lto | — | — | — | 无 | 链接失败：SRAM 超出 44232 B |
| t-rocket | 31980 | 8 | 2116 | 31988 | 成功 |
| t-s5 | 31988 | 8 | 2116 | 31996 | 成功 |
| t-sched | 32000 | 8 | 2116 | 32008 | 成功 |
| t-inl400 | 31968 | 8 | 2116 | 31976 | 成功 |
| t-inl1000 | 31968 | 8 | 2116 | 31976 | 成功 |
| t-al8-lto | — | — | — | 无 | 链接失败：SRAM 超出 44488 B |

构建日志：本 worktree `build/cm-flags/<变体>.log`；程序：本文同级 `<变体>/monitor.{bin,elf}`。两个失败变体未生成可交付 ELF/bin。

## 完整 CFLAGS

以下从各变体实际命令中的 `BUILD_CFLAGS` 宏提取，与串口值一致，不含 `-I` 路径和独立的构建元数据宏。第三方 `core_main.c` 额外使用 `-Dmain=coremark_main`，第三方编译规则过滤 `-Werror`，与原 Makefile 一致。

### t-base

`-march=rv32im_zicsr_zifencei -mabi=ilp32 -std=c11 -Wall -Wextra -Werror -O2 -ffreestanding -fno-builtin -ffunction-sections -fdata-sections -DITERATIONS=10 -O3 -funroll-all-loops -finline-limit=600 -falign-functions=4 -falign-jumps=4 -falign-loops=4`

链接额外选项：空。

### t-al8

`-march=rv32im_zicsr_zifencei -mabi=ilp32 -std=c11 -Wall -Wextra -Werror -O2 -ffreestanding -fno-builtin -ffunction-sections -fdata-sections -DITERATIONS=10 -O3 -funroll-all-loops -finline-limit=600 -falign-functions=8 -falign-jumps=8 -falign-loops=8`

链接额外选项：空。

### t-lto

`-march=rv32im_zicsr_zifencei -mabi=ilp32 -std=c11 -Wall -Wextra -Werror -O2 -ffreestanding -fno-builtin -ffunction-sections -fdata-sections -DITERATIONS=10 -O3 -funroll-all-loops -finline-limit=600 -falign-functions=4 -falign-jumps=4 -falign-loops=4 -flto`

链接额外选项：`-O3 -flto`。

### t-rocket

`-march=rv32im_zicsr_zifencei -mabi=ilp32 -std=c11 -Wall -Wextra -Werror -O2 -ffreestanding -fno-builtin -ffunction-sections -fdata-sections -DITERATIONS=10 -O3 -funroll-all-loops -finline-limit=600 -falign-functions=4 -falign-jumps=4 -falign-loops=4 -mtune=rocket`

链接额外选项：空。

### t-s5

`-march=rv32im_zicsr_zifencei -mabi=ilp32 -std=c11 -Wall -Wextra -Werror -O2 -ffreestanding -fno-builtin -ffunction-sections -fdata-sections -DITERATIONS=10 -O3 -funroll-all-loops -finline-limit=600 -falign-functions=4 -falign-jumps=4 -falign-loops=4 -mtune=sifive-5-series`

链接额外选项：空。

### t-sched

`-march=rv32im_zicsr_zifencei -mabi=ilp32 -std=c11 -Wall -Wextra -Werror -O2 -ffreestanding -fno-builtin -ffunction-sections -fdata-sections -DITERATIONS=10 -O3 -funroll-all-loops -finline-limit=600 -falign-functions=4 -falign-jumps=4 -falign-loops=4 -fschedule-insns -fsched-pressure`

链接额外选项：空。

### t-inl400

`-march=rv32im_zicsr_zifencei -mabi=ilp32 -std=c11 -Wall -Wextra -Werror -O2 -ffreestanding -fno-builtin -ffunction-sections -fdata-sections -DITERATIONS=10 -O3 -funroll-all-loops -finline-limit=400 -falign-functions=4 -falign-jumps=4 -falign-loops=4`

链接额外选项：空。

### t-inl1000

`-march=rv32im_zicsr_zifencei -mabi=ilp32 -std=c11 -Wall -Wextra -Werror -O2 -ffreestanding -fno-builtin -ffunction-sections -fdata-sections -DITERATIONS=10 -O3 -funroll-all-loops -finline-limit=1000 -falign-functions=4 -falign-jumps=4 -falign-loops=4`

链接额外选项：空。

### t-al8-lto

`-march=rv32im_zicsr_zifencei -mabi=ilp32 -std=c11 -Wall -Wextra -Werror -O2 -ffreestanding -fno-builtin -ffunction-sections -fdata-sections -DITERATIONS=10 -O3 -funroll-all-loops -finline-limit=600 -falign-functions=8 -falign-jumps=8 -falign-loops=8 -flto`

链接额外选项：`-O3 -flto`。

## LTO 失败与一次原因核对

两个 LTO 变体的链接失败首行为（`<OUT>` 为本 worktree 的 `build/sw/monitor`，工具路径按实际日志缩写）：

```text
riscv-none-elf/bin/ld: <OUT>/monitor.elf section `.text' will not fit in region `SRAM'
```

t-lto：`region SRAM overflowed by 44232 bytes`，`.bss` 结束 `0x1001acc8`；t-al8-lto：实际为 `overflowed by 44488 bytes`，`.bss` 结束 `0x1001adc8`。两者均保留原 flags；未调整优化选项、链接脚本或 SRAM 上限。

按协调者要求仅作一次原因核对，不调整优化 flags：原始 map 为 `build/cm-flags/t-base.map`、`t-lto.map`；LTO map 的局部函数名未展开，因此额外保留一次链接临时汇编，重新汇编后用 objdump 读取局部符号大小（链接前、未 relaxation），不作为可上板 ELF。命令如下：

```sh
make -C sw PROGRAM=monitor MEMORY=sram MONITOR_OPT_FLAGS="-O3 -funroll-all-loops -finline-limit=600 -falign-functions=4 -falign-jumps=4 -falign-loops=4 -flto" LINK_FLAGS_EXTRA="-O3 -flto -save-temps=obj"
# 上一条仍按原样报 SRAM 溢出，仅保留诊断临时文件。
riscv-none-elf-gcc -march=rv32im_zicsr_zifencei -mabi=ilp32 -c build/sw/monitor/monitor.elf.ltrans0.ltrans.s -o build/cm-flags/t-lto.ltrans.o
riscv-none-elf-objdump -t tasks/win/20261102-41-coremark-flags/src/t-base/monitor.elf
riscv-none-elf-objdump -t build/cm-flags/t-lto.ltrans.o
riscv-none-elf-objdump -dr build/cm-flags/t-lto.ltrans.o
```

增长最大的 4 个同名函数（t-base 已链接 ELF → LTO 未 relaxation 对象，B）：`main` 892 → 43208（+42316）、`monitor_coremark` 1708 → 43288（+41580）、`timer_handler` 280 → 2440（+2160）、`info_ratio` 1152 → 1872（+720）；map 对比 `.text` 从 28256 B 增至 103892 B（+75636 B），`.rodata` 从 3712 B 降至 3704 B；LTO map 中 `main` 所在 `.text.startup` 最终为 43176 B，确认膨胀发生在编译生成代码阶段，而非仅为对齐空洞。

LTO 生效证据（原定 t-lto 无最终 ELF，以下以链接前 objdump 为准）：

1. t-base 的 `core_bench_list` 为独立函数（3420 B），LTO 对象中该符号及调用重定位均消失，仍保留 `monitor_coremark` 和对 `calc_func` 的调用，说明列表算法已合入其调用者。
2. t-base 的 `core_bench_state` 为独立函数（2548 B），LTO 对象中符号及调用重定位消失；`calc_func` 从 t-base 中已内联、无独立符号，变为 LTO 的独立局部函数（10828 B）。
3. t-base 的 `core_bench_matrix` 为独立函数（3328 B），LTO 对象中符号及调用重定位消失。`core_bench_state`、`core_bench_matrix` 的调用源位于 `core_list_join.c` 的 `calc_func`，被调函数分别位于 `core_state.c`、`core_matrix.c`，符号消失与 `calc_func` 膨胀共同证实跨文件内联/合并。

上述证据确认 LTO 参与了跨文件优化；跨文件内联与全循环展开导致代码膨胀是与证据一致的解释，未进一步隔离各选项的贡献。诊断原始数据位于 `build/cm-flags/t-lto.{symbols,dis,ltrans.o,ltrans.s}` 和 `t-lto-diagnostic.{log,map}`。未生成或交付超限程序。

验证：9 个原定变体均实际尝试构建；7 个成功、2 个明确链接失败，已由协调者接受此交付范围；成功变体均小于 61440 B，除允许的第三方告警外为 0 warning。`git diff --check` 通过；未改动 RTL，仓库 Verilog 风格检查和 Verilator lint 无适用输入；按任务约束未运行仿真。

## 协调者评审（2026-11-02）

- t-inl400、t-inl1000 的反汇编与 t-base 逐条相同（`-finline-limit` 在本组 `-O3` 选项下不改变代码），不上板，已删除镜像。
- LTO 两个变体链接失败、不采用；为它临时增加的 `sw/Makefile` 链接变量 `LINK_FLAGS_EXTRA` 已撤回（CLAUDE.md 1.2 参数收敛）。上文"仅向 Makefile 增加"的描述以此为准。
- 上板变体：t-base、t-al8、t-rocket、t-s5、t-sched（与 t-base 的反汇编差异行数分别为 —、3486、332、3299、340）。
