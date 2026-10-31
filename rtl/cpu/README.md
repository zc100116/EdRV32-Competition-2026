# EdRV32 CPU — RTL 与 B1 联调

`edrv32_cpu_core` 集成RV32IM、Zicsr/Zicntr、Zifencei和可选RV32C，
单一clk_sys时钟域，参数仅有 `RVC_EN`。当前包含数据通路、前端与D/E/M/W后端。
当前行为依据协调者已确认的 cpu-spec v0.9 与开发约定；早期 C-R1/C-R2/C-R3
依据 v0.4–v0.6 开发。共享规格、rtl/include 和 rtl/filelists 由协调者维护。

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
| `edrv32_cpu_csr` | 42位select、access_valid、write/commit、2位command、32位write_data；D级12位decode_addr译码为42位decode_select并检查权限；retire_count[1:0]、event_count[31:0]；trap与MRET；IRQ和mtime | 组合read_data/illegal，以及mstatus/mie/mtvec/mepc；提交沿更新；参数RVC_EN默认1 |

ALU operation 为 `{SUB/SRA选择, funct3}`：0 ADD、8 SUB、1 SLL、2 SLT、3 SLTU、
4 XOR、5 SRL、13 SRA、6 OR、7 AND。LUI/AUIPC 在流水控制中使用独立 class。
译码 class：0 ALU、1 LUI、2 AUIPC、3 JAL、4 JALR、5 BRANCH、6 LOAD、7 STORE、
8 MUL、9 DIV、10 CSR、11 SYSTEM、12 FENCE、13 FENCE.I。
未实现/保留指令由 illegal 指示，其他控制输出仅在指令合法时使用。

乘法 operation：0 MUL、1 MULH、2 MULHSU、3 MULHU。
除法 operation：0 DIV、1 DIVU、2 REM、3 REMU。
乘法E输入经过M/W两级寄存器，匹配规格结果延迟3；本单元并不额外插入第三级寄存器。

CSR command：1 WRITE、2 SET、3 CLEAR，读访问时write=0。
write_i 表示架构上实际发生的写入：调用方按CSRR[S/C]的源寄存器号或zimm
是否为0决定，而不是按操作数数值判断。access_valid_i 可用于提交前非法访问检查，
实际提交时才使能commit_i。非法访问不修改状态。
event_count_i 每个事件占2位，编码1对应[1:0]，编码16对应[31:30]，值0/1/2；
编码0、17–31不计数。调用方负责生成规格7.1定义的事件及配对失败原因优先级。
trap_i 的pc/cause/value由后端提供，覆盖同拍CSR写和MRET。

## C-R2 前端接口

新增 `edrv32_cpu_frontend` 集成 F1/F2、`edrv32_cpu_predictor` 和
`edrv32_cpu_ib`，复用 `edrv32_cpu_rvc`。时钟域均为 clk_sys，前端参数仅有
规格允许的 RVC_EN；BTB=32、gshare=512、RAS=4、IB=4 均为固定 localparam。
复位入口遵守 SoC 5.3，PC=0。

后端提供 `decode_pop_count_i[1:0]`（0/1/2），每个时钟沿取走最老的指定数量记录；
不得超过 `decode_valid_count_o`。`decode_data_o[357:0]` 的低179位是最老指令，
高179位是下一条；仅有效记录有意义。`ib_count_o[2:0]` 为全部IB占用数。

每条179位记录的字段如下，前后端用同名 `REC_*` localparam 取得字段：

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
调用/返回按x1/x5链接寄存器分类；按协调者确认的范围，rd和rs1均为链接寄存器
且不同时的JALR按call处理，只push，不做协程pop-then-push。`return_pc`是PC+2/4。

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

## C-R3 后端与提交

D从IB取最老1/2条，双译码和4读寄存器堆，按规格4.2进行配对。
同组RAW禁止、同组WAW允许且槽1写入优先；槽1只支持ALU/LUI/AUIPC。
旁路按W→M→E覆盖选择，每一级中槽1覆盖槽0，保证最近且最年轻的生产者优先。
load在E阻塞消费者1拍，乘法在E/M阻塞消费者2拍，CSR读在E阻塞1拍；
消费者分别在结果延迟2/3/2满足时进入E。

CSR单独发射，等待E/M中更老指令排空。CSR文件的`write_i`用于架构写访问及非法
判定，新增`commit_i`仅在M提交时使能状态修改；D探测访问不会提前改变CSR。
除法在E等更老M/W排空后启动，迭代时D/E/M/W冻结；结束后经M/W写回。
已接收的I$响应仍须保存，前端停止发起新的取指请求。

E完成ALU、地址与对齐、分支/跳转、乘法和除法。D处理BTB未命中JAL重定向；
E核对方向和目标，并对普通指令被错误预测为跳转的情况重定向、清除BTB。
这包含槽1的ALU：槽1错误预测重定向仍保留同组两条指令进入M；
槽0重定向则冲刷年轻的槽1。M重定向优先于E、D、前端F2恢复。

D$请求仅在E指令本周期确定进入M时有效（包括ready条件），M停顿不发新请求。
M等待load/store响应，load按size/unsigned符号扩展；store数据在提交时提供。
`dc_commit_o`每条访存单拍；设备访问发出提交后用控制位记住，等待最终响应期间
不重复提交，不让该指令进入W，保持非推送store语义。
M异常/中断取消尚未提交的D$请求；未发出请求的对齐/非法异常不产生无关kill。

同步异常随指令到M，M槽0异常不提交该组；按配对规则，槽1只容纳无异常ALU，
不保留槽1异常状态。中断优先级MEI>MSI>MTI，设备已提交访问、除法与FENCE.I
执行期间不接受中断。EBREAK的mtval为指令PC；非法短编码不包含后续半字。
CSR trap更新优先于CSR写和MRET，vectored只对中断增加4×cause。
MRET恢复mstatus并跳mepc；WFI提交后停止新取指，被使能中断等待即可唤醒，
不依赖全局MIE。FENCE等D$排空；FENCE.I按clean_all→ic_inv→提交/下一PC重取。

M→W是不可撤销提交点，W写回、退休。后端维护独立的提交RAS（4项），
按实际提交的call/return更新；异常恢复提交点检查点，较年轻预测不污染它。
数据寄存器和寄存器堆不复位，valid、状态与指针异步复位。

## HPM、debug与退休追踪

CSR文件负责mcycle/minstret/mhpmcounter的存储与inhibit；core生成事件0–16。
配对失败按RAW、结构、类型、第二条未取到的优先级；除法、load-use、设备等待、
前端断流分别计数。I$/D$缺失由接受请求后下一拍未响应判定一次，设备不作为D$缺失。
用户确认的新增顶层输入`dc_wb_event_i`每个脏行写回突发给1拍，含维护写回，
作为HPM事件15；否则core没有足够信息从原有D$端口观测脏行写回。

`debug_o`按规格7.2驱动全部字段。顶层保留3.4全部trace内部线网，无新增trace端口。
Verilator public_flat_rd注释只用于保持这些验证信号可观察，不含RTL断言或条件编译。
新增三个已确认的追踪字段：

| 信号 | 布局/编码 |
|---|---|
| trace_bypass_w[11:0] | 4个3位字段：槽0 rs1/rs2、槽1 rs1/rs2；0 RF/未使用，1 E0，2 E1，3 M0，4 M1，5 W0，6 W1 |
| trace_redirect_cause_w[1:0] | 0无，1条件方向错误，2目标错误，3普通指令被预测跳转 |
| trace_stall_cause_w[2:0] | 0无，1load，2乘法，3CSR读，4CSR等更老E/M排空，5除法；同时成立取最小值，M停顿另见debug |

## F2 误取恢复（C-R2b已解决）

仅`RVC_EN=1`的`g_rvc_recover`核对实际起始半字和长度两项。
不符时取消在途请求、清除该BTB项、恢复预测前37位RAS并从实际指令PC重取。
保留IB中更老指令，同拍第一条正常指令也可入队后重取第二条。
关闭C时只生成固定长度分支，恢复使能为常量0，未增加其他检测、计数或错误标志。

frontend内部新增`update_clear_i/update_clear_index_i`，供E清除已变为普通指令的
陈旧BTB项；预测器训练仍只对未被更老异常/重定向冲刷的实际分支进行。

## 统一验证与复现

全部CPU测试现用tools/regress.py清单：top/files/defines/parameters/software/
timeout/pass/tier/simulator，files.f中的路径相对于各自文件所在目录。所有U级均纳入smoke；
寄存器堆、CSR另外自动运行Icarus。RVC参考表由testbench调用Python在build下生成。
移除编译的-Wno-fatal；通过实际告警修正和正确文件顺序处理timescale与位宽。

```sh
. ~/.local/opt/edrv32/env.sh
make smoke
make lint
python3 tools/check/verilog_style.py rtl/
verilator --lint-only -Wall +incdir+rtl/include --top-module edrv32_cpu_core \
    rtl/cpu/*.v rtl/tech/edrv32_mul_s33x33.v
verilator --lint-only -Wall -GRVC_EN=0 +incdir+rtl/include --top-module edrv32_cpu_core \
    rtl/cpu/*.v rtl/tech/edrv32_mul_s33x33.v
```

C-R3交付时的结果：make smoke为33 PASS、0 FAIL（含P0）；make lint通过，
verilog_style.py为22文件、0告警；core两种RVC配置独立-Wall lint均0告警。
日志在build/cpu-smoke-acceptance.log、build/cpu-lint-final.log及build/regress/smoke/。
各test目录README列出框架入口与配置；无需人工先生成引用数据或软件镜像。

| 测试 | 结果 |
|---|---|
| U-01 decode | PASS，393216编码组合与定向控制 |
| U-02 RVC | PASS，65536半字 |
| U-03/U-04 ALU/branch | PASS，随机与边界 |
| U-05/U-06 mul/div | PASS，四种操作、延迟与边界 |
| U-07 regfile | PASS，Verilator与Icarus |
| U-08 IB | PASS，队列模型随机检查 |
| U-09 predictor | PASS，BTB/gshare/RAS模型 |
| U-10 CSR | PASS，Verilator与Icarus；另含不提交写访问无副作用 |
| U-11 F2 recover | PASS，8场景 |
| frontend RVC=0/1 | 两配置PASS |
| core_smoke RVC=0/1 | 两配置PASS，各432拍、334条观察到的退休、81次双退休 |

顶层冒烟用理想I$/D$模型，命中下一拍返回、平坦ROM/SRAM、tohost判定。
程序覆盖ALU、宽度/符号访存、分支、乘除余、CSR、FENCE/FENCE.I、
SRAM自修改指令及槽1陈旧预测、紧邻store/load。该单元冒烟与独立B1环境互补；B1的ISA比对、随机缺失/错误/中断回归入口见
`tools/cpu/README.md`。本目录的Linux验证不包含PDS时序或资源测量。

## 已确认的实现约定

- v0.4规定CSR复位/WARL/计数器写优先、精确trap优先，已实现，无保留的旧差异。
- 用户确认v0.5新增dc_wb_event_i；HPM13/14按协调者指定的响应时序判定。
- 用户确认v0.6新增三个内部trace字段，按原有选择和停顿逻辑驱动。
- 协调者确认除法先排空更老M/W再开始，迭代期间冻结，完成后经M/W写回。
- 协调者确认普通指令的错误预测也做E恢复并清BTB；协程JALR按call只push。
- 协调者授权sw/Makefile的通用ARCH默认值与可选program.mk包含机制，cpu_smoke
  指定rv32im_zicsr，BSP采用同一ISA，两种RVC core运行同一合法软件镜像。

没有因10分钟未答复而先行采用的未确认约定。未修改共享规格或文件列表，未合入main。

## 共享rtl/filelists/cpu.f内容

以下路径相对rtl/filelists/cpu.f；按tools/regress.py文件列表规则解析：

```text
+incdir+../include
../cpu/edrv32_cpu_core.v
../cpu/edrv32_cpu_frontend.v
../cpu/edrv32_cpu_ib.v
../cpu/edrv32_cpu_predictor.v
../cpu/edrv32_cpu_rvc.v
../cpu/edrv32_cpu_decode.v
../cpu/edrv32_cpu_regfile.v
../cpu/edrv32_cpu_alu.v
../cpu/edrv32_cpu_branch.v
../cpu/edrv32_cpu_mul.v
../cpu/edrv32_cpu_div.v
../cpu/edrv32_cpu_csr.v
../tech/edrv32_mul_s33x33.v
```

## C-I1/C-I2 联调结果

功能 RTL 修复截至 `503c67a`，显式 RVC 参数的 lint 等价修订为 `8a223df`；
真实 B1、生成清单与软件适配见本次集成提交。
复现命令为 `. ~/.local/opt/edrv32/env.sh` 后执行 `make smoke`、`make full`。
最终 smoke 为 **135 PASS / 0 FAIL**，full 为 **820 PASS / 0 FAIL**，包含 P0、cache、
CPU 单元测试和 746 个真实 B1 配置（RVC_EN=1：388；RVC_EN=0：358）。

CPU 配置中 714 项严格逐条比对 Spike，其中 155 项同时比对全部架构签名；
30 项按协调者确认，以完整 B1 程序自检和独立观察器判定，另跑参考冒烟版；
2 项 ma_fetch 采用已确认的 tohost 判据。400 个随机流均严格比对，包含随机缺失和反压。
B-06 另外进行两次 NOP 补丁对照并比较真实预测器状态。

`tools/cpu/coverage_report.py` 合并 748 次真实仿真，覆盖 **57/57**；
`build/cpu/full-coverage-report.md` 为逐项报告。未混入桩或人工覆盖自测数据。
`make lint`、`tools/check/verilog_style.py rtl/` 和 core / core+cache 两种 RVC 的
独立 `-Wall` lint 均为 0 告警。完整日志位于 `build/cpu/make-smoke-final.log`、
`build/cpu/make-full-final.log`、`build/cpu/make-lint-final.log`。
