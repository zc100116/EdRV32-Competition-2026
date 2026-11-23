# V-1a 验证结果

结论：GT-01–GT-08 模型对模型全部 PASS；testbench 本机 lint 0 告警。
仅修改 verif/block/gpu；未读取 rtl/gpu，未修改参考模型。
提交：本报告所在提交，`git log -1 --format=%H -- verif/block/gpu`。
参考模型基线：M-1b `bea702e01`（独立验证副本），v0.2 API。
环境：用户提供的仿真主机（环境不记录）；本机仅 lint、风格检查。

| 测试 | DDR 比较字节数 | Surface 区域数 | 结果 |
|---|---:|---:|---|
| GT-01 | 33408 | 3 | PASS |
| GT-02 | 13760 | 1 | PASS |
| GT-03 | 260288 | 21 | PASS |
| GT-04 | 124096 | 10 | PASS |
| GT-05 | 74720 | 6 | PASS |
| GT-06 | 24992 | 1 | PASS |
| GT-07 | 99616 | 8 | PASS |
| GT-08 | 302432 | 24 | PASS |

共比较 933312 字节、74 个 Surface 区域、96 个功能寄存器读值。
GT-01 的第三个 Surface 在非法操作码之后，保持初始值；ERR_CODE=1，DONE 不置位。
GT-06 3136 个像素恰好各累加一次，128 个有效三角形，退化三角形不贡献像素。
GT-04 PERF2=18；GT-05 PERF2=4。
每项比较 PERF1–4；PERF0、5–8 仅采集，不作周期判定（协调者确认）。
比较器对 DDR/寄存器各一个 bit 的人为改动均正确返回失败，恢复后 PASS。

复现（仓库根目录；运行前使用所记录参考模型基线）：

```sh
python3 verif/block/gpu/run.py model
python3 verif/block/gpu/run.py compare
verilator --lint-only --timing -Wall --top-module edrv32_gpu_tb -f verif/block/gpu/lint.f
python3 tools/check/verilog_style.py verif/block/gpu
```

仓库风格工具只扫描 .v/.vh，本任务无此类文件；4 个 .sv 的文件头、缩进和行宽
另行逐项检查，0 告警。lint.vlt 对验证过程、共享检查器及未使用 APB 槽做局部豁免。
RTL 尚未提供，lint 使用仅有公共端口的独立桩，不宣称真实 GPU RTL 回归通过。
RTL 集成后运行 `python3 verif/block/gpu/run.py rtl`，或统一 smoke 回归。
生成物：build/gpu/block/gt01–gt08；主机上的进程和构建目录在结束后清理。
环境使用方法和新增测试的三步见 README.md；后续测试复用同一顶层、生成器和比较器。
