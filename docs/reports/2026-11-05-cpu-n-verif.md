# CPU v0.17 独立验证

- 基线 RTL：798530a8（v0.16），测试版本 dcc7bb47；B-03 布局修正 252b1aee。
- 依据 cpu-spec v0.17、cpu-testplan v0.4；没有阅读/修改 rtl/cpu、rtl/cache。
- 环境：本机 Verilator、GCC 15.2、Spike；工具版本见 build/cpu-n-verif/versions.log。
- 改动：P-04 load 2/1、mul 4、CSR 2，间隔 0–4；E/D/M 代价 4/3/5。
- 新增 B-10/B-11、A-01–A-04、L-01–L-03；P-03 增加 early load E0 和 W2/RF 检查。
- 接入确认后的 dc_early 四端口、寄存重定向 stage/PC、W2 退休结束判定和冲刷撤销。
- B1 模型查询只更新响应寄存器；A-03 比较有/无错路查询时的确定性接口观察。
- 实际 D$ tag/LRU/脏位不变由 cache 单元测试覆盖，不在 B1 中模拟。

## v0.16 基线 smoke（执行一次）

```sh
. ~/.local/opt/edrv32/env.sh
flock /tmp/edrv32-sim.lock python3 tools/regress.py smoke --path verif/block/cpu -j 1
```

- 47 项：39 PASS、8 FAIL；日志 build/cpu-n-verif/smoke.log。
- 不依赖新行为的 35 项全部 PASS：B-02/B-09/b1；C-01/02/04；E-01/02/04/05/06/07；
  M-01/04；P-01/02/03/08；I-01 子集（rv32ui add/addi/and、rv32um div/divu/mul、
  rv32mi csr/illegal/instret_overflow）；random branch/high-dep/low-dep/memory 各种子 00/01。
- 新项中原有语义可通过的 A-02/A-03/A-04/B-10 共 4 PASS；提前端口当时尚未接入。
- v0.17 期望的 8 FAIL：B-01/B-07 代价期望 4、实际 3；B-08 期望 3、实际 2；
  A-01/L-01/L-02/P-04 的相关指令间隔期望 1、实际 2。
- B-03 首轮暴露 JAL 实际在槽 1；252b1aee 修正布局后单独复查，代价期望 3、实际 2。
  复查：flock /tmp/edrv32-sim.lock python3 tools/cpu/run_b1.py verif/block/cpu/b-03-no-c/case.json
- 基线 core 的 -Wall 编译 0 告警；新 trace/early 端口接线后的 core 编译、lint、运行，
  按协调者答复留到 N-INT 的 v0.17 RTL；最终提交不要求在 v0.16 core 上编译。

## 独立检查与复现

```sh
python3 tools/cpu/build_directed.py p-03 p-04 b-03 b-10 b-11 a-01 a-02 a-03 a-04 l-01 l-02 l-03
flock /tmp/edrv32-sim.lock python3 verif/block/cpu/b1/early_selftest.py
flock /tmp/edrv32-sim.lock python3 verif/block/cpu/b1/coverage_selftest.py
flock /tmp/edrv32-sim.lock python3 verif/block/cpu/b1/selftest.py
```

- 实现提交 d3f2e60d / d6d260f0；新增 9 项均可构建并在 Spike 完成；提交日志位于 build/cpu/directed/<编号>/no-c/spike/。
- B-10/A-01/A-04/L-01/L-02 为逐条比对；含外部错误/设备/中断的项按方案用 Spike smoke。
- early 模型自测：PASS，-Wall 0 告警；命中复用、连续查询、五种失败原因、推测无副作用。
- 覆盖器自测：86 项，逐项统计/双文件合并/缺项退出码；结果见 coverage-selftest.log。
- 桩协议自测 9/9 PASS（含 3 个故障注入），-Wall 0 告警；日志 stub-selftest.log。
- Python 编译检查和 git diff --check 通过；SV 行宽/缩进/Tab 检查 0 告警。
- 原工具 verilog_style.py 为 RTL Verilog-2001 检查器，不适用允许 SystemVerilog 的 B1。
- R-04 已加入预热后逐次退休间隔判定（E=4/M=5），实际 B2 运行留到 N-INT。
- R-05 尚未收到 N-MODEL 新值，原 predicted=2058075、上限 2160978 保持不变。
- 系统重定向按 1dd80de3：stage=3 也包含 MRET/FENCE.I/WFI，覆盖/HPM 区分比较分支。
- 原始证据统一在 build/cpu-n-verif/；最终接线和全功能覆盖数须由 N-INT 复核。
