# NPU A5 权重寄存器按字节保留

基线 `63a14aba`；改后为本报告所在提交；原物理路径来自卡 23 B3N 结果 `80baca24`。
目标 PG2L200H-6，clk_npu 150 MHz。

## 背景

卡 23 B3N：clk_npu slow WNS −0.078 ns，唯一终点为 `g_weight_channel[*].weight_r[43]` → APM_659_366，
起点 CLMS_147_973，走线 5.863 ns，扇出 2。核查 RTL：权重每字节只驱动一个 APM，扇出 2 是同一 SIMD APM 的
b0/b1 两个输入，不是两个 APM。卡 23 精简产物不含以 weight_r 为终点的路径，D 端裕量和源位置未取得，
寄存器被拉远的原因无法判定。

## 改动

- `edrv32_npu_window`：A5 权重由 32 个 64 位寄存器改为 256 个 8 位寄存器，各自 `syn_preserve`，
  便于 PDS 把每个字节放到所驱动的 APM 旁；FF 数量不变，不增加流水级，A5 时刻不变。
- 激活保持设计 4.3.2 的四份物理副本，不改。（worker 曾按通道复制激活，Yosys FF +21376，且把 32 扇出
  前移到 a4_activation_r，与失败路径无关，协调者撤回。）

## 验证

- 风格检查 `python3 tools/check/verilog_style.py rtl/npu/edrv32_npu_window.v`：0 告警。
- `python3 tools/regress.py smoke --path verif/unit/<npu_window|npu_mac_array|npu_datapath> -j 1`：3/3 PASS。

## 待 PDS 复验

物理 WNS 是否消除需卡 24 B3N 重跑；卡 24 需补报 `g_weight_byte[*].weight_r` 的 D 端路径（源单元位置、裕量）。
