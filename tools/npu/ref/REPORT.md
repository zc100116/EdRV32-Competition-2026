# N-M2 验收与性能测量

测量代码 commit：`e102398d2b2d78dffe684c68d9ed7f5a207d7719`。
日期：2026-10-27。分支：`zc100116/task-npu-ref`。
环境：Linux、AMD EPYC 7742；`nproc` 为 3，开发资源预算 8 GB，
同时有其他 worker 运行；Python 3.12.3、numpy 2.5.2、OpenBLAS 0.3.34。
性能测量设置 `OPENBLAS_NUM_THREADS=1`。

## 自检

```sh
~/.local/opt/edrv32-py/bin/python -m unittest discover -s tools/npu/ref -v
```

17 个 unittest 方法全部通过，最后一次无 BLAS 线程设置的运行耗时 13.800 s。
TL-01 有 16 组手算向量和 4 个 LUT 下标；TL-02 有 112 组随机 CONV、
3 组随机 POOL、1 组全负 POOL、3 组随机 UPSAMPLE。三个随机种子对应多种形状，
覆盖 4×4 到 16×8、宽度 12、奇数输入高度的 S2 边界、三种权重块、单平面写回、
LUT 和残差、四种基址、非零偏移和平面间隙。

另覆盖描述符顺序依赖、快照、原始容量字段、非法 OP 停止、错误 CUR_DESC、
派生字段不参与算术、hex 字节序、命令行和 `--split-at` 的完整状态恢复。
测试的描述符/权重/参数打包和纯 Python 逐元素算术均独立于编译工具。

`git diff --check` 无输出；所有 Python 代码无 Tab、无超过 100 列的代码行。
本次未改 RTL，Verilog 风格检查和 Verilator lint 无适用文件。

## 3×3 S1 命令行演示

```sh
PYTHONPATH=tools/npu/ref ~/.local/opt/edrv32-py/bin/python -c \
    "from test_ref import create_demo; create_demo('build/npu/ref_demo')"
~/.local/opt/edrv32-py/bin/python tools/npu/ref/npu_ref.py build/npu/ref_demo/
~/.local/opt/edrv32-py/bin/python tools/npu/ref/npu_ref.py build/npu/ref_demo/ --per-desc
```

固定种子 2026，输入 8×4×16，3×3 S1，输出 8×4×32。
命令返回 0，产生 `build/npu/ref_demo/ref_out.hex` 和可选的
`ref_desc_0.hex`；最终文件共 58 行（1 条地址和 57 个 beat，检查范围包含平面间隙
及未写入的哨兵平面）。同一用例在 unittest 中与朴素实现逐字节比对。

最终输出起始地址行为 `@288000`；首个 beat 为：

```text
7ff5f5f4e4f5f5e780f4fbf6eb4ff5e512f6f5f6e9f7f5f81de3cdf4e0b3f5d6
```

## 合成整网规模吞吐

```sh
OPENBLAS_NUM_THREADS=1 ~/.local/opt/edrv32-py/bin/python tools/npu/ref/benchmark.py
OPENBLAS_NUM_THREADS=1 /usr/bin/time -f 'CLI wall=%e s peak=%M KiB' \
    ~/.local/opt/edrv32-py/bin/python tools/npu/ref/npu_ref.py build/npu/ref_benchmark/
```

| 层 | 形状与算子 | MAC 数 | 单层执行耗时 |
|---|---|---:|---:|
| L7 | 40×24×128 → 20×12×256，3×3 S2 | 70,778,880 | 0.021034 s |
| L15.split | 80×48×192 → 80×48×64，1×1 S1 | 47,185,920 | 0.012692 s |

单层计时包含输入读取、权重与参数解码、卷积、量化、写回，不包含测试夹具生成。
68 条合成描述符由以上两层各重复 34 次组成，所有容量检查通过；总计
4,010,803,200 MAC，描述符表执行实测 **1.069301 s**。完整命令行（含 Python/numpy
启动、hex 装载和最终输出文件写入）实测 **1.24 s**，峰值 RSS **43,624 KiB**。
基准进程连同夹具生成的峰值 RSS 为 **50.16 MiB**。

按实测吞吐线性折算 26 亿 MAC：`1.069301 × 2.6e9 / 4010803200 = 0.693173 s`。
这是算术吞吐估算，未包含真实 68 层形状分布和全网文件 I/O；实测的完整合成命令行
证明本实现满足“几分钟内”的规模要求，不能据此声称真实 YOLOv8n 已完成逐层验证。
无此前参考模型基线可比较。

原始日志：`build/npu/ref_benchmark/benchmark.log`、`cli-time.log`。
可重放镜像：同目录的 regs.txt、mem_model.hex、check.txt；最终输出 ref_out.hex。
以上均为生成物，不入库。

## 规格提问与采用的解释

四项问题均获协调者回复，无超时后自行决定的事项：

1. 第 6 节三项容量检查只对 CONV，使用描述符原始 ROW_SLOT_BEATS、COUT_BLOCKS、
   WEIGHT_BLOCK_BYTES；不检查自洽。算术和权重块寻址始终按形状重算。
2. 稀疏存储未装载/未写入字节读 0；check.txt 范围按 32 B beat 对齐。
3. `5×ROW_SLOT_BEATS=1024` 不可达，3×3 行槽测试最大合法 204 和首个非法 205；
   1×1 测试 512/513。协调者已确认更新验证方案。
4. 协调者追加 `--split-at N --out <新目录>`；为避免猜测地址的区域归属，
   公共格式增加 mem_state.hex 作为完整绝对地址状态容器，所有装载逻辑读取
   全部 mem_*.hex。提取目录仅含 mem_state.hex、regs.txt、check.txt。

真实模型 TL-04、编译工具互操作、RTL 逐位比较仍由后续集成任务完成。
