# Pango DDR IP + 256-bit AXI Interconnect 仿真

两个独立的 256-bit AXI Master 同时经过通用 M:1 Interconnect、Pango Adapter 和真实
DDR IP/行为模型。Master 0 和 Master 1 并发发起 16 拍事务，写和读均并发，用于检查
最大长度事务之间的仲裁、全局 ID 路由和真实 DDR 返回时序。

该 case 使用 Pango 生成 IP 的 ModelSim 仿真库，并以 `-novopt` 运行。测试日志保存在
`sim/build/modelsim/cases/soc/pango-ddr-ip-interconnect/run.log`。
