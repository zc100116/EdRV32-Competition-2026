# DDR smoke

该软件直接从 Boot ROM 启动，通过 UART 输出结果，并依次检查：

- `0xc000_0000` 非缓存视图写入后，从 `0x8000_0000` 缓存视图读回；
- 256 个 32-bit word 的确定性数据写读；
- byte 和 halfword 窄访问。

编译：

```sh
make sw-build CASE=test/soc/ddr-smoke
```

生成的 `build/program.hex` 是 64-bit Boot ROM 初始化镜像。
