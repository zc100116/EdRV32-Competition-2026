文件列表，仿真和综合共用。路径相对本目录；由协调者维护（CLAUDE.md 11.4）。

| 文件 | 内容 |
|---|---|
| `cpu.f` | 处理器核 `edrv32_cpu_core` 及其子模块、乘法器包装 |
| `cache.f` | I$、D$、cache_ctrl、PMA 译码和 4 个 RAM 包装 |
| `cpu_subsys.f` | CPU 子系统 `edrv32_cpu_subsys`（core + I$/D$ + cache_ctrl），包含 cpu.f 和 cache.f |
| `sys_subsys.f` | 系统子系统 `edrv32_sys_subsys`（sys_xbar、ROM/SRAM、APB 桥、CLINT、PLIC、外设、reset_ctrl）及所用公共原语 |
| `npu_datapath.f` | NPU 数据通路子顶层 `edrv32_npu_datapath` 及 12 个子模块、10 个 NPU 包装模块（N-D1；控制器、DMA、寄存器块在 N-C1 补入完整 NPU 文件列表） |
