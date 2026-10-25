# EdRV32 CPU datapath and frontend — C-R1/C-R2

依据 `docs/spec/cpu-spec.md` v0.2 和 `docs/testplan/cpu-testplan.md` U-01–U-07、U-10。
本目录包含C-R1数据通路与C-R2前端；后端流水控制和core顶层属于C-R3。

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

## C-R2 前端接口

新增 `edrv32_cpu_frontend` 集成 F1/F2、`edrv32_cpu_predictor` 和
`edrv32_cpu_ib`，复用 `edrv32_cpu_rvc`。时钟域均为 clk_sys，前端参数仅有
规格允许的 RVC_EN；BTB=32、gshare=512、RAS=4、IB=4 均为固定 localparam。
复位入口遵守 SoC 5.3，PC=0。

后端提供 `decode_pop_count_i[1:0]`（0/1/2），每个时钟沿取走最老的指定数量记录；
不得超过 `decode_valid_count_o`。`decode_data_o[357:0]` 的低179位是最老指令，
高179位是下一条；仅有效记录有意义。`ib_count_o[2:0]` 为全部IB占用数。

每条179位记录的字段如下，前后端直接用切片取得：

| 位 | 字段 |
|---|---|
| 31:0 | 指令PC |
| 63:32 | 规范32位指令 |
| 95:64 | 原始编码；压缩指令高16位=0 |
| 96 | compressed，决定顺序PC增量2或4 |
| 97 | RVC展开发现非法；普通32位指令由D级译码器检查 |
| 98 | 取指访问异常，跨边界任一半字错误均置位 |
| 99 | 此指令BTB命中 |
| 100 | 此指令预测跳转 |
| 132:101 | 预测目标，仅命中/预测跳转时使用 |
| 141:133 | 原查询gshare索引，供该条E级条件分支训练 |
| 178:142 | 预测前RAS检查点（布局见下） |

后端的较老 M/E 重定向已在后端按 M>E 仲裁后，通过 `redirect_valid_i`、
`redirect_pc_i` 和对应 `redirect_ras/push/pop/return_pc` 输入；
D级JAL通过同构的 `d_redirect_*` 输入。前端固定优先级为 M/E > D。
重定向当拍不再接受请求，清空IB和拼接状态，对尚未返回请求输出ic_kill，
下一周期从重定向PC所在的8字节组发起请求，并从PC的半字偏移开始解释。
`halt_i` 只停止新请求，已接收的响应仍可进入IB；适用于WFI及后端停顿控制。
`invalidate_i`、`invalidate_done_o` 直连I$的ic_inv/ic_inv_done，FENCE.I次序由后端负责。

E级 `update_valid_i` 只能对未被冲刷的已判定分支置位；提供完整PC、实际目标、
实际taken、compressed和随指令保存的9位index。`update_type_i`：0条件分支、
1 JAL、2 JALR、3调用、4返回。JAL在D级未命中时仅重定向，最终仍在E级训练。
调用/返回按RISC-V x1/x5的隐式RAS提示由后端分类；恢复动作的push/pop均可为1，
实现协程的先pop后push。`return_pc` 是实际指令PC+2/4。

经协调者批准的预测初值：BTB index=PC[7:3]，tag=PC[31:8]，位置=PC[2:1]，
每组保留最近训练的一个分支；gshare index=实际分支PC[9:1] XOR 9位GHR，
计数器复位01、GHR复位0；仅E级未冲刷条件分支非推测更新GHR，训练使用保存的原index。
query_pc/update_pc在predictor子模块中只传[31:1]，半字对齐由CPU契约保证。
BTB还保存compressed以确定预测截断位置；预测32位分支位于组末半字时，
先取下一组的一个半字完成该指令，再请求预测目标，不把顺序后继送入IB。

RAS在F1请求被I$接受时推测更新；调用push、返回pop、满栈覆盖最老项。
37位检查点：`[36:34]`有效计数、`[33:32]`下一push指针、`[31:0]`当前栈顶值。
空栈时栈顶值无意义。重定向恢复计数和指针、写回保存的栈顶，再按实际指令执行
pop/push；异常使用后端维护的提交点检查点且不执行额外动作。
后端负责从退休指令顺序维护提交点状态，不能直接使用当前推测指针。
协调者明确选择只保存栈顶而非完整栈：错误路径满栈覆盖可能污染更深的预测项，
只影响预测准确率；E级必须核对真实目标，保证架构执行正确。

F2为最多8个半字预留响应空间，按IB当拍可用空间送入0/1/2条指令。
响应可与下一个请求同拍；无IB空间时保存响应且暂停继续取指，不要求I$反压响应。
每个半字保留PC、异常和预测元数据，跨组32位指令的两个半字拼接后作为一条送入IB。

### C-R2 验证与命令

U-08（`cpu_ib`）、U-09（`cpu_predictor`）、组合测试（`cpu_frontend`）均PASS。
前端RVC=1测试包含组末32位预测调用：先顺序请求一个半字再跳预测目标；
RVC=0也单独构建运行。组合测试随机改变I$ ready、缺失延迟和D级消费数量，
覆盖同时响应/请求、预测截断、取指错误传播、较老重定向优先于D重定向、
取消在途请求、halt与FENCE.I接口直连。所有C-R1测试重新PASS，
寄存器堆与CSR另经Icarus复测PASS；新增前端还通过Icarus -g2001语法编译。

```sh
. ~/.local/opt/edrv32/env.sh
mkdir -p build/unit
for n in ib predictor frontend; do
    verilator --binary --timing -Wno-fatal --top-module tb -DSIM_MODE \
        -f verif/unit/cpu_$n/files.f --Mdir build/unit/cpu_$n \
        > build/unit/cpu_$n-compile.log 2>&1 || exit
    build/unit/cpu_$n/Vtb || exit
done
verilator --binary --timing -Wno-fatal --top-module tb -GRVC_EN=0 -DSIM_MODE \
    -f verif/unit/cpu_frontend/files.f --Mdir build/unit/cpu_frontend_no_c \
    > build/unit/cpu_frontend_no_c-compile.log 2>&1
build/unit/cpu_frontend_no_c/Vtb
```

新增和修改的RTL全部 `verilator --lint-only -Wall` 0告警；组合顶层命令：

```sh
verilator --lint-only -Wall --top-module edrv32_cpu_frontend \
    rtl/cpu/edrv32_cpu_frontend.v rtl/cpu/edrv32_cpu_ib.v \
    rtl/cpu/edrv32_cpu_predictor.v rtl/cpu/edrv32_cpu_rvc.v
verilator --lint-only -Wall -GRVC_EN=0 --top-module edrv32_cpu_frontend \
    rtl/cpu/edrv32_cpu_frontend.v rtl/cpu/edrv32_cpu_ib.v \
    rtl/cpu/edrv32_cpu_predictor.v rtl/cpu/edrv32_cpu_rvc.v
```

`tools/check/`仍未在本worktree就位，沿用C-R1协调者确认的合入前补风格工具安排。
RTL人工检查无Tab，非注释行≤100列，文件头包含规格、功能和准确时钟域。
C-R1评审修订包括全部RTL文件头和单元测试头部，以及把乘法器的有效64位乘积命名为
`product_w`，仅物理乘积未使用的两个符号扩展位接入`unused_product_sign_w`。
乘法tech包装仅修改文件头，已单独取得协调者授权。

本次测试计数（Verilator默认确定性随机种子）：U-08满866次、空533次、
同时入出1359次、冲刷137次；U-09满栈覆盖4次、恢复44次、BTB别名替换858次、
饱和保持16次。前端RVC=1：293请求、1133条指令、390次双取、2次kill、
257等待周期、99反压周期、1条跨组指令、4条携带取指错误的指令；
RVC=0：479请求、942条指令、312次双取、2次kill、427等待周期、
165反压周期、2条携带取指错误的指令。计数用于证明上述用例被激励，不代表性能测量。

### C-R2b F2 误取恢复（已解决）

依据用户确认的cpu-spec v0.3第4.4节（协调者提交038716b），原问题
`msg_5ee8edcf1fe7`已由C-R2b实现并通过U-11关闭。

仅在 `RVC_EN=1` 的 `g_rvc_recover` generate分支核对两项：BTB位置是否落在
实际指令的起始半字，以及记录长度是否与实际低半字编码一致。长度核对不需要等
上半字返回，因此即使BTB错误地把32位指令截成16位，也能先恢复而不会拼入目标字节。
半字元数据增加一位保存BTB记录的compressed，前后端179位记录布局不变。

恢复优先级为M/E > D > F2。F2恢复清除对应BTB有效位，取消尚未返回请求，
恢复该预测之前的37位RAS检查点，从包含该位置的实际指令PC重新发请求。
只丢弃待重取指令及其后的拼接内容；IB中更老指令保留，且同拍较老的第一条
指令仍可入队，不会因重取第二条而丢失。

predictor新增内部接口 `clear_valid_i` / `clear_index_i[4:0]`，由F2恢复驱动；
未增加core对外端口、错误标志或RTL计数器。`RVC_EN=0`的固定长度分支将恢复
及BTB清除使能固定为0，不生成边界/长度比较或恢复选择逻辑；Verilator两种配置
lint均0告警，关闭C的展开XML只含 `g_fixed_length`、不含 `g_rvc_recover`。
这是Linux参数展开检查，未声称进行PDS综合或取得器件资源测量。

U-11目录为 `verif/unit/cpu_f2_recover/`，独立命令如下：

```sh
. ~/.local/opt/edrv32/env.sh
mkdir -p build/unit
verilator --binary --timing -Wno-fatal --top-module tb -DSIM_MODE \
    -f verif/unit/cpu_f2_recover/files.f --Mdir build/unit/cpu_f2_recover \
    > build/unit/cpu_f2_recover-compile.log 2>&1
build/unit/cpu_f2_recover/Vtb
```

U-11共8个场景PASS，每场景核对14条指令：同组32位指令上半字、跨组上半字、
记录16位/实际32位、记录32位/实际16位，各触发1次恢复和1次kill；正确16位、
正确32位预测均0恢复0kill；D和M/E同时覆盖F2的场景均0次F2恢复、1次外部kill。
检查包含PC、原始字节、规范指令、每条RAS检查点，及恢复沿后的BTB有效位、
重取PC与RAS状态。较老IB内容在恢复后仍与内存序列一致。

参数展开复现命令：

```sh
verilator --xml-only -GRVC_EN=0 --top-module edrv32_cpu_frontend \
    --Mdir build/unit/frontend_no_c_elab rtl/cpu/edrv32_cpu_frontend.v \
    rtl/cpu/edrv32_cpu_ib.v rtl/cpu/edrv32_cpu_predictor.v rtl/cpu/edrv32_cpu_rvc.v
```

C-R2b完整验收回归：U-01至U-11（U-08/U-09/U-10/U-11含在内），以及前端
RVC_EN=0/1组合测试全部Verilator PASS；这里的U-01至U-11指该范围内已定义的
各项单元测试，不包含CPU模块级或SoC回归。未新增规格差异或待确认行为。
