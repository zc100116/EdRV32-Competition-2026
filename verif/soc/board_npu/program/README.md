# B3N 原始 board_npu ELF 的 SoC 仿真

```sh
. ~/.local/opt/edrv32/env.sh
export EDRV32_PANGO_SIM_DIR=/path/to/private/vendor-model-directory
python3 verif/soc/board_npu/program/run.py
```

只在指定仿真主机运行；同一时刻一个仿真，Verilator 构建使用 `-j 4`。
`--mac sim` / `--mac vendor` 分别运行行为 MAC / FPGA 包装加厂商 `GTP_APM_E2.v`，
默认依次运行两者。`--lint-only` 只运行相应变体的 `--lint-only -Wall`。

不重编译卡 13 的 ELF 或 ROM。`tools/elf2mem.py` 将 PT_LOAD 的物理地址内容装入 DDR；
采用同一卡的 `src/ip_rom_boot.dat`，经真实 BIOS `3=Run` 跳转至 `0x80000000`。
DDR shell 仅在 `build/board_npu_program/ip_ddr3.sv` 中扩展 `MEMORY_BYTES` 至 1 GiB：
除 NPU 物理区 `0x16000000`，原始 ELF 的栈顶 `0xc0000000` 还需要物理区末端
`0x3fffffff`。CPU 执行数据复制、cache clean/invalidate 和比较。
该入口还生成稀疏字节 DDR 模型，避免 Verilator 的单维大数组限制；公共 DDR 模型不变。

沿用 board_npu 的 UART 加速（6.25 Mbaud）和 BIOS 按键窗口时间加速。
每个变体的 UART 文本保存在 `build/board_npu_program/{sim,vendor}/simulation.log`；
收到完整 `NPU B-OP-01-c16_32` 行后立即结束，不继续后续用例。
PASS 返回 0，FAIL 返回非零；运行器按字段逐字对照调试记录原样引用的卡 13 日志并打印差异。
厂商分支仅替换 MAC 链包装，其余仍为 `SIM_MODE`，不修改仓库 RTL。
与 EQ-01 一样提供厂商模型需要的 `GRS_INST.GRSNET=1`；包装的 `GRS_EN=FALSE`。
`-Wall` 检查工程 RTL 和新 testbench，厂商文件的编码告警按文件豁免；
包装中三个有意悬空的厂商输出端口仅豁免 `PINCONNECTEMPTY`。
