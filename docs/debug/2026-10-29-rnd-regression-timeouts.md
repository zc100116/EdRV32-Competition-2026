# RND 模块级回归的档位与超时预算

## 1. 现象

R-I1 联调中出现三项测试执行问题：

- RN-01–16 的原 smoke 清单包含 531 个案例，真实 RTL 全部 PASS，但首次串行约 566 秒，超过 CLAUDE 9.1 的约 60 秒预算。
- 首次 full 在 RN-19 种子 2 触发 300 秒主机超时，无像素差异或协议错误输出。
- 移除强制 C++ `-O0` 后，full 的种子 3 在仿真时刻 200 ms 触发 testbench 超时，无此前的像素或协议失败。

本组回归运行时间问题的处理跨越半小时，按 CLAUDE 3.4 留存本记录。

## 2. 复现

工具：Verilator 5.020（Debian 5.020-1）、Python 3.12.3、g++ 13.3.0；125 MHz。
所有命令先执行 `. ~/.local/opt/edrv32/env.sh`，不使用并行仿真。

```sh
# c7d01bf：原始 smoke 清单，531 个案例 PASS。
python3 tools/regress.py smoke --path verif/block/rnd -j 1
# 0fa2e27：强制 -O0，种子 2 触发主机超时。
python3 tools/regress.py full --path verif/block/rnd -j 1
# a7552bd：默认 -Os，种子 3 触发 200 ms 仿真超时。
python3 tools/regress.py full --path verif/block/rnd -j 1
```

原始证据：

- `build/regress/smoke/block/rnd/verilator/run.log`
- `build/rnd/full-initial-timeout.log`、`build/rnd/integration-full-initial.log`
- `build/rnd/full-watchdog-timeout.log`、`build/rnd/integration-full-watchdog.log`
- 种子 2、3 的配置与四份二进制镜像：`build/rnd/full/RN-19-0096-seed2/`、`RN-19-0097-seed3/`

## 3. 观察

- 种子 2：50 条命令，读延迟 23 周期、随机背压参数 29、B 延迟 32 周期。
  不变的配置和镜像在默认 `-Os` 下单独复跑 49.457 秒 PASS。
  日志为 `build/rnd/full-seed2-optimized.log`。
- 种子 3：50 条命令，读延迟 36 周期、随机背压参数 16、B 延迟 25 周期。
  描述符序号 27、36 均为 R=31 的 BOX_SHADOW，矩形分别为
  `(-3,0)–(17,20)`、`(7,-4)–(29,20)`。
- 原 watchdog 在 `200000000000 ps` 报 BUSY，对应 25,000,000 个 clk_mem 周期。
- 只延长测试时间预算、使用相同配置与镜像后，种子 3 单独复跑 237.843 秒 PASS。
  日志为 `build/rnd/full-seed3-extended.log`。
- 两个单独复跑均通过完整存储逐字节比较和协议检查；没有修改被测 RTL。

## 4. 根因

均属于测试执行配置问题：

1. 根目录 `test.yaml` 原归 smoke，与真实 RTL 的构建和 531 个串行案例耗时不符。
   协调者按 CLAUDE 9.1 将模块级用例归 full，并修订验证方案第 6 节（`7dcb7ed`）。
2. `run.py:compile_sim` 的强制 `-CFLAGS -O0` 使合法随机用例在 300 秒主机预算内未完成；
   默认 `-Os` 对同一输入的完整 PASS 证实不需要修改 RTL。
3. `edrv32_rnd_tb.sv` 的固定 200 ms watchdog 不足以执行带延迟模型下的 50 条随机命令；
   RN-19 允许随机延迟及全部八种命令，rnd-spec 第 7 节没有规定这类混合列表的总周期门槛。
   同一输入在延长预算后的完整 PASS 排除了必须通过 RTL 修复才能完成的情形。

## 5. 修复

- `e9750ae` 同步协调者的验证方案提交，`0fa2e27` 把根清单归 full，保留原有所有组合。
- `a7552bd` 删除强制 C++ `-O0`，使用 Verilator 默认 `-Os`。
- 现有 watchdog 从 200 ms 改为 2000 ms；现有单案例主机预算从 300 秒改为 1800 秒；
  full 补充目录的总主机预算从 1800 秒改为 7200 秒。
- 没有修改 RTL、命令编码、存储初值、参考模型、期望结果、协议检查或 RN-18 性能门槛。

## 6. 防回归

继续运行现有 RN-19 的十种子、每种子 50 条命令；其中种子 2、3 直接复现这两项超时。
根目录的 531 个定向案例和 full 补充集的 105 个案例保持不变，使用完整 full 命令验收。
RN-18 的无等待指标仍按原阈值检查，40 周期读延迟只记录。
最终命令、结果、耗时和测量数据见 `docs/reports/2026-10-29-perf-rnd.md`。

## 7. 同类排查

检查了本环境两级时间预算：testbench 仿真时刻、run.py 单案例主机时间及 test.yaml 目录时间。
根定向清单和独立 selftest 保留各自的目录预算，perf 保留 1800 秒目录预算；
只有需要容纳十种子混合列表的 full 补充目录增加总预算。
未改动其他模块或公共回归工具，没有新增超时检查、重试或备用路径。
