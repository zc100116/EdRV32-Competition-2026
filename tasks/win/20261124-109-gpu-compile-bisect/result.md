# 卡 109 结果

| 项 | 内容 |
|---|---|
| 代码 HEAD | `6ba07201ee55bea0f5f0d33975df67df5b5c5cc9` |
| PDS 版本 | Windows PDS 2022.2-SP6.1 build 138931 |
| 器件 | Logos2 PG2L200H-6 FBB676 |
| 输入 | 卡 107 的 GPU-only 文件列表与已生成的 IP |
| 结果 | `edrv32_gpu_unpack` 可单独触发 `InferWriteMode.cpp:2983`，独立 Verilog 样例可重复复现 |

## 模块扫描

35 个候选逐个用相同源文件列表、各自的顶层与独立工作目录编译。32 个通过，1 个复现内部崩溃，2 个报告其他错误。各次 PDS 进程墙钟时间合计 1791.72 秒。完整结果包含最后一条 `Found Ram`、退出类别及第一条错误。[35 个模块的扫描表](artifacts/module-scan.txt)

| 模块 | 结果 | 最后一条 Found Ram | 用时 |
|---|---|---|---:|
| `edrv32_gpu_unpack` | `InferWriteMode.cpp:2983` 与 `Flow-0189` | 无，DFF-inference 完成后即崩溃 | 5.90 秒 |
| `edrv32_gpu_clip` | `output_r` 多驱动 | 无 | 261.25 秒 |
| `edrv32_gpu_geometry` | 内部 `edrv32_gpu_clip.output_r` 多驱动 | `screen_r`，深度 8，宽度 259 | 514.48 秒 |

## 崩溃定位

`rtl/gpu/edrv32_gpu_unpack.v:73–75` 在模块作用域声明 3 个共享数组。第 153 行展开 5 个通道，每个通道各有一个时序过程，用自己的尾指针写共享数组中对应的 2 个槽。PDS 对多个过程经动态地址写同一数组的写法触发内部错误。删除任意两组写入、仅保留第三组时，`data_r`、`keep_r`、`last_r` 都能各自触发同一错误。删除三组写入后通过。原样编译该模块且只加入这一个源文件也复现。[原文读写语句与行号](artifacts/unpack-rtl-accesses.txt) · [逐项删减记录](artifacts/isolation-results.txt)

```verilog
data_r[c*2+{31'b0, tail_r[c]}] <= data_w[c];
keep_r[c*2+{31'b0, tail_r[c]}] <= keep_w[c];
last_r[c*2+{31'b0, tail_r[c]}] <= last_w[c];
```

最小已验证样例使用 3 个通道、每通道 2 槽、每槽 1 位。写地址为 `c*2 + tail_i[c]`，读地址为 `c*2 + head_i[c]`。该样例可以独立 Compile，并重复触发相同错误。在这组对照中，1 个通道通过，2 个通道报 `Sdm-4010` 多端口 RAM，3 个起复现内部崩溃。去掉原始的 31 位补零仍可复现。每个通道改用各自的两槽局部数组后，小样例和完整 unpack 模块的诊断副本均通过 Compile。[独立复现 Verilog](artifacts/min_repro_edrv32_gpu_unpack.v) · [分开存储的对照样例](artifacts/unpack-local-banks-control.v) · [崩溃和通过日志](artifacts/min_repro_edrv32_gpu_unpack.log)

复现时用同版本 PDS 开空工程，器件设为 PG2L200H-6 FBB676，加入该单个 Verilog 文件，设顶层为 `unpack_probe` 后执行 Compile。样例无外部 RTL、IP 和约束依赖。卡 107 的整片和 GPU-only 在崩溃前最后打印了写 DMA 的 `strobe_r`。本卡对原写 DMA 作顶层编译通过，原错已在独立 unpack 模块定位。

## 另一处编译问题

`edrv32_gpu_clip.v:286–289` 在同一个时序过程内，对 `output_r[write_r]` 的两个互斥分支分别做整字写和分段写。缩到 16 位数组的小样例仍会报多驱动。两条路径先选出整字再做一次写入，样例通过。这个结果也解释了 `geometry` 扫描中的同类错误。[独立样例](artifacts/clip-multiple-drivers.v) · [失败和通过日志](artifacts/clip-multiple-drivers.log)

## 问题与偏离

诊断改动均在 G 盘临时副本验证。完整 unpack 的分通道存储变体已通过单模块 Compile，尚未进行功能回归或整片 Compile 复测。源码管理分支收录扫描表、样例和日志节选。原始工作目录在 `G:/codex_project/edrv32-card109/build/card109/modules/` 与 `probes/`。
