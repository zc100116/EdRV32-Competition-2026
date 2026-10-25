# CPU 定向测试（C-V4）

对应 cpu-spec v0.9、cpu-testplan 3.3–3.7 / 第4节。共31个测试项；独立构建脚本原有32个配置（E-01含无C配置），统一B1回归扩展为64个配置，见末节。

```sh
. ~/.local/opt/edrv32/env.sh
python3 tools/cpu/build_directed.py
# 单项重跑
python3 tools/cpu/build_directed.py p-03 e-01
```

每项源程序是 `<编号>/main.S`，共用 `common/test.h`，链接器和复位跳板直接使用
`verif/block/cpu/env/{link.ld,boot.S}`。默认关闭自动压缩，保证候选对和PC标签可读。
程序使用 `tohost=1` 报告成功，其他非零奇数报告失败；处理程序核对异常元组后用MRET恢复。
中断处理程序保留被打断代码使用的临时寄存器，并为E-03保存5组mepc/mcause。

输出位于 `build/cpu/directed/<编号>/`：`b1/` 为完整B1程序，含ELF、反汇编、符号表、区域镜像和绝对字节地址 `mem.hex`。
`spike/spike.log` 是Spike提交日志；`spike=compare`时运行同一B1 ELF，`spike=smoke`时另编译
`-DSPIKE_SMOKE` ELF，仅检查Spike可满足的路径。E-01的无C配置位于 `no-c/` 子目录。
构建器对链接器告警报错，对Spike非零退出报错，单次Spike运行超时60秒即失败并终止其进程组。

B1程序不能用冒烟ELF代替。完整B1激励、观察器尚须C-I1接线，当前结果仅说明编译和Spike执行通过，
不表示RTL时序、中断、错误注入、HPM或debug检查已通过。按照协调者答复，`test.yaml`由C-I1在
`verif/block/cpu/<编号>/`统一生成；现有 `tools/regress.py` 只扫描verif，`sw/Makefile`也尚未接入本套程序。
本任务不修改这些共享工具，不在sw下放无法被扫描的回归文件。

## 测试项—程序—检查方法—B1激励

表中程序路径相对于本目录；所有项均需tohost成功，时序项还必须满足配置中的B1检查和覆盖。

| 测试项 | 程序 | 档位 | 检查方法 | 所需B1激励/观察 | Spike |
|---|---|---|---|---|---|
| B-01 | [b-01/main.S](b-01/main.S) | smoke | 年轻指令取消、方向误预测代价3拍 | 冷预测器；E重定向观察 | 同ELF比对 |
| B-02 | [b-02/main.S](b-02/main.S) | smoke | JALR目标变化和错误RAS返回 | 目标重定向与冲刷观察 | 同ELF比对 |
| B-03 | [b-03/main.S](b-03/main.S) | smoke | 链接PC+4，D级重定向代价2拍 | 冷BTB | 同ELF比对 |
| B-04 | [b-04/main.S](b-04/main.S) | full | 六层调用正常返回 | RAS覆盖溢出观察 | 同ELF比对 |
| B-05 | [b-05/main.S](b-05/main.S) | full | 精确异常、M>E>D优先级 | 指定load错误与三种重定向重叠 | 冒烟 |
| B-06 | [b-06/main.S](b-06/main.S) | full | 冲刷无副作用；预测器对照 | 等长NOP补丁对照运行 | 同ELF比对 |
| C-01 | [c-01/main.S](c-01/main.S) | smoke | CSR复位/掩码/WARL/别名/六种操作/非法写 | 复位CSR观察；mtime固定0 | 冒烟 |
| C-02 | [c-02/main.S](c-02/main.S) | smoke | 冻结计数、64位别名、双退休加2 | 独立退休参考写expected_instret | 冒烟 |
| C-03 | [c-03/main.S](c-03/main.S) | full | 事件0–31计数逐项比较；0及保留为0 | 独立事件参考写expected_hpm；miss/设备/wb激励 | 冒烟 |
| C-04 | [c-04/main.S](c-04/main.S) | smoke | time/timeh两个半部精确值 | 固定64位mtime | 冒烟 |
| C-05 | [c-05/main.S](c-05/main.S) | full | 每位debug与定义状态对应 | 逐位观察器，软件读debug_errors | 冒烟 |
| E-01 | [e-01/main.S](e-01/main.S) | smoke | mcause/mepc/mtval/mstatus；含no-C mcause0 | 按PC注入I/D访问错误 | 冒烟 |
| E-02 | [e-02/main.S](e-02/main.S) | smoke | 候选对第一/第二位置异常，老ALU提交一次 | 非法指令必须拆对，不存在实际槽1异常 | 同ELF比对 |
| E-03 | [e-03/main.S](e-03/main.S) | full | 5次IRQ记录、边界PC及计算无遗漏 | 普通/除法/设备/D缺失/重定向5窗口MEIP | 冒烟 |
| E-04 | [e-04/main.S](e-04/main.S) | smoke | MEI>MSI>MTI三次cause | 三IRQ同时置位，逐源清除 | 冒烟 |
| E-05 | [e-05/main.S](e-05/main.S) | smoke | direct/vectored同步入口与MEI偏移 | vectored窗口MEIP | 冒烟 |
| E-06 | [e-06/main.S](e-06/main.S) | smoke | MIE=0唤醒，MIE=1进handler | WFI等待8拍后MSIP | 冒烟 |
| E-07 | [e-07/main.S](e-07/main.S) | smoke | MRET恢复MIE/MPIE，指定mepc返回 | 无 | 同ELF比对 |
| E-08 | [e-08/main.S](e-08/main.S) | full | 设备错误精确异常，年轻无副作用 | 设备写延迟20拍并报错 | 冒烟 |
| M-01 | [m-01/main.S](m-01/main.S) | smoke | 非法指令后设备load/store均不执行 | 设备访问计数均0 | 同ELF比对 |
| M-02 | [m-02/main.S](m-02/main.S) | full | 写响应前后续无退休，回读正确 | 设备写延迟20拍 | 冒烟 |
| M-03 | [m-03/main.S](m-03/main.S) | full | FENCE提交前写缓冲排空 | 写缓冲保持8拍 | 同ELF比对 |
| M-04 | [m-04/main.S](m-04/main.S) | smoke | 旧代码1→写新指令→FENCE.I→42 | 维护各延迟8拍；顺序检查 | 同ELF比对 |
| P-01 | [p-01/main.S](p-01/main.S) | smoke | 867 类型/相关矩阵；配对、失败原因、IB 单条 | WFI 唤醒；单条 IB 取指延迟 | 冒烟 |
| P-02 | [p-02/main.S](p-02/main.S) | smoke | 两组 WAW，检查槽1生效、x0 | 至少一次同组双退休 | 同ELF比对 |
| P-03 | [p-03/main.S](p-03/main.S) | smoke | 24 旁路组合，结果与实际源/消费者槽位 | 旁路覆盖观察器 | 同ELF比对 |
| P-04 | [p-04/main.S](p-04/main.S) | smoke | 12 个间隔场景，比较结果及 E 入口延迟 | D停顿与E入口观察器 | 同ELF比对 |
| P-05 | [p-05/main.S](p-05/main.S) | full | 商余数、整流水停顿、特殊值 | 除法期间逐级保持检查 | 同ELF比对 |
| P-06 | [p-06/main.S](p-06/main.S) | full | CSR 读后依赖与排空/单发射 | CSR发射时E/M状态检查 | 同ELF比对 |
| P-07 | [p-07/main.S](p-07/main.S) | full | I缺失后端继续、D缺失冻结前级 | I/D各20周期延迟 | 同ELF比对 |
| P-08 | [p-08/main.S](p-08/main.S) | smoke | 连续写与字节/半字合并、符号扩展 | 全命中；写缓冲吞吐检查 | 同ELF比对 |

## b1.json 配置契约

配置采用标准JSON，方便C-I1用Python标准库读取。它是C-I1的接线输入，当前B1模型本身尚不直接读取此文件。
`checks`中的每项均为必须实现的断言/覆盖义务，不能仅解析`spike`然后宣告B1成功。

| 字段 | 含义 |
|---|---|
| `test` / `tier` | 测试编号、testplan档位；full包含smoke |
| `rvc` | 依次运行的RVC_EN配置，true或false |
| `spike` | compare：同一ELF可比对退休；smoke：另编译SPIKE_SMOKE，仅做参考冒烟 |
| `stimulus` / `checks` | 激励和判据的完整文字说明 |
| `schedule` | 按下面kind契约接线的激励记录；PC/地址一律从对应B1 ELF符号表解析 |
| `cases` | P-01配对矩阵、P-03旁路目标、P-04结果延迟场景 |
| `device` | 合成B1设备寄存器组的符号、地址、长度和初值 |

默认环境：所有irq=0，I$/D$全命中且ready=1，命中按规格下一拍响应；无错误注入；
维护操作在下一拍完成；所有设备寄存器为0。除显式delay/error外，不叠加随机缺失/反压，以免改变周期测试条件。
设备符号在B1 ELF中为`0x40000000`（B1合成寄存器组，不代表SoC外设寄存器），在Spike冒烟ELF中为SRAM后备存储。
该地址符合C-V2内存模型的设备分类。M-01在Spike运行完整ELF，设备路径被精确异常跳过。

`schedule`记录的kind：

- `delay`：在port=ic/dc指定PC或地址的请求上，额外等待cycles拍后响应；地址表达式`symbol & ~7`表示8字节对齐取指块。
- `error`：仅指定PC/地址的请求返回错误。response_delay指定等待拍数；response_when指定竞争窗口。
  `apply_store=false`表示错误写不能改变设备值。E-01的fault_load/fault_store仅各自出错，其余scratch访问正常。
- `irq`：when描述一次精确的流水/事件条件，source可为一个源或三源数组，after_cycles为条件出现后的等待拍数，
  clear描述下降沿条件。每项默认一次；E-03五个窗口分别一次，不能合并成一个长电平。
- `write_buffer_hold` / `maintenance_delay`：分别延后写缓冲排空、指定维护操作完成，单位为时钟周期。
- `paired_run`：原程序和对指定PC写入word后的对照程序各复位运行一次，在相同已解析条件分支历史后比较指定预测行为。
- `mtime`：固定外部mtime_i为给定64位值，不按周期自增。
- `reference_write`：独立观察器按给定公式算参考值，在指定时刻写入软件邮箱；软件load前必须写好。
- `event_window`：对N=0..31分别运行。HPM使能/冻结CSR实际生效界定窗口；对事件1–16需同时观察到非零对应事件。
  根据独立模型的事务起止、真实发射/退休计算参考，不读取硬件HPM计数值作为期望；冻结后写`expected_hpm+4*N`。
- `debug_observer`：逐位比对规格7.2定义的内部状态与debug_o，失败打印位号/期望/实际/周期并结束。
  也在P-01/B-01/E-01运行；`debug_errors`为软件最终检查的错误计数。

C-02的`expected_instret`按IR使能时真实退休条数累计，双退休加2，计数器CSR写优先于自动增加。
C-03周期事件的参考可从独立接口模型、退休序列及流水观察推导；事件5–8须独立解码候选指令和配对条件并应用5>6>7>8优先级。
事件13/14用模型实际缺失开始计数，事件15按真实dc_wb_event_i脉冲计数，事件16只数E/D重定向。
软件邮箱供程序内部逐项比较，B1检查器同时承担精确时间关系和覆盖要求；缺少观察器接线的运行不能算完整通过。

P-03 cases中源级/管线/操作数/消费者槽位是必须命中的覆盖目标，实际发射由B1观察器确认；
不能仅凭源程序排布认定覆盖。P-04以实际生产者/消费者E入口和D冒险状态判定结果延迟2/3/2，不将指令间隔误当周期数。
B-05必须观测M异常、E重定向、D重定向同拍，否则该场景未覆盖。

## 覆盖目标对应

| 验证方案第4节覆盖 | 程序/检查 |
|---|---|
| 双发射、四种配对失败原因 | P-01/P-02；P-01的半块入口加下一块延迟制造IB单条 |
| 6源 × 2操作数 × 2槽位旁路 | P-03的24条cases，逐条确认实际路径 |
| 异常原因 × 可达槽位 | E-01（含no-C）、C-01、E-08；E-02检查候选对第二位置拆对 |
| E方向/目标、D、异常、中断、MRET、FENCE.I重定向 | B-01/B-02/B-03、E-01/E-03/E-07、M-04 |
| load-use/乘法/除法/CSR/I缺失/D缺失/设备停顿 | P-04/P-05/P-06/P-07、M-02 |
| 五种中断到达窗口 | E-03 |

协调者已确认的适用性：4.2禁止非法/取指异常进入槽1且槽1仅ALU，实际槽1异常不可达；
E-02检查候选对第二位置，协调者会同步验证方案。MEI>MSI>MTI按标准优先级，协调者将补入规格。
C-01在软件首读前mcycle/minstret已前进，复位零需要B1在复位释放时直接检查；其他稳定CSR由软件比较。
`misa`及ID、WARL、HPM、计数器时序与Spike不同的断言仅在B1完整版本检查。
cpu-spec v0.9已统一EBREAK的mtval为指令PC，P-01/E-01与Spike采用相同期望。

## 验证记录

参考工具基线为C-V1 `144949a`，规格读取协调者分支v0.5；复现命令见顶部。
本次交付未执行RTL仿真：C-V2尚未合并，C-I1须将本表的观察/激励义务接入真实core，之后才能报告B1结果。
生成物不入库，Spike日志、ELF、反汇编和构建诊断均保存在上述build目录。

验证命令 `. ~/.local/opt/edrv32/env.sh; python3 tools/cpu/build_directed.py`：
31项、32个配置全部到达成功tohost，其中17项运行同一B1 ELF，14项运行明确标注的Spike冒烟ELF，
另有E-01 no-C配置；全部完整B1版本也已编译，所有build.log为空（零诊断）。
`PYTHONPYCACHEPREFIX=build/cpu/pycache python3 -m py_compile tools/cpu/build_directed.py`通过。
仅新增汇编/Python/JSON/README，没有HDL改动，Verilator lint不适用。

## C-I1/C-I2 接入

统一回归由 `tools/cpu/generate_regress.py` 生成、`tools/cpu/run_b1.py` 执行。
31 个既有测试项各有有 C / 无 C 两种构建，另有 M-04 的两种 FENCE.I clean 阶段
IRQ 激励，共 64 个定向配置。I-03 合入 E-01 的无 C 激励，不新增测试项。
P-01 用连续序列化指令预填 IB，观察器要求每个矩阵项实际出现两个候选；P-03
使用独立填充指令和序列化起点，逐一检查真实旁路源；P-04 对紧邻消费者检查
精确结果延迟。C-02/C-03 的参考邮箱由独立退休/事件模型写入，未读取硬件计数器
作为期望值。每项的义务未命中时明确失败。

协调者已确认：原表中 17 项 `spike=compare` 保持同 ELF 严格逐条比对；14 项
`spike=smoke` 用完整 B1 程序的软件自检和独立断言验收，参考冒烟版另外运行并
单列为 `SPIKE_SMOKE`，不计作逐条比对通过。新增 M-04 IRQ 配置按中断测试自检。
