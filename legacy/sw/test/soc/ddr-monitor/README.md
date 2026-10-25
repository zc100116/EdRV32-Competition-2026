# DDR monitor board test

该程序直接从 16 KiB Boot ROM 启动，依次执行：

- CPU 对 DDR 缓存/非缓存别名和 32-bit 数据的读写检查；
- 由 APB 配置 DDR monitor；
- monitor 通过 256-bit AXI 发起 4096 拍、AxLEN=255、循环两次的写入和读回校验；
- 通过 UART 输出周期、有效拍数和各类等待周期。

编译：

```sh
make sw-build CASE=test/soc/ddr-monitor
```

Boot ROM IP 使用 64-bit 初始化宽度，因此 `program.hex` 每行 8 字节。
