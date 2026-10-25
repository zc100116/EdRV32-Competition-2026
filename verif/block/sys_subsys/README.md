# 系统子系统 SB 验证环境（S-V1）

依据 sys-subsys-spec v0.1 及协调者确认并写入 v0.2 的顶层端口、复位和覆盖契约；
依据 sys-subsys-testplan 3.1–3.5、5、6。编写时没有读取被测的
`rtl/bus/`、`rtl/periph/`、`rtl/soc/` 实现。

`edrv32_sys_env.sv` 通过规格 3.4 的扁平端口连接 DUT；`edrv32_sys_cases.svh`
包含全部 50 项测试。两个 `edrv32_axi64_master` 实例模拟 I$/D$；M0 只连接 AR/R，
M1 连接五通道。驱动支持 SIZE、WSTRB、LEN、事务间隔和响应反压；每方向一次一笔。
系统复位会将驱动置为空闲并终止在途调用，包括允许被 SOC 软复位取消的触发写。

复用 `edrv32_axi64_memory` 作为 S6 DDR 模型，复用其独立 `reference_memory`
字节阵列作为 ROM/SRAM/DDR oracle；DDR 别名共享物理存储。地址均来自生成的
`edrv32_soc_map.vh`。`edrv32_sys_reference.sv` 单独实现区域、矩阵、响应和字节写参考。
`+ROM_HEX`、`+SRAM_HEX` 同时提供给 DUT 和参考模型；MEM-01/05 缺少对应镜像会明确失败。
镜像为 64 位 `$readmemh` 格式；固定镜像测试应传完整镜像，以便比较区域首尾。

APB 模型提供 16 槽寄存器阵列、`delay_cycles`、`inject_error`、`never_ready`；
`used_slots` 默认媒体 0–9，CACHE_CTRL 实例只启用槽 5。预留槽返回 ready/error，
已用槽才记录传输。`last_data` / `last_strb` 保存最后一次传输的 AXI 半部转换结果。
`edrv32_apb_checker` 检查单热选择、SETUP/ACCESS、等待期间负载保持，并允许在第
256 个 ACCESS 周期后结束超时传输。

AXI 检查器增加经授权的 `CACHE_CONTRACT` 参数，默认 1 保持原 cache 检查；SB 使用
0 保留通道保持、事务并发、LEN/LAST 和写数据完成前不能产生 BVALID 等协议检查，
允许测试规定的非法请求和任意 WSTRB 交给 DUT 返回错误。两个主口和外部 S6 都挂检查器；
`binds.f` 将同一检查器绑定到 sys_xbar 的全部七个从口，并在 APB decoder 和四个
内部 APB 外设边界绑定 APB 检查器。绑定只使用规格端口；端口 fixture 的六个顶层
在 `stub/` 中单独编译，避免读取正在并行开发的 RTL。

UART 模型 `verif/models/uart_model.sv` 提供 `baud`、`deviation`（比例偏差）、
`send(byte, frame_error)`、`expect_byte(byte)` 和接收队列；8N1，位时间以 ns 计。
SCCB 模型 `verif/models/sccb_model.sv` 响应写地址 0x78 / 读地址 0x79，16 位寄存器
指针、8 位数据；`nack_byte` 按 START 后的字节序号配置，地址字节为 0，-1 为不注入。
它支持 STOP+START 和重复起始的读取，记录 `bytes_seen`、`writes`、`reads`、`nacks`；
`quarter_ns` 配置四相时序检查（0 关闭速率检查），覆盖 SCL 周期/高低时间、
SDA 建立/保持和 START/STOP 建立/保持。

默认系统时钟半周期 3.333 ns，媒体半周期 4 ns，相位偏移 1.137 ns；系统频率近似
150 MHz（1 ps 时间精度），寄存器分频计算按规格 150 MHz。`sys_half` / `mem_half`
可配置；AB-07 遍历 0.5、0.83、1、2 的比率并随机化访问相位和从设备延迟。
GPIO 激励由 `gpio` 提供，两个 SCCB peer 分别连接两对开漏引脚。

## 桩和真实 RTL 的使用

`stub.f` 固定使用 `stub/edrv32_sys_subsys.sv`，只用于环境自测；桩提供基本 AXI
存储事务、DECERR/SLVERR、媒体和 CACHE_CTRL 的 APB 时序、UART 回环及上电复位顺序，
不实现 CLINT/PLIC/UART/GPIO/I2C 寄存器功能或软复位。桩的跨时钟传输是测试平台
事件调度，不是待综合的 CDC 实现；本 Task 没有增加 RTL CDC 或存储 IP。

经协调者授权，40 项 S 测试的清单暂标 `sb_smoke`，10 项 F 测试标 `sb_full`，
当前 `tools/regress.py` 不选择这些档位；`selftest/test.yaml` 属于 `smoke`。
S-I1 应将 `environment.f` 中的桩替换为 S-T1 的真实 RTL 文件列表、加入内部绑定
（`binds.f` 的 checker 源码已有一部分在 `models.f`，合并清单时只列一次），再将
两个档位分别改为 `smoke` / `full`。MEM-01/05 和所有初始内存比较必须使用相同
ROM/SRAM 镜像；现有 P0 清单不支持任意运行期 plusarg，镜像应在 S-I1 的运行入口
或软件构建入口提供。不能将桩的通过结果当作这 50 项功能测试已通过。

## 已确认的测试契约

- M0 写不适用；真实仲裁竞争只要求 S0/S1/S6。S2–S5 检查 M0 DECERR 与 M1 合法访问
  同时发生时的隔离。PLIC 认领覆盖只统计已分配的 12 个源，3/4/7 保持为零。
- 预留 APB 槽可以有自身的 SETUP/ACCESS，但不能选中已用槽；非法突发、SIZE、对齐
  请求必须在 AXI 侧拒绝，不能发出任何 APB SETUP。绑定观察器为内部系统槽提供计数。
- MEDIA 软复位写正常返回 B；SOC 软复位写允许被复位取消，驱动随 `rst_sys_n` 复位。
- CL-01 以 AR 接受到 R 返回之间的 `mtime_o` 范围核对读值，不假设额外的采样周期。

## 命令

从仓库根目录执行，生成物都在 `build/sys/`：

```sh
. ~/.local/opt/edrv32/env.sh
python3 verif/block/sys_subsys/verify.py selftest
python3 verif/block/sys_subsys/verify.py probes
python3 verif/block/sys_subsys/verify.py lint
python3 verif/block/sys_subsys/verify.py compile
python3 verif/block/sys_subsys/verify.py style
make lint
python3 verif/block/sys_subsys/coverage.py build/sys/selftest/run.log
```

`selftest` 构建环境、生成完整 ROM/SRAM 镜像并传 plusarg；检查双主、存储回读、
DECERR、ROM 写错误、APB 延迟/错误/256 周期超时和恢复、UART 正常字节及帧错误、
SCCB 写/读/NACK。P0 的 smoke 自测不传镜像时仍检查上述事务，只跳过初始镜像比较。
`probes` 正例还验证公共 AXI 内存模型的 DDR 别名；负例进程必须非零退出，且日志
必须出现对应诊断：AR 保持、BVALID 提前、APB 保持、非单热选择、SCCB START 保持时间。
`lint` 对 50 项参数配置、自测及六种绑定 fixture 分别进行 `--lint-only --timing -Wall`；
`compile` 对九组代表配置构建 binary。每次构建使用 `-j 1`。

`style` 复用仓库风格检查的机械规则；对 CLAUDE.md 9.1 允许的 timed SystemVerilog
语法不应用可综合 RTL 的禁令，并避开 RTL scanner 将 task/function 误认成实例的情形。
模块实例的命名连接仍单独检查；每行一端口、100 列、四空格缩进和文件头规则仍检查。
局部 lint 豁免只针对生成地址头的无关 UNUSEDPARAM，以及时钟生成、串行事件模型、
覆盖计数和复位引脚更新中必须原子执行的 BLKSEQ，以及 testbench 同步采样异步复位
输出的 SYNCASYNCNET。桩的复位同步使用公共 `cdc_sync_bit` / `reset_sync` 原语。

覆盖脚本逐项打印 covered/uncovered 和计数，不把缺失分箱伪装为通过。功能日志输出
`COVER name=count`，统计主从读写、三类响应、仲裁/隔离、APB、PLIC、UART、I2C 和复位；
真实 full 回归将所有通过日志传入 `coverage.py` 做覆盖收敛。XB-07 每次执行种子 1–50，
每种子每个主设备 100 笔，记录 SEED；M0/M1 使用分离的数据区避免参考模型读写竞争。

## 测试项—文件对照

全部场景实现在 `edrv32_sys_cases.svh`；目录内均有 `test.yaml` / `files.f`，
`edrv32_sys_case_tb.sv` 按 CASE_ID 运行。S/F 是验证方案档位，对应当前暂存的
`sb_smoke` / `sb_full`。

| 测试项 | 目录（相对本目录） | CASE_ID | 场景任务 | 档位 |
|---|---|---:|---|---|
| XB-01 | `xb_01/` | 101 | `xbar_case` | S |
| XB-02 | `xb_02/` | 102 | `xbar_case` | S |
| XB-03 | `xb_03/` | 103 | `xbar_case` | S |
| XB-04 | `xb_04/` | 104 | `xbar_case` | S |
| XB-05 | `xb_05/` | 105 | `xbar_case` | F |
| XB-06 | `xb_06/` | 106 | `xbar_case` | S |
| XB-07 | `xb_07/` | 107 | `xbar_case` | F |
| MEM-01 | `mem_01/` | 201 | `memory_case` | S |
| MEM-02 | `mem_02/` | 202 | `memory_case` | S |
| MEM-03 | `mem_03/` | 203 | `memory_case` | S |
| MEM-04 | `mem_04/` | 204 | `memory_case` | S |
| MEM-05 | `mem_05/` | 205 | `memory_case` | S |
| AB-01 | `ab_01/` | 301 | `apb_case` | S |
| AB-02 | `ab_02/` | 302 | `apb_case` | S |
| AB-03 | `ab_03/` | 303 | `apb_case` | S |
| AB-04 | `ab_04/` | 304 | `apb_case` | F |
| AB-05 | `ab_05/` | 305 | `apb_case` | S |
| AB-06 | `ab_06/` | 306 | `apb_case` | S |
| AB-07 | `ab_07/` | 307 | `apb_case` | F |
| CL-01 | `cl_01/` | 401 | `clint_case` | S |
| CL-02 | `cl_02/` | 402 | `clint_case` | S |
| CL-03 | `cl_03/` | 403 | `clint_case` | S |
| CL-04 | `cl_04/` | 404 | `clint_case` | S |
| CL-05 | `cl_05/` | 405 | `clint_case` | F |
| PL-01 | `pl_01/` | 501 | `plic_case` | S |
| PL-02 | `pl_02/` | 502 | `plic_case` | S |
| PL-03 | `pl_03/` | 503 | `plic_case` | S |
| PL-04 | `pl_04/` | 504 | `plic_case` | F |
| PL-05 | `pl_05/` | 505 | `plic_case` | S |
| UA-01 | `ua_01/` | 601 | `uart_case` | S |
| UA-02 | `ua_02/` | 602 | `uart_case` | S |
| UA-03 | `ua_03/` | 603 | `uart_case` | S |
| UA-04 | `ua_04/` | 604 | `uart_case` | F |
| UA-05 | `ua_05/` | 605 | `uart_case` | S |
| UA-06 | `ua_06/` | 606 | `uart_case` | F |
| GP-01 | `gp_01/` | 701 | `gpio_case` | S |
| GP-02 | `gp_02/` | 702 | `gpio_case` | S |
| GP-03 | `gp_03/` | 703 | `gpio_case` | S |
| IC-01 | `ic_01/` | 801 | `i2c_case` | S |
| IC-02 | `ic_02/` | 802 | `i2c_case` | S |
| IC-03 | `ic_03/` | 803 | `i2c_case` | S |
| IC-04 | `ic_04/` | 804 | `i2c_case` | S |
| IC-05 | `ic_05/` | 805 | `i2c_case` | F |
| IC-06 | `ic_06/` | 806 | `i2c_case` | F |
| SY-01 | `sy_01/` | 901 | `sysctrl_case` | S |
| SY-02 | `sy_02/` | 902 | `sysctrl_case` | S |
| SY-03 | `sy_03/` | 903 | `sysctrl_case` | S |
| SY-04 | `sy_04/` | 904 | `sysctrl_case` | S |
| SY-05 | `sy_05/` | 905 | `sysctrl_case` | S |
| SY-06 | `sy_06/` | 906 | `sysctrl_case` | S |

环境自测：`selftest/edrv32_sys_selftest_tb.sv`；协议正负例：
`protocol/edrv32_sys_protocol_tb.sv`。外部串行模型在 `verif/models/`；新增总线 BFM、
协议检查器和被动适配器在 `verif/common/`。

## S-V1 验收记录

最终命令、结果和源码提交见本节末尾；真实 RTL 的功能回归与覆盖收敛由 S-I1 完成。
