# CPU / NPU 测量产物

总报告：`../result.md`。重点风险：`cpu/dangerous_paths.md`、`npu/dangerous_paths.md`。

每个工程目录包含：

- timing_summary.txt：所有检查类型与两角汇总。
- setup_top200.txt、hold_top200.txt：两角各 200 条，不限于负裕量。
- setup_top20_detail.txt、hold_top20.txt：两角各 20 条原文逐级明细。
- recovery_removal_top20.txt、unconstrained_io_paths.txt：异步检查和没有 slack 的 IO 路径。
- all_paths.tsv：全部扩展路径索引；CPU 额外保存正裕量过滤视图。
- resource_summary.txt、resource_hier.txt、high_fanout.txt：最终资源、完整层次、前 100 高扇出及控制网络表。
- flow_summary.txt、logs/：最终阶段耗时、W/E 全部原文、执行节选与历史 GUI 操作节选。
- native_reports/：完整原生 cmr/snr/dmr/prr/rtr、约束检查和相关资源报告。

CPU 另有 ip_sram_ports.md；NPU 另有 ip_ports.md 和两次 ModelSim 检查/诊断日志。
完整原始 run.log 和扩展 .rtr 留在 result.md 标明的本机目录，不上传数据库、工程、IP RTL 或 bitstream。
