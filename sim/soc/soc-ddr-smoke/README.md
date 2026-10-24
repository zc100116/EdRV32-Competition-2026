# CPU DDR 软件仿真

该 SoC case 从片上 SRAM 启动 `sw/test/soc/ddr-smoke`，完整经过 CPU Cache、现有 64-bit
System AXI、64→256 DDR Gateway、通用 256-bit AXI Interconnect 和 Pango UI Adapter。
末端使用快速 DDR UI 行为模型，以便软件和 RTL 联调；真实控制器/PHY 已由前三个独立
ModelSim case 覆盖。

ModelSim 运行：

```sh
make soc-msim SOC=soc-ddr-smoke \
    IMAGE=sw/test/soc/ddr-smoke/build/program.hex
```

需要快速交叉回归时仍可使用 `make soc-sim` 调用 Icarus；两种仿真器使用同一份
`files.f`、同一个软件 case 和同一个 SRAM 镜像。

当前工程在 Linux 虚拟机编译软件、Windows 运行 ModelSim。先在虚拟机执行
`make sw-build CASE=test/soc/ddr-smoke` 并同步构建目录；若两套工具在同一环境，也可以
把上面的 `IMAGE=` 换成 `SW=test/soc/ddr-smoke`，由 Makefile 先编译软件。

通过标志为 UART/APB 控制台中的 `DDR_SMOKE_PASS` 和测试台的
`SOC_DDR_SMOKE_PASS`。
