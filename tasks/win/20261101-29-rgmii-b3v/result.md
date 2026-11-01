# 卡29：B3V综合约束检查失败

- 分支win/20261101-29-rgmii-b3v；输入fd21b2d7。
- 工程G:/codex_project/EdRV32-FPGA/EdRV32-B3V，PDS 2022.2-SP6.1、PG2L200H-6 FBB676。
- compile结束；synthesize在约束检查阶段报2条错误并停止。没有运行后续dev_map/pnr/timing/bitgen，也没有新上板结果。

## 错误原文

```text
E: ConstraintEditor-0046: [G:/codex_project/EdRV32-Competition-2026/fpga/constraints/edrv32_fpga_board_vision_top.fdc(line number: 1162)] Object 'i:u_rgmii.u_pll_eth.u_gpll.gpll_inst' can not be found in current view.
E: ConstraintEditor-0046: [G:/codex_project/EdRV32-Competition-2026/fpga/constraints/edrv32_fpga_board_vision_top.fdc(line number: 1163)] Object 'i:u_pll_sys.u_gpll.gpll_inst' can not be found in current view.
```

对应FDC内容：

```tcl
define_attribute {i:u_rgmii.u_pll_eth.u_gpll.gpll_inst} {PAP_LOC} {GPLL_7_1381}
define_attribute {i:u_pll_sys.u_gpll.gpll_inst} {PAP_LOC} {GPLL_727_463}
```

失败是当前综合视图找不到这两个实例对象；不是include路径错误或源码文件不存在。尚不能据此判断两个GPLL站点本身无效，也未证明仅更换层次分隔符即可修复。按任务卡第5节“有约束不被接受就停下，不自行改写约束”，本轮没有改FDC/RTL/IP或尝试绕过错误。

## 输入延迟命令

日志中4条set_input_delay均返回successfully：max3.0、min1.0，以及带-clock_fall/-add_delay的max3.0/min1.0。完整执行原文见artifacts/logs/input_delay_execution.txt。这只证明本阶段命令被接受，不代表已完成时序覆盖或setup/hold验证。

另有UserConstraintEditor-4009提示i:u_rgmii及i:u_ddr3/u_ddrphy_top不是GTP实例，LOC/REGION可能不生效，原文保存在constraint_warnings.txt；不将它们与两个新增PLL对象找不到的错误混为一谈。

## 流程与产物

compile耗时1m38s、峰值内存池496MB；失败的synthesize耗时12s、峰值567MB。CPU/Process CPU与警告/错误行数见artifacts/flow_summary.txt。

保存了两条错误、上下文、输入延迟执行原文、约束提示、实际FDC副本和流程摘要。未上传完整PDS原始run.log或旧实现数据库。完整日志留在上述工程的compile/run.log和synthesize/run.log。

PLL/缓冲实际站点：未取得本卡结果。RGMII RX上升/下降沿setup/hold、各时钟域时序、布局布线耗时及5次PHY复位/视频测试：均未执行，不以旧卡数据填补。
