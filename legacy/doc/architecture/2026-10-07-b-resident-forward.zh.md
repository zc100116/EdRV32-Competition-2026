# B 槽的跨组寄存旁路

## 本轮选择

起点为访存＋ALU 配对提交 `90b2375`。其 64 位取指 CoreMark i10 热态 O2/O3 周期为 3,120,522 / 3,121,790。

先核对了 resident Load 的阶段边界：DECODE-to-EX 驻留 Load 进入 EX 计算地址，下一周期 MEM1 才进行 PMA 分类和 Load Queue 分配。不能把此时队列的空闲 token 直接当作该 Load 的 token，因为同周期更老的 MEM1 Load 可能分配它，且目标 Load 可能是 MMIO 或访问错误。常见 Cache 命中路径中，将消费者提前放入 EX 仍需等到 Load 数据到达，可能只是转移等待。这里是基于现有 RTL 的时序分析，并未声称实现提前 token 分配或测出了它的性能收益。

本轮改为消除明确存在的 B 槽限制：上一版本仅允许 A 捕获上一组的寄存 ALU 结果，B 遇到同类依赖就拒绝配对。O2 每轮约 205,655 次 B 因 resident 依赖被拒绝。这一限制可以在不连接同组两级 ALU 的情况下放宽。

## 结构

DECODE 的 B payload 新增两组 2 位源选择，分别对应 ALU lhs、rhs：0 表示已解析的 DECODE 值，1 表示上一组主槽 A 的结果，2 表示上一组 B 的结果。源选择字段和原有数据一起保存到纯寄存 pipe；父包 PC 复用主槽已有的 `resident_bypass_pc` 字段。

上一组 A 仅在 ALU/JUMP 结果可用时允许选择；上一组 B 仅在有效、写非 x0 时允许选择。当前同组 A→B 的 RAW 仍禁止，WAW、顺序 PC、epoch、非法指令和预测跳转约束仍然有效。未就绪 Load/MDU 仍不能作为 B 的新旁路源。

若年轻的 resident ALU 覆盖了更老的未就绪 Load/MDU 的同一 rd，B 的选择器指向这个年轻生产者，同时忽略被覆盖的旧外部阻塞。这是年龄优先选择，不能保留旧 Load token 再从其返回值取数。

EX 根据父 PC 匹配其**已寄存**的上一组结果；lhs、rhs 可以分别来自上一组 A、B。两个 32 位局部保留寄存器在本组 A 等待其他操作数或输出反压时捕获所选数据，使上一组可以继续流向 MEM1。它们不属于架构寄存器，整组消费、无效或 kill 时清除所有权，payload 不需复位。两条指令都满足操作数和既有侧效应条件时，整组才能写入 EX 输出 pipe。

例如上一组 A 更新 x10、B 更新 x11，下一组 A 执行独立指令，B 执行 `add x12,x10,x11`。B 在 EX 使用上一组已经寄存的两个结果；当前组 A 的组合 ALU 输出没有连接到 B 的输入。因此本轮没有形成两级 ALU 串联的组合路径。

仅改动 `edrv32_decode_stage.v`、`edrv32_ex_stage.v` 和 `edrv32_pair.vh`。流水寄存模块仍只保存 payload，无新增 FPGA IP 或 IP 配置。

## 固定固件周期

GCC 15.2，固定 RV32IMC i10 固件，第二轮 CSR mcycle：

| 配置 | 优化 | 访存配对版本 | 本轮 B 旁路 | 节省 | 周期减少 |
|---|---|---:|---:|---:|---:|
| 32 位取指 | O2 | 3,308,581 | 3,295,554 | 13,027 | 0.39% |
| 32 位取指 | O3 | 3,289,601 | 3,272,409 | 17,192 | 0.52% |
| 64 位取指 | O2 | 3,120,522 | 3,061,910 | 58,612 | 1.88% |
| 64 位取指 | O3 | 3,121,790 | 3,058,049 | 63,741 | 2.04% |

相对已上板 3.115 源码的 i10 仿真，O2/O3 累计周期减少约 4.39% / 4.17%。板上固件为 i4000，不能将这些仿真比例直接当作新的板上成绩。本轮尚未上板。

同一旁路机制在 32 位取指配置中收益较小，说明能否形成 B 配对与前端供给及指令分组有关。64 位配置也有更大的半字缓冲，不能把两个配置的差异全部归因于一个总线位宽数字。

O2 第二轮共捕获 lhs 来自上一组 A 108,929 次、rhs 来自 A 4,157 次、lhs 来自 B 14,979 次、rhs 来自 B 3,627 次。B resident 拒绝由 205,655 降至 51,686；B 退休从 449,903 增至 538,611，净增 88,708，但空退休周期也增加 30,096，所以净节省 58,612。新增配对同样会改变后续分组与依赖间距，不能按旁路次数直接算节省周期。

## 验证与复现

新增 `ex-second-resident` 的 35 项检查覆盖错误父 PC、两个源的所有组合、生产者离开后保留、MDU 等待、输出反压、kill 和 Load 主槽旁的独立 B。整核参考模型新增确定性压缩序列，覆盖四个源选择器；随机部分仍检查 PC、寄存器值、存储顺序和实际配对覆盖。

```sh
python3 sim/script/run_dual_issue.py --suite all --output ../directed-final
python3 sim/script/run_dual_isa.py --mode all --memory both --jobs 8 --output ../isa
python3 sim/script/run_dual_coremark.py --mode all --opt both --jobs 8 --output ../coremark
```

虚拟机目录：`/home/edward/File/edrv32-b-operand-20261007/`。本机 audit：`out/audit/2026-10-07-b-resident/`。回归、物理结果、源码哈希和原始日志的最终索引为 `sim/regressions/b-resident-baseline.json`。

最终 **105/105 模块与定向、864/864 ISA/ACT、24/24 CoreMark** 通过；旧单发射及仅双窗口配置周期逐轮不变。三份编译源码清单均与工作区核对；四个继承的 CRLF/LF 文件经逐字节规范化确认等价，其余文件 SHA-256 相同。负对照的错误保留值稳定触发 EX 用例失败。原始完整源码和结果保存为 `source-and-results.tar.gz`，包含早期随机覆盖不足的日志；确定性 C.ADD 序列补足覆盖后再执行了最终全回归。

## 100 MHz 物理结果

沿用既有 PG2L200H、-6、FBB676、100 MHz 约束和 FPGA IP，在独立目录运行 compile/synthesize/dev_map/pnr/report_timing。最终 **All Constraints Met**：slow setup WNS **+0.212 ns**、TNS **0**、失败端点 **0**；slow hold **+0.146 ns**、fast hold **+0.102 ns**。报告 SHA-256：`1d5b322433d71a73371a43f5225e7e6f15204f03f850a9e2612bbbfcdc29dcd4`。

报告路径：`out/audit/2026-10-07-b-resident/pds/report_timing/edrv32_pango_200h_coremark_top.rtr`。`run_timing.ps1` 可在现有工作区复现完整物理流程。本轮未生成新上板成绩，也未向板卡下载；不需增加源码文件或修改 IP 配置。
