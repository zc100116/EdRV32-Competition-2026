# CPU v2 DIV C07 日程回放

- 日期：2026-11-28；实现/模型提交：本报告同一提交（`git log -1 --format=%H -- rtl/cpu2/edrv32_cpu2_div.v`）。
- 输入提交：1a26a7924；原模型提交：c6bd0dbd0b7dbc644edde2883f61e0e302c1747b；GCC 15.2。
- 输入：`build/cpu-v2/isa/zba/{coremark,vision,render}/{coremark.elf,spike.log}`，start_time 至 stop_time。
- 配置：规格 2.2 单发射精简+Zba、双发射满配+Zba；FPU_FORMAT=NONE；V3s 异步 RF。
- C07：普通 L=3+n，n=k/ceil(k/2)；除零/有符号溢出 L=2；k=0 仍独立修正。
- `pipe_model` 已含 1 拍 EX，故 division_left 输入从普通 1+n 改为 2+n，特殊为 1。
- 仅 v2 single/round4 启用 complete_schedule；历史 round2/round3 默认保留旧口径。

| 配置 | 负载 | 原周期 | C07 周期 | 增量 |
|---|---|---:|---:|---:|
| 单发射 | CoreMark | 2673925 | 2673925 | 0 |
| 双发射 | CoreMark | 1599073 | 1599073 | 0 |
| 单发射 | 视觉 | 2000889 | 2005575 | 4686 |
| 双发射 | 视觉 | 1169941 | 1174627 | 4686 |
| 单发射 | LVGL | 606286 | 606296 | 10 |
| 双发射 | LVGL | 421058 | 421068 | 10 |

CoreMark/MHz 不变：单发射 3.7398206756，双发射 6.2536231929；以上为 trace 模型，非板级成绩。
原始回放数据：`build/cpu2_i03/perf/*-w*.jsonl`；旧值见 cpu-v2-spec 7。
复现（仓库根目录，先加载仓库工具环境；三个负载串行）：

```sh
for w in coremark vision render; do python3 tools/cpu/eval/run_v2_single.py "$w" || exit; done
for w in coremark vision render; do python3 tools/cpu/eval/run_v2_round4.py "$w" --bases full --names combo4-zba --output "build/cpu2_i03/perf/dual-$w.jsonl" || exit; done
python3 -m unittest discover -s tools/cpu/eval -p test_pipe_model.py
```

验证：Verilator 5.051，mul/div 各六配置 smoke 共 12 项通过；12 次 RTL `--lint-only -Wall` 和风格检查均零告警；性能模型 94 项通过。
命令：`python3 tools/regress.py smoke --path verif/unit/cpu2_mul -j 1`，div 同理；覆盖及向量数量见对应单元 README。
时序切分经协调者确认：MUL E1 四个标准部分积/E2 交叉和/E3 合并/E4 捕获；DIV E0 并行捕获原始源/幅值，E1 位长差/3倍除数，E2 对齐/n 初始化。
DIV E0 路径为 issue 寄存→择老/源选择→标准取负→幅值寄存；E1 为幅值寄存→四字节并行前导位编码/平衡合并→位长差寄存。
Yosys 0.67+94 (`7defa5186`) `synth -noabc; abc -lut 6` 纯 LUT 参考：E0 幅值 12 级、E1 位长差 10 级、E2 对齐 4 级、迭代/修正最长 14 级；不含 issue 上游选择。
复现：`verif/unit/cpu2_div/README.md` 的 Yosys 命令及 `levels.py`；原始报告 `build/cpu2_i03/div-levels.log`。
纯 LUT 映射展开了标准进位链，不能代替 PDS；165 MHz、完整 issue→DIV 输入路径及区域控制扇出仍需 PDS 实测。
