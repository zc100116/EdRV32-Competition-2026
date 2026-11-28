# CPU v2 NONE 核级集成调试

实现与验证提交、最终回归数字见 `verif/block/cpu2_core/README.md`。
工具：GCC 15.2.0；Verilator 5.051 devel（v5.050-99-gf8fb1d664）。

## 1. 现象

- 恢复拍旧 IB 分配：`rv32ui-add` 已通过 ADD 检查，ECALL 后最终却写 `tohost=0x539`。
- 完成锁：双发射 CoreMark 在 8920 条退休后停于 `0x10003c74`；另有分支背压 tag 别名问题。
- FENCE.I 分类：`rv32ui-fence_i` 在 `PC=0x800001d0` 的 `0x0000100f` 报非法指令。

## 2. 复现

```sh
. ~/.local/opt/edrv32/env.sh
python3 tools/cpu/build_cpu2_tests.py --suite isa
python3 tools/cpu/run_cpu2_core.py --width 1 --program rv32ui-add
python3 tools/cpu/run_cpu2_core.py --width 2 --program rv32ui-fence_i
```

旧 IB 问题在修复前两宽均复现。诊断仿真加 `+CONTROL_LOG`，或 `+TRACE=<文件>` 记录退休事件。
原始测试和构建日志归档于 `build/i06/`；完整测试输出位于 `build/cpu2_core/w{1,2}/`。

## 3. 观察

- 单发射 ADD：1296 拍 ECALL 在 `0x80000650` 触发 cause 11，并发出 cancel。
- 1297 拍 `commit_redirect_valid=1`，同时 `allocate_valid=1`、PC 为旧 IB 的 `0x80000654`。
- 1300 拍该年轻非法字 `0xc0001073` 再次触发 cause 2，覆盖原陷阱状态。
- FENCE.I：693 拍 cause 2、mtval `0x0000100f`；此前 store 已退休，FENCE.I 本身未退休。

- CoreMark 波形末态：branch pipe0 的 skid valid=1/tag0，local lock valid=1/tag2，
  compare0 valid=0；取消的旧结果已离开，但锁仍指向旧 tag。
- 分支单元新增复现：无效 pipe1 与 pipe0 同 tag 的背压用例在修复前报结果丢失。
- 分支/ALU 新就绪 MEM 取消用例均在修复前失败；ALU 新 tag 结果 valid=0。

## 4. 根因

- 恢复拍：commit 重定向注册输出，IB 在重定向边沿清空；边沿前旧头仍有效。
  issue 仅在 cancel 当拍禁止分配，下一拍仍能分配即将被前端清除的旧头。
- FENCE.I：所有有序系统指令共享 CSR 请求通道；`edrv32_cpu2_csr.v:129` 的 `req_illegal_w` 仅检查 funct3 非零，
  缺少 SYSTEM opcode 限定，将 funct3=1 的 FENCE.I 当作不存在的 CSR 0 访问。
- 最初怀疑 ECALL 译码合法性；检查发现 `legal_w` 默认已为 1，未实施该无效改动。

- 分支全局锁（`branch.v:1395`）以 `compare1_tag==lock_tag` 选管线，未检查 compare1 valid，旧无效 tag 可劫持结果。
- ALU/branch 局部锁（`alu.v:162/546`、`branch.v:615/1001`）只清“此前已锁定”的取消项；新就绪且同沿取消的结果仍能建立锁，
  随后结果被清而锁残留。branch 全局锁同类建立条件也缺取消限定。

## 5. 修复

- 经协调者批准，top 在寄存 commit/branch 重定向有效时屏蔽送 issue 的两个 IB 头 valid。
  其他字段直连；该拍 remove/allocate 自然为零，IB 在边沿清空。
- 按协调者“明确根因、≤10 行可先修”授权，为 CSR 非法判定加 opcode `7'h73` 限定。
- 观察线按授权由模块输出复用已有 trace/HPM/debug 状态；未使用层次引用或复制架构状态。

- 在已授权的 ≤10 行明确缺陷范围内，分支选择要求 pipe1 valid；ALU/branch 取消项不再建立锁。
  取消仍按原年龄边界，不新增状态/兜底；三处缺陷均由单元失败和修后通过证明。

## 6. 防回归

- `env/trap.S`：ECALL、EBREAK 后紧跟非法字；处理器跳过该年轻字，并校验 cause/mtval。
  同一程序检查未对齐 load/store 的 cause 4/6、原地址 mtval 和四次处理计数。
- `env/redirect.S`：条件分支循环与冷 JAL 后的错路非法字及失败 store 必须被取消。
- `tb.sv`：所有 commit/branch 恢复拍断言 allocate/remove 为零；两宽运行。
- `verif/unit/cpu2_csr/tb.sv` 增 FENCE.I 通道合法完成检查，六配置运行。
- 原 `rv32ui-add` 与自修改代码 `rv32ui-fence_i` 纳入两宽核级 smoke。

- branch 单元新增无效管线同 tag 背压、刚就绪 MEM 结果取消两例；ALU 单元增加后者。
  两模块六配置均测；核级 CoreMark 两宽复测，程序退休条数相同。

## 7. 同类排查

- branch 重定向与 commit 重定向使用同一 top 屏蔽点。
- CSR 架构写判定原本已有 opcode 限定，无须修改。
- FENCE funct3=0、MRET/WFI 均沿原系统请求/提交路径；未新增异常兜底或重试。
- 按同一取消建立规则检查 ALU 两管线、branch 两管线及全局锁，并补对应复现测试。


## 8. I06P：同 ELF 性能定位与授权修复（2026-11-28）

代码提交：LSU `279af665c`、early_resp `aff3a92ae`、观测/复现工具 `c4589f343`。
对照 RTL 基线 `86f413ddf`；NONE、ISSUE_WIDTH=1/2，GCC 15.2.0、Verilator 5.051 devel。
两项修复均先取得协调者授权；完成队列容量、寄存信用、LSU 单请求结构保持冻结行为。

### 8.1 口径

直接把模型输入 `build/cpu-v2/isa/zba/coremark/coremark.elf` 后门加载到同一核级 BFM，
10 次迭代。模型和 RTL 都用 start_time 首指令到 stop_time 首指令的退休窗口；观察
区间为 [start, stop)，两宽都精确退休 2,456,216 条。模型 ELF 的 start/stop 为
100049c0/10004a4c，I06 原 ELF 为 100048ac/10004938；启动、输出代码和布局不同。
两者均为 O3、funroll-all-loops、finline-limit=600、函数/跳转/循环对齐 4、ILP32、
RV32IM/Zicsr/Zba；I06 构建另显式列入 Zifencei，完整命令见 core2 README/构建脚本。
不把两份 ELF 的周期直接当作修复前后比较。

BFM 保留固定小等待与真实 I$/D$ refill；原模型 IcacheProbe(1) 只计增量 1 拍
I$ miss，没有等价 AXI refill/存储器探针，也没有真实有限完成队列/寄存信用和
串行 LSU 接受间隔。下表“模型”专指任务给定的原无限完成窗口模型，源码基线
`86f413ddf`；模型 worker 已另提交 `83aebc308` 加入容量，默认值已改变。
新模型脚本重现旧口径时须加 `--completion-entries 0`，不能把新默认结果混入此表。

| 同模型 ELF | 原模型 W1 | RTL 前 W1 | RTL 后 W1 | 原模型 W2 | RTL 前 W2 | RTL 后 W2 |
|---|---:|---:|---:|---:|---:|---:|
| 窗口周期 | 2673925 | 3785675 | 3534269 | 1599073 | 3314628 | 3053180 |
| CoreMark/MHz | 3.739821 | 2.641537 | 2.829439 | 6.253623 | 3.016930 | 3.275274 |
| 退休 IPC | .918581 | .648818 | .694971 | 1.536025 | .741023 | .804478 |
| 2 条退休拍 HPM1 | 0 | 0 | 0 | 1029338 | 749334 | 747627 |
| 0 条退休拍 HPM3 | 217709 | 1329459 | 1078053 | 172195 | 1607746 | 1344591 |
| IB 空拍 | 未单列 | 105883 | 105900 | 未单列 | 31117 | 32315 |
| 完成队列 credit=0 拍 | 未建模 | 640790 | 456365 | 未建模 | 1164695 | 914081 |
| LSU 非 ready 拍 | 未建模 | 1248461 | 980967 | 未建模 | 1286442 | 1018912 |
| store 队头拍 | 未单列 | 653342 | 383754 | 未单列 | 717365 | 447522 |
| 最短缓存 store 队头拍 | 未单列 | 4 | 2 | 未单列 | 4 | 2 |
| RAW 配对失败 HPM5 | N/A | 0 | 0 | 150516 | 151853 | 151710 |
| 结构/操作数失败 HPM6 | N/A | 0 | 0 | 98468 | 802214 | 802655 |
| 类型失败 HPM7 | N/A | 0 | 0 | 112443 | 51446 | 51909 |
| 仅一条 HPM8 | N/A | 0 | 0 | 31778 | 4377 | 4676 |
| load 等待 HPM9 | 153881 | 400796 | 335974 | 163814 | 396679 | 333048 |
| 分支依赖 HPM12 | 49360 | 105381 | 108841 | 22120 | 30250 | 33117 |
| 执行误预测 HPM16 | 49340 | 52372 | 52371 | 12949 | 12797 | 13047 |
| F2 更正 | 0 | 0 | 0 | 45754 | 39301 | 39305 |
| I$ miss HPM13 / miss 状态拍 | 未等价计数 | 318/1908 | 318/1908 | 未等价计数 | 324/1944 | 324/1944 |
| D$ miss HPM14 / miss 状态拍 | 未等价计数 | 22/132 | 22/132 | 未等价计数 | 22/132 | 22/132 |
| DIV/设备等待 HPM10/11 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 |

这些事件有重叠，不能相加为总周期。退休 trace 另确认两宽均有 504,996 条分支，
RTL 当前 HPM4 连接没有计入这项，表中使用 trace 分类，未把 HPM4=0 当作没有分支。
修后重定向到目标首次 allocate 的匹配记录：W1 EX 52371 次/157771 拍；
W2 F2 29252/262764、EX 12258/37413、MEM 769/2372。
F2 统计含保留的较老 IB 指令排空，且仅统计窗口内匹配成功的事件，不能作为独占
恢复停顿。原模型 redirect E/M/D 为损失槽数，W1 184420/0/9707，
W2 36504/5308/5969；不是同单位的恢复延迟，不能直接相减。

### 8.2 最大差距与证据

1. 完成窗口是双发射最大的结构限制。`completion.v:247` 的 credit 来自 count_r，
   `:273` 在退休沿更新 count，`:497` 先捕获 done，下一拍才供 commit 退休。
   NONE 深度为 4；allocate E0、完成捕获 E1、退休 E2、信用 E3 可用。
   新增热缓存 dispatch.S 在没有 IB 空/访存等待/miss 时，64 条独立 ALU 指令：
   W1 64 拍（IPC=1），W2 48 拍（IPC=4/3），后者 16 拍队列满且正在退休。
   原模型 IPC=1.536 已超过这个纯 ALU 上限。修后 W2 HPM6 的 762783/802655
   （95.03%）由 credit<2 引起，操作数 24038、通道 15834。
   修后队列全满拍中，W1 正在退休/头 store/头 load 为 216374/158452/51520，
   W2 为 519037/278064/234837。协调者决定保留冻结结构，另扫模型 N=4/8/16。
2. LSU 接受吞吐/提交串行化。`lsu.v:257` 仅 S_IDLE 接收普通请求；
   热缓存 load_stream.S 的 64 个独立 load：W1 127 拍、W2 126 拍，均无 I$/D$ miss，
   LSU busy 63 拍；early 查询 61、命中 0。真实 load 接受间隔约 2 拍，原模型约 1 拍。
   原模型 early_loads W1/W2 为 334064/260738；修后 RTL 查询/命中为
   325863/150971、324195/138762。模型可短路的 load 与真实下一拍预约可用性不同，
   不能把查询都当作短延迟成功。单发射没有 EX/MEM late 依赖执行，本次 early 输入
   对其不建立 ID 反馈路径；W1 提速主要由 store fall-through 产生。
3. 缓存/预测不是百万拍差距的主因。真实 miss 状态总计约 2 千拍；执行误预测次数
   接近原模型。分支依赖和恢复有次级差异，但不能解释队列和 LSU 的数量级差距。

### 8.3 修复、复现与回归

- LSU `edrv32_cpu2_lsu.v:230,288,380,388`：原 AUTHORIZE→COMMIT 和最终
  BEAT_DONE→DONE 各引入一个无必要的等待拍。授权后第一 beat 直接提交，最后 done
  直接向 commit 报告；背压时仍保留原寄存状态，FD 第一 beat 明确使用低字。
  单元新增授权同拍 valid、最终 done 同拍 valid/data/error、ready 时回到 idle
  检查；在旧代码上报“authorization did not fall through to first beat”，修后
  NONE/F/FD 三配置 PASS，覆盖双 beat、设备、错误和背压。
- early_resp `top.v:1235,1331`、`alu.v:181`、`branch.v:634`：原 top 将 LSU
  early 回应仅放到 unused_w，late 操作数只等普通 completion。按协调者授权为两模块
  接入 valid/tag/hit/data；只在 valid&&hit&&tag 匹配时按既有 EX/MEM 捕获路径接收。
  不产生重复 load completion，不反馈 ID。ALU/branch 单元均增加 early miss 保持等待、
  随后 early hit 唤醒而普通 completion 不到达的用例；各六配置全部 PASS。
- 两宽各 55 个核级程序 PASS：原 53 个加 dispatch/load_stream；含 rv32ui/rv32um/Zba、
  trap/redirect。完整 I06 CoreMark 各一次通过，list/matrix/state CRC e714/1fd7/8e3a、
  最终 fcaf，退休 2,477,565 条。原 ELF 修后 W1 3520496 拍/2.840509 CM/MHz，
  W2 3054727 拍/3.273615；同 ELF 对照以前述模型 ELF 表为准。
- 风格 22 文件 0 告警；两宽 NONE top `--lint-only -Wall` 0 告警。
  单元有效最终结果为 LSU 三配置、ALU 六配置、branch 六配置 PASS。

复现命令（加载仓库 GCC 环境，在仿真目录执行）：

```sh
python3 tools/cpu/build_cpu2_tests.py --suite isa
python3 tools/cpu/run_cpu2_core.py --width 1
python3 tools/cpu/run_cpu2_core.py --width 2
python3 tools/cpu/build_cpu2_tests.py --suite coremark
python3 tools/cpu/run_cpu2_core.py --width 1 --program coremark --no-build
python3 tools/cpu/run_cpu2_core.py --width 2 --program coremark --no-build
python3 tools/cpu/cpu2_perf.py --elf build/cpu-v2/isa/zba/coremark/coremark.elf --width 1
python3 tools/cpu/cpu2_perf.py --elf build/cpu-v2/isa/zba/coremark/coremark.elf --width 2
python3 tools/regress.py full --path verif/unit/cpu2_alu
python3 tools/regress.py full --path verif/unit/cpu2_branch
python3 tools/regress.py smoke --path verif/unit/cpu2_lsu
python3 tools/cpu/eval/run_v2_single.py coremark --completion-entries 0
python3 tools/cpu/eval/run_v2_round4.py coremark --bases full --names combo4-zba --completion-entries 0
```

`cpu2_perf.py` 的 +PERF_ONLY 在 stop_time 即结束，适用于模型 ELF 的 HTIF 输出环境；
这只验证窗口而不检查输出 CRC，CRC 由完整 CoreMark 核级运行另验。
原始逐项数值写入 build/cpu2_perf/w{1,2}.log；定向窗口也可用同脚本选择
build/cpu2_core/programs/dispatch/dispatch.elf 或
build/cpu2_core/programs/load_stream/load_stream.elf。所有观测均在验证环境，
没有增加 RTL 参数、架构状态或运行门禁。剩余容量/LSU 结构差异交协调者的模型任务，
本轮没有待批准 RTL 修改。


## 9. I05b：普通 load 每拍接收（2026-11-28）

实现/测试提交：a1b81d626；前测为第 8 节 I06P，early 规则补充由协调者提交
`bdb44511f`。GCC 15.2.0、Verilator 5.051 devel；同一模型 ELF、10 次迭代、
[start_time, stop_time) 退休窗口，两宽均为 2,456,216 条指令，BFM 条件沿用 8.1。

### 9.1 根因与实现

旧 LSU 仅 S_IDLE 准入，即使普通命中响应正通过 fall-through 完成，S_RESPONSE
也不能接受下一条；D$ 本身已有两个响应上下文，能够每拍完成一条命中请求。
在 `edrv32_cpu2_lsu.v:279` 用已有寄存状态/类型与新增一项 queue_valid 构成
准入容量。上一条响应捕获沿可直接装入新请求元数据（`:476`）；若上一条延迟返回
或完成被背压，第二项保留 tag、地址、指令类型、数据和已发出/等待状态，直到按序
接替。已拉起但未接受的 D$ 请求跨头完成背压持续保持 valid 和载荷（`:297`）。
store、设备、FD 双 beat 仍按原准备/头授权/最终 done 流程处理；每个在途项按年龄
取消。替换元数据与旧错误同沿时，新项的 fault_addr 优先，避免覆盖成旧请求地址。
`lsu_req_ready` 没有来自 D$ ready、response valid 或 completion ready 的组合路径；
D$ 请求 ready 仍为其原有寄存容量，D$ RTL 无须修改。

只做双槽时，原 early 优先规则使核级连续 load 的当前实际请求被后一条 ID 查询
顺延，W1 仍为 125 拍、early 查询 61/命中 0。经 ask，协调者授权并提交唯一例外：
已登记、valid/tag/hit 成功且 dc_req_early=1 的实际请求不再读 RAM，可与下一条
early 查询同拍接受。LSU `:307` 实现该例外；未命中、已过期和普通未复用请求保持
既有仲裁，已等待的普通请求仍保留读口。D$ 既有 promote/read_array/early_read
选择本来就支持这一无双读操作，新增测试确认连续复用的数据/tag 完整性。

### 9.2 测量

| 项目 | W1 前→后 | W2 前→后 |
|---|---:|---:|
| 热 load_stream：64 条 load 窗口周期 | 127→64 | 126→63 |
| 热 load_stream：LSU 非 ready 拍 | 63→0 | 63→0 |
| 同模型 ELF CoreMark 周期 | 3534269→3381542 | 3053180→2883957 |
| 同模型 ELF CoreMark/MHz | 2.829439→2.957231 | 3.275274→3.467458 |
| 同模型 ELF LSU 非 ready 拍 | 980967→457205 | 1018912→484038 |
| 同模型 ELF load 等待 HPM9 | 335974→261299 | 333048→217666 |
| 完成队列 credit=0 拍 | 456365→374899 | 914081→808879 |
| store 队头拍 | 383754→322877 | 447522→383911 |
| early 成功回应 | 150971→177842 | 138762→191039 |

热 load_stream 两宽均无 I$/D$ miss、无 IB 空或满完成队列停顿；双发射窗口的
63 拍是按 start/stop 退休边界计时的窗口数字，不能把 64/63 解释为单 LSU
每拍接受多条；流中实际普通请求/响应仍各最多每拍一条。
CoreMark/MHz 相对 I06P 分别提升 4.52%/5.87%，LSU busy 降低 53.39%/52.49%。
这些计数有重叠，不能相加。缓存 miss 状态拍仍为 W1 1908/132、W2 1944/132；
最短缓存 store 队头仍为 2 拍。尚有 store/设备等局部忙和四项完成窗口限制，
本任务没有扩容或改动这些结构，也没有把结果宣称达到原无限窗口模型。

完整原 I06 ELF 另跑到 tohost/CRC 检查结束：W1 3368305 拍、2.968852 CM/MHz；
W2 2885148 拍、3.466027 CM/MHz。与模型 ELF 布局不同，修复前后对照以上表为准。

### 9.3 防回归与命令

- LSU NONE/F/FD 三配置 PASS：普通连续 load 每拍请求/下一拍完成；miss 头后接受
  store；双响应完成背压；未接受请求跨完成背压/early 竞争保持；年轻槽取消；
  queued FD 低高 beat/头授权；8 条连续 early 成功复用及中间 early 失败走普通访问。
  early 测试保持在端口 tag 容量内，不复用仍有未完成实例的 tag。
- D$ NONE/F/FD 三配置 PASS：连续不同字的命中、每拍 early 复用并查询下一项、
  同步 miss 发现沿保留第二个 hit/miss 请求；原 store、维护、设备、取消测试一并通过。
  期望数据由外部字节内存模型产生，不读取 RTL 内部状态计算参考值。
- 两宽各 55 个程序 PASS，含 rv32ui/rv32um/Zba、trap/redirect、dispatch/load_stream；
  完整 CoreMark 两宽 PASS。新普通流测试在旧 LSU 上以 load stream admission n=1
  失败，确认复现原隔拍准入问题。
- 22 个 CPU2 RTL 风格 0 告警；ISSUE_WIDTH=1/2 × NONE/F/FD 六组 top
  `--lint-only -Wall` 0 告警，front size 字段只取实际使用的两位。

```sh
python3 tools/regress.py smoke --path verif/unit/cpu2_lsu -j 2
python3 tools/regress.py smoke --path verif/unit/cpu2_dcache -j 2
python3 tools/cpu/build_cpu2_tests.py --suite isa
python3 tools/cpu/build_cpu2_tests.py --suite coremark
for w in 1 2; do
    python3 tools/cpu/run_cpu2_core.py --width "$w"
    python3 tools/cpu/run_cpu2_core.py --width "$w" --program coremark --no-build
    python3 tools/cpu/cpu2_perf.py --elf build/cpu2_core/programs/load_stream/load_stream.elf --width "$w" --no-build
    python3 tools/cpu/cpu2_perf.py --elf build/cpu-v2/isa/zba/coremark/coremark.elf --width "$w" --no-build
done
python3 tools/check/verilog_style.py rtl/cpu2/*.v
```

top lint 的复现命令：

```sh
cd rtl/filelists
for f in NONE F FD; do
    for w in 1 2; do
        verilator --lint-only -Wall -DSIM_MODE --top-module edrv32_cpu2_top \
            -GISSUE_WIDTH="$w" "-GFPU_FORMAT=\"$f\"" -f cpu2.f
    done
done
```

原始结果位于 build/i05b 的 stream、model、smoke、coremark、lsu-final、
dcache-final 与 lint 日志；单元逐项日志副本在 build/i05b/unit/cpu2_{lsu,dcache}，
复现运行的默认目录为 build/regress/smoke/unit/cpu2_{lsu,dcache}。
仿真使用独立目录，结果收集后清理；本轮没有需要协调者追加决定的项目。

### FE1：BTB 几何与恢复边界（2026-11-28）
基线 c72091981；下表 R1/R2 为冻结后端加 FE1（仅回置旧 tag 接口），M1/M2 保持模型原默认，未改模型文件。
D02（a类，修正A00旧b判定）：W1 BTB 改为 PC[8:3] 的64组，复用 tag 空位保存 PC[2]；组内最后训练的控制指令替换整项，W2仍为128字项。
D03：已寄存恢复 PC 同沿启动 F1；I$ 取消旧上下文并保留同沿新请求；空 IB 直通到 ID；冷 JAL 在 F2 译码恢复，RAS 先恢复再作用新预测。
| 微基准 | M1 | R1 | M2 | R2 |
|---|---:|---:|---:|---:|
| branch_taken | 95 | 94 | 197 | 197 |
| branch_not_taken | 67 | 66 | 66 | 66 |
| branch_alternating | 207 | 206 | 165 | 197 |
| jal | 71 | 70 | 71 | 71 |
| jalr | 325 | 324 | 325 | 325 |
| call_return | 168 | 167 | 131 | 131 |
| late_AB | 187 | 188 | 261 | 261 |
| pair_AB | 133 | 132 | 67 | 98 |
| pair_BA | 133 | 132 | 69 | 101 |
N4 诊断模型的 W2 AB/BA 为98/101，隔离 RTL 完全相等；联合 N16 快照为67/69，与原默认相等。
剩余32拍逐条证据见 [c720 CSV](../../verif/block/cpu2_core/perf/fe1-branch-alternating-c720.csv) 与 [联合 CSV](../../verif/block/cpu2_core/perf/fe1-branch-alternating-joint.csv)：各64行，联合 stage_difference=1 的32行即差异。
模型32条晚分支全部预测正确，另外32条在EX重定向；c720同样早晚分布，但错误分支先等1拍 credit；联合快照则等待前一XORI的x22而选MEM，共64条晚分支。
例如80000070：模型 x22 ready_in=0；c720 credit0→credit1 后EX；联合 credit12、等待tag7@8000006c后MEM；两种RTL的已登记恢复→目标IB/ID均1拍，根因留协调者判断。
CoreMark/MHz：W1 2.968852→3.070552（3368305→3256743拍），W2 3.466027→3.505579（2885148→2852596拍），同一ELF与冻结后端。
HPM16（仅EX/MEM恢复）W1 49151→41846、W2 13478→9924；F2更正另列：W1 0→6839、W2 40766→42746。
联合N16快照另有CoreMark超时（20M拍、最后退休10001aac），已将末端控制日志及源快照交BE1；隔离两宽CoreMark均PASS。
Yosys LUT6参考级数（W1/W2）：F1地址4/5、BTB读索引4/8、写索引2/6、恢复控制6/6；BTB读的8级含carry/INV，JAL目标12/13级分别为4/6级LUT加8/7级carry。
frontend+I$相对基线增量：LUT −2985/+1934、FF +100/+44、LUTRAM 0/0；tech宏未改，DRM/APM实例增量0；BTB仍为逻辑64/128项，物理读副本及59位数据宽度均未增加。
IB直通的空标志按16位分区，8区计数副本限制新增控制扇出；复用既有上下文/RAS恢复寄存器，不增加数据流水拍；上述是逻辑级参考，尚非PDS 165MHz收敛结论。
验证：27个单元配置PASS；九流×三RTL均通过Spike寄存器/PC轨迹对照；核级55程序×两宽PASS；两宽NONE RTL top --lint-only -Wall及六个改动RTL风格检查零告警。
复现：run_model_conformance.py 的 build/run --names 加上述九例；audit_branches.py 只观察原模型调度，输出逐分支等待源与解析级；measure.py 输出前端/I$映射资源和路径级数。
原始日志、ELF、CSV、PPA摘要与联合死锁源快照保留在 build/fe1/results；接口取消沿新请求与BTB沿前读语义由协调者补冻结记录。

## 10. BE1：完成窗口、store 退休和消费者边界（2026-11-28）

基线01177676b，联合FE1=6532c3553，后端=6cd8b9296/5565f2dad；两宽NONE、GCC15.2、同一模型ELF/10迭代/start_time–stop_time，BFM固定等待；未改模型。
D06：全部使用现有共享LUTRAM，W1 NONE/F=8、FD=16、W2=16；T/信用由N导出，无短环信用。D01：四beat SQ准备即done，退休计数标记，逐beat排入写缓冲不等done；设备仍授权/done。
D05删除冗余MUL E3，最终合并进入现有skid/完成口，相关EX间隔4；D08复用CSR请求寄存，分配沿直入，II3；D07 W1复用本地pending等待已寄存early结果，W2复用原MEM/EX skid实现同沿替换。
普通load原195→132拍：ID源旁路误依赖完成表同bank写口ready；改valid+tag旁路，完成/退休仍握手，未改普通load配对矩阵；audit_backend.py观察原模型对应逐拍调度。
D$纠正三类顺序问题：延迟store准备way被年轻miss驱逐；维护后旧way提交；旧miss等待时年轻store准备/年轻miss填充造成循环等待。分别用准备记录排空、失效重查/重新写分配、pipe_ordered_w约束解决（dcache.v:389–400）。
render W2复现1292777条后分支8008c7fc/tag9死锁：EX背压期间pending漏采load返回，生产者已退休；issue.v:1606起复用源FF捕获ALU/early/接受LSU/WB0/1并清wait，新增返回→退休→物理tag复用用例，旧实现可复现FAIL。

| 微基准 | 模型W1 | RTL W1 | 模型W2 | RTL W2 |
|---|---:|---:|---:|---:|
| store_stream | 131 | 131 | 130 | 131 |
| load_store | 131 | 131 | 130 | 131 |
| mul_chain | 256 | 257 | 255 | 257 |
| mul_stream | 131 | 132 | 130 | 132 |
| alu_stream | 259 | 258 | 131 | 131 |
| csr_read | 194 | 194 | 193 | 193 |
| load_use | 131 | 131 | 67 | 67 |
| ordinary_load_use | 259 | 258 | 131 | 132 |

全部23例（含15个pair_*）正向差距最大2拍；W1 pair_AD/DA=1917对1987（快70拍）：原A00已1928对1987，DIV未改功能；硬件独立ALU可与DIV重叠，模型pipe_model.py:851–861的div_wait挡全局发射；请求间隔30，非本轮新增慢拍。
同模型ELF CoreMark：I05b→联合本轮W1 3381542/2.957231→2674632/3.738832，W2 2883957/3.467458→1757049/5.691361；模型2673925/3.739821、1599073/6.253623；收益含FE1。原I06 ELF另跑tohost/CRC：2666532/3.750189、1757087/5.691238。
同窗口LSU非ready：457205→7893、484038→19269；HPM9：261299→91494、217666→96046。W2退休双条/零条拍：模型1029338/172195，RTL932411/233244；少96927个双退拍＋多61049个零退拍＝157976拍总差。
W2 HPM5/6/7/8：模型150516/98468/112443/31778，RTL162252/212740/107284/43948；HPM9模型163814/RTL96046；HPM16模型12949/RTL13567。W1 HPM8模型计单条与RTL口径不同，不作逐项归因。
剩余证据①共读口：131190次early查询被普通读占口（dcache.v:381–382），模型id_early_load只检查基址可用、不建模读口仲裁（pipe_model.py:569–578）；branch+load结构失败29222对模型505，load+load49671对29523。
剩余证据②完成bank等待：ALU0/1/branch有效未接收137821/192369/103642拍，模型CompletionWindow:80–84按tick+latency+1完成、没有bank写口仲裁；ALU+ALU结构失败45206对28498。各计数重叠，不能直接相加当成可回收拍数。
次要证据：晚消费者捕获遇未接受ALU/LSU分别2604/16次；branch已寄存early可用558次、其中延后555次（另22次与其他结果重叠）。只列已观测事件，不把它们解释成全部差距。
普通miss等待store排空的事件/累计拍（W1,W2）：CoreMark 5/19、4/16；vision 770/3669、694/2778；render 2037/8118、2085/8278。vision RTL2106684/1448242对C07模型2005575/1174627；render694229/562736对606296/421068。
Yosys0.67+94、XC7同IP几何flatten：W1 LUT15838→25075（+9237）、FF10780→14422（+3642）、LUTRAM281→341（+60）；W2 LUT40773→80383（+39610）、FF19731→35816（+16085）、LUTRAM398→482（+84）；DRM IP10/30、APM4/4，增量均0。
同脚本read_slang --keep-hierarchy且不flatten的总LUT/FF/LUTRAM：W1 21573/12108/472→31941/16677/532；W2 49089/20678/526→100758/38618/610；逐模块表及两宽各最差20条路径在下述原始数据中，tech/IP子树计入最近CPU模块，不按flatten别名猜资源归属。
flatten全核最差32→54级、42→91级：W1 I$ tag读→D$ tag地址（27LUT/24MUX/3carry）；W2 completion.head_r→D$.early_grant_r（47LUT/35MUX/8carry/1INV）。early_data寄存→ALU skid为21/15级；→完成RAM写数据最长23/21级；完整路径保留ABC无src段，已知模块与来源分开列出。
资源显著超过模型预算W1 LUT6662/FF3877、W2 LUT11907/FF6550；不宣称165MHz或PDS收敛，协调者已将资源/时序收敛另派且不得增加模型拍数。新增状态用于N扩容控制、四beat SQ/≤16位CE叶及失效重查；短load、pending捕获和MEM替换复用既有寄存，MUL减少结果寄存。
性能加载器仅cpu2_perf.py按PT_LOAD补零p_memsz−p_filesz，并在退休stop_time结束、不依赖tohost；bss_smoke.S检查初始化哨兵和32字零填充，修前失败、修后W1/W2 249/156拍PASS；正常55程序仍检查tohost。
验证：55程序×两宽及原I06 CoreMark CRC/tohost PASS；23例×三核Spike寄存器/PC轨迹PASS；后端60种配置、FPU接口tag迁移16种配置PASS；含SQ满/同字load等待/设备授权/FSD双beat/取消/FENCE/维护失效及同沿drain+年轻miss；15个改动RTL风格与六种top --lint-only -Wall均零告警。
复现：`python3 tools/cpu/run_model_conformance.py {build,run} --names`后接上述八例与所有pair_*；两宽分别`python3 tools/cpu/run_cpu2_core.py --width W`及`--program coremark --no-build`；`python3 tools/cpu/cpu2_perf.py --width W --elf build/cpu-v2/isa/zba/coremark/coremark.elf --no-build`。
单元：`python3 tools/regress.py full --path verif/unit/cpu2_MODULE -j 2`；PPA：`python3 verif/block/cpu2_core/perf/measure_backend.py W`及加`--hierarchy`，基线同命令在01177676b运行；BSS：GCC15.2 `-march=rv32im_zicsr_zba -mabi=ilp32 -nostdlib -nostartfiles -Wl,-Ttext=0x80000000`构建bss_smoke.S后交cpu2_perf.py。
原始数据保留`build/be1/results/`：tables/{kernels,modules,worst20-both,workloads,coremark-profile}.csv及完整日志/映射JSON；曾发现Verilator5.051复用旧binary，已作废相关数字，最终删除Mdir并以私有wrapper追加--no-skip-identical重新构建；独立仿真目录结果收集后清理。
