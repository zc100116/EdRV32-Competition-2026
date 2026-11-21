# NPU Python 参考模型

本目录实现 `docs/spec/npu-spec.md` v0.2 的存储和整数算术语义，对应
`docs/testplan/npu-testplan.md` 的 TL-01、TL-02；不导入编译工具或旧工程代码。
仅依赖标准库和 `tools/requirements.txt` 中的 numpy。

```sh
~/.local/opt/edrv32-py/bin/python tools/npu/ref/npu_ref.py build/npu/<用例>/
# 同时保存每条描述符后的输出平面，编号从 0 开始：
~/.local/opt/edrv32-py/bin/python tools/npu/ref/npu_ref.py build/npu/<用例>/ --per-desc
```

输入为 `regs.txt`、所有存在的 `mem_*.hex` 和 `check.txt`。寄存器文件每行为
`名称 十六进制值`，必须提供 MODEL_BASE、WORK_BASE、INPUT_BASE、OUTPUT_BASE、
DESC_BASE、DESC_COUNT。检查文件每行为 `名称 起始字节地址十六进制 字节数十六进制`。
检查区间的地址和长度均按 32 B 对齐。

镜像文件的 `@` 地址以 32 B beat 为单位；每行 64 个十六进制字符，最高字节在左侧，
最低 DDR 地址对应最右侧字节。装载时按绝对地址写入同一份稀疏存储；未装载、未写入的
字节为 0。文件区名支持 model、desc、input、work、output、state。

成功时写 `ref_out.hex`，按 `check.txt` 的顺序输出全部区间；`--per-desc` 另写
`ref_desc_<n>.hex`，逐平面输出有效输出区，忽略平面之间的空隙。
非法 OP 或容量超限时立即停止，进程返回 1，并在标准输出报告：

```text
ERR_CODE 00000003
CUR_DESC 00000001
```

ERR_CODE 3 表示非法 OP，4 表示容量超限；CUR_DESC 从 0 开始。错误描述符不执行，
后续描述符不执行，且本次运行不生成最终输出；已完成描述符的快照保留。

协调者增加的代表层提取接口：

```sh
~/.local/opt/edrv32-py/bin/python tools/npu/ref/npu_ref.py build/npu/<用例>/ \
    --split-at 25 --out build/npu/<新用例>/
~/.local/opt/edrv32-py/bin/python tools/npu/ref/npu_ref.py build/npu/<新用例>/
```

提取命令只执行前 N 条描述符，将执行第 N 条之前的完整稀疏存储按页写入
`mem_state.hex`，并写出 regs.txt/check.txt；目标必须是新目录。新的 DESC_BASE 指向
原来的第 N 条，DESC_COUNT 为 1，check.txt 列出该描述符的有效输出平面。
未分配页仍隐含为零；存储页内的字节全部保留，包括其他层、模型和描述符。

| 规格条款 | 实现对应 |
|---|---|
| 2.1 | CONV 窗口补零、1×1/3×3、S1/S2；POOL 5×5/−128 补边；2× UPSAMPLE |
| 2.2 | C16 平面中 `[行][像素][16 通道]`；C4 `[行][像素][4 字节]`；独立平面跨距 |
| 2.3 | int64 保存 33/49 位中间值；带正舍入偏置的算术右移、加零点、饱和、无符号 LUT 下标、残差加 |
| 2.4 | 描述符顺序执行；每条完成写回后再读取下一条 |
| 4.1 | 小端 16×32 位字段；四种基址、偏移；HALF_TAIL 只写末块一个 C16 平面 |
| 4.2 | 独立读取各 C32 的 512 B 记录、通道参数和 LUT；不使用记录第 7 字节作为零点 |
| 4.3 | 普通块、半块尾块、C4 首层分别解码为数学权重；权重块位置由形状重算 |
| 6 | 非法 OP；仅 CONV 的三项原始字段容量检查；不检查派生量自洽或地址范围 |

CONV 使用 numpy 滑窗视图和分块 float64 矩阵乘。INT8 乘积和累加都是整数，
合法 INT32 累加范围远小于 float64 精确整数范围 2^53，转回 int64 不丢位。
每块约 1024 个输出像素，避免把整层窗口展开为大矩阵；不模拟物理 MAC 的调度。
共享开发主机上建议用 `OPENBLAS_NUM_THREADS=1` 限制单进程的 BLAS 线程。

自检与独立生成的 3×3 S1 演示：

```sh
~/.local/opt/edrv32-py/bin/python -m unittest discover -s tools/npu/ref
PYTHONPATH=tools/npu/ref ~/.local/opt/edrv32-py/bin/python -c \
    "from test_ref import create_demo; create_demo('build/npu/ref_demo')"
~/.local/opt/edrv32-py/bin/python tools/npu/ref/npu_ref.py build/npu/ref_demo/ --per-desc
```

17 个 unittest 方法包括 16 组手算量化向量、4 个 LUT 边界下标，以及 112 组随机
CONV（96 组覆盖全部 K3/S2/LUT/RES/HALF 组合、6 组多输入/输出块、6 组 C4、
4 组四基址）。POOL/UPSAMPLE 各用 3 种形状和种子，另有全负池化、错误停止、
容量边界、派生字段不影响算术、描述符依赖、hex 字节序、命令行和提取状态测试。
所有算子期望值由测试中的纯 Python 逐元素循环计算；描述符、权重和量化记录由
测试独立按规格打包。

性能复现命令：

```sh
OPENBLAS_NUM_THREADS=1 ~/.local/opt/edrv32-py/bin/python tools/npu/ref/benchmark.py
OPENBLAS_NUM_THREADS=1 /usr/bin/time -f 'wall=%e s peak=%M KiB' \
    ~/.local/opt/edrv32-py/bin/python tools/npu/ref/npu_ref.py build/npu/ref_benchmark/
```

基准独立生成 68 条合成描述符，交替执行 L7（40×24×128 → 20×12×256，3×3 S2）
和 L15.split（80×48×192 → 80×48×64，1×1 S1），总计约 40 亿 MAC。
生成物位于 build/npu/ref_benchmark/；测量条件和数字见 [REPORT.md](REPORT.md)。
这是规模和吞吐测量，真实 68 层网络逐层比对属于后续 TL-04。

协调者确认的解释：

- 容量检查仅对 CONV 生效，读取原始 ROW_SLOT_BEATS、COUT_BLOCKS、
  WEIGHT_BLOCK_BYTES；算术和权重寻址从形状重算，不比较派生字段是否自洽。
- 未写字节为 0；检查区间按 beat 对齐。
- 3×3 行槽上限不能恰好等于 1024，测 204/205；1×1 测 512/513。
- 提取状态使用公共格式新增的 mem_state.hex，装载目录内全部 mem_*.hex。

已知限制：模型只描述完成后的功能状态，不模拟 AXI 响应、事务时序、ABORT、
性能计数器或硬件读写错误 ERR_CODE 1/2。合法形状、地址对齐和无效通道参数由
离线工具保证；模型只执行规格第 6 节规定的检查。真实权重整网、量化精度和 RTL
比对不属于本目录自检的结论。
