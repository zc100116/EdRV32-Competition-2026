# DMA2D 写单元测试

依据 dma2d-spec v0.1 和 dma2d-testplan v0.1。
完整覆盖说明、命令、实测结果、Yosys LUT6/FF 参考及 ask 记录见
[本任务验证报告](../dma2d_rd/README.md)。

```sh
. ~/.local/opt/edrv32/env.sh
make smoke REGRESS_ARGS='-j 1 --path verif/unit/dma2d_wr'
make full REGRESS_ARGS='-j 1 --path verif/unit/dma2d_wr'
```

根配置为 smoke；full_1、full_4、full_8 加入 DM-04/08/09，
分别验证 OUTSTANDING=1/4/8，每个 full_N 含 1000 个随机描述符。
期望突发列表独立按规格 2.2 计算，并复用公共 AXI256 checker。
