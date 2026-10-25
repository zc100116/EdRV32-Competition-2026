# CPU System AXI + DDR Gateway 仿真

该 case 不例化 CPU，而是用两个合成 Master 模拟 I-Cache 和 D-Cache，先经过现有 64-bit
`axi_interconnect`，再进入 `edrv32_axi_ddr_gateway` 和 256-bit AXI 内存模型。测试包括：

- D-Cache Master 从 `0xc000_0000` Uncached Alias 连续写 8 个 64-bit beat；
- I-Cache Master 从 `0x8000_0000` Cacheable View 回读同一物理地址；
- 4-byte 窄访问、交替 64-bit byte lane 和 `WSTRB` 合并；
- 64 个 64-bit beat 打包为最大合法的 16 个 256-bit DDR beat；
- System AXI 全局 ID 在 Gateway 前正确返回成本地 ID。

ModelSim 运行：

```sh
make case-msim CASE=soc/ddr-cpu-interconnect
```
