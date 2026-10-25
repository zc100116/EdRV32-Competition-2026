# Cache 模块级验证

依据 cache-spec v0.1、cache-testplan v0.1；独立于 RTL 开发，未读取 `rtl/cache/`。

环境入口 `edrv32_cache_env.sv` 连接 `edrv32_icache`、`edrv32_dcache` 和
`edrv32_cache_ctrl` 的规格端口。core 驱动包含定向事务、连续命中流和可配置随机流；
APB 驱动直接访问维护控制器。`edrv32_cache_core_checker.sv` 检查命中时序、kill、
设备提交顺序、地址、大小和写数据。维护测试中 STATUS 地址作为设备事务地址，
AXI 模型提供设备数据；真实控制器寄存器由 APB 驱动检查，环境不包含 sys_xbar/APB 桥。

`verif/common/` 下新增：

- `edrv32_axi64_if.sv`：完整 AXI64 五通道接口。
- `edrv32_axi64_memory_pkg.sv`：共享平坦物理内存和独立架构内存，按字节寻址，
  DDR 两个地址窗口映射到同一物理字节。未写字节由地址确定初始值。
- `edrv32_axi64_memory.sv`：每方向一笔事务，随机 READY、响应延迟和响应间隔，
  R/B 停顿时保持负载；按行地址注入读/写 SLVERR。
- `edrv32_axi64_checker.sv`：五通道 VALID/负载保持、ID、突发类型、行大小/对齐、
  单拍大小、WSTRB、LAST、事务并发和响应顺序。

参考模型在提交 store 时立即更新；load 比较有效访问字节。整体 clean 后比较两个
内存已写字节的并集，能够检查未提交 store 导致的额外写入。所有失败打印期望、实际和时刻并退出非零。

## 运行

从仓库根目录执行，生成物全部位于 `build/cache/`：

```sh
. ~/.local/opt/edrv32/env.sh
mkdir -p build/cache/selftest
verilator --binary --timing -Wall \
    --top-module edrv32_cache_selftest_tb \
    -f verif/block/cache/stub/files.f \
    -f verif/block/cache/selftest/files.f \
    --Mdir build/cache/selftest
build/cache/selftest/Vedrv32_cache_selftest_tb +SEED=17
```

桩只执行最简单的总线转发，不实现 cache、LRU、PMA 或维护写回；不能用桩上的功能
PASS 代替真实 RTL 回归。`selftest/` 验证定向/随机驱动、行读、单拍访问、kill、
APB、维护握手和参考模型；真实功能测试必须换成 RTL worker 交付的源文件列表，
替换上述命令中的 `-f verif/block/cache/stub/files.f`，其余环境不变。
每项 `files.f` 包含环境和测试顶层，DUT 源列表由命令另外指定。

全部 34 项的桩编译（不执行功能断言）：

```sh
. ~/.local/opt/edrv32/env.sh
for family in ic dc mt pf
do
    for test_dir in verif/block/cache/${family}_*
    do
        test_name=${test_dir##*/}
        mkdir -p build/cache/${test_name}
        verilator --binary --timing -Wall \
            --top-module edrv32_cache_${test_name}_tb \
            -f verif/block/cache/stub/files.f \
            -f ${test_dir}/files.f \
            --Mdir build/cache/${test_name} || exit 1
    done
done
```

真实 RTL 测试执行示例：构建 `ic_01` 后运行
`build/cache/ic_01/Vedrv32_cache_ic_01_tb`。
随机测试支持 `+SEED=1 +COUNT=300 +BASE=10000000 +CONFLICT_LINES=6`
以及 `+STORE_PERCENT=50 +KILL_PERCENT=15`。IC-08、DC-15 的 full 回归分别跑 50 个种子，
smoke 跑两个种子；PF-02 自动关闭随机停顿，测量请求到响应和 AR 到首拍 R 的周期数。
其外部可见上界为一个同步查找周期加 cache-spec 第 7 节缺失上界。

故障注入自测（预期 FAIL 和非零退出码）：

```sh
ulimit -c 0
build/cache/selftest/Vedrv32_cache_selftest_tb +BAD_AXI_LEN
build/cache/selftest/Vedrv32_cache_selftest_tb +BAD_CORE_HIT
```

前者仅让桩的行 ARLEN 从 3 变为 2；后者将延迟返回的 ROM 请求声明为期望命中，
验证 core 时序检查器。二者只用于环境自测，不属于验证方案新增的功能测试项。

## 测试映射

| 编号 | 目录 | 内容 |
|---|---|---|
| IC-01 | `ic_01/` | 冷启动顺序取指：每行先缺失后命中；命中时每周期返回一个 |
| IC-02 | `ic_02/` | 三个映射到同一组的行轮流访问，检查 LRU 替换顺序 |
| IC-03 | `ic_03/` | ROM 取指不装入 cache（再次取同一地址仍然发出 AXI 读） |
| IC-04 | `ic_04/` | 取指访问非可执行区域：返回错误，不发出 AXI 事务 |
| IC-05 | `ic_05/` | 缺失期间 `ic_kill_o`：响应被丢弃，该行仍然装入 |
| IC-06 | `ic_06/` | `ic_inv_o` 后全部重新缺失 |
| IC-07 | `ic_07/` | 填充返回 SLVERR：请求返回错误，该行不装入，下一次访问重新缺失 |
| IC-08 | `ic_08/` | 随机取指流（含 kill），AXI 随机延迟和反压，每次返回的数据与内存一致 |
| DC-01 | `dc_01/` | load 命中下一周期返回；连续 load 每周期一个 |
| DC-02 | `dc_02/` | store 命中后提交，数据写入；字节、半字、字三种宽度和所有对齐位置 |
| DC-03 | `dc_03/` | 写缓冲旁路：store 提交后紧跟同一字的 load（全覆盖和部分覆盖） |
| DC-04 | `dc_04/` | 连续 store 不停顿 |
| DC-05 | `dc_05/` | 缺失替换干净行：只有填充突发 |
| DC-06 | `dc_06/` | 缺失替换脏行：先写回（4 拍，数据正确），再填充 |
| DC-07 | `dc_07/` | store 缺失：写分配，填充后合并 store 数据 |
| DC-08 | `dc_08/` | `dc_kill_o`：被取消的 load 不返回，被取消的 store 不改变内存；正在进行的填充继续完成 |
| DC-09 | `dc_09/` | 设备 load/store：只在提交后发出；store 收到 B 后才返回；WSTRB 和数据落在正确字节 |
| DC-10 | `dc_10/` | 设备访问被 kill：不发出总线事务 |
| DC-11 | `dc_11/` | 对 ROM 的 store 返回访问错误；对未映射地址的 load/store 返回访问错误，且都不发出总线事务 |
| DC-12 | `dc_12/` | DDR 非缓存别名：不装入 cache，每次都发出单拍事务 |
| DC-13 | `dc_13/` | 填充返回错误：请求返回错误，该行不装入 |
| DC-14 | `dc_14/` | 设备访问返回错误：请求返回错误 |
| DC-15 | `dc_15/` | 随机 load/store 流（组冲突密集、kill 随机、AXI 随机延迟和反压），全程与参考模型一致，结束时整体 clean 后内存一致 |
| MT-01 | `mt_01/` | 范围 clean：范围内的脏行被写回、清脏位；范围外的脏行不变；行首、行尾不对齐的范围 |
| MT-02 | `mt_02/` | 范围 invalidate：范围内的行失效，脏数据不写回 |
| MT-03 | `mt_03/` | 范围 clean+invalidate |
| MT-04 | `mt_04/` | 整个 D$ clean |
| MT-05 | `mt_05/` | FENCE.I 序列：`dc_clean_all_o` 完成后 `ic_inv_o`；之后取指能看到 store 写入的新代码（I$ 与 D$ 共用同一个 AXI 内存模型） |
| MT-06 | `mt_06/` | FENCE：写缓冲非空时等到排空 |
| MT-07 | `mt_07/` | 维护期间可缓存请求不被接受；设备请求（轮询 STATUS）照常完成 |
| MT-08 | `mt_08/` | OP_SIZE = 0 立即完成；BUSY 期间写 OP_CMD 无效果 |
| MT-09 | `mt_09/` | 写回返回错误：IRQ_STAT.bit1 置位、ERR_ADDR 正确、`irq_o` 按 IRQ_EN 输出；写 1 清除 |
| PF-01 | `pf_01/` | 命中流的吞吐 |
| PF-02 | `pf_02/` | 缺失代价（SRAM 时序的内存模型，无反压，干净替换） |

## 覆盖

每次运行输出 `COVER name=count`，统计命中 load/store、缺失 clean/dirty × load/store、
全/部分写缓冲旁路、三种 kill 时刻、九个 PMA 区域（含未映射）、四个维护命令、
FENCE.I、FENCE，以及填充/设备/写回错误。`instruction_hits` 是附加的 I$ 命中统计。

```sh
python3 verif/block/cache/coverage.py build/cache/selftest/run.log \
    > build/cache/selftest/coverage.txt
```

真实 full 回归将所有日志作为参数传入相同命令；报告逐箱输出 `covered/uncovered`。
桩不具备完整 cache 行为，因此自测报告中命中、替换、旁路和错误等分箱为零是预期结果；
真实 RTL 的覆盖收敛属于 K-I1，不在桩阶段声称覆盖完成。

## 已确认的规格问题

协调者通过 ask 确认：I$ ROM 取指允许单拍 SIZE=3（SoC 单拍 SIZE≤2 针对数据侧）；
覆盖分箱采用命中 × load/store 两箱、缺失 × clean/dirty × load/store 四箱，空路填充计 clean。
无需更改本 worker 归属之外的规格文件。

尚待协调者回复：P0 的 test.yaml 字段名和文件列表约定、RTL 的平坦端口命名确认，
以及 OP_SIZE=0 是否仅适用于范围命令。MT-04 使用非零 OP_SIZE=32，仍检查范围以外
全部脏行的整体 clean；MT-08 独立检查范围命令的零长度行为，不依赖未确认的
“整体 clean 且 OP_SIZE=0”语义。当前 test.yaml 的字段完整涵盖 CLAUDE 9.1 要求，
直接 Verilator 命令不依赖 P0 框架。

## 本次桩验证结果（2026-10-25）

工具：Verilator 5.020；分支 `zc100116/task-cache-verif`，开发基点
`7894b4438c62880b3984830ebb4b79a9dd4a6e66`，源代码随本文件一起提交。

- 34 个功能/性能顶层全部通过 `--binary --timing -Wall` 桩编译。
- 34 个功能/性能顶层加 selftest，共 35 个顶层，最终 `--lint-only --timing -Wall`
  为零告警。共享行为内存的原子字节更新仅局部豁免 BLKSEQ，未关闭其他诊断。
- selftest 种子 1、17、101：全部 PASS，退出码 0；记录首个随机数和种子便于复现。
- `+BAD_AXI_LEN`：时刻 85 报出 `expected=3 actual=2`，退出码非零。
- `+BAD_CORE_HIT`：时刻 85 报出 `expected=1 actual=0`，退出码非零。
- 三种子覆盖汇总：缺失/等待时 kill 24 次，设备等提交时 kill 22 次；PMA ROM/SRAM/CLINT
  分别 126/6/141 次；范围 clean、FENCE.I、FENCE 各 3 次。其余分箱尚未覆盖，需真实 RTL。

原始数据：`build/cache/compile-summary.txt`、各测试目录下 `compile.log` / `lint.log`、
`build/cache/selftest/seed-{1,17,101}.log`、`bad_axi_len.log`、`bad_core_hit.log`、
`coverage.txt`。当前分支没有 `tools/check/`，已检查全部 44 个 SystemVerilog 文件的
100 列限制、空格缩进、接口分组和命名连接；仓库风格工具在 P0 集成后仍需补跑。
