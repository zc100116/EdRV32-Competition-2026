# Pango DDR AXI adapter 仿真

本 case 单独验证标准 256-bit AXI4 到 PG2L200H DDR3 用户接口的适配层，不依赖 SoC 顶层。

覆盖内容：

- 1、8、16 拍合法 AXI burst 与 DDR UI 命令一一映射；
- 17 拍越界读写在本地返回 `DECERR`，且不访问 DDR UI；
- AXI 字节地址到 DDR UI 32-bit word 地址的换算；
- 写数据完整缓存后才向无 `WVALID` 的 DDR UI 发出 AW；
- DDR UI 在接受 AW 的同周期请求首个写数据 beat；
- DDR UI 无 `RREADY` 时的完整事务接收缓冲；
- AXI R 通道长时间回压；
- 三个请求同时在途、UI 地址随机回压和按 UI ID 乱序返回；
- 两级 R/B 弹性输出缓冲及跨事务连续 R 吞吐；
- 一个写事务只返回一次 B，一个读事务只在最后一拍给出 RLAST；
- UI 命令和 AXI 返回 payload 在回压期间保持稳定。

运行：

```sh
make case-sim CASE=soc/pango-ddr-axi-adapter
```
