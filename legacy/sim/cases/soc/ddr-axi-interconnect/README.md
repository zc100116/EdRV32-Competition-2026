# 通用 AXI M:1 Interconnect 仿真

目录名沿用早期DDR开发阶段的名称；被测RTL已经是与目标从设备无关的
`edrv32_axi_m2s_interconnect`。本 case 覆盖：

- urgent 仲裁、下游 ID 分配和乱序返回；
- AR/AW 在反压期间保持 payload 稳定；
- 每主设备 R/B 缓冲与上游反压；
- W burst 所有权、相邻 burst 无额外空拍；
- 非对齐请求的本地 DECERR；
- `accept_i` 停止接收新事务；
- outstanding 计数与协议错误监测。

`ddr-axi-throughput` 是持续流量测试，覆盖：

- 1:2 加权轮询下 AR 连续逐周期传输；
- R 通道连续逐周期返回，包括同一主设备连续响应；
- 16 个下游 ID 全满时，RLAST 释放与新 AR 分配同周期完成。

在 Linux/虚拟机项目根目录运行：

```sh
make case-sim CASE=soc/ddr-axi-interconnect
make case-sim CASE=soc/ddr-axi-throughput
```

需要波形时追加 `WAVE=1`。
