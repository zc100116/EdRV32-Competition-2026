# NPU 后处理 SoC 软件运行配置：超时与 UART 对端

## 1. 现象
PP-SW-01、PP-SW-02 首次 full 运行均在 600 秒时由主机回归运行器终止；DUT 未输出功能断言失败。
运行器仅终止了 runner，仿真子进程仍运行；本次均手工停止遗留进程，再继续串行测试。
扩大主机预算后，PP-SW-01 的 DUT 输出 PASS（starts=2、invalidates=2），但 Python 读取日志遇到 UnicodeDecodeError。

## 2. 复现
旧配置提交 `54c62593`；本机 Verilator 5.020、xPack GCC 15.2.0、Python 3.12.3，确定性镜像，无随机种子。
先初始化 ultralytics/lvgl 子模块及软件数据依赖，执行 `. ~/.local/opt/edrv32/env.sh`。
命令：`flock /tmp/edrv32-sim.lock python3 tools/regress.py full --path verif/soc/pp_sw_01 -j 1`（02 同理）。
首跑摘要：`build/npu_post/integ_pp_sw_0{1,2}.log`；各自输出 `FAIL ... 600s`。

## 3. 观察
600 秒限额覆盖软件构建、lint、Verilator/C++ 编译和仿真，不只是 DUT 执行。
将原有单次进度输出改为每 1 ms 打印公开 debug、启动数、invalidate 数及既有 CPU 请求地址后，重跑可观察到：
- 2 ms：`cpu_addr=88001984`；8 ms：`88028a04`；23 ms：`88088c84`；此时启动数和 invalidate 数均为 0。
- 61 ms：首次 NPU 启动（starts=1）；62 ms：首次候选 invalidate（invalidates=1），所有权检查未报错。
- 这些地址位于首帧离线输入 `0x88000000..0x880b12ff`，在持续前进。
`sw/tests/npu_post/common.h:pp_init()` 必须复制并 clean 两帧各 725760 B 输入，之后才配置并启动 NPU。
软件反汇编的 `main+0x84` 循环对应第一帧复制；未采用 testbench 代拷贝。
UART 字节中出现 0x91，默认 UTF-8 读取失败；DUT 的 PASS 位于同一原始日志末尾，外层 runner 因解码异常返回失败。

## 4. 根因
测试配置错误：`verif/soc/pp_sw_01/test.yaml:6`、`pp_sw_02/test.yaml:6` 的 600 秒主机预算不足以覆盖首次构建和真实 CPU/cache/DDR 下的大块初始化及完整软件验证。
DUT 的 `#600000000` ns 仿真超时与主机的 600 秒不是同一限制；本次没有改变前者或任何功能断言。
UART 对端也是测试配置错误：sys 实际为 100 MHz，但复位分频按生成常量 EDRV32_CLK_SYS_HZ=125 MHz 计算；实际约92160波特，对端仍按115200采样。`uart_init()` 只使能 UART，不修改分频。

## 5. 修复
两个 PP-SW `test.yaml` 的主机预算均改为 3600 秒；保留原程序、时钟和全部字段/所有权检查。
扩展既有进度日志以定位长时间运行所在阶段；移除不再使用的 SC case_number。
UART 模型波特率设为 `115200.0 * 100000000.0 / EDRV32_CLK_SYS_HZ`，匹配原硬件分频；不加替代编码或吞解码错误。
本问题不修改 RTL、CPU/cache、软件算法或参考候选。

UART对端修复提交 `c911e904`；预算与进度修复为本记录所属提交。

## 6. 防回归
复用 PP-SW-01/02 的完整 SoC 运行，要求候选/EDDT/UI、IoU 边界、100 框及 cache/双缓冲所有权检查全部通过。
两项完整回归均PASS：PP-SW-01为1273秒、starts=2、invalidates=2；PP-SW-02为starts=3、invalidates=3。最终结果和修复提交见 `docs/reports/2026-11-08-npu-post-integ.md`。

## 7. 同类排查
两个 PP-SW 用例均使用同一 runner 且原预算都是 600 秒，已同时修正。
本任务未修改归属外的通用 `tools/regress.py`；本次超时后的遗留 sim 均已停止，未保留并行仿真。
