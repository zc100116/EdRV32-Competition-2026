# 32 KiB I$ 评估（T-IC1）

- 基线：`d240547f`（b3）；评估版：本报告所属提交，独立分支，未修改 cache-spec。
- 环境：本机，同机前后对比；主机不可用于本次测试。
- 工具：Verilator 5.020、Yosys 0.70+219（5053d0e26）、GCC 15.2.0、Spike 1.1.1-dev。
- 配置：I$ 2 路 × 512 组 × 32 B；tag 18 位；D$ 保持 8 KiB。
- 器件参考 PG2L200H；无 PDS 器件映射、速度等级或物理时序约束，Yosys 仅 LUT6 参考。
- 原始数据：`build/icache-32k/`；前后分别在 `before/`、`after/`。

## 测量

| 指标 | 8 KiB | 32 KiB |
|---|---:|---:|
| CoreMark 测量窗口周期 | 2,774,333 | 2,774,323 |
| 窗口退休指令 | 2,882,012 | 2,882,012 |
| 窗口 I$ 缺失（HPM event 13） | 168 | 166 |
| 全程 I$ 缺失（含启动、打印） | 307 | 302 |
| CoreMark CRC list/matrix/state | e714/1fd7/8e3a PASS | e714/1fd7/8e3a PASS |
| NES Spike I$ 读访问 | 241,991,928 | 241,991,928 |
| NES Spike I$ 缺失 | 832,667 | 28,477 |
| NES I$ MPKI（缺失/取指访问 × 1000） | 3.440887 | 0.117677 |
| Yosys LUT6 / FF（RAM 黑盒） | 1,449 / 623 | 5,197 / 2,159 |
| 最长组合逻辑级数 | 7 | 8 |
| `ic_inv_i` / 请求地址 bit5 扇出 | 261 / 262 | 1,030 / 838 |

CoreMark 周期减少 10；NES 模型缺失减少 96.58%，只代表内置 NROM 模板 ROM。
NES 使用 O2、RV32IM、180 帧、NES_DISPLAY=0、NES_SKIP=0；MPKI 采用 Spike 功能模型取指访问口径。
有效位/LRU 仍为寄存器，新增 1,536 FF（含 one-hot 索引快照）；高扇出已用 ask 提交协调者，尚未回复；PDS 时序和板上收益未测。

## 复现与验证

使用 `. ~/.local/opt/edrv32/env.sh`；本机所有 Verilator/Yosys/regress 均加 `flock /tmp/edrv32-sim.lock`，编译 `-j 1`。
- 风格：`python3 tools/check/verilog_style.py rtl/cache rtl/tech`，32 文件、0 告警。
- Lint：按 `tools.regress.expand_files` 展开 `rtl/filelists/cpu_subsys.f`，执行 `verilator --lint-only -Wall -DSIM_MODE --top-module edrv32_cpu_subsys <展开源列表>`；0 告警；I$ 单模块同选项也为 0 告警，日志 `lint-edrv32_{icache,cpu_subsys}.log`。
- 单元：`python3 tools/regress.py smoke --path verif/unit/cache_icache -j 1` 和 `--path verif/unit/cache_ram`，各 1 PASS；覆盖全部组双路容量、扩展 RAM 地址、旧数据冲突、读保持、整体失效。
- CPU：`python3 tools/regress.py smoke --path verif/block/cpu -j 1`，74 PASS（含 19 项 riscv-tests）；arch-test 没有 smoke 条目，额外逐 `verif/block/cpu/arch-*` 目录执行同入口的 `full --path "$test_dir" -j 1`，155 PASS，日志 `arch-full.log`。
- Cache 模块：`python3 tools/regress.py smoke --path verif/block/cache -j 1`，22 PASS / 1 FAIL；IC-02 的旧 0x1000 冲突间隔不适用于新容量，共享测试文件不在 Task 归属内，申请授权三轮等待未获回复，故未改；日志 `cache-smoke.log`。
- CoreMark：前后各执行 `python3 tools/cpu/b2_run.py r05 --rvc 0 --read-latency 2`；O2、10 iterations，`before/run.log`、`after/run.log`。
- NES：使用 `sw/apps/nes/run_spike.py` 的 O2/skip=0 分支，仅在 Spike 命令增加 `--ic=128:2:32` 或 `--ic=512:2:32`，分别输出到 `build/sw/nes-ic{128,512}-O2-skip0/`；编排命令 `python3 build/icache-32k/nes_cache.py`，原始 `console.log` 含统计。
- Yosys：基线源码以 `git show d240547f:<文件>` 放入 `before/src/`，评估版读工作树；`read_verilog -D FPGA_MODE -Irtl/include` 读 I$、PMA、两种 I$ RAM 包装和 `tools/synth/ip_stubs.v`。
  接着 `hierarchy -check -top edrv32_icache; synth -top edrv32_icache -flatten -noabc; abc -lut 6 -dress; opt_clean; write_json <输出>/netlist.json; stat`，执行 `python3 tools/synth/netlist_paths.py <输出>/netlist.json`。
  对应脚本/日志：`{before,after}/synth.ys`、`synth.log`、`paths.json`；4 个 RAM 黑盒，不计其存储位为 FF。

## 未完成项与上板前提

本任务验收未全部完成：需协调者授权并修正共享 IC-02 的冲突地址间隔为 0x4000 后复测，同时决策高扇出评估风险。
用户需按更新后的 `fpga/ip/ip_ram_icache_{tag,data}.md` 在 PDS 重新生成两个评估用 IP，模块名保持不变。
本报告不决定容量定稿；尚需上板评估 LVGL 收益、DRM 占用和时序，由协调者随后修订规格并决定合入。
