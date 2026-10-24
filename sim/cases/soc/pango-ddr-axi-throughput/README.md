# Pango DDR AXI adapter 吞吐仿真

该配置复用 `pango-ddr-axi-adapter` 的完整功能测试，但关闭 DDR UI 模型的随机阻塞。
除数据、地址、最大16拍约束和回压检查外，它还逐拍断言：一个 AXI 写 burst 开始后，
适配器不得主动拉低 `WREADY`；DDR UI 开始取写数据后，事务内部不得产生空拍。多个
读事务的数据预取完成后，AXI R 通道在事务边界也必须连续输出。

运行：

```sh
make case-sim CASE=soc/pango-ddr-axi-throughput
```
