# NPU 按切片复制（T-FANOUT-NPU）

- 基线：`zc100116/b3`，`09290bda`；测量对象为本报告所在提交的 RTL。
- `edrv32_npu_residual_add.v`：仅恢复 `6c55d387^` 的通道旁路选择；
  64 份 `wb1_bypass_r`、64 份带 keep/syn_preserve 的 `wb1_res_en_r`，WB1 计算 y+r−zp。
- `edrv32_npu.v`：新增 post_active/is_conv 各 8 份带 keep/syn_preserve 的控制副本，
  每份仅选择自己的 32 位写数据；复位、更新优先级及保持条件与原寄存器相同。
- 原 valid/ready/地址/beats 选择及 WB1/WB2 延迟保持不变。

参考扇出（Yosys 0.67+94，LUT6，RAM 黑盒、乘法器保留；不是 PDS 布线结果）：
- `quant_tag_w[28]`：64；`wb1_res_en_r`：64 份，每份 8–9。
- 写数据 post_active/is_conv 副本：各 8 份，每份 32；原寄存器分别为 86/114。
- 命令：`python3 tools/synth/fanout_soc.py build/fanout-npu/yosys --target npu`。
  参考映射须保留 syn_preserve 副本及原 post_active/is_conv FF，避免 Yosys 合并同值 FF。
  脚本原样运行时，post_active 的原 FF 合并到一份副本：7 份 32、1 份 120；is_conv 各份 32。

验证命令与结果（仿真场景成功运行一次；缩减验收前已完成的用例不重跑）：
- `python3 tools/regress.py smoke --path verif/unit/npu_residual_add -j 1`：PASS，1098 对。
- `python3 tools/regress.py smoke --path verif/unit/npu_writeback -j 1`：PASS，
  323 次读、109 个数据块、107 个命令。
- npu_top：用 `tools.regress.expand_files` 展开 `verif/unit/npu_top/files.f`，
  `verilator --binary --timing -Wall -j 1 +define+SIM_MODE --top-module tb_npu_top` 编译后运行；
  PASS：空列表、CUR_DESC=COUNT-1、X10、软复位；不执行 runner 附带的 RG-02。
- `python3 verif/block/npu/run.py --test OP-06`：PASS，work/output 两种残差来源。
- `python3 verif/block/npu/post/run.py --test PP-05`：PASS，count1–count5 共 5 个场景。
- `python3 tools/check/verilog_style.py rtl/npu/edrv32_npu.v rtl/npu/edrv32_npu_residual_add.v`：
  2 文件，0 告警。
- 展开 `rtl/filelists/npu.f`，`verilator --lint-only -Wall -DSIM_MODE --top-module edrv32_npu`：
  PASS，0 告警。
- `python3 verif/unit/npu_post_tail/lint.py`：SoC/FPGA 整片顶层 PASS，0 告警。
- npu_top/FPGA 首次检查受现有 PROCASSINIT 告警阻塞（FAIL）；改用 Verilator 5.020，
  保留全部 -Wall 诊断；后处理准备脚本失败后改用支持所需语法的 Python，未改源文件。
- `git diff --check`：PASS；`rg '\bg_\w+(\[[^]]+\])?\.'` 检查两文件：0 处层次引用。
