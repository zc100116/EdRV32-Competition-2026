# EdRV32 CPU datapath — C-R1

依据 `docs/spec/cpu-spec.md` v0.2 和 `docs/testplan/cpu-testplan.md` U-01–U-07、U-10。
本目录只含当前任务的数据通路；前端、流水控制和 core 顶层属于 C-R2/C-R3。

## 模块与接口

所有有时钟的模块使用 clk_sys，时钟名 `clk_i`；控制复位为 `rst_n_i`。
组合模块没有时钟或复位。操作类型未另定义共享宏，后续控制逻辑采用下列编码。

| 模块 | 输入概要 | 输出概要与时序 |
|---|---|---|
| `edrv32_cpu_decode` | `instr_i[31:0]` 规范指令 | rs1/rs2/rd 各5位、源使用和写回标志、32位立即数、4位class和ALU操作、立即数操作数选择、illegal；组合 |
| `edrv32_cpu_rvc` | 16位压缩指令 | 32位展开指令和illegal；组合；quadrant 3由32位取指路径处理，本模块报illegal |
| `edrv32_cpu_alu` | 两个32位操作数、4位operation | 32位结果；组合 |
| `edrv32_cpu_branch` | 两个32位操作数、3位condition=funct3 | taken；组合 |
| `edrv32_cpu_regfile` | 4个5位读地址；2组valid/5位地址/32位写数据 | 4个32位组合读口；写口1优先，写读旁路，x0=0；数据阵列无复位 |
| `edrv32_cpu_mul` | enable/valid、两个32位操作数、2位operation=funct3[1:0] | valid/32位结果；两个使能时钟沿后输出，enable=0同时保持数据与valid |
| `edrv32_mul_s33x33` | enable、两个33位有符号数 | 66位乘积；两个使能时钟沿后输出，无数据复位；位于rtl/tech |
| `edrv32_cpu_div` | start、两个32位操作数、2位operation=funct3[1:0] | busy/valid/32位结果；busy=0时接收start；特殊情况1个沿，普通情况33个沿；valid单拍 |
| `edrv32_cpu_csr` | 12位addr、access_valid、实际提交write、2位command、32位write_data；retire_count[1:0]、event_count[31:0]；trap与MRET；IRQ和mtime | 组合read_data/illegal，以及mstatus/mie/mtvec/mepc；提交沿更新；参数RVC_EN默认1 |

ALU operation 为 `{SUB/SRA选择, funct3}`：0 ADD、8 SUB、1 SLL、2 SLT、3 SLTU、
4 XOR、5 SRL、13 SRA、6 OR、7 AND。LUI/AUIPC 在流水控制中使用独立 class。
译码 class：0 ALU、1 LUI、2 AUIPC、3 JAL、4 JALR、5 BRANCH、6 LOAD、7 STORE、
8 MUL、9 DIV、10 CSR、11 SYSTEM、12 FENCE、13 FENCE.I。
未实现/保留指令由 illegal 指示，其他控制输出仅在指令合法时使用。

乘法 operation：0 MUL、1 MULH、2 MULHSU、3 MULHU。
除法 operation：0 DIV、1 DIVU、2 REM、3 REMU。
乘法E输入经过M/W两级寄存器，匹配规格结果延迟3；本单元并不额外插入第三级寄存器。

CSR command：1 WRITE、2 SET、3 CLEAR，读访问时write=0。
write_i 表示架构上实际发生的、已提交的写入：调用方按CSRR[S/C]的源寄存器号或zimm
是否为0决定，而不是按操作数数值判断。access_valid_i 可用于提交前非法访问检查，
实际提交时才使能write_i。非法访问不修改状态。
event_count_i 每个事件占2位，编码1对应[1:0]，编码16对应[31:30]，值0/1/2；
编码0、17–31不计数。调用方负责生成规格7.1定义的事件及配对失败原因优先级。
trap_i 的pc/cause/value由后端提供，覆盖同拍CSR写和MRET。

## 验证结果与复现

2026-10-25，Verilator 5.020，Icarus 12.0 (stable)。U-01至U-07、U-10全部PASS；
寄存器堆和CSR也在Icarus下PASS。各测试目录的README提供独立完整命令。

| 测试 | 目录 | 结果/主要覆盖 |
|---|---|---|
| U-01 | `verif/unit/cpu_decode` | PASS；393216组opcode/funct3/funct7/寄存器组合，以及定向控制与立即数检查 |
| U-02 | `verif/unit/cpu_rvc` | PASS；穷举65536个半字，与独立编码表生成的展开结果比较 |
| U-03 | `verif/unit/cpu_alu` | PASS；随机、边界、移位0/31、所有ALU操作 |
| U-04 | `verif/unit/cpu_branch` | PASS；六种条件、随机和有符号边界 |
| U-05 | `verif/unit/cpu_mul` | PASS；四种乘法、连续输入、bubble、enable停顿和两级延迟 |
| U-06 | `verif/unit/cpu_div` | PASS；1200次请求、四种运算、除0、溢出、精确1/33沿延迟 |
| U-07 | `verif/unit/cpu_regfile` | PASS (Verilator/Icarus)；2000组4读2写、WAW、旁路、x0 |
| U-10 | `verif/unit/cpu_csr` | PASS (Verilator/Icarus)；全部4096地址、复位、WARL、RO、事件0–31、64位进位、写优先、trap/MRET、RVC_EN=0/1 |

在仓库根目录执行；每条编译命令成功后运行对应二进制：

```sh
. ~/.local/opt/edrv32/env.sh
mkdir -p build/unit
python3 verif/unit/cpu_rvc/vectors.py
for n in decode rvc alu branch mul div regfile csr; do
    verilator --binary --timing -Wno-fatal --top-module tb -DSIM_MODE \
        -f verif/unit/cpu_$n/files.f --Mdir build/unit/cpu_$n \
        > build/unit/cpu_$n-compile.log 2>&1 || exit
    build/unit/cpu_$n/Vtb || exit
done
for n in regfile csr; do
    iverilog -g2012 -s tb -o build/unit/cpu_$n.vvp -f verif/unit/cpu_$n/files.f || exit
    vvp build/unit/cpu_$n.vvp || exit
done
```

新增RTL的以下lint命令全部0告警（仿真编译的timescale提示不属于RTL独立lint）：

```sh
for n in decode rvc alu branch div regfile csr; do
    verilator --lint-only -Wall rtl/cpu/edrv32_cpu_$n.v || exit
done
verilator --lint-only -Wall +incdir+rtl/include --top-module edrv32_cpu_mul \
    rtl/cpu/edrv32_cpu_mul.v rtl/tech/edrv32_mul_s33x33.v
verilator --lint-only -Wall +incdir+rtl/include rtl/tech/edrv32_mul_s33x33.v
verilator --lint-only -Wall -GRVC_EN=0 rtl/cpu/edrv32_cpu_csr.v
```

`tools/check/`在本worktree中尚不存在。协调者确认本任务先以Verilator lint验收，
合入前再执行P0-rest提供的风格检查；已人工检查RTL头部、命名、端口分组、无Tab、
非注释行≤100列、Verilog-2001语法及控制/数据寄存器复位规则。

## 经协调者确认的规格补充

协调者在本Dispatch的ask回复中批准下列开发初值，后续由其补入规格并在定稿时确认：

- 可写CSR、事件选择与计数器复位0，mstatus.MPP固定3；四个标识CSR均为0。
- mtvec.MODE写2/3收敛为0；CSR写计数器优先于同拍递增。
- 同拍trap优先于CSR写和MRET。
- 与当前规格第5节“misa只读”有差异：misa按WARL实现，写忽略且不报非法，
  读值为RV32IMC，RVC_EN=0时去掉C。其余只读CSR写入报非法。

回归框架接入、P0-rest风格检查，以及FPGA乘法IP创建说明/Windows IP等价验证不在
本次已执行的Linux单元测试中；IP分支的模块名与端口严格按Task要求实现。
