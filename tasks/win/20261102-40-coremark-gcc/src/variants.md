# GCC 15.2 / 16.1 CoreMark monitor 编译对比

源代码 commit：`23cc1643bfd02fe80fcf6dd17af6b3063805148c`（所有镜像的 `BUILD_COMMIT`）。
CoreMark 子模块：`cfa9ab377835911f23d9b0831c7be302ed1f58de`。
本任务只构建程序，不运行仿真或上板；串口中的 `Compiler version` / `Compiler flags`
由协调者上板时核对，沿用现有 `BUILD_COMPILER` / `BUILD_CFLAGS`，没有增加机制。

工具链安装、源码版本和 configure 命令见 [环境说明](../../../../docs/guides/env-setup.md#21-gcc-1610仅用于-coremark-编译器对比)。
两套 binutils 均为 2.45。monitor 原始构建日志位于本机
`~/.cache/edrv32-gcc16/monitor-logs/g15-<变体>.log`；GCC 16 的日志仅在远端读取，按用户要求不回传。
GCC 15 的 `.dis` 留在各变体目录，不入库；GCC 16 的 `.dis` 随远端目录清理。
各变体仅 `.bin` 和 `.elf` 入库。

表中 CFLAGS 从每个构建日志的 `BUILD_CFLAGS` 取得，与串口一致，不含 `-I` 路径。text/data/bss 来自 `riscv-none-elf-size`，大小单位均为字节。
上游 CoreMark 编译保留现有去掉 `-Werror` 的例外；仅 `core_main.c` 另加
`-Dmain=coremark_main`，不改变 authored C 的选项。

| 变体 | 编译器 -dumpfullversion | 完整 CFLAGS | text | data | bss | .bin 字节数 |
|---|---|---|---:|---:|---:|---:|
| g15-o2 | 15.2.0 | `-march=rv32im_zicsr_zifencei -mabi=ilp32 -std=c11 -Wall -Wextra -Werror -O2 -ffreestanding -fno-builtin -ffunction-sections -fdata-sections -DITERATIONS=10` | 20400 | 8 | 2116 | 20408 |
| g15-tuned | 15.2.0 | `-march=rv32im_zicsr_zifencei -mabi=ilp32 -std=c11 -Wall -Wextra -Werror -O2 -ffreestanding -fno-builtin -ffunction-sections -fdata-sections -DITERATIONS=10 -O3 -funroll-all-loops -finline-limit=600 -falign-functions=4 -falign-jumps=4 -falign-loops=4` | 31968 | 8 | 2116 | 31976 |
| g15-peer | 15.2.0 | `-march=rv32im_zicsr_zifencei -mabi=ilp32 -std=c11 -Wall -Wextra -Werror -O2 -ffreestanding -fno-builtin -ffunction-sections -fdata-sections -DITERATIONS=10 -O2 -funroll-all-loops -mtune=sifive-7-series -mstrict-align -mbranch-cost=3 -fno-if-conversion -fno-if-conversion2` | 29100 | 8 | 2116 | 29108 |
| g15-combo | 15.2.0 | `-march=rv32im_zicsr_zifencei -mabi=ilp32 -std=c11 -Wall -Wextra -Werror -O2 -ffreestanding -fno-builtin -ffunction-sections -fdata-sections -DITERATIONS=10 -O3 -funroll-all-loops -finline-limit=600 -falign-functions=4 -falign-jumps=4 -falign-loops=4 -mtune=sifive-7-series -mstrict-align -mbranch-cost=3 -fno-if-conversion -fno-if-conversion2` | 32240 | 8 | 2116 | 32248 |
| g16-o2 | 16.1.0（用户提供的仿真主机，环境不记录） | `-march=rv32im_zicsr_zifencei -mabi=ilp32 -std=c11 -Wall -Wextra -Werror -O2 -ffreestanding -fno-builtin -ffunction-sections -fdata-sections -DITERATIONS=10` | 20492 | 8 | 2116 | 20500 |
| g16-tuned | 16.1.0（用户提供的仿真主机，环境不记录） | `-march=rv32im_zicsr_zifencei -mabi=ilp32 -std=c11 -Wall -Wextra -Werror -O2 -ffreestanding -fno-builtin -ffunction-sections -fdata-sections -DITERATIONS=10 -O3 -funroll-all-loops -finline-limit=600 -falign-functions=4 -falign-jumps=4 -falign-loops=4` | 33012 | 8 | 2116 | 33020 |
| g16-peer | 16.1.0（用户提供的仿真主机，环境不记录） | `-march=rv32im_zicsr_zifencei -mabi=ilp32 -std=c11 -Wall -Wextra -Werror -O2 -ffreestanding -fno-builtin -ffunction-sections -fdata-sections -DITERATIONS=10 -O2 -funroll-all-loops -mtune=sifive-7-series -mstrict-align -mbranch-cost=3 -fno-if-conversion -fno-if-conversion2` | 29224 | 8 | 2116 | 29232 |
| g16-combo | 16.1.0（用户提供的仿真主机，环境不记录） | `-march=rv32im_zicsr_zifencei -mabi=ilp32 -std=c11 -Wall -Wextra -Werror -O2 -ffreestanding -fno-builtin -ffunction-sections -fdata-sections -DITERATIONS=10 -O3 -funroll-all-loops -finline-limit=600 -falign-functions=4 -falign-jumps=4 -falign-loops=4 -mtune=sifive-7-series -mstrict-align -mbranch-cost=3 -fno-if-conversion -fno-if-conversion2` | 32832 | 8 | 2116 | 32840 |

复现命令（从本任务 worktree 根目录执行；每个变体先删除 `build/sw/monitor/`）：

```sh
set -e
. ~/.local/opt/edrv32/env.sh
mkdir -p ~/.cache/edrv32-gcc16/monitor-logs
git submodule update --init third_party/coremark
for compiler in g15 g16; do
  case "$compiler" in
    g15) prefix=$HOME/.local/opt/xpack-riscv-none-elf-gcc-15.2.0-1/bin/riscv-none-elf ;;
    g16) prefix=$HOME/.local/opt/riscv-gcc-16.1.0/bin/riscv-none-elf ;;
  esac
  "$prefix-gcc" -dumpfullversion
  for variant in o2 tuned peer combo; do
    case "$variant" in
      o2) flags='' ;;
      tuned) flags='-O3 -funroll-all-loops -finline-limit=600 -falign-functions=4 -falign-jumps=4 -falign-loops=4' ;;
      peer) flags='-O2 -funroll-all-loops -mtune=sifive-7-series -mstrict-align -mbranch-cost=3 -fno-if-conversion -fno-if-conversion2' ;;
      combo) flags='-O3 -funroll-all-loops -finline-limit=600 -falign-functions=4 -falign-jumps=4 -falign-loops=4 -mtune=sifive-7-series -mstrict-align -mbranch-cost=3 -fno-if-conversion -fno-if-conversion2' ;;
    esac
    python3 -c 'from pathlib import Path; import shutil; p=Path("build/sw/monitor"); p.exists() and shutil.rmtree(p)'
    make -C sw PROGRAM=monitor MEMORY=sram CC="$prefix-gcc" \
      OBJDUMP="$prefix-objdump" OBJCOPY="$prefix-objcopy" MONITOR_OPT_FLAGS="$flags" \
      > "$HOME/.cache/edrv32-gcc16/monitor-logs/$compiler-$variant.log" 2>&1
    mkdir -p "tasks/win/20261102-40-coremark-gcc/src/$compiler-$variant"
    cp build/sw/monitor/monitor.{bin,elf,dis} \
      "tasks/win/20261102-40-coremark-gcc/src/$compiler-$variant/"
    "$prefix-size" build/sw/monitor/monitor.elf
    stat -c '%s' build/sw/monitor/monitor.bin
  done
done
```

八个构建各有一条既有第三方告警：上游 `core_list_join.c:376:29`
的 `info.data16 may be used uninitialized [-Wmaybe-uninitialized]`；项目自有源码均为
0 warning，保留 `-Wall -Wextra -Werror`。没有修改 monitor、CoreMark、BSP 或驱动源码。

本任务未改 RTL，Verilog 风格检查和 Verilator lint 无适用文件；按任务要求未运行仿真。

按协调者转达的用户要求，GCC 16.1 另在**用户提供的仿真主机（环境不记录）**上以相同
configure 选项构建（安装前缀使用任务专用目录，主机路径不记录）。本机的 GCC 16.1
后台构建保持运行；按协调者确认，本机安装后的 `-dumpfullversion` / `-v` 验收及源码、
中间目录清理由协调者接手，远端镜像交付不等待本机构建结束。

快照用 `git archive` 传送当前提交中构建所需的 `sw/`、`tools/elf2mem.py`、
`rtl/include/soc_address_map.json`，CoreMark 用其锁定提交单独 archive。快照无 `.git`，
因此使用现有 make `CPPFLAGS` 参数传入 `BUILD_COMMIT="23cc1643"`、实际
`BUILD_COMPILER="GCC 16.1.0"`、既有 `BUILD_CFLAGS` 和 `BUILD_ISA`，未修改源码或增加机制。

GCC 16.1.0 的 `-dumpfullversion` 实际输出为 `16.1.0`，四个变体均构建成功，
无新增告警；所有八个镜像为 20408–33020 B，均严格小于 61440 B。
GCC 16 的 CFLAGS 在远端从构建日志读取，与表内内容一致。
