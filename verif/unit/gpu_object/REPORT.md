# R-3o 对象单元验证

结论：PASS；对象核 12 级、II=1，输入两项弹性槽，三个输出独立握手。
环境：用户提供的仿真主机（环境不记录）。
指定的环境脚本不存在；已尝试加载，随后使用主机 PATH 中的工具完成验证。
Commit：`gpu: object unit`；精确版本执行下列命令取得：

```sh
git log -1 --format=%H -- rtl/gpu/edrv32_gpu_object.v
```

- 仿真：15 组全部 PASS，1,569 个对象输入。
- 写回 1,037 条，事件 1,557 条，四边形 836 条，逐项对照 Python 对象模型。
- 两组连续流共 1,272 次相邻拍检查全部 PASS；输入及三个输出均为 II=1。
- 覆盖推进、正负舍入和半值、速度/位置回绕、寿命、存活区域半开边界。
- 覆盖八目标框、逐位掩码、边缘接触、相隔一单位、本次失效者不碰撞。
- 覆盖 STEP=0、绘制开关、空槽、保留位、零/恰好/超出容量、计数与溢出清除。
- 覆盖独立背压负载保持、配置快照、finish 排空、publish 延后发布、stop 丢弃。
- RTL 风格、本机 Verilog-2001 lint、仿真主机 RTL lint：均 0 告警。
- 仿真编译：0 告警；未发现工具版本差异导致的问题。
- 已清理仿真主机上的本任务构建目录；列表 DDR 打包由 R-1 负责。
- 协调者确认：STEP=1 空槽不 update、发零事件；STEP=0 所有对象均无事件/写回。

复现（仿真命令在仿真主机工作副本中运行）：

```sh
python3 tools/check/verilog_style.py rtl/gpu/edrv32_gpu_object.v
verilator --lint-only -Wall --language 1364-2001 rtl/gpu/edrv32_gpu_object.v
python3 tools/regress.py smoke --path verif/unit/gpu_object -j 1
```

向量固定随机种子 303；生成物在 `build/gpu_object/`，回归日志在
`build/regress/smoke/unit/gpu_object/verilator/`。
