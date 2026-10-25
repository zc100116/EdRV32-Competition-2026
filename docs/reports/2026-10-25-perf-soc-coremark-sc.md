# CPU + 系统子系统 CoreMark 测量（S-I2）

## 环境与复现

本次运行真实 `edrv32_cpu_subsys` 和 `edrv32_sys_subsys`，程序从 ROM bootloader
进入 SRAM。DDR 组通过 SRAM 中的两条跳转指令进入 `ddr.ld` 链接的程序，代码、
数据和栈均在可缓存 DDR 窗口。没有修改生产 RTL 或第三方 CoreMark 源码。

| 项目 | 配置 |
| --- | --- |
| CoreMark | v1.01，子模块 `cfa9ab377835911f23d9b0831c7be302ed1f58de` |
| 软件 | 10 次迭代，MEM_STATIC，单 context，2000 字节，volatile seeds 0 / 0 / 0x66 |
| CPU | RVC_EN=1，rv32imc_zicsr，ilp32；HPM3–10 配置为事件 1–8 |
| 编译器 | xPack GCC 15.2.0，GNU binutils 2.45；C11，Wall/Wextra/Werror |
| 仿真器 | Verilator 5.020，`--binary --timing -Wall +define+SIM_MODE -j 2` |
| 时钟 | clk_sys 周期 6.666 ns，clk_mem 周期 8 ns；DDR 模型运行在 clk_sys |
| SRAM | 真实 sys_xbar、SRAM AXI 从设备和技术包装存储器 |
| DDR | 复用 B2 固定首拍延迟适配器与公共 AXI 存储模型，关闭随机停顿 |
| DDR 延迟 | S6 AR 握手至首个 R 握手，分别 20、60 个 clk_sys 周期；后续拍连续 |
| O2 | `-O2` |
| tuned | `-O3 -funroll-all-loops -finline-limit=600 -falign-functions=4 -falign-jumps=4 -falign-loops=4` |
| 器件和速度等级 | RTL 仿真，无器件或速度等级；未测 FPGA 频率、资源或板上时间 |

在本报告的提交中，从仓库根目录执行：

```sh
. ~/.local/opt/edrv32/env.sh
git submodule update --init third_party/coremark
for case_id in 01 02 03 04 05 06 07; do
    python3 verif/block/sys_cpu/run.py sc${case_id}
done
python3 verif/block/sys_cpu/run.py perf
python3 verif/block/sys_cpu/check_style.py
```

每条实际构建和仿真命令保存在对应日志首行；构建统一经 `sw/Makefile`。
原始数据根目录为
`/home/workspace/orca/workspaces/EdRV32-Competition-2026/task-sys-integ/build/sys_cpu/`：`coremark.csv` 为四组汇总，
`coremark_{sram_o2,sram_tuned,ddr_o2_l20,ddr_o2_l60}/run.log` 为 UART、CRC、
HPM、CSR、填充服务时间原文，`sw/<组名>/build.log` 保存实际编译参数和 ELF，
`compile.log`、`lint.log`、`icarus-compile.log` 和 `versions.log` 保存工具输出。

CoreMark/MHz = 10,000,000 / Total ticks。`start_time` 入口退休至 `stop_time`
入口退休构成 HPM 窗口，与 C-I3 B2 相同；16 类事件由 CPU 事件总线并行计数，
日志另有八个实际硬件 HPM CSR 的差值。ROM/UART 启动前缀及结束日志不计入该窗口。
未改动的 CoreMark port 对所有组仍打印静态的 O2/SRAM 说明，以实际构建命令为准。
十次迭代不足官方要求的十秒，原程序的短时运行警告保留；本报告只记录 CRC 和
归一化周期测量值，不作为满足官方时长要求的 CoreMark 得分。

## 测量输入与验证结果

SC 环境和测量软件 commit：`771ad8b877a89650f9b9ca8aac714334a4910f12`；
它包含 UART 对端模型修复 `30a9809`，生产 RTL 输入为 `10d882b`。
B2 对照为报告 `7c63c3b:docs/reports/2026-10-25-perf-cpu-b2.md` 的
RVC_EN=1、READ_LATENCY=2 两组，RTL 输入
`ab9f8f48a6b04c297ad2dfb5e0f91b7915e1b89e`；两次输入间 CPU/cache RTL 无差异。

| 检查 | 结果 | 日志 |
| --- | --- | --- |
| SC-01–SC-07 / Verilator | 7/7 PASS，0 FAIL；SC-04 两条下载路径均通过 | `sc01`–`sc07/run.log`、`sc04_scratch/run.log` |
| SC-07 性能四组 | 4/4 PASS，三项算法 CRC 均为 e714 / 1fd7 / 8e3a | `coremark_*/run.log` |
| UART 模型影响回归 UA-01–UA-06 | 6/6 PASS，0 FAIL | `uart-regression.log` |
| SC 顶层严格 lint | 0 告警 | `lint.log`；命令见 SC README |
| SC 风格检查 | 2 个 SV 文件，0 告警 | `python3 verif/block/sys_cpu/check_style.py` |
| SC-01 / Icarus 12.0 | 编译失败：现有公共 AXI memory/checker 和 B2 adapter 的 interface 端口不受支持，未取得 X 传播结果 | `icarus-compile.log` |

UART 影响回归使用 `verif.block.sys_subsys.run.run`，依次传入 `601` 至 `606`，
串行运行，等价命令为：

```sh
for test_id in 601 602 603 604 605 606; do
    python3 verif/block/sys_subsys/run.py "$test_id"
done
```

首次用 P0 的 180 秒外层超时进行冷构建时超时；完成构建后上述六项
直接 runner 均正常通过。没有生产 RTL 修复；唯一已有文件修复是 UART 模型在
停止位中点检查后立即重新等待起始沿，避免连续字符间漏掉起始沿。

## SRAM 与 B2 同配置对照

SC 使用真实 ROM/UART 启动和真实 sys_xbar/SRAM 路径；B2 使用两指令 ROM 跳转
和固定延迟内存模型。SC 还链接真实 UART/SIM_EXIT host，B2 链接其控制台 host，
因此两组不是相同 ELF；CoreMark 源码、编译选项、seeds、迭代数和 ISA 相同。
下表周期差为整个计时窗口的实测差值，ROM 前缀另列，未将周期差全部归为填充服务。

| 选项 | B2 周期 | SC 周期 | SC−B2 | B2 CoreMark/MHz | SC CoreMark/MHz | 变化 | SC window instret | SC window 周期 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| o2 | 2789093 | 2813548 | +24455 | 3.585395 | 3.554231 | -0.8692% | 2882012 | 2813548 |
| tuned | 2322015 | 2310207 | -11808 | 4.306604 | 4.328616 | +0.5111% | 2487916 | 2310207 |

| 选项 | ROM 复位释放至应用入口退休周期 | 对应 instret | 整机结束周期 | 整机结束 instret |
| --- | ---: | ---: | ---: | ---: |
| o2 | 3933365 | 693720 | 12673553 | 5072432 |
| tuned | 3933365 | 693720 | 12169168 | 4677598 |

### 16 类 HPM

八个硬件 CSR 的事件 1–8 差值与下表对应并行计数完全相同；事件 9–16 也在同一次
运行的同一窗口采集。B2 与 SC 的窗口退休指令数分别均为 O2 2,882,012、
tuned 2,487,916，事件分布的差异直接保留如下。

| 编码 / 事件 | O2 B2 | O2 SC | O2 差值 | tuned B2 | tuned SC | tuned 差值 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 双退休周期 | 794925 | 778244 | -16681 | 641376 | 641140 | -236 |
| 2 单退休周期 | 1292162 | 1325524 | +33362 | 1205164 | 1205636 | +472 |
| 3 零退休周期 | 702006 | 709780 | +7774 | 475475 | 463431 | -12044 |
| 4 退休分支/跳转 | 609103 | 609103 | +0 | 505036 | 505036 | +0 |
| 5 配对失败：RAW | 448007 | 442832 | -5175 | 290360 | 288926 | -1434 |
| 6 配对失败：结构 | 105040 | 117153 | +12113 | 116908 | 119091 | +2183 |
| 7 配对失败：槽 1 类型 | 662406 | 663064 | +658 | 702062 | 700552 | -1510 |
| 8 配对失败：第二条未取到 | 32666 | 60485 | +27819 | 48073 | 57463 | +9390 |
| 9 load-use 停顿 | 279911 | 270579 | -9332 | 187341 | 185845 | -1496 |
| 10 除法停顿 | 0 | 0 | +0 | 0 | 0 | +0 |
| 11 设备/非缓存等待 | 0 | 0 | +0 | 0 | 0 | +0 |
| 12 前端断流 | 171522 | 182482 | +10960 | 190029 | 181152 | -8877 |
| 13 I$ 缺失 | 122 | 120 | -2 | 2010 | 1977 | -33 |
| 14 D$ 缺失 | 24 | 24 | +0 | 22 | 22 | +0 |
| 15 D$ 脏行写回 | 0 | 0 | +0 | 0 | 0 | +0 |
| 16 分支/跳转误预测 | 80058 | 87756 | +7698 | 83038 | 80515 | -2523 |

### 缺失次数与填充服务周期

`HPM13/14` 是 CPU 事件定义的 I$/D$ 缺失次数；`SC_FILL` 是源 AXI 上完成的
四拍填充事务数，两者分别记录。服务周期是源端 AR 握手到最后一拍 R 握手的
间隔之和；I/D 服务与其他 CPU 工作可重叠，不能与整个 CPU 周期差直接相加。
下表同时列出 I$/D$ 缺失 busy 电平累计周期。

| 组 | HPM I$/D$ 缺失 | AXI I$/D$ 四拍填充 | I$ 服务周期 | D$ 服务周期 | I$/D$ busy 周期 | I$/D$ 平均每填充服务周期 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| coremark_sram_o2 | 120 / 24 | 130 / 24 | 786 | 157 | 816 / 205 | 6.0462 / 6.5417 |
| coremark_sram_tuned | 1977 / 22 | 2256 / 22 | 13536 | 149 | 14401 / 193 | 6.0000 / 6.7727 |
| coremark_ddr_o2_l20 | 122 / 24 | 130 / 24 | 3275 | 689 | 2596 / 737 | 25.1923 / 28.7083 |
| coremark_ddr_o2_l60 | 122 / 24 | 130 / 24 | 8515 | 1809 | 6316 / 1857 | 65.5000 / 75.3750 |

B2 的固定延迟 2、连续四拍协议对应 AR 至最后一拍 R 的 5 周期间隔。
将 SC 相同数量的填充事务各减去此 5 周期参考，得到以下服务周期增量；
这不是 B2 相同 ELF 的重新测量，也不等于 CPU 停顿增量。

| SRAM 组 | I$ 服务周期增量 | D$ 服务周期增量 | HPM I$/D$ 缺失次数相对 B2 |
| --- | ---: | ---: | ---: |
| o2 | 136 | 37 | -2 / +0 |
| tuned | 2256 | 39 | -33 / +0 |

## DDR 可缓存窗口：延迟 20 与 60

两个 DDR 组的程序、数据、栈均使用 `ddr.ld`，优化为 O2；除模型延迟外构建相同。

| 首拍延迟 | Total ticks | CoreMark/MHz | window 周期 | window instret | ROM 前缀周期 | HPM I$/D$ 缺失 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 20 | 2816465 | 3.550550 | 2816465 | 2882012 | 3933397 | 122 / 24 |
| 60 | 2822625 | 3.542801 | 2822625 | 2882012 | 3933437 | 122 / 24 |

延迟 60 相对 20：计时周期增加 6160，等于 `(60−20) × (130+24)`；
I$ 填充服务周期增加 5240，D$ 填充服务周期增加 1120。
源端两个通道的服务时间包含各自等待路径，未把二者的增量求和作为 CPU 周期增量。

| HPM 事件 | DDR 20 | DDR 60 |
| --- | ---: | ---: |
| 1 双退休周期 | 778245 | 778245 |
| 2 单退休周期 | 1325522 | 1325522 |
| 3 零退休周期 | 712698 | 718858 |
| 4 退休分支/跳转 | 609103 | 609103 |
| 5 配对失败：RAW | 442832 | 442832 |
| 6 配对失败：结构 | 117153 | 117153 |
| 7 配对失败：槽 1 类型 | 663061 | 663061 |
| 8 配对失败：第二条未取到 | 60488 | 60488 |
| 9 load-use 停顿 | 270578 | 270578 |
| 10 除法停顿 | 0 | 0 |
| 11 设备/非缓存等待 | 0 | 0 |
| 12 前端断流 | 184870 | 189910 |
| 13 I$ 缺失 | 122 | 122 |
| 14 D$ 缺失 | 24 | 24 |
| 15 D$ 脏行写回 | 0 | 0 |
| 16 分支/跳转误预测 | 87755 | 87755 |
