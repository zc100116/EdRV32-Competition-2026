# Pango DDR IP 仿真

该 case 只包含生成的 `ddr` 控制器/PHY、两颗 Micron x16 DDR3 行为模型和直接
连接用户接口的测试激励，不经过项目中的 AXI Adapter、DDR Interconnect 或 CPU。

测试等待真实训练完成后，分别执行 1、8、16 拍写入和回读，检查数据、ID、末拍和训练
错误，并输出 8/16 拍读事务的用户时钟周期数。该 case 必须用 ModelSim 运行；Pango
加密库不能由 Icarus 或 Verilator 编译。

当前机器上的 ModelSim 2020.4 运行 Pango DDR 模型时必须给 `vsim` 加 `-novopt`；
优化模式会在 `GTP_GPLL` 的 real-delay 计算中失败。测试日志保存在
`sim/build/modelsim/cases/soc/pango-ddr-ip/run.log`。
