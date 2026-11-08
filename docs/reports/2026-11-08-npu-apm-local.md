# NPU APM 本地寄存（2026-11-08）
基线 `edd42bca`；改后为本报告所在提交（`git log -1 -- docs/reports/2026-11-08-npu-apm-local.md`）。
目标 PG2L200H-6 FBB676，整片 clk_npu 180 MHz；Linux 仿真 Verilator 5.020，NPU/mem 150/125 MHz。
只读证据：`origin/win/20261108-68-soc-v021-full:tasks/win/20261108-68-soc-v021-full/artifacts/R2/`，以 `git show` 读取。
使用 top200、top20_detail 和 `native_reports/edrv32_fpga_board_full_top.rtr.gz`；R2 WNS −0.205 ns、47 个违例。

| 类 | 上一跳 / 下一跳（R2） | 做法 / 新增寄存位（RTL 估算） |
|---|---|---|
| W | window `g_weight_byte.weight_r` → `lane_weight_r` → 同一 APM Y；违例 Q 扇出 2–3、最差走线 4.919 ns。可见同类 D 路径 ch29/lane5/bit5 setup +0.048 ns，走线 4.707 ns；违例寄存器精确 D 路径未收录 | (b) window `weight_r` 后新增 `weight_route_r`，再送每 APM 原 `lane_weight_r`；256×8=2048 位 |
| A | window activation → 本地选择/skew 前一级 → skew 末级 → 4 通道 APM X；符号位扇出可达20。19 个违例全属 copy1，前一级 setup 明细未收录 | (a) 只把 copy1 的末级移入 ch4–7 各 lane，前缀共享；(4−1)×8×16=384 位，每份仅驱动一个 APM 的 X 引脚组 |
| P | 尾 APM P → `local_sum_r`（最差 setup −0.138 ns）→ accum `r4_folded_r` / `r5_data_r` 逻辑；后跳 setup 明细未收录 | 经协调者确认保留原单 APM 输出边界，仅禁止 SRL，使其可作为本地 FF；0 位，无额外流水 |

RTL 前驱例：W ch7/lane0/bit7.D←window byte56/bit7；A copy1/lane6/skew[93].D←skew[77]；P ch7/local_sum[21].D←尾 APM P[26]；W/A 这些精确 D 路径的 setup 数值未取得。
W 对齐：window 分发四份 activation 前增加共享 256 位 A5，valid/first/last/tag 增加 1+1+1+49=52 位；共308 位。
总增量 2048+384+308=2740 位，≤3000；APM/DRM 实例不变，512 MAC/拍不变，无新增行间气泡。
window 输出 A5→A6，datapath 固定延迟 +1；MAC 内部仍12拍，读请求/读完成通知不变。
新增负载不复位，valid 按原控制契约复位/取消；window 单元期望 +1，datapath WB2/done 的固定期望 42/50→43/51；数据比较不变。
激活 skew/末级、APM 输出及 W 新旧边界采用 `(* keep = "true", syn_preserve = 1, syn_srlstyle = "registers" *)`。
该属性在 PDS 的实际效果、FF/SRL 资源变化、相邻 setup 及布线收益待卡69确认；未将 hold 裕量当作 setup 依据。

NET-02 latency94：改前/改后均725760 B逐字节PASS；PERF0 6194390→6194664，+274拍（+0.004423%，≤+0.1%）；PERF1均5347440。
回归：mac_array、window 各1/1 PASS；block 22/22 PASS，datapath 获批补跑1/1 PASS（12个参考模型用例）；两个顶层 -Wall lint 与3个RTL文件风格均0告警。
datapath 首轮因漏改固定延迟期望而停止（actual51/expected50）；协调者批准仅该项补跑一次，首轮日志 `build/npu-apm-local/datapath-initial-latency-failure.log`。
原始日志：`build/npu-apm-local/`、`build/regress/smoke/`、`build/npu/yolo/apm_local_{baseline,candidate}_latency94.log`。
复现环境：`. ~/.local/opt/edrv32/env.sh`；所有构建/仿真命令前加 `flock /tmp/edrv32-sim.lock`，单作业 `-j 1`。
单元（mac_array、window 各一次，datapath 获批补跑一次）：`python3 tools/regress.py smoke --path verif/unit/npu_<模块> -j 1`。
模块：`python3 tools/regress.py smoke --path verif/block/npu -j 1`。
整网：在基线/改后 commit 分别运行（label 区分日志；build 内部 `-j 1`）：
`PYTHONPATH=verif/block/npu python3 -c "from run import build,simulate; from prepare import prepare_network; p,a=prepare_network('NET-02')[1]; r,t,l=simulate(build(False),p,a,'latency94'); print(t); assert r==0 and 'PASS NB' in t and 'FAIL' not in t"`。
风格：`python3 tools/check/verilog_style.py rtl/npu/edrv32_npu_{mac_array,window,datapath}.v`；`git diff --check`。
lint：`tools.regress.expand_files` 展开源列表，命令 `verilator --lint-only --timing -Wall -j 1 +define+SIM_MODE --top-module <top> <展开源>`：
SoC `edrv32_soc_top` 用 `rtl/filelists/soc.f`；整片 `edrv32_fpga_board_full_top` 用 `verif/soc/board_vnpu/files.f`、`rtl/filelists/rnd.f` 与 `fpga/rtl/edrv32_fpga_board_full_top.v` 的去重并集。
生成块层次名自查：`rg -n '\bg_\w+(\[[^]]+\])?\.' rtl/npu/edrv32_npu_{mac_array,window,datapath}.v`，应无匹配。
未改“其他”7类端点；Linux 结果不能代替整片 PDS 时序与拥塞确认。
