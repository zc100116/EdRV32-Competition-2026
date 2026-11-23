# X-3 reset_ctrl / SYSCTRL GPU variants

- 依据：gpu-soc-spec v0.2 5.1、5.3、8.1；gpu-soc-testplan ST-14 模块级部分。
- reset_ctrl：NPU 域改为 GPU，删除两路摄像头域，新增 AUD 域；其余逻辑沿用。
- SYSCTRL：CHIP_ID 为 `0xED32_0002`，其余逻辑沿用。
- 视觉 RTL、系统子系统顶层、公共文件列表未改。
- 测试从 soc_reset_ctrl、periph_sysctrl 单元测试复制到 `_gpu` 目录。
- 新增 ST-14：六个媒体域同批请求、各自两拍同步释放、16 个系统周期保持、
  两次 SYSCTRL 媒体软复位、存储副本先于系统释放、全域异步置位。

环境：用户提供的仿真主机（环境不记录）。

兼容性：复制测试中的 POR 复位信号声明前移，满足主机 Icarus 的先声明要求；
未改 RTL 行为。

结果：reset_ctrl 默认、fast_mem、ST-14 在两个仿真器下共 6 PASS / 0 FAIL；
SYSCTRL 在两个仿真器下共 2 PASS / 0 FAIL；RTL lint 和风格检查均 0 告警。

复现（仓库根目录）：

```sh
python3 tools/regress.py full -j 1 --path verif/unit/soc_reset_ctrl_gpu
python3 tools/regress.py smoke -j 1 --path verif/unit/periph_sysctrl_gpu
python3 tools/check/verilog_style.py rtl/soc/edrv32_soc_reset_ctrl_gpu.v \
    rtl/periph/edrv32_periph_sysctrl_gpu.v
verilator --lint-only -Wall -Irtl/include --top-module edrv32_soc_reset_ctrl_gpu \
    rtl/soc/edrv32_soc_reset_ctrl_gpu.v rtl/common/edrv32_cdc_sync_bit.v \
    rtl/common/edrv32_reset_sync.v rtl/common/edrv32_reset_copy.v
verilator --lint-only -Wall -Irtl/include --top-module edrv32_periph_sysctrl_gpu \
    rtl/periph/edrv32_periph_sysctrl_gpu.v rtl/common/edrv32_cdc_sync_bit.v
```

实现和报告同一提交：`sys: reset_ctrl and sysctrl variants for the GPU SoC`。
Commit：`git log -1 --format=%H -- verif/unit/soc_reset_ctrl_gpu/README.md`。
