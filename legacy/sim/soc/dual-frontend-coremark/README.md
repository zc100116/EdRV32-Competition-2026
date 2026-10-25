# 单发射 / 双窗口 / 独立双 ALU 的 CoreMark 对照

这套用例固定 GCC 15.2 的 O2/O3 软件镜像，对照硬件配置。需要 Linux Python 3、Verilator、GNU make 和 C++ 编译器，不需要重新编译固件。

```sh
python3 sim/script/run_dual_coremark.py --mode all --opt both
python3 sim/script/run_dual_coremark.py --mode dual --opt o2
```

`scalar`：原前端与单发射后端；`paired`：双窗口前端与单发射后端；`dual`：独立 ALU+ALU 双发射/双退休。`wide`：64 位命中取指与双 ALU；`all` 编译四种配置；旧默认 `both` 仍仅编译 scalar/paired。每个配置 O2/O3 各运行三轮。dual 仍有一个 LSU、一个 MDU，分支/系统等指令单独发射。

镜像在 `sim/fixtures/coremark/o2-i10/`、`o3-i10/`，固定 10 次迭代，三轮 CRC 必须为 e3c1/0747/8d84/c64e；软件 CSR 区间的退休数 O2=2,899,049、O3=2,944,145。它们与板上 4000 次迭代固件不同。scalar 第二轮还必须精确匹配基线周期 O2=3,487,221、O3=3,523,737。

构建失败、退出码非零、CRC 错误、退休数不符、未完成三轮或超时都判为失败。manifest 保存源码/头文件、固定镜像、工具版本、编译和执行命令、二进制/日志 SHA256。所有测试使用新建输出目录，便于保留前次记录。

SoC wrapper 使用快速 UART 仿真模型，通过 APB 写口观察输出。`HPM cycles/instret` 来自软件读 CSR 的计数区域，作为周期/CPI 对照；`SIM_PROFILE` 是 testbench 观察窗口，含额外统计管理指令，不能混用。原标量/paired 窗口多 25 周期和 5 条；本阶段 wide O2 热态多 26 周期和 5 条，wide O3 多 24 周期和 5 条，实际偏移由两组数据直接核对。

`SIM_PROFILE` 同时记录 B 实际退休数、A 接收/B 配对数和互斥配对拒绝原因。拒绝原因只在 A 真正接收时统计，不把停顿期间同一候选反复计数；优先级为 B 不存在、非双 ALU、组内 RAW、组内 WAW、B 老生产者未准备、B 依赖 DECODE resident、metadata。它们含推测路径接收，故不能当成可直接消掉的退休周期。`a_resident_second_wait` 是周期计数，另行记录。

结果仅属于仿真。资源、最高频率、真实 UART 和板上 CoreMark 需后续综合布线/上板验证。
