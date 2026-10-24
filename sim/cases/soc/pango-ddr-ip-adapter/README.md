# Pango DDR IP + AXI Adapter 仿真

该 case 将标准 256-bit AXI Master 接到 `edrv32_pango_ddr_axi_adapter`，再连接真实生成的
`ddr` 和 Micron DDR3 行为模型。覆盖 1、8、16 拍事务，验证受限 DDR AXI profile 中
一个 AXI 请求与一个 DDR UI 请求的一一映射。每次写入均回读比较数据、ID、响应和
`RLAST`，日志记录写、读各自的用户时钟周期数。

该 case 使用 Pango 生成 IP 的 ModelSim 仿真库，并以 `-novopt` 运行。测试日志保存在
`sim/build/modelsim/cases/soc/pango-ddr-ip-adapter/run.log`。
