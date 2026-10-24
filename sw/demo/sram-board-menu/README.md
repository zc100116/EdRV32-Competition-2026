# SoC board menu

PG2L200H SoC 的交互式上板程序。复位入口、初始化代码和开机日志位于
Boot ROM；菜单主程序和测试代码位于片上 SRAM。

串口菜单包含：

1. UART 回环
2. GPIO/LED
3. SRAM/Cache
4. CLINT
5. PLIC
6. CoreMark
7. Cache 控制
8. CPU 访问 DDR
9. DDR monitor 写入、读回校验和吞吐计数

编译：

```sh
make sw-build CASE=demo/sram-board-menu
```

输出文件：

- `build/bootrom.hex`：64-bit、2048 深度的 Boot ROM 初始化文件；
- `build/sram.hex`：64-bit、4096 深度的 SRAM 初始化文件；
- `build/program.elf`、`program.dis`、`program.map`：调试文件。
